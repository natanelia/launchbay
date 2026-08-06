#if os(macOS)
    import Foundation
    import XCTest

    @testable import LaunchBay
    @testable import LaunchBayCore

    @MainActor
    final class AppModelRefreshTests: XCTestCase {
        func testNewerForcedRefreshWinsAndOwnsVisibleProgress() async throws {
            let executor = RoutingCommandExecutor()
            await executor.enqueue(
                .status,
                responses: [
                    .success(#"{"status":"not running"}"#),
                    .success(
                        #"{"status":"not running"}"#,
                        delayNanoseconds: 5_000_000_000
                    ),
                    .success(#"{"status":"running"}"#),
                ]
            )
            await executor.enqueue(
                .containers,
                responses: [
                    .success(
                        #"[{"id":"web","configuration":{"id":"web","image":{"reference":"nginx:latest"}},"status":{"state":"running"}}]"#
                    )
                ]
            )
            await executor.enqueue(.images, responses: [.success("[]")])
            let model = makeModel(executor: executor, autoRefreshSeconds: 0)
            await model.handleApplicationActive(true)

            let olderRefresh = Task { @MainActor in
                await model.refreshAll(force: true)
            }
            await waitUntil("the older refresh to block") {
                await executor.invocationCount(for: .status) == 2
            }

            await model.refreshAll(force: true)
            await olderRefresh.value

            XCTAssertEqual(model.systemStatus.state, .running)
            XCTAssertEqual(model.containers.map(\.id), ["web"])
            XCTAssertFalse(model.isRefreshing)
            let cancellationCount = await executor.cancellationCount()
            XCTAssertGreaterThanOrEqual(cancellationCount, 1)
            await model.setApplicationActive(false)
        }

        func testFailedMutationStillRefreshesInvalidatedContainerState() async throws {
            let oldPayload =
                #"[{"id":"old","configuration":{"id":"old","image":{"reference":"old:latest"}},"status":{"state":"stopped"}}]"#
            let freshPayload =
                #"[{"id":"fresh","configuration":{"id":"fresh","image":{"reference":"fresh:latest"}},"status":{"state":"running"}}]"#
            let executor = RoutingCommandExecutor()
            await executor.enqueue(.status, responses: [.success(#"{"status":"running"}"#)])
            await executor.enqueue(
                .containers,
                responses: [.success(oldPayload), .success(freshPayload)]
            )
            await executor.enqueue(.images, responses: [.success("[]")])
            await executor.enqueue(
                .startContainer,
                responses: [.failure(stderr: "start failed")]
            )

            let model = makeModel(
                executor: executor,
                autoRefreshSeconds: 0,
                cachePolicy: ContainerCLIReadCachePolicy(
                    systemStatusTTL: 60,
                    containersTTL: 60,
                    imagesTTL: 60
                )
            )
            await model.handleApplicationActive(true)
            let oldContainer = try XCTUnwrap(model.containers.first)

            let didStart = await model.startContainer(oldContainer)
            let containerReadCount = await executor.invocationCount(for: .containers)
            XCTAssertFalse(didStart)
            XCTAssertEqual(model.containers.map(\.id), ["fresh"])
            XCTAssertEqual(model.alertMessage?.title, "Start old")
            XCTAssertEqual(model.alertMessage?.message, "start failed")
            XCTAssertEqual(containerReadCount, 2)
            await model.setApplicationActive(false)
        }
    }
#endif
