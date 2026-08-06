import XCTest

@testable import LaunchBayCore

final class PollingLoadModelTests: XCTestCase {
    func testDocumentedProcessCountsAreExplicitSteadyStateModels() {
        let policy = ContainerCLIReadCachePolicy.interactive
        let cadence = RefreshCadence()

        XCTAssertEqual(
            modeledProcessLaunches(
                interval: cadence.interval(
                    baseInterval: 5,
                    systemState: .running,
                    runningContainerCount: 1
                ),
                systemRunning: true,
                cachePolicy: policy
            ),
            18
        )
        XCTAssertEqual(
            modeledProcessLaunches(
                interval: cadence.interval(
                    baseInterval: 5,
                    systemState: .running,
                    runningContainerCount: 0
                ),
                systemRunning: true,
                cachePolicy: policy
            ),
            10
        )
        XCTAssertEqual(
            modeledProcessLaunches(
                interval: cadence.interval(
                    baseInterval: 5,
                    systemState: .notRunning,
                    runningContainerCount: 0
                ),
                systemRunning: false,
                cachePolicy: policy
            ),
            2
        )
    }

    private func modeledProcessLaunches(
        interval: TimeInterval,
        systemRunning: Bool,
        cachePolicy: ContainerCLIReadCachePolicy
    ) -> Int {
        guard interval > 0 else { return 0 }
        var launches = 0
        var statusExpiry: TimeInterval = -.infinity
        var containersExpiry: TimeInterval = -.infinity
        var imagesExpiry: TimeInterval = -.infinity
        var timestamp: TimeInterval = 0

        while timestamp < 60 {
            if timestamp >= statusExpiry {
                launches += 1
                statusExpiry = timestamp + cachePolicy.systemStatusTTL
            }
            if systemRunning {
                if timestamp >= containersExpiry {
                    launches += 1
                    containersExpiry = timestamp + cachePolicy.containersTTL
                }
                if timestamp >= imagesExpiry {
                    launches += 1
                    imagesExpiry = timestamp + cachePolicy.imagesTTL
                }
            }
            timestamp += interval
        }
        return launches
    }
}
