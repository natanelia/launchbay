#if os(macOS)
    import Foundation
    import XCTest

    @testable import LaunchBay
    @testable import LaunchBayCore

    @MainActor
    func makeModel(
        executor: RoutingCommandExecutor,
        autoRefreshSeconds: Double,
        cachePolicy: ContainerCLIReadCachePolicy = .disabled,
        sleepRecorder: SleepRecorder? = nil
    ) -> AppModel {
        let suiteName = "LaunchBay.AppModelLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("/usr/bin/true", forKey: "customContainerCLIPath")
        defaults.set(autoRefreshSeconds, forKey: "autoRefreshSeconds")
        let client = ContainerCLI(
            executor: executor,
            readCachePolicy: cachePolicy
        )
        return AppModel(
            defaults: defaults,
            client: client,
            refreshSleep: { interval in
                if let sleepRecorder {
                    await sleepRecorder.record(interval)
                }
                do {
                    try await Task<Never, Never>.sleep(for: .seconds(interval))
                } catch {
                    if let sleepRecorder {
                        await sleepRecorder.recordCancellation()
                    }
                    throw error
                }
            }
        )
    }

    func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        condition: @escaping @Sendable () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for \(description)")
                return
            }
            await Task.yield()
        }
    }
    actor SleepRecorder {
        private var recordedIntervals: [TimeInterval] = []
        private var cancellations = 0

        func record(_ interval: TimeInterval) {
            recordedIntervals.append(interval)
        }

        func recordCancellation() {
            cancellations += 1
        }

        func intervals() -> [TimeInterval] {
            recordedIntervals
        }

        func cancellationCount() -> Int {
            cancellations
        }
    }

    actor RoutingCommandExecutor: CommandExecuting {
        enum CommandKind: Hashable, Sendable {
            case status
            case containers
            case images
            case startSystem
            case startContainer
            case other
        }

        struct Response: Sendable {
            let stdout: String
            let stderr: String
            let exitCode: Int32
            let delayNanoseconds: UInt64

            static func success(
                _ stdout: String,
                delayNanoseconds: UInt64 = 0
            ) -> Response {
                Response(
                    stdout: stdout,
                    stderr: "",
                    exitCode: 0,
                    delayNanoseconds: delayNanoseconds
                )
            }

            static func failure(stderr: String) -> Response {
                Response(stdout: "", stderr: stderr, exitCode: 1, delayNanoseconds: 0)
            }
        }

        enum StubError: Error, Sendable {
            case missingResponse(CommandKind)
        }

        private var responses: [CommandKind: [Response]] = [:]
        private var invocations: [CommandKind: [CommandInvocation]] = [:]
        private var cancellations = 0

        func enqueue(_ kind: CommandKind, responses newResponses: [Response]) {
            responses[kind, default: []].append(contentsOf: newResponses)
        }

        func execute(_ invocation: CommandInvocation) async throws -> CommandResult {
            let kind = Self.kind(for: invocation.arguments)
            invocations[kind, default: []].append(invocation)
            guard var queue = responses[kind], !queue.isEmpty else {
                throw StubError.missingResponse(kind)
            }
            let response = queue.removeFirst()
            responses[kind] = queue

            if response.delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: response.delayNanoseconds)
                } catch {
                    cancellations += 1
                    throw error
                }
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
            invocations.values.reduce(0) { $0 + $1.count }
        }

        func invocationCount(for kind: CommandKind) -> Int {
            invocations[kind]?.count ?? 0
        }

        func cancellationCount() -> Int {
            cancellations
        }

        private static func kind(for arguments: [String]) -> CommandKind {
            if arguments == ["system", "status", "--format", "json"] {
                return .status
            }
            if arguments == ["list", "--all", "--format", "json"] {
                return .containers
            }
            if arguments == ["image", "list", "--format", "json"] {
                return .images
            }
            if arguments == ["system", "start"] {
                return .startSystem
            }
            if arguments.count == 2, arguments.first == "start" {
                return .startContainer
            }
            return .other
        }
    }
#endif
