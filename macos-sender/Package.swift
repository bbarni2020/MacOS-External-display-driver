// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VirtualDisplaySender",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "VirtualDisplaySender",
            targets: ["VirtualDisplaySender"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "VirtualDisplaySender",
            dependencies: [],
            path: "Sources"
        )
    ]
)
