import Foundation

/// Adapts background refresh frequency to the amount of state that can actually change.
public struct RefreshCadence: Hashable, Sendable {
    public var idleRunningFloor: TimeInterval
    public var stoppedFloor: TimeInterval

    public init(
        idleRunningFloor: TimeInterval = 15,
        stoppedFloor: TimeInterval = 30
    ) {
        self.idleRunningFloor = max(0, idleRunningFloor)
        self.stoppedFloor = max(0, stoppedFloor)
    }

    public func interval(
        baseInterval: TimeInterval,
        systemState: ContainerSystemState,
        runningContainerCount: Int
    ) -> TimeInterval {
        let baseInterval = max(0, baseInterval)
        guard baseInterval > 0 else { return 0 }

        if systemState == .running {
            return runningContainerCount > 0 ? baseInterval : max(baseInterval, idleRunningFloor)
        }
        return max(baseInterval, stoppedFloor)
    }
}
