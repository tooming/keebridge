// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeeBridgeCore",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "KeeBridgeCore",
            targets: ["KeeBridgeCore"]
        ),
    ],
    dependencies: [
        // KDBXKit has no tagged release yet (checked 2026-08-07: zero tags,
        // single `develop` branch). Pinning to a specific revision rather
        // than `branch:` so this doesn't silently float to a future commit.
        .package(
            url: "https://github.com/shadone/KDBXKit.git",
            revision: "e9b8839f1226b82665e1e4b7f12f13635d189deb"
        ),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "KeeBridgeCore",
            dependencies: [
                .product(name: "KDBXKit", package: "KDBXKit"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "KeeBridgeCoreTests",
            dependencies: [
                "KeeBridgeCore",
                // Needed only to construct a passkey-bearing KDBX.Entry
                // directly in PasskeyTests.swift (via KDBXKit's own
                // KeePassXC-compatible setPasskey* methods), ahead of
                // VaultService having any write-side passkey API of its own.
                .product(name: "KDBXKit", package: "KDBXKit"),
                // Needed only in PasskeyCryptoTests.swift, to independently
                // verify a PasskeyCrypto-produced signature against the
                // matching public key — PasskeyCrypto itself only signs,
                // it deliberately doesn't expose a verify() (KeeBridge is
                // the authenticator, not the relying party that verifies).
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
    ]
)
