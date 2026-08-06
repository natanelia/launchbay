import Foundation

public enum ContainerConfigurationError: LocalizedError, Equatable, Sendable {
    case missingImage
    case invalidName(String)
    case invalidPort(String)
    case invalidVolume(String)
    case invalidEnvironmentKey(String)
    case invalidMemory(String)
    case missingBuildContext
    case missingBuildTag

    public var errorDescription: String? {
        switch self {
        case .missingImage:
            "Choose an image to run."
        case .invalidName(let name):
            "“\(name)” is not a valid container name. Use 2–63 letters, numbers, dots, underscores, or hyphens, starting with a letter or number."
        case .invalidPort(let value):
            "Invalid port mapping: \(value). Ports must be between 1 and 65535."
        case .invalidVolume(let value):
            "Invalid volume mapping: \(value). Both the host source and container target are required."
        case .invalidEnvironmentKey(let key):
            "Invalid environment variable name: \(key)."
        case .invalidMemory(let memory):
            "Invalid memory limit: \(memory). Examples: 512M, 2G."
        case .missingBuildContext:
            "Choose a build context directory."
        case .missingBuildTag:
            "Enter a tag for the built image."
        }
    }
}

public enum ConfigurationValidator {
    public static func validate(_ configuration: RunContainerConfiguration) throws {
        let image = configuration.imageReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !image.isEmpty else { throw ContainerConfigurationError.missingImage }

        let name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            let pattern = #"^[A-Za-z0-9][A-Za-z0-9_.-]{1,62}$"#
            guard name.range(of: pattern, options: .regularExpression) != nil else {
                throw ContainerConfigurationError.invalidName(name)
            }
        }

        for port in configuration.ports {
            guard (1...65_535).contains(port.hostPort), (1...65_535).contains(port.containerPort) else {
                throw ContainerConfigurationError.invalidPort(port.cliValue)
            }
        }

        for volume in configuration.volumes {
            let source = volume.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = volume.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, target.hasPrefix("/") else {
                throw ContainerConfigurationError.invalidVolume(volume.cliValue)
            }
        }

        let environmentPattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#
        for variable in configuration.environment {
            guard variable.key.range(of: environmentPattern, options: .regularExpression) != nil else {
                throw ContainerConfigurationError.invalidEnvironmentKey(variable.key)
            }
        }

        if let memory = configuration.memory?.trimmingCharacters(in: .whitespacesAndNewlines),
            !memory.isEmpty
        {
            let pattern = #"^[1-9][0-9]*(?:[KMGTP](?:B)?)?$"#
            guard memory.uppercased().range(of: pattern, options: .regularExpression) != nil else {
                throw ContainerConfigurationError.invalidMemory(memory)
            }
        }
    }

    public static func validate(_ configuration: BuildImageConfiguration) throws {
        guard !configuration.contextPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContainerConfigurationError.missingBuildContext
        }
        guard !configuration.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContainerConfigurationError.missingBuildTag
        }
    }
}
