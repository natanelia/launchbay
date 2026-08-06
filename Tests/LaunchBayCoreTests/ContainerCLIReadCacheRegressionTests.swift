import Foundation
import XCTest

@testable import LaunchBayCore

final class ContainerCLIReadCacheRegressionTests: XCTestCase, @unchecked Sendable {
    func testFailedReadIsNotCached() async throws {
        let executor = ScriptedCommandExecutor([
            .init(stdout: "", stderr: "temporary failure", exitCode: 1),
            .init(stdout: "[]", stderr: "", exitCode: 0),
        ])
        let cli = makeCLI(executor: executor)

        do {
            _ = try await cli.listImages()
            XCTFail("Expected image read to fail")
        } catch let error as ContainerCLIError {
            guard case .commandFailed = error else {
                return XCTFail("Unexpected CLI error: \(error)")
            }
        }

        _ = try await cli.listImages()
        let invocationCount = await executor.invocationCount()
        XCTAssertEqual(invocationCount, 2)
    }

    func testFailedMutationInvalidatesCachedContainerList() async throws {
        let executor = ScriptedCommandExecutor([
            .init(stdout: "[]", stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "start failed", exitCode: 1),
            .init(stdout: "[]", stderr: "", exitCode: 0),
        ])
        let cli = makeCLI(executor: executor)

        _ = try await cli.listContainers()
        do {
            _ = try await cli.startContainer(id: "web")
            XCTFail("Expected start to fail")
        } catch let error as ContainerCLIError {
            guard case .commandFailed = error else {
                return XCTFail("Unexpected CLI error: \(error)")
            }
        }
        _ = try await cli.listContainers()

        let arguments = await executor.recordedArguments()
        XCTAssertEqual(
            arguments,
            [
                ["list", "--all", "--format", "json"],
                ["start", "web"],
                ["list", "--all", "--format", "json"],
            ]
        )
    }

    func testThrownMutationInvalidatesCachedContainerList() async throws {
        let executor = ScriptedCommandExecutor([
            .init(stdout: "[]", stderr: "", exitCode: 0),
            .init(error: .simulatedLaunchFailure),
            .init(stdout: "[]", stderr: "", exitCode: 0),
        ])
        let cli = makeCLI(executor: executor)

        _ = try await cli.listContainers()
        do {
            _ = try await cli.startContainer(id: "web")
            XCTFail("Expected executor error")
        } catch ScriptedCommandExecutor.StubError.simulatedLaunchFailure {
            // Expected.
        }
        _ = try await cli.listContainers()

        let invocationCount = await executor.invocationCount()
        XCTAssertEqual(invocationCount, 3)
    }

    func testExecInvalidatesContainerCacheBecauseCommandCanStopContainer() async throws {
        let executor = ScriptedCommandExecutor([
            .init(stdout: "[]", stderr: "", exitCode: 0),
            .init(stdout: "done\n", stderr: "", exitCode: 0),
            .init(stdout: "[]", stderr: "", exitCode: 0),
        ])
        let cli = makeCLI(executor: executor)

        _ = try await cli.listContainers()
        _ = try await cli.execContainer(id: "web", command: ["kill", "1"])
        _ = try await cli.listContainers()

        let arguments = await executor.recordedArguments()
        XCTAssertEqual(
            arguments,
            [
                ["list", "--all", "--format", "json"],
                ["exec", "web", "kill", "1"],
                ["list", "--all", "--format", "json"],
            ]
        )
    }

    func testCancelPendingReadsCancelsCommandAndAllowsFreshRead() async throws {
        let executor = ScriptedCommandExecutor([
            .init(
                stdout: #"{"status":"running"}"#,
                stderr: "",
                exitCode: 0,
                delayNanoseconds: 5_000_000_000
            ),
            .init(stdout: #"{"status":"running"}"#, stderr: "", exitCode: 0),
        ])
        let cli = makeCLI(executor: executor)

        let pendingRead = Task { try await cli.systemStatus() }
        while await executor.invocationCount() == 0 {
            await Task.yield()
        }

        await cli.cancelPendingReads()
        do {
            _ = try await pendingRead.value
            XCTFail("Expected pending read to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        let fresh = try await cli.systemStatus()
        XCTAssertEqual(fresh.value.state, .running)
        let invocationCount = await executor.invocationCount()
        XCTAssertEqual(invocationCount, 2)
    }

    private func makeCLI(executor: ScriptedCommandExecutor) -> ContainerCLI {
        ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor,
            readCachePolicy: ContainerCLIReadCachePolicy(
                systemStatusTTL: 60,
                containersTTL: 60,
                imagesTTL: 60
            )
        )
    }
}

private actor ScriptedCommandExecutor: CommandExecuting {
    enum StubError: Error, Sendable {
        case simulatedLaunchFailure
        case missingResponse
    }

    struct Response: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        let delayNanoseconds: UInt64
        let error: StubError?

        init(
            stdout: String = "",
            stderr: String = "",
            exitCode: Int32 = 0,
            delayNanoseconds: UInt64 = 0,
            error: StubError? = nil
        ) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
            self.delayNanoseconds = delayNanoseconds
            self.error = error
        }
    }

    private var responses: [Response]
    private var invocations: [CommandInvocation] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func execute(_ invocation: CommandInvocation) async throws -> CommandResult {
        invocations.append(invocation)
        guard !responses.isEmpty else { throw StubError.missingResponse }
        let response = responses.removeFirst()
        if response.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: response.delayNanoseconds)
        }
        if let error = response.error {
            throw error
        }
        return CommandResult(
            invocation: invocation,
            standardOutput: response.stdout,
            standardError: response.stderr,
            exitCode: response.exitCode,
            durationSeconds: 0.01
        )
    }

    func invocationCount() -> Int {
        invocations.count
    }

    func recordedArguments() -> [[String]] {
        invocations.map(\.arguments)
    }
}
