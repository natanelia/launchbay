import Foundation
import XCTest

@testable import LaunchBayCore

final class CommandExecutionTests: XCTestCase, @unchecked Sendable {
    func testDisplayCommandQuotesArgumentsAndRedactsEnvironmentValues() {
        let invocation = CommandInvocation(
            executableURL: URL(fileURLWithPath: "/usr/local/bin/container"),
            arguments: [
                "run", "--env", "TOKEN=super secret", "--env", "PLAIN", "--name", "my web", "alpine:latest",
            ]
        )

        XCTAssertEqual(
            invocation.redactedDisplayCommand,
            "/usr/local/bin/container run --env 'TOKEN=••••' --env '••••' --name 'my web' alpine:latest"
        )
        XCTAssertFalse(invocation.redactedDisplayCommand.contains("super secret"))
    }

    func testRunArgumentsCoverSupportedConfiguration() {
        let configuration = RunContainerConfiguration(
            imageReference: " nginx:latest ",
            name: "web",
            command: ["nginx", "-g", "daemon off;"],
            ports: [PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80)],
            volumes: [VolumeMapping(source: "/tmp/site", target: "/site", readOnly: true)],
            environment: [EnvironmentVariable(key: "TOKEN", value: "secret")],
            cpuCount: 2,
            memory: " 1G ",
            removeWhenStopped: true,
            useInit: true,
            enableRosetta: true,
            readOnlyRootFilesystem: true
        )

        XCTAssertEqual(
            ContainerCLI.runArguments(for: configuration),
            [
                "run", "--detach", "--name", "web", "--remove", "--init", "--rosetta", "--read-only",
                "--cpus", "2", "--memory", "1G", "--publish", "127.0.0.1:8080:80/tcp",
                "--volume", "/tmp/site:/site:ro", "--env", "TOKEN=secret", "nginx:latest",
                "nginx", "-g", "daemon off;",
            ]
        )
    }

    func testProcessExecutorCapturesStdoutStderrAndExitCode() async throws {
        let invocation = CommandInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf output; printf error >&2; exit 7"],
            timeoutSeconds: 5
        )

        let result = try await ProcessCommandExecutor().execute(invocation)
        XCTAssertEqual(result.standardOutput, "output")
        XCTAssertEqual(result.standardError, "error")
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertFalse(result.succeeded)
        XCTAssertGreaterThanOrEqual(result.durationSeconds, 0)
    }

    func testProcessExecutorTimesOut() async {
        let invocation = CommandInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            timeoutSeconds: 0.1
        )

        do {
            _ = try await ProcessCommandExecutor().execute(invocation)
            XCTFail("Expected a timeout")
        } catch let error as CommandExecutionError {
            guard case .timedOut = error else {
                return XCTFail("Unexpected execution error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
