import Foundation

public struct ContainerExecutableLocator: Sendable {
    public let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func locate(explicitPath: String? = nil) -> URL? {
        var candidates: [String] = []

        if let explicitPath, !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append((explicitPath as NSString).expandingTildeInPath)
        }
        if let configured = environment["CONTAINER_CLI_PATH"], !configured.isEmpty {
            candidates.append((configured as NSString).expandingTildeInPath)
        }

        candidates.append(contentsOf: [
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container",
            "/usr/bin/container",
        ])

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/container" })
        }

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
