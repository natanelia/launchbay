@preconcurrency import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public struct CommandInvocation: Hashable, Codable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let currentDirectoryURL: URL?
    public let timeoutSeconds: TimeInterval

    public init(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeoutSeconds: TimeInterval = 30
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.currentDirectoryURL = currentDirectoryURL
        self.timeoutSeconds = timeoutSeconds
    }

    public var redactedDisplayCommand: String {
        let redacted = Self.redacted(arguments: arguments)
        return ([executableURL.path] + redacted).map(Self.shellQuoted).joined(separator: " ")
    }

    static func redacted(arguments: [String]) -> [String] {
        var output: [String] = []
        var shouldRedactNext = false

        for argument in arguments {
            if shouldRedactNext {
                if let equalsIndex = argument.firstIndex(of: "=") {
                    output.append("\(argument[..<equalsIndex])=••••")
                } else {
                    output.append("••••")
                }
                shouldRedactNext = false
                continue
            }

            output.append(argument)
            if argument == "-e" || argument == "--env" || argument == "--registry-password" {
                shouldRedactNext = true
            }
        }
        return output
    }

    static func shellQuoted(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/:=@+"))
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public struct CommandResult: Hashable, Codable, Sendable {
    public let invocation: CommandInvocation
    public let standardOutput: String
    public let standardError: String
    public let exitCode: Int32
    public let durationSeconds: TimeInterval

    public var succeeded: Bool { exitCode == 0 }

    public init(
        invocation: CommandInvocation,
        standardOutput: String,
        standardError: String,
        exitCode: Int32,
        durationSeconds: TimeInterval
    ) {
        self.invocation = invocation
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
    }
}

public protocol CommandExecuting: Sendable {
    func execute(_ invocation: CommandInvocation) async throws -> CommandResult
}

public enum CommandExecutionError: LocalizedError, Sendable {
    case executableNotFound(String)
    case launchFailed(String)
    case timedOut(command: String, timeoutSeconds: TimeInterval)
    case outputReadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            "Executable was not found or is not executable: \(path)"
        case .launchFailed(let message):
            "Could not launch command: \(message)"
        case .timedOut(let command, let timeoutSeconds):
            "Command exceeded its \(Int(timeoutSeconds))-second timeout: \(command)"
        case .outputReadFailed(let message):
            "Could not read command output: \(message)"
        }
    }
}

public struct ProcessCommandExecutor: CommandExecuting, Sendable {
    public init() {}

    public func execute(_ invocation: CommandInvocation) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.executeSynchronously(invocation)
        }.value
    }

    private static func executeSynchronously(_ invocation: CommandInvocation) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: invocation.executableURL.path) else {
            throw CommandExecutionError.executableNotFound(invocation.executableURL.path)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchbay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let stdoutURL = temporaryDirectory.appendingPathComponent("stdout")
        let stderrURL = temporaryDirectory.appendingPathComponent("stderr")
        guard
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil),
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        else {
            throw CommandExecutionError.outputReadFailed("Could not create temporary output files.")
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectoryURL
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        var environment = ProcessInfo.processInfo.environment
        let usefulPaths = [
            "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (usefulPaths + [existingPath])
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) { result.append(item) }
            }
            .joined(separator: ":")
        process.environment = environment

        let start = Date()
        do {
            try process.run()
        } catch {
            throw CommandExecutionError.launchFailed(error.localizedDescription)
        }

        let deadline = start.addingTimeInterval(max(0.1, invocation.timeoutSeconds))
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                Thread.sleep(forTimeInterval: 0.15)
                if process.isRunning {
                    _ = kill(process.processIdentifier, SIGKILL)
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
        process.waitUntilExit()

        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()

        let stdoutData: Data
        let stderrData: Data
        do {
            stdoutData = try Data(contentsOf: stdoutURL)
            stderrData = try Data(contentsOf: stderrURL)
        } catch {
            throw CommandExecutionError.outputReadFailed(error.localizedDescription)
        }

        if timedOut {
            throw CommandExecutionError.timedOut(
                command: invocation.redactedDisplayCommand,
                timeoutSeconds: invocation.timeoutSeconds
            )
        }

        return CommandResult(
            invocation: invocation,
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus,
            durationSeconds: Date().timeIntervalSince(start)
        )
    }
}
