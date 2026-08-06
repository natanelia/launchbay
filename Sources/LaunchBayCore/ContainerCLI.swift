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
    case missingCommand
    case commandFailed(CommandResult)
    case noMachineReadableOutput(CommandResult)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Apple’s container CLI was not found. Install it, or choose its executable in Settings."
        case .missingCommand:
            "Enter a command to execute in the running container."
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
    private struct CacheEntry<Value: Sendable>: Sendable {
        let executed: Executed<Value>
        let expiresAt: ContinuousClock.Instant

        func isFresh(at instant: ContinuousClock.Instant) -> Bool {
            expiresAt > instant
        }
    }

    private struct PendingRequest<Value: Sendable>: Sendable {
        let id: UUID
        let generation: UInt64
        let task: Task<Executed<Value>, any Error>
    }

    private let executor: any CommandExecuting
    private let readCachePolicy: ContainerCLIReadCachePolicy
    private let cacheClock = ContinuousClock()
    private var executableURL: URL?

    private var cacheGeneration: UInt64 = 0
    private var systemStatusCache: CacheEntry<ContainerSystemStatus>?
    private var containerCaches: [Bool: CacheEntry<[ContainerSummary]>] = [:]
    private var imageCache: CacheEntry<[ImageSummary]>?
    private var systemStatusRequest: PendingRequest<ContainerSystemStatus>?
    private var containerRequests: [Bool: PendingRequest<[ContainerSummary]>] = [:]
    private var imageRequest: PendingRequest<[ImageSummary]>?

    public init(
        executableURL: URL? = nil,
        executor: any CommandExecuting = ProcessCommandExecutor(),
        readCachePolicy: ContainerCLIReadCachePolicy = .interactive
    ) {
        self.executableURL = executableURL
        self.executor = executor
        self.readCachePolicy = readCachePolicy
    }

    public func configure(executableURL: URL?) {
        cancelPendingRequests()
        self.executableURL = executableURL
        invalidateReadCache()
    }

    public func configuredExecutableURL() -> URL? {
        executableURL
    }

    /// Clears completed reads and detaches future callers from any reads already in flight.
    ///
    /// Existing callers still receive the result they requested, but an older request cannot repopulate
    /// the cache after this method advances the cache generation.
    public func invalidateReadCache() {
        invalidate(systemStatus: true, containers: true, images: true)
    }

    /// Cancels all in-flight read commands and detaches their callers from future cache state.
    ///
    /// Completed cache entries are preserved. Call `invalidateReadCache()` as well when the next read
    /// must be authoritative, such as a manual refresh or application resume.
    public func cancelPendingReads() {
        cancelPendingRequests()
    }

    public func version() async throws -> Executed<String> {
        let result = try await execute(["--version"], timeout: 10)
        try requireSuccess(result)
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return Executed(value: output, result: result)
    }

    public func systemStatus() async throws -> Executed<ContainerSystemStatus> {
        let now = cacheClock.now
        if let systemStatusCache, systemStatusCache.isFresh(at: now) {
            return systemStatusCache.executed
        }
        if let systemStatusRequest {
            return try await systemStatusRequest.task.value
        }

        let request = PendingRequest(
            id: UUID(),
            generation: cacheGeneration,
            task: Task { try await self.loadSystemStatus() }
        )
        systemStatusRequest = request

        do {
            let executed = try await request.task.value
            if systemStatusRequest?.id == request.id {
                systemStatusRequest = nil
            }
            if request.generation == cacheGeneration, readCachePolicy.systemStatusTTL > 0 {
                systemStatusCache = CacheEntry(
                    executed: executed,
                    expiresAt: cacheClock.now.advanced(
                        by: .seconds(readCachePolicy.systemStatusTTL)
                    )
                )
            }
            return executed
        } catch {
            if systemStatusRequest?.id == request.id {
                systemStatusRequest = nil
            }
            throw error
        }
    }

    public func startSystem() async throws -> Executed<Void> {
        let result = try await executeMutation(
            ["system", "start"],
            timeout: 180,
            systemStatus: true,
            containers: true,
            images: true
        )
        return Executed(value: (), result: result)
    }

    public func stopSystem() async throws -> Executed<Void> {
        let result = try await executeMutation(
            ["system", "stop"],
            timeout: 180,
            systemStatus: true,
            containers: true,
            images: true
        )
        return Executed(value: (), result: result)
    }

    public func listContainers(includeStopped: Bool = true) async throws -> Executed<
        [ContainerSummary]
    > {
        let now = cacheClock.now
        if let cached = containerCaches[includeStopped], cached.isFresh(at: now) {
            return cached.executed
        }
        if let request = containerRequests[includeStopped] {
            return try await request.task.value
        }

        let request = PendingRequest(
            id: UUID(),
            generation: cacheGeneration,
            task: Task { try await self.loadContainers(includeStopped: includeStopped) }
        )
        containerRequests[includeStopped] = request

        do {
            let executed = try await request.task.value
            if containerRequests[includeStopped]?.id == request.id {
                containerRequests.removeValue(forKey: includeStopped)
            }
            if request.generation == cacheGeneration, readCachePolicy.containersTTL > 0 {
                containerCaches[includeStopped] = CacheEntry(
                    executed: executed,
                    expiresAt: cacheClock.now.advanced(by: .seconds(readCachePolicy.containersTTL))
                )
            }
            return executed
        } catch {
            if containerRequests[includeStopped]?.id == request.id {
                containerRequests.removeValue(forKey: includeStopped)
            }
            throw error
        }
    }

    public func listImages() async throws -> Executed<[ImageSummary]> {
        let now = cacheClock.now
        if let imageCache, imageCache.isFresh(at: now) {
            return imageCache.executed
        }
        if let imageRequest {
            return try await imageRequest.task.value
        }

        let request = PendingRequest(
            id: UUID(),
            generation: cacheGeneration,
            task: Task { try await self.loadImages() }
        )
        imageRequest = request

        do {
            let executed = try await request.task.value
            if imageRequest?.id == request.id {
                imageRequest = nil
            }
            if request.generation == cacheGeneration, readCachePolicy.imagesTTL > 0 {
                imageCache = CacheEntry(
                    executed: executed,
                    expiresAt: cacheClock.now.advanced(by: .seconds(readCachePolicy.imagesTTL))
                )
            }
            return executed
        } catch {
            if imageRequest?.id == request.id {
                imageRequest = nil
            }
            throw error
        }
    }

    public func startContainer(id: String) async throws -> Executed<Void> {
        let result = try await executeMutation(["start", id], timeout: 120, containers: true)
        return Executed(value: (), result: result)
    }

    public func stopContainer(id: String) async throws -> Executed<Void> {
        let result = try await executeMutation(["stop", id], timeout: 120, containers: true)
        return Executed(value: (), result: result)
    }

    public func deleteContainer(id: String, force: Bool = false) async throws -> Executed<Void> {
        var arguments = ["delete"]
        if force { arguments.append("--force") }
        arguments.append(id)
        let result = try await executeMutation(arguments, timeout: 120, containers: true)
        return Executed(value: (), result: result)
    }

    public func containerLogs(id: String, tail: Int = 500, boot: Bool = false) async throws
        -> Executed<String>
    {
        var arguments = ["logs"]
        if boot { arguments.append("--boot") }
        arguments += ["-n", String(max(1, tail)), id]
        let result = try await execute(arguments, timeout: 30)
        try Task.checkCancellation()
        try requireSuccess(result)
        return Executed(value: result.standardOutput, result: result)
    }

    /// Executes a command in an already-running container instead of creating and booting another VM.
    public func execContainer(
        id: String,
        command: [String],
        timeoutSeconds: TimeInterval = 1_800
    ) async throws -> Executed<String> {
        guard let executable = command.first,
            !executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ContainerCLIError.missingCommand
        }
        let result = try await executeMutation(
            ["exec", id] + command,
            timeout: max(0.1, timeoutSeconds),
            containers: true
        )
        return Executed(value: result.standardOutput, result: result)
    }

    public func pullImage(reference: String, platform: String? = nil) async throws -> Executed<Void> {
        var arguments = ["image", "pull", "--progress", "plain"]
        if let platform, !platform.isEmpty {
            arguments += ["--platform", platform]
        }
        arguments.append(reference)
        let result = try await executeMutation(arguments, timeout: 1_800, images: true)
        return Executed(value: (), result: result)
    }

    public func deleteImage(reference: String, force: Bool = false) async throws -> Executed<Void> {
        var arguments = ["image", "delete"]
        if force { arguments.append("--force") }
        arguments.append(reference)
        let result = try await executeMutation(arguments, timeout: 300, images: true)
        return Executed(value: (), result: result)
    }

    public func runContainer(_ configuration: RunContainerConfiguration) async throws -> Executed<
        Void
    > {
        try ConfigurationValidator.validate(configuration)
        let arguments = Self.runArguments(for: configuration)
        let result = try await executeMutation(
            arguments,
            timeout: 1_800,
            containers: true,
            images: true
        )
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

        let result = try await executeMutation(arguments, timeout: 3_600, images: true)
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

    private func loadSystemStatus() async throws -> Executed<ContainerSystemStatus> {
        let result = try await execute(["system", "status", "--format", "json"], timeout: 15)
        try Task.checkCancellation()
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

    private func loadContainers(includeStopped: Bool) async throws -> Executed<[ContainerSummary]> {
        var arguments = ["list"]
        if includeStopped { arguments.append("--all") }
        arguments += ["--format", "json"]
        let result = try await execute(arguments, timeout: 30)
        try Task.checkCancellation()
        try requireSuccess(result)
        return Executed(
            value: try ContainerJSONParser.parseContainers(result.standardOutput), result: result)
    }

    private func loadImages() async throws -> Executed<[ImageSummary]> {
        let result = try await execute(["image", "list", "--format", "json"], timeout: 60)
        try Task.checkCancellation()
        try requireSuccess(result)
        return Executed(
            value: try ContainerJSONParser.parseImages(result.standardOutput), result: result)
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

    private func executeMutation(
        _ arguments: [String],
        timeout: TimeInterval,
        systemStatus: Bool = false,
        containers: Bool = false,
        images: Bool = false
    ) async throws -> CommandResult {
        defer {
            invalidate(systemStatus: systemStatus, containers: containers, images: images)
        }
        let result = try await execute(arguments, timeout: timeout)
        try requireSuccess(result)
        return result
    }

    private func requireSuccess(_ result: CommandResult) throws {
        guard result.succeeded else { throw ContainerCLIError.commandFailed(result) }
    }

    private func cancelPendingRequests() {
        cacheGeneration &+= 1
        systemStatusRequest?.task.cancel()
        for request in containerRequests.values {
            request.task.cancel()
        }
        imageRequest?.task.cancel()
        systemStatusRequest = nil
        containerRequests.removeAll()
        imageRequest = nil
    }

    private func invalidate(
        systemStatus: Bool = false,
        containers: Bool = false,
        images: Bool = false
    ) {
        cacheGeneration &+= 1
        if systemStatus {
            systemStatusCache = nil
            systemStatusRequest = nil
        }
        if containers {
            containerCaches.removeAll()
            containerRequests.removeAll()
        }
        if images {
            imageCache = nil
            imageRequest = nil
        }
    }
}
