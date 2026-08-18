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
        )
    ],
    targets: [
        .executableTarget(
            name: "HermesUsageMonitorApp"
        )
    ]
)
