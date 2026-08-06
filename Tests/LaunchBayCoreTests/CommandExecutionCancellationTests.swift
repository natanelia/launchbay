import Foundation
import XCTest

@testable import LaunchBayCore

final class CommandExecutionCancellationTests: XCTestCase, @unchecked Sendable {
    func testProcessExecutorTerminatesCommandWhenTaskIsCancelled() async throws {
        let shell = URL(fileURLWithPath: "/bin/sh")
        guard FileManager.default.isExecutableFile(atPath: shell.path) else {
            throw XCTSkip("The test requires /bin/sh")
        }

        let executor = ProcessCommandExecutor()
        let invocation = CommandInvocation(
            executableURL: shell,
            arguments: ["-c", "while :; do :; done"],
            timeoutSeconds: 30
        )
        let start = ContinuousClock.now
        let task = Task { try await executor.execute(invocation) }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected command execution to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        let elapsed = start.duration(to: .now)
        XCTAssertLessThan(elapsed, .seconds(2))
    }
}
