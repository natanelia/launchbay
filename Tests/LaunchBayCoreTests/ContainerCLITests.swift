import Foundation
import XCTest

@testable import LaunchBayCore

final class ContainerCLITests: XCTestCase, @unchecked Sendable {
    func testListContainersUsesJSONAndAllFlag() async throws {
        let executor = StubCommandExecutor([
            .init(stdout: "[]", stderr: "", exitCode: 0)
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        let response = try await cli.listContainers(includeStopped: true)
        XCTAssertEqual(response.value, [])
        let recorded = await executor.recordedInvocations()
        let invocation = try XCTUnwrap(recorded.first)
        XCTAssertEqual(invocation.arguments, ["list", "--all", "--format", "json"])
    }

    func testSystemStatusParsesJSONEvenWhenCLIUsesNonzeroForStoppedState() async throws {
        let executor = StubCommandExecutor([
            .init(stdout: "{\"status\":\"unregistered\"}", stderr: "", exitCode: 1)
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        let response = try await cli.systemStatus()
        XCTAssertEqual(response.value.state, .unregistered)
        XCTAssertEqual(response.result.exitCode, 1)
    }

    func testSystemStatusMapsEmptyFailedOutputToNotRunning() async throws {
        let executor = StubCommandExecutor([
            .init(stdout: "", stderr: "service unavailable", exitCode: 1)
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        let response = try await cli.systemStatus()
        XCTAssertEqual(response.value.state, .notRunning)
    }

    func testPullBuildAndDeleteArgumentOrdering() async throws {
        let executor = StubCommandExecutor([
            .init(stdout: "", stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "", exitCode: 0),
            .init(stdout: "", stderr: "", exitCode: 0),
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        _ = try await cli.pullImage(reference: "alpine:latest", platform: "linux/arm64")
        _ = try await cli.buildImage(
            BuildImageConfiguration(
                contextPath: "/tmp/context",
                dockerfilePath: "/tmp/context/Containerfile",
                tag: "demo:latest",
                platform: "linux/arm64",
                pullBaseImages: true,
                noCache: true
            )
        )
        _ = try await cli.deleteImage(reference: "demo:latest", force: true)

        let invocations = await executor.recordedInvocations()
        XCTAssertEqual(
            invocations[0].arguments,
            ["image", "pull", "--progress", "plain", "--platform", "linux/arm64", "alpine:latest"]
        )
        XCTAssertEqual(
            invocations[1].arguments,
            [
                "build", "--progress", "plain", "--tag", "demo:latest", "--file",
                "/tmp/context/Containerfile",
                "--platform", "linux/arm64", "--pull", "--no-cache", "/tmp/context",
            ]
        )
        XCTAssertEqual(invocations[2].arguments, ["image", "delete", "--force", "demo:latest"])
    }

    func testCommandFailureIncludesCapturedResult() async {
        let executor = StubCommandExecutor([
            .init(stdout: "", stderr: "container does not exist", exitCode: 1)
        ])
        let cli = ContainerCLI(
            executableURL: URL(fileURLWithPath: "/mock/container"),
            executor: executor
        )

        do {
            _ = try await cli.startContainer(id: "missing")
            XCTFail("Expected command failure")
        } catch let error as ContainerCLIError {
            guard case .commandFailed(let result) = error else {
                return XCTFail("Unexpected CLI error: \(error)")
            }
            XCTAssertEqual(result.exitCode, 1)
            XCTAssertEqual(error.localizedDescription, "container does not exist")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNotInstalledFailsBeforeExecutorIsCalled() async {
        let executor = StubCommandExecutor([])
        let cli = ContainerCLI(executor: executor)
        do {
            _ = try await cli.version()
            XCTFail("Expected not-installed error")
        } catch let error as ContainerCLIError {
            guard case .notInstalled = error else {
                return XCTFail("Unexpected CLI error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let recorded = await executor.recordedInvocations()
        XCTAssertTrue(recorded.isEmpty)
    }
}

private actor StubCommandExecutor: CommandExecuting {
    struct Response: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private var responses: [Response]
    private var invocations: [CommandInvocation] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func execute(_ invocation: CommandInvocation) async throws -> CommandResult {
        invocations.append(invocation)
        guard !responses.isEmpty else {
            throw StubError.missingResponse
        }
        let response = responses.removeFirst()
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
