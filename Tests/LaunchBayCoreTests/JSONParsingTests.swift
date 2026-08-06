import Foundation
import XCTest

@testable import LaunchBayCore

final class JSONParsingTests: XCTestCase, @unchecked Sendable {
    func testParsesCurrentContainerListPayload() throws {
        let json = #"""
            [
              {
                "id": "web",
                "configuration": {
                  "id": "web",
                  "image": {
                    "reference": "docker.io/library/nginx:latest",
                    "descriptor": {"digest": "sha256:abc", "mediaType": "application/vnd.oci.image.index.v1+json", "size": 1}
                  },
                  "publishedPorts": [
                    {"hostAddress": "127.0.0.1", "hostPort": 8080, "containerPort": 80, "protocol": "tcp"}
                  ],
                  "labels": {"com.example.owner": "launchbay"},
                  "initProcess": {"executable": "/docker-entrypoint.sh", "arguments": ["nginx", "-g", "daemon off;"]},
                  "resources": {"cpus": 2, "memoryInBytes": 1073741824},
                  "creationDate": "2026-08-05T01:02:03Z"
                },
                "status": {
                  "state": "running",
                  "networks": [{"network": "default", "address": "192.168.64.3"}],
                  "startedDate": "2026-08-05T01:03:03.123Z"
                },
                "futureField": {"safeToIgnore": true}
              }
            ]
            """#

        let containers = try ContainerJSONParser.parseContainers(json)

        XCTAssertEqual(containers.count, 1)
        let container = try XCTUnwrap(containers.first)
        XCTAssertEqual(container.id, "web")
        XCTAssertEqual(container.name, "web")
        XCTAssertEqual(container.imageReference, "docker.io/library/nginx:latest")
        XCTAssertEqual(container.state, .running)
        XCTAssertEqual(container.command, ["/docker-entrypoint.sh", "nginx", "-g", "daemon off;"])
        XCTAssertEqual(container.publishedPorts.first?.displayValue, "127.0.0.1:8080 → 80/tcp")
        XCTAssertEqual(container.addresses, ["192.168.64.3"])
        XCTAssertEqual(container.cpuCount, 2)
        XCTAssertEqual(container.memoryBytes, 1_073_741_824)
        XCTAssertEqual(container.labels["com.example.owner"], "launchbay")
        XCTAssertNotNil(container.createdAt)
        XCTAssertNotNil(container.startedAt)
    }

    func testParsesAlternativePortAndNetworkKeys() throws {
        let json = #"""
            [{
              "configuration": {
                "id": "compat",
                "image": {"name": "alpine:latest"},
                "publishedPorts": [{"hostIP": "0.0.0.0", "hostPort": "2222", "guestPort": 22, "proto": "TCP"}],
                "initProcess": {"command": "/bin/sh", "args": ["-c", "sleep 100"]}
              },
              "status": {"state": "stopped", "networks": [{"attachment": {"ipv4Address": "10.0.0.8"}}]}
            }]
            """#

        let container = try XCTUnwrap(ContainerJSONParser.parseContainers(json).first)
        XCTAssertEqual(container.id, "compat")
        XCTAssertEqual(container.imageReference, "alpine:latest")
        XCTAssertEqual(container.state, .stopped)
        XCTAssertEqual(container.publishedPorts.first?.hostPort, 2222)
        XCTAssertEqual(container.publishedPorts.first?.containerPort, 22)
        XCTAssertEqual(container.publishedPorts.first?.protocolName, "tcp")
        XCTAssertEqual(container.addresses, ["10.0.0.8"])
    }

    func testParsesCurrentImageListPayload() throws {
        let json = #"""
            [{
              "id": "0123456789abcdef",
              "configuration": {
                "creationDate": "2026-08-04T11:12:13Z",
                "name": "docker.io/library/alpine:3.22",
                "descriptor": {"digest": "sha256:0123456789abcdef", "mediaType": "application/vnd.oci.image.index.v1+json", "size": 123}
              },
              "variants": [{
                "platform": {"os": "linux", "architecture": "arm64", "variant": "v8"},
                "digest": "sha256:variant",
                "size": 8246337,
                "config": {"created": "2026-07-30T03:04:05.123Z"}
              }]
            }]
            """#

        let images = try ContainerJSONParser.parseImages(json)

        XCTAssertEqual(images.count, 1)
        let image = try XCTUnwrap(images.first)
        XCTAssertEqual(image.id, "0123456789abcdef")
        XCTAssertEqual(image.reference, "docker.io/library/alpine:3.22")
        XCTAssertEqual(image.digest, "sha256:0123456789abcdef")
        XCTAssertEqual(image.totalSizeBytes, 8_246_337)
        XCTAssertEqual(image.platforms.first?.displayName, "linux/arm64/v8")
        XCTAssertEqual(image.platforms.first?.digest, "sha256:variant")
    }

    func testDerivesImageIDFromDigest() throws {
        let json = #"""
            [{"configuration":{"name":"demo:latest","descriptor":{"digest":"sha256:deadbeef"}},"variants":[]}]
            """#
        let image = try XCTUnwrap(ContainerJSONParser.parseImages(json).first)
        XCTAssertEqual(image.id, "deadbeef")
    }

    func testParsesSystemStatusEvenWhenFutureFieldsExist() throws {
        let json = #"""
            {
              "status": "running",
              "appRoot": "/Users/natan/Library/Application Support/com.apple.container",
              "installRoot": "/usr/local/libexec/container",
              "logRoot": "/Users/natan/Library/Logs/container",
              "apiServerVersion": "0.8.0",
              "apiServerCommit": "abc123",
              "apiServerBuild": "release",
              "apiServerAppName": "container-apiserver",
              "future": true
            }
            """#

        let status = try ContainerJSONParser.parseSystemStatus(json)
        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.version, "0.8.0")
        XCTAssertEqual(status.commit, "abc123")
        XCTAssertEqual(status.build, "release")
        XCTAssertEqual(status.installRoot, "/usr/local/libexec/container")
    }

    func testRejectsWrongTopLevelShape() {
        XCTAssertThrowsError(try ContainerJSONParser.parseContainers("{}")) { error in
            guard case ContainerJSONParsingError.invalidTopLevel = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsMissingRequiredContainerID() {
        XCTAssertThrowsError(try ContainerJSONParser.parseContainers("[{\"configuration\":{}}]")) {
            error in
            XCTAssertEqual(
                error.localizedDescription,
                "A container record is missing required field “id”."
            )
        }
    }

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(try ContainerJSONParser.parseImages("[")) { error in
            guard case ContainerJSONParsingError.malformedJSON = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
