import Foundation

public enum ContainerRuntimeState: String, Codable, CaseIterable, Sendable {
    case unknown
    case stopped
    case running
    case stopping

    public init(cliValue: String?) {
        self = ContainerRuntimeState(rawValue: cliValue?.lowercased() ?? "") ?? .unknown
    }
}

public struct PublishedPort: Identifiable, Hashable, Codable, Sendable {
    public let hostAddress: String?
    public let hostPort: Int?
    public let containerPort: Int?
    public let protocolName: String

    public var id: String {
        "\(hostAddress ?? ""):\(hostPort.map(String.init) ?? ""):\(containerPort.map(String.init) ?? "")/\(protocolName)"
    }

    public var displayValue: String {
        let host = [hostAddress, hostPort.map(String.init)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        let target = containerPort.map(String.init) ?? "?"
        return host.isEmpty ? "\(target)/\(protocolName)" : "\(host) → \(target)/\(protocolName)"
    }

    public init(
        hostAddress: String? = nil,
        hostPort: Int? = nil,
        containerPort: Int? = nil,
        protocolName: String = "tcp"
    ) {
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.protocolName = protocolName
    }
}

public struct ContainerSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let imageReference: String
    public let state: ContainerRuntimeState
    public let createdAt: Date?
    public let startedAt: Date?
    public let command: [String]
    public let publishedPorts: [PublishedPort]
    public let addresses: [String]
    public let cpuCount: Int?
    public let memoryBytes: UInt64?
    public let labels: [String: String]

    public init(
        id: String,
        name: String,
        imageReference: String,
        state: ContainerRuntimeState,
        createdAt: Date? = nil,
        startedAt: Date? = nil,
        command: [String] = [],
        publishedPorts: [PublishedPort] = [],
        addresses: [String] = [],
        cpuCount: Int? = nil,
        memoryBytes: UInt64? = nil,
        labels: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.imageReference = imageReference
        self.state = state
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.command = command
        self.publishedPorts = publishedPorts
        self.addresses = addresses
        self.cpuCount = cpuCount
        self.memoryBytes = memoryBytes
        self.labels = labels
    }
}

public struct ImagePlatform: Identifiable, Hashable, Codable, Sendable {
    public let operatingSystem: String
    public let architecture: String
    public let variant: String?
    public let sizeBytes: Int64?
    public let digest: String?
    public let createdAt: Date?

    public var id: String {
        [operatingSystem, architecture, variant ?? "", digest ?? ""].joined(separator: "/")
    }

    public var displayName: String {
        [operatingSystem, architecture, variant]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    public init(
        operatingSystem: String,
        architecture: String,
        variant: String? = nil,
        sizeBytes: Int64? = nil,
        digest: String? = nil,
        createdAt: Date? = nil
    ) {
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.variant = variant
        self.sizeBytes = sizeBytes
        self.digest = digest
        self.createdAt = createdAt
    }
}

public struct ImageSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let reference: String
    public let digest: String
    public let createdAt: Date?
    public let platforms: [ImagePlatform]

    public var totalSizeBytes: Int64? {
        let sizes = platforms.compactMap(\.sizeBytes)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    public init(
        id: String,
        reference: String,
        digest: String,
        createdAt: Date? = nil,
        platforms: [ImagePlatform] = []
    ) {
        self.id = id
        self.reference = reference
        self.digest = digest
        self.createdAt = createdAt
        self.platforms = platforms
    }
}

public enum ContainerSystemState: String, Codable, Sendable {
    case running
    case notRunning = "not running"
    case unregistered
    case unavailable
    case unknown

    public init(cliValue: String?) {
        self = ContainerSystemState(rawValue: cliValue?.lowercased() ?? "") ?? .unknown
    }
}

public struct ContainerSystemStatus: Hashable, Codable, Sendable {
    public let state: ContainerSystemState
    public let appRoot: String?
    public let installRoot: String?
    public let logRoot: String?
    public let version: String?
    public let commit: String?
    public let build: String?

    public static let unavailable = ContainerSystemStatus(state: .unavailable)

    public init(
        state: ContainerSystemState,
        appRoot: String? = nil,
        installRoot: String? = nil,
        logRoot: String? = nil,
        version: String? = nil,
        commit: String? = nil,
        build: String? = nil
    ) {
        self.state = state
        self.appRoot = appRoot
        self.installRoot = installRoot
        self.logRoot = logRoot
        self.version = version
        self.commit = commit
        self.build = build
    }
}

public struct PortMapping: Identifiable, Hashable, Codable, Sendable {
    public enum Transport: String, CaseIterable, Codable, Sendable {
        case tcp
        case udp
    }

    public var id: UUID
    public var hostAddress: String
    public var hostPort: Int
    public var containerPort: Int
    public var transport: Transport

    public var cliValue: String {
        let address = hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = address.isEmpty ? "" : "\(address):"
        return "\(prefix)\(hostPort):\(containerPort)/\(transport.rawValue)"
    }

    public init(
        id: UUID = UUID(),
        hostAddress: String = "127.0.0.1",
        hostPort: Int = 8080,
        containerPort: Int = 80,
        transport: Transport = .tcp
    ) {
        self.id = id
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.transport = transport
    }
}

public struct VolumeMapping: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var source: String
    public var target: String
    public var readOnly: Bool

    public var cliValue: String {
        "\(source):\(target)\(readOnly ? ":ro" : "")"
    }

    public init(id: UUID = UUID(), source: String = "", target: String = "", readOnly: Bool = false) {
        self.id = id
        self.source = source
        self.target = target
        self.readOnly = readOnly
    }
}

public struct EnvironmentVariable: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

public struct RunContainerConfiguration: Hashable, Codable, Sendable {
    public var imageReference: String
    public var name: String
    public var command: [String]
    public var ports: [PortMapping]
    public var volumes: [VolumeMapping]
    public var environment: [EnvironmentVariable]
    public var cpuCount: Int?
    public var memory: String?
    public var removeWhenStopped: Bool
    public var useInit: Bool
    public var enableRosetta: Bool
    public var readOnlyRootFilesystem: Bool

    public init(
        imageReference: String = "",
        name: String = "",
        command: [String] = [],
        ports: [PortMapping] = [],
        volumes: [VolumeMapping] = [],
        environment: [EnvironmentVariable] = [],
        cpuCount: Int? = nil,
        memory: String? = nil,
        removeWhenStopped: Bool = false,
        useInit: Bool = true,
        enableRosetta: Bool = false,
        readOnlyRootFilesystem: Bool = false
    ) {
        self.imageReference = imageReference
        self.name = name
        self.command = command
        self.ports = ports
        self.volumes = volumes
        self.environment = environment
        self.cpuCount = cpuCount
        self.memory = memory
        self.removeWhenStopped = removeWhenStopped
        self.useInit = useInit
        self.enableRosetta = enableRosetta
        self.readOnlyRootFilesystem = readOnlyRootFilesystem
    }
}

public struct BuildImageConfiguration: Hashable, Codable, Sendable {
    public var contextPath: String
    public var dockerfilePath: String?
    public var tag: String
    public var platform: String?
    public var pullBaseImages: Bool
    public var noCache: Bool

    public init(
        contextPath: String = "",
        dockerfilePath: String? = nil,
        tag: String = "",
        platform: String? = nil,
        pullBaseImages: Bool = false,
        noCache: Bool = false
    ) {
        self.contextPath = contextPath
        self.dockerfilePath = dockerfilePath
        self.tag = tag
        self.platform = platform
        self.pullBaseImages = pullBaseImages
        self.noCache = noCache
    }
}
