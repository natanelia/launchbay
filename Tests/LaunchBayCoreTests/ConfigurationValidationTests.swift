import XCTest

@testable import LaunchBayCore

final class ConfigurationValidationTests: XCTestCase, @unchecked Sendable {
    func testAcceptsFullRunConfiguration() throws {
        let configuration = RunContainerConfiguration(
            imageReference: "nginx:latest",
            name: "web.frontend-1",
            command: ["nginx", "-g", "daemon off;"],
            ports: [PortMapping(hostAddress: "127.0.0.1", hostPort: 8080, containerPort: 80)],
            volumes: [
                VolumeMapping(source: "/tmp/site", target: "/usr/share/nginx/html", readOnly: true)
            ],
            environment: [EnvironmentVariable(key: "NODE_ENV", value: "production")],
            cpuCount: 2,
            memory: "1GB",
            removeWhenStopped: false,
            useInit: true,
            enableRosetta: false,
            readOnlyRootFilesystem: true
        )

        XCTAssertNoThrow(try ConfigurationValidator.validate(configuration))
    }

    func testRejectsMissingImage() {
        assertRunError(RunContainerConfiguration(), equals: .missingImage)
    }

    func testRejectsSingleCharacterNameToMatchAppleCLI() {
        var configuration = RunContainerConfiguration(imageReference: "alpine")
        configuration.name = "x"
        assertRunError(configuration, equals: .invalidName("x"))
    }

    func testRejectsInvalidPort() {
        var configuration = RunContainerConfiguration(imageReference: "alpine")
        configuration.ports = [PortMapping(hostPort: 0, containerPort: 80)]
        assertRunError(configuration, equals: .invalidPort("127.0.0.1:0:80/tcp"))
    }

    func testRejectsRelativeContainerVolumeTarget() {
        var configuration = RunContainerConfiguration(imageReference: "alpine")
        configuration.volumes = [VolumeMapping(source: "/tmp", target: "work")]
        assertRunError(configuration, equals: .invalidVolume("/tmp:work"))
    }

    func testRejectsInvalidEnvironmentKey() {
        var configuration = RunContainerConfiguration(imageReference: "alpine")
        configuration.environment = [EnvironmentVariable(key: "NOT-VALID", value: "secret")]
        assertRunError(configuration, equals: .invalidEnvironmentKey("NOT-VALID"))
    }

    func testRejectsInvalidMemory() {
        var configuration = RunContainerConfiguration(imageReference: "alpine")
        configuration.memory = "1.5G"
        assertRunError(configuration, equals: .invalidMemory("1.5G"))
    }

    func testBuildValidation() {
        XCTAssertThrowsError(try ConfigurationValidator.validate(BuildImageConfiguration())) { error in
            XCTAssertEqual(error as? ContainerConfigurationError, .missingBuildContext)
        }
        XCTAssertThrowsError(
            try ConfigurationValidator.validate(BuildImageConfiguration(contextPath: "/tmp/context"))
        ) { error in
            XCTAssertEqual(error as? ContainerConfigurationError, .missingBuildTag)
        }
        XCTAssertNoThrow(
            try ConfigurationValidator.validate(
                BuildImageConfiguration(contextPath: "/tmp/context", tag: "demo:latest")
            )
        )
    }

    private func assertRunError(
        _ configuration: RunContainerConfiguration,
        equals expected: ContainerConfigurationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try ConfigurationValidator.validate(configuration), file: file, line: line) { error in
            XCTAssertEqual(error as? ContainerConfigurationError, expected, file: file, line: line)
        }
    }
}
