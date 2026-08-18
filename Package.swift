// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HermesUsageMonitor",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "HermesUsageMonitor",
            targets: ["HermesUsageMonitorApp"]
        ),
        .library(
            name: "HermesUsageCore",
            targets: ["HermesUsageCore"]
        )
    ],
    targets: [
        .target(
            name: "HermesUsageCore"
        ),
        .executableTarget(
            name: "HermesUsageMonitorApp",
            dependencies: ["HermesUsageCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HermesUsageCoreTests",
            dependencies: ["HermesUsageCore"]
        ),
        .testTarget(
            name: "HermesUsageCoreIntegrationTests",
            dependencies: ["HermesUsageCore"]
        ),
        .testTarget(
            name: "HermesUsageMonitorAppTests",
            dependencies: ["HermesUsageMonitorApp"]
        )
    ]
)
