// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LaunchBay",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "LaunchBayCore",
            targets: ["LaunchBayCore"]
        ),
        .executable(
            name: "LaunchBay",
            targets: ["LaunchBay"]
        ),
    ],
    targets: [
        .target(
            name: "LaunchBayCore"
        ),
        .executableTarget(
            name: "LaunchBay",
            dependencies: ["LaunchBayCore"]
        ),
        .testTarget(
            name: "LaunchBayCoreTests",
            dependencies: ["LaunchBayCore"]
        ),
    ]
)
