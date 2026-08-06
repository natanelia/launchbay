import Foundation

/// Controls how long low-volatility `container` CLI reads can be reused.
///
/// A zero duration disables result caching for that read while still allowing concurrent identical
/// requests to share one in-flight CLI process.
public struct ContainerCLIReadCachePolicy: Hashable, Sendable {
    public var systemStatusTTL: TimeInterval
    public var containersTTL: TimeInterval
    public var imagesTTL: TimeInterval

    public init(
        systemStatusTTL: TimeInterval = 15,
        containersTTL: TimeInterval = 1,
        imagesTTL: TimeInterval = 30
    ) {
        self.systemStatusTTL = max(0, systemStatusTTL)
        self.containersTTL = max(0, containersTTL)
        self.imagesTTL = max(0, imagesTTL)
    }

    /// Tuned for an interactive desktop client: container state remains responsive while system and
    /// image metadata avoid unnecessary process launches.
    public static let interactive = ContainerCLIReadCachePolicy()

    /// Disables completed-result caching. In-flight request coalescing remains enabled.
    public static let disabled = ContainerCLIReadCachePolicy(
        systemStatusTTL: 0,
        containersTTL: 0,
        imagesTTL: 0
    )
}
