// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VaultProbe",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "../KeeBridgeCore"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "VaultProbe",
            dependencies: [
                "KeeBridgeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
