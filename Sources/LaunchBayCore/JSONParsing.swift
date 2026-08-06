import Foundation

public enum ContainerJSONParsingError: LocalizedError, Sendable {
    case invalidUTF8
    case invalidTopLevel(expected: String)
    case missingRequiredField(resource: String, field: String)
    case malformedJSON(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "The container CLI returned text that is not valid UTF-8."
        case .invalidTopLevel(let expected):
            "The container CLI JSON has an unexpected top-level value; expected \(expected)."
        case .missingRequiredField(let resource, let field):
            "A \(resource) record is missing required field “\(field)”."
        case .malformedJSON(let message):
            "The container CLI returned malformed JSON: \(message)"
        }
    }
}

public enum ContainerJSONParser {
    public static func parseContainers(_ text: String) throws -> [ContainerSummary] {
        let array = try parseArray(text)
        return try array.compactMap { raw in
            guard let object = raw as? JSONObject else { return nil }
            guard let id = object.string(at: ["id"]) ?? object.string(at: ["configuration", "id"]),
                !id.isEmpty
            else {
                throw ContainerJSONParsingError.missingRequiredField(resource: "container", field: "id")
            }

            let configuration = object.object(at: ["configuration"]) ?? [:]
            let status = object.object(at: ["status"]) ?? [:]
            let name = configuration.string(at: ["id"]) ?? id
            let image =
                configuration.string(at: ["image", "reference"])
                ?? configuration.string(at: ["image", "name"])
                ?? "unknown"
            let state = ContainerRuntimeState(cliValue: status.string(at: ["state"]))
            let createdAt = parseDate(configuration.string(at: ["creationDate"]))
            let startedAt = parseDate(status.string(at: ["startedDate"]))

            let initProcess = configuration.object(at: ["initProcess"]) ?? [:]
            let executable =
                initProcess.string(at: ["executable"])
                ?? initProcess.string(at: ["command"])
            var command =
                initProcess.stringArray(at: ["arguments"])
                ?? initProcess.stringArray(at: ["args"])
                ?? []
            if let executable, command.first != executable {
                command.insert(executable, at: 0)
            }

            let ports = (configuration.array(at: ["publishedPorts"]) ?? []).compactMap(parsePort)
            let addresses = collectAddresses(in: status.array(at: ["networks"]) ?? [])
            let resources = configuration.object(at: ["resources"]) ?? [:]
            let labels = configuration.stringDictionary(at: ["labels"]) ?? [:]

            return ContainerSummary(
                id: id,
                name: name,
                imageReference: image,
                state: state,
                createdAt: createdAt,
                startedAt: startedAt,
                command: command,
                publishedPorts: ports,
                addresses: addresses,
                cpuCount: resources.int(at: ["cpus"]),
                memoryBytes: resources.uint64(at: ["memoryInBytes"]),
                labels: labels
            )
        }
    }

    public static func parseImages(_ text: String) throws -> [ImageSummary] {
        let array = try parseArray(text)
        return try array.compactMap { raw in
            guard let object = raw as? JSONObject else { return nil }
            let configuration = object.object(at: ["configuration"]) ?? [:]
            let digest =
                configuration.string(at: ["descriptor", "digest"]) ?? object.string(at: ["id"]) ?? ""
            let id = object.string(at: ["id"]) ?? digest.removingDigestAlgorithm
            guard !id.isEmpty else {
                throw ContainerJSONParsingError.missingRequiredField(resource: "image", field: "id")
            }
            let reference =
                configuration.string(at: ["name"])
                ?? object.string(at: ["name"])
                ?? "<untagged>"
            let variants = (object.array(at: ["variants"]) ?? []).compactMap(parsePlatform)

            return ImageSummary(
                id: id,
                reference: reference,
                digest: digest,
                createdAt: parseDate(configuration.string(at: ["creationDate"])),
                platforms: variants
            )
        }
    }

    public static func parseSystemStatus(_ text: String) throws -> ContainerSystemStatus {
        let object = try parseObject(text)
        return ContainerSystemStatus(
            state: ContainerSystemState(cliValue: object.string(at: ["status"])),
            appRoot: object.nonEmptyString(at: ["appRoot"]),
            installRoot: object.nonEmptyString(at: ["installRoot"]),
            logRoot: object.nonEmptyString(at: ["logRoot"]),
            version: object.nonEmptyString(at: ["apiServerVersion"]),
            commit: object.nonEmptyString(at: ["apiServerCommit"]),
            build: object.nonEmptyString(at: ["apiServerBuild"])
        )
    }

    private static func parseArray(_ text: String) throws -> [Any] {
        let value = try parseJSON(text)
        guard let array = value as? [Any] else {
            throw ContainerJSONParsingError.invalidTopLevel(expected: "an array")
        }
        return array
    }

