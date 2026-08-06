import Foundation
import XCTest

@testable import LaunchBayCore

final class ContainerCLIReadCacheTests: XCTestCase, @unchecked Sendable {
    func testSequentialImageReadsReuseCachedResult() async throws {
        let executor = RecordingCommandExecutor([
            .init(stdout: "[]", stderr: "", exitCode: 0)
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        _ = try await cli.listImages()
        _ = try await cli.listImages()

        let invocations = await executor.recordedInvocations()
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations.first?.arguments, ["image", "list", "--format", "json"])
    }

    func testConcurrentContainerReadsShareOneInFlightProcess() async throws {
        let executor = RecordingCommandExecutor([
            .init(stdout: "[]", stderr: "", exitCode: 0, delayNanoseconds: 100_000_000)
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor,
            readCachePolicy: .disabled
        )

        async let first = cli.listContainers(includeStopped: true)
        async let second = cli.listContainers(includeStopped: true)
        _ = try await (first, second)

        let invocations = await executor.recordedInvocations()
        XCTAssertEqual(invocations.count, 1)
    }

    func testContainerMutationInvalidatesCachedList() async throws {
        let executor = RecordingCommandExecutor([
            .init(stdout: "[]", stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "", exitCode: 0),
            .init(stdout: "[]", stderr: "", exitCode: 0),
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        _ = try await cli.listContainers()
        _ = try await cli.startContainer(id: "web")
        _ = try await cli.listContainers()

        let invocations = await executor.recordedInvocations()
        XCTAssertEqual(
            invocations.map(\.arguments),
            [
                ["list", "--all", "--format", "json"],
                ["start", "web"],
                ["list", "--all", "--format", "json"],
            ]
        )
    }

    func testExplicitInvalidationForcesFreshRead() async throws {
        let executor = RecordingCommandExecutor([
            .init(stdout: "[]", stderr: "", exitCode: 0),
            .init(stdout: "[]", stderr: "", exitCode: 0),
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        _ = try await cli.listImages()
        await cli.invalidateReadCache()
        _ = try await cli.listImages()

        let invocations = await executor.recordedInvocations()
        XCTAssertEqual(invocations.count, 2)
    }

    func testExpiredImageCacheLaunchesAnotherRead() async throws {
        let executor = RecordingCommandExecutor([
            .init(stdout: "[]", stderr: "", exitCode: 0),
            .init(stdout: "[]", stderr: "", exitCode: 0),
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor,
            readCachePolicy: ContainerCLIReadCachePolicy(
                systemStatusTTL: 0,
                containersTTL: 0,
                imagesTTL: 0.01
            )
        )

        _ = try await cli.listImages()
        try await Task.sleep(nanoseconds: 50_000_000)
        _ = try await cli.listImages()

        let invocations = await executor.recordedInvocations()
        XCTAssertEqual(invocations.count, 2)
    }

    func testOlderInFlightReadCannotReplaceCacheAfterInvalidation() async throws {
        let oldPayload =
            #"[{"id":"old","configuration":{"id":"old","image":{"reference":"old:latest"}},"status":{"state":"stopped"}}]"#
        let freshPayload =
            #"[{"id":"fresh","configuration":{"id":"fresh","image":{"reference":"fresh:latest"}},"status":{"state":"running"}}]"#
        let executor = RecordingCommandExecutor([
            .init(
                stdout: oldPayload,
                stderr: "",
                exitCode: 0,
                delayNanoseconds: 100_000_000
            ),
            .init(stdout: freshPayload, stderr: "", exitCode: 0),
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor,
            readCachePolicy: ContainerCLIReadCachePolicy(
                systemStatusTTL: 0,
                containersTTL: 60,
                imagesTTL: 0
            )
        )

        let olderRead = Task { try await cli.listContainers() }
        while await executor.recordedInvocations().isEmpty {
            await Task.yield()
        }

        await cli.invalidateReadCache()
        let fresh = try await cli.listContainers()
        XCTAssertEqual(fresh.value.map(\.id), ["fresh"])

        _ = try await olderRead.value
        let cached = try await cli.listContainers()
        XCTAssertEqual(cached.value.map(\.id), ["fresh"])

        let invocations = await executor.recordedInvocations()
        XCTAssertEqual(invocations.count, 2)
    }

    func testExecRunsInsideExistingContainer() async throws {
        let executor = RecordingCommandExecutor([
            .init(stdout: "ok\n", stderr: "", exitCode: 0)
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        let executed = try await cli.execContainer(
            id: "dev-web",
            command: ["npm", "test", "--", "--runInBand"]
        )

        XCTAssertEqual(executed.value, "ok\n")
        let invocations = await executor.recordedInvocations()
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(
            invocation.arguments,
            ["exec", "dev-web", "npm", "test", "--", "--runInBand"]
        )
    }

    func testExecRejectsEmptyCommandBeforeLaunchingProcess() async {
        let executor = RecordingCommandExecutor([])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        do {
            _ = try await cli.execContainer(id: "dev-web", command: [])
            XCTFail("Expected missing-command error")
        } catch let error as ContainerCLIError {
            guard case .missingCommand = error else {
                return XCTFail("Unexpected CLI error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let invocations = await executor.recordedInvocations()
        XCTAssertTrue(invocations.isEmpty)
    }
}

private actor RecordingCommandExecutor: CommandExecuting {
    struct Response: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        let delayNanoseconds: UInt64

        init(
            stdout: String,
            stderr: String,
            exitCode: Int32,
            delayNanoseconds: UInt64 = 0
        ) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
            self.delayNanoseconds = delayNanoseconds
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
        return CommandResult(
            invocation: invocation,
            standardOutput: response.stdout,
            standardError: response.stderr,
            exitCode: response.exitCode,
            durationSeconds: 0.01
        )
    }

    func recordedInvocations() -> [CommandInvocation] {
        invocations
    }

    enum StubError: Error {
        case missingResponse
    }
}
