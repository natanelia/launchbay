import Foundation
import XCTest

@testable import LaunchBayCore

final class ContainerExecutableLocatorTests: XCTestCase, @unchecked Sendable {
    func testExplicitPathWins() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("container-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let explicit = directory.appendingPathComponent("explicit-container")
        let fromEnvironment = directory.appendingPathComponent("environment-container")
        try "#!/bin/sh\n".write(to: explicit, atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: fromEnvironment, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: explicit.path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: fromEnvironment.path)

        let locator = ContainerExecutableLocator(environment: [
            "CONTAINER_CLI_PATH": fromEnvironment.path
        ])
        XCTAssertEqual(locator.locate(explicitPath: explicit.path), explicit)
    }

    func testSearchesPATH() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("container-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("container")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let locator = ContainerExecutableLocator(environment: ["PATH": directory.path])
        XCTAssertEqual(locator.locate(), executable)
    }

    func testIgnoresNonExecutableFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("container-nonexec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("container")
        try "not executable".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)

        let locator = ContainerExecutableLocator(environment: ["PATH": directory.path])
        XCTAssertNil(locator.locate())
    }
}
