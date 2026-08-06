import XCTest

@testable import LaunchBayCore

final class RefreshCadenceTests: XCTestCase {
    func testUsesConfiguredIntervalWhileContainersAreRunning() {
        let cadence = RefreshCadence()
        XCTAssertEqual(
            cadence.interval(baseInterval: 5, systemState: .running, runningContainerCount: 2),
            5
        )
    }

    func testBacksOffWhenSystemIsRunningButIdle() {
        let cadence = RefreshCadence()
        XCTAssertEqual(
            cadence.interval(baseInterval: 5, systemState: .running, runningContainerCount: 0),
            15
        )
    }

    func testBacksOffFurtherWhenSystemIsStopped() {
        let cadence = RefreshCadence()
        XCTAssertEqual(
            cadence.interval(baseInterval: 5, systemState: .notRunning, runningContainerCount: 0),
            30
        )
    }

    func testNeverRefreshesFasterThanUserConfiguredInterval() {
        let cadence = RefreshCadence()
        XCTAssertEqual(
            cadence.interval(baseInterval: 60, systemState: .notRunning, runningContainerCount: 0),
            60
        )
    }

    func testZeroDisablesRefresh() {
        let cadence = RefreshCadence()
        XCTAssertEqual(
            cadence.interval(baseInterval: 0, systemState: .running, runningContainerCount: 1),
            0
        )
    }
}
