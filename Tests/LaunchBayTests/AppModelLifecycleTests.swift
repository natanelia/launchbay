#if os(macOS)
    import Foundation
    import XCTest

    @testable import LaunchBay
    @testable import LaunchBayCore

    @MainActor
    final class AppModelLifecycleTests: XCTestCase {
        func testInitialInactiveSceneBootstrapsWithoutLaunchingCLIReads() async throws {
            let executor = RoutingCommandExecutor()
            let sleepRecorder = SleepRecorder()
            let model = makeModel(
                executor: executor,
                autoRefreshSeconds: 5,
                sleepRecorder: sleepRecorder
            )

            await model.handleApplicationActive(false)
            await Task.yield()

            let invocationCount = await executor.invocationCount()
            let intervals = await sleepRecorder.intervals()
            XCTAssertEqual(invocationCount, 0)
            XCTAssertTrue(intervals.isEmpty)
            XCTAssertNil(model.scheduledAutoRefreshInterval)
        }

        func testBecomingInactiveCancelsInFlightStatusAndPreventsListLaunches() async throws {
            let executor = RoutingCommandExecutor()
            await executor.enqueue(
                .status,
                responses: [
                    .success(#"{"status":"running"}"#),
                    .success(
                        #"{"status":"running"}"#,
                        delayNanoseconds: 5_000_000_000
                    ),
                ]
            )
            await executor.enqueue(.containers, responses: [.success("[]")])
            await executor.enqueue(.images, responses: [.success("[]")])

            let model = makeModel(executor: executor, autoRefreshSeconds: 0)
            await model.handleApplicationActive(true)

            let refresh = Task { @MainActor in
                await model.refreshAll(silent: true, force: true)
            }
            await waitUntil("the delayed status read to start") {
                await executor.invocationCount(for: .status) == 2
            }

            await model.setApplicationActive(false)
            await refresh.value

            let statusCount = await executor.invocationCount(for: .status)
            let containerCount = await executor.invocationCount(for: .containers)
            let imageCount = await executor.invocationCount(for: .images)
            let cancellationCount = await executor.cancellationCount()
            XCTAssertEqual(statusCount, 2)
            XCTAssertEqual(containerCount, 1)
            XCTAssertEqual(imageCount, 1)
            XCTAssertGreaterThanOrEqual(cancellationCount, 1)
            XCTAssertNil(model.scheduledAutoRefreshInterval)
        }

        func testRuntimeStateChangeCancelsObsoleteSleepAndSchedulesActiveCadence() async throws {
            let executor = RoutingCommandExecutor()
            await executor.enqueue(
                .status,
                responses: [
                    .success(#"{"status":"not running"}"#),
                    .success(#"{"status":"running"}"#),
                ]
            )
            await executor.enqueue(.startSystem, responses: [.success("")])
            await executor.enqueue(
                .containers,
                responses: [
                    .success(
                        #"[{"id":"web","configuration":{"id":"web","image":{"reference":"nginx:latest"}},"status":{"state":"running"}}]"#
                    )
                ]
            )
            await executor.enqueue(.images, responses: [.success("[]")])
            let sleepRecorder = SleepRecorder()

            let model = makeModel(
                executor: executor,
                autoRefreshSeconds: 5,
                cachePolicy: .disabled,
                sleepRecorder: sleepRecorder
            )
            await model.handleApplicationActive(true)
            await waitUntil("the stopped-state sleep to be scheduled") {
                await sleepRecorder.intervals().count >= 1
            }
            XCTAssertEqual(model.scheduledAutoRefreshInterval, 30)

            let didStart = await model.startSystem()
            XCTAssertTrue(didStart)
            await waitUntil("the active-container sleep to be scheduled") {
                await sleepRecorder.intervals().count >= 2
            }

            let intervals = await sleepRecorder.intervals()
            let cancellationCount = await sleepRecorder.cancellationCount()
            XCTAssertEqual(intervals.prefix(2), [30, 5])
            XCTAssertGreaterThanOrEqual(cancellationCount, 1)
            XCTAssertEqual(model.scheduledAutoRefreshInterval, 5)
            await model.setApplicationActive(false)
        }

        func testRapidLifecycleTransitionsCancelEverySupersededResumeRead() async throws {
            let executor = RoutingCommandExecutor()
            await executor.enqueue(
                .status,
                responses: [
                    .success(
                        #"{"status":"running"}"#,
                        delayNanoseconds: 5_000_000_000
                    ),
                    .success(
                        #"{"status":"running"}"#,
                        delayNanoseconds: 5_000_000_000
                    ),
                ]
            )
            let model = makeModel(executor: executor, autoRefreshSeconds: 0)
            await model.handleApplicationActive(false)

            let firstResume = Task { @MainActor in
                await model.setApplicationActive(true)
            }
            await waitUntil("the first resume read to start") {
                await executor.invocationCount(for: .status) == 1
            }
            await model.setApplicationActive(false)
            await firstResume.value

            let secondResume = Task { @MainActor in
                await model.setApplicationActive(true)
            }
            await waitUntil("the second resume read to start") {
                await executor.invocationCount(for: .status) == 2
            }
            await model.setApplicationActive(false)
            await secondResume.value

            let containerCount = await executor.invocationCount(for: .containers)
            let imageCount = await executor.invocationCount(for: .images)
            let cancellationCount = await executor.cancellationCount()
            XCTAssertEqual(containerCount, 0)
            XCTAssertEqual(imageCount, 0)
            XCTAssertGreaterThanOrEqual(cancellationCount, 2)
            XCTAssertNil(model.scheduledAutoRefreshInterval)
        }
    }
#endif
