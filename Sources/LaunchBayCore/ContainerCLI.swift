import Foundation

public struct Executed<Value: Sendable>: Sendable {
    public let value: Value
    public let result: CommandResult

    public init(value: Value, result: CommandResult) {
        self.value = value
        self.result = result
    }
}

public enum ContainerCLIError: LocalizedError, Sendable {
    case notInstalled
    case commandFailed(CommandResult)
    case noMachineReadableOutput(CommandResult)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Apple’s container CLI was not found. Install it, or choose its executable in Settings."
        case .commandFailed(let result):
            result.standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Command failed with exit code \(result.exitCode): \(result.invocation.redactedDisplayCommand)"
                : result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        case .noMachineReadableOutput(let result):
            "The command returned no JSON output: \(result.invocation.redactedDisplayCommand)"
        }
    }
}

public actor ContainerCLI {
    private let executor: any CommandExecuting
    private var executableURL: URL?

    public init(executableURL: URL? = nil, executor: any CommandExecuting = ProcessCommandExecutor()) {
        self.executableURL = executableURL
        self.executor = executor
    }

    public func configure(executableURL: URL?) {
        self.executableURL = executableURL
    }

    public func configuredExecutableURL() -> URL? {
        executableURL
    }

    public func version() async throws -> Executed<String> {
        let result = try await execute(["--version"], timeout: 10)
        try requireSuccess(result)
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return Executed(value: output, result: result)
    }

    public func systemStatus() async throws -> Executed<ContainerSystemStatus> {
        let result = try await execute(["system", "status", "--format", "json"], timeout: 15)
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            if result.succeeded { throw ContainerCLIError.noMachineReadableOutput(result) }
            return Executed(
                value: ContainerSystemStatus(state: .notRunning),
                result: result
            )
        }
        return Executed(value: try ContainerJSONParser.parseSystemStatus(output), result: result)
    }

    public func startSystem() async throws -> Executed<Void> {
        let result = try await execute(["system", "start"], timeout: 180)
        try requireSuccess(result)
        return Executed(value: (), result: result)
    }

    public func stopSystem() async throws -> Executed<Void> {
        let result = try await execute(["system", "stop"], timeout: 180)
        try requireSuccess(result)
        return Executed(value: (), result: result)
    }

    public func listContainers(includeStopped: Bool = true) async throws -> Executed<
        [ContainerSummary]
    > {
        var arguments = ["list"]
        if includeStopped { arguments.append("--all") }
        arguments += ["--format", "json"]
        let result = try await execute(arguments, timeout: 30)
        try requireSuccess(result)
        return Executed(
            value: try ContainerJSONParser.parseContainers(result.standardOutput), result: result)
    }

    public func listImages() async throws -> Executed<[ImageSummary]> {
        let result = try await execute(["image", "list", "--format", "json"], timeout: 60)
        try requireSuccess(result)
        return Executed(
            value: try ContainerJSONParser.parseImages(result.standardOutput), result: result)
    }

    public func startContainer(id: String) async throws -> Executed<Void> {
        let result = try await execute(["start", id], timeout: 120)
        try requireSuccess(result)
        return Executed(value: (), result: result)
    }

    public func stopContainer(id: String) async throws -> Executed<Void> {
        let result = try await execute(["stop", id], timeout: 120)
        try requireSuccess(result)
        return Executed(value: (), result: result)
    }

    public func deleteContainer(id: String, force: Bool = false) async throws -> Executed<Void> {
        var arguments = ["delete"]
        if force { arguments.append("--force") }
        arguments.append(id)
        let result = try await execute(arguments, timeout: 120)
        try requireSuccess(result)
        return Executed(value: (), result: result)
    }

    public func containerLogs(id: String, tail: Int = 500, boot: Bool = false) async throws
        -> Executed<String>
    {
        var arguments = ["logs"]
        if boot { arguments.append("--boot") }
        arguments += ["-n", String(max(1, tail)), id]
        let result = try await execute(arguments, timeout: 30)
        try requireSuccess(result)
        return Executed(value: result.standardOutput, result: result)
    }

    public func pullImage(reference: String, platform: String? = nil) async throws -> Executed<Void> {
        var arguments = ["image", "pull", "--progress", "plain"]
        if let platform, !platform.isEmpty {
            arguments += ["--platform", platform]
        }
        arguments.append(reference)
        let result = try await execute(arguments, timeout: 1_800)
        try requireSuccess(result)
        return Executed(value: (), result: result)
    }

    public func deleteImage(reference: String, force: Bool = false) async throws -> Executed<Void> {
        var arguments = ["image", "delete"]
        if force { arguments.append("--force") }
        arguments.append(reference)
        let result = try await execute(arguments, timeout: 300)
        try requireSuccess(result)
        return Executed(value: (), result: result)
    }

    public func runContainer(_ configuration: RunContainerConfiguration) async throws -> Executed<
        Void
    > {
        try ConfigurationValidator.validate(configuration)
        let arguments = Self.runArguments(for: configuration)
        let result = try await execute(arguments, timeout: 1_800)
        try requireSuccess(result)
        return Executed(value: (), result: result)
    }

    public func buildImage(_ configuration: BuildImageConfiguration) async throws -> Executed<Void> {
        try ConfigurationValidator.validate(configuration)
        var arguments = ["build", "--progress", "plain", "--tag", configuration.tag]
        if let dockerfile = configuration.dockerfilePath, !dockerfile.isEmpty {
            arguments += ["--file", dockerfile]
        }
        if let platform = configuration.platform, !platform.isEmpty {
            arguments += ["--platform", platform]
        }
        if configuration.pullBaseImages { arguments.append("--pull") }
        if configuration.noCache { arguments.append("--no-cache") }
        arguments.append(configuration.contextPath)

        let result = try await execute(arguments, timeout: 3_600)
        try requireSuccess(result)
        return Executed(value: (), result: result)
    }

    public static func runArguments(for configuration: RunContainerConfiguration) -> [String] {
        var arguments = ["run", "--detach"]
        let name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { arguments += ["--name", name] }
        if configuration.removeWhenStopped { arguments.append("--remove") }
        if configuration.useInit { arguments.append("--init") }
        if configuration.enableRosetta { arguments.append("--rosetta") }
        if configuration.readOnlyRootFilesystem { arguments.append("--read-only") }
        if let cpuCount = configuration.cpuCount { arguments += ["--cpus", String(cpuCount)] }
        if let memory = configuration.memory?.trimmingCharacters(in: .whitespacesAndNewlines),
            !memory.isEmpty
        {
            arguments += ["--memory", memory]
        }
        for port in configuration.ports { arguments += ["--publish", port.cliValue] }
        for volume in configuration.volumes { arguments += ["--volume", volume.cliValue] }
        for variable in configuration.environment {
            arguments += ["--env", "\(variable.key)=\(variable.value)"]
        }
        arguments.append(configuration.imageReference.trimmingCharacters(in: .whitespacesAndNewlines))
        arguments.append(contentsOf: configuration.command)
        return arguments
    }

    private func execute(_ arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        guard let executableURL else { throw ContainerCLIError.notInstalled }
        return try await executor.execute(
            CommandInvocation(
                executableURL: executableURL,
                arguments: arguments,
                timeoutSeconds: timeout
            )
        )
    }

    private func requireSuccess(_ result: CommandResult) throws {
        guard result.succeeded else { throw ContainerCLIError.commandFailed(result) }
    }
}