    private static func parseObject(_ text: String) throws -> JSONObject {
        let value = try parseJSON(text)
        guard let object = value as? JSONObject else {
            throw ContainerJSONParsingError.invalidTopLevel(expected: "an object")
        }
        return object
    }

    private static func parseJSON(_ text: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw ContainerJSONParsingError.invalidUTF8
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ContainerJSONParsingError.malformedJSON(error.localizedDescription)
        }
    }

    private static func parsePort(_ raw: Any) -> PublishedPort? {
        guard let object = raw as? JSONObject else { return nil }
        let hostAddress =
            object.string(at: ["hostAddress"])
            ?? object.string(at: ["hostIP"])
            ?? object.string(at: ["hostIp"])
        let hostPort = object.int(at: ["hostPort"])
        let containerPort =
            object.int(at: ["containerPort"])
            ?? object.int(at: ["guestPort"])
        let protocolName =
            object.string(at: ["protocol"])
            ?? object.string(at: ["proto"])
            ?? "tcp"
        return PublishedPort(
            hostAddress: hostAddress,
            hostPort: hostPort,
            containerPort: containerPort,
            protocolName: protocolName.lowercased()
        )
    }

    private static func parsePlatform(_ raw: Any) -> ImagePlatform? {
        guard let object = raw as? JSONObject else { return nil }
        let platform = object.object(at: ["platform"]) ?? [:]
        let os = platform.string(at: ["os"]) ?? "unknown"
        let architecture =
            platform.string(at: ["architecture"])
            ?? platform.string(at: ["arch"])
            ?? "unknown"
        let config = object.object(at: ["config"]) ?? [:]
        return ImagePlatform(
            operatingSystem: os,
            architecture: architecture,
            variant: platform.nonEmptyString(at: ["variant"]),
            sizeBytes: object.int64(at: ["size"]),
            digest: object.nonEmptyString(at: ["digest"]),
            createdAt: parseDate(config.string(at: ["created"]))
        )
    }

    private static func collectAddresses(in networks: [Any]) -> [String] {
        var addresses: [String] = []
        let interestingKeys = ["address", "ipv4Address", "ipv6Address", "ipAddress"]

        for raw in networks {
            guard let object = raw as? JSONObject else { continue }
            for key in interestingKeys {
                if let value = object.nonEmptyString(at: [key]), !addresses.contains(value) {
                    addresses.append(value)
                }
            }
            for (_, value) in object {
                if let nested = value as? JSONObject {
                    for key in interestingKeys {
                        if let address = nested.nonEmptyString(at: [key]), !addresses.contains(address) {
                            addresses.append(address)
                        }
                    }
                }
            }
        }
        return addresses
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: string) { return date }

        if let seconds = TimeInterval(string) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}

private typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    fileprivate func value(at path: [String]) -> Any? {
        var current: Any = self
        for component in path {
            guard let object = current as? JSONObject, let next = object[component] else { return nil }
            current = next
        }
        return current
    }

    fileprivate func object(at path: [String]) -> JSONObject? { value(at: path) as? JSONObject }
    fileprivate func array(at path: [String]) -> [Any]? { value(at: path) as? [Any] }

    fileprivate func string(at path: [String]) -> String? {
        if let string = value(at: path) as? String { return string }
        if let number = value(at: path) as? NSNumber { return number.stringValue }
        return nil
    }

    fileprivate func nonEmptyString(at path: [String]) -> String? {
        guard let value = string(at: path), !value.isEmpty else { return nil }
        return value
    }

    fileprivate func int(at path: [String]) -> Int? {
        if let number = value(at: path) as? NSNumber { return number.intValue }
        if let string = value(at: path) as? String { return Int(string) }
        return nil
    }

    fileprivate func int64(at path: [String]) -> Int64? {
        if let number = value(at: path) as? NSNumber { return number.int64Value }
        if let string = value(at: path) as? String { return Int64(string) }
        return nil
    }

    fileprivate func uint64(at path: [String]) -> UInt64? {
        if let number = value(at: path) as? NSNumber { return number.uint64Value }
        if let string = value(at: path) as? String { return UInt64(string) }
        return nil
    }

    fileprivate func stringArray(at path: [String]) -> [String]? {
        guard let array = value(at: path) as? [Any] else { return nil }
        return array.compactMap { $0 as? String }
    }

    fileprivate func stringDictionary(at path: [String]) -> [String: String]? {
        guard let object = value(at: path) as? JSONObject else { return nil }
        return object.reduce(into: [String: String]()) { result, item in
            if let string = item.value as? String {
                result[item.key] = string
            }
        }
    }
}

extension String {
    fileprivate var removingDigestAlgorithm: String {
        guard let index = firstIndex(of: ":") else { return self }
        return String(self[self.index(after: index)...])
    }
}
