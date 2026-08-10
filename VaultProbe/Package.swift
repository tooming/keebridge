// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VaultProbe",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "../KeeBridgeCore"),
    ],
    targets: [
        .executableTarget(
            name: "VaultProbe",
            dependencies: ["KeeBridgeCore"]
        ),
    ]
)
