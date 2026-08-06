import Foundation

public struct HostCompatibility: Hashable, Codable, Sendable {
    public let isMacOS: Bool
    public let isAppleSilicon: Bool
    public let operatingSystemVersion: OperatingSystemVersion

    public var supportsAppleContainerRuntime: Bool {
        isMacOS && isAppleSilicon && operatingSystemVersion.majorVersion >= 26
    }

    public init(
        isMacOS: Bool,
        isAppleSilicon: Bool,
        operatingSystemVersion: OperatingSystemVersion
    ) {
        self.isMacOS = isMacOS
        self.isAppleSilicon = isAppleSilicon
        self.operatingSystemVersion = operatingSystemVersion
    }

    public static func detect() -> HostCompatibility {
        #if os(macOS)
            let isMacOS = true
        #else
            let isMacOS = false
        #endif

        #if arch(arm64)
            let isAppleSilicon = true
        #else
            let isAppleSilicon = false
        #endif

        return HostCompatibility(
            isMacOS: isMacOS,
            isAppleSilicon: isAppleSilicon,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
    }
}
