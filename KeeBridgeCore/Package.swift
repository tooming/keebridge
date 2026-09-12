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
        // Points at a personal fork, not upstream `shadone/KDBXKit`, to carry one patch
        // upstream hasn't taken: widening KDBXKit's *own* swift-crypto constraint from
        // `from: "3.0.0"` (SwiftPM: `>=3.0.0, <4.0.0`) to `"3.0.0"..<"5.0.0"`. SwiftPM
        // resolves the intersection of every manifest's constraint across the whole
        // graph, so no matter how wide this repo's own two manifests go (see the
        // swift-crypto line below), KDBXKit's own narrower cap held the entire build
        // below swift-crypto 4.0.0 regardless — see #89 (closed 2026-09-12 as
        // blocked-upstream) and ROADMAP.md's swift-crypto bullet for the full trail.
        // Filed shadone/KDBXKit#5 (issue) and #6 (PR, this exact one-line diff) upstream
        // 2026-09-09; both closed 2026-09-12 in favor of this fork instead of waiting on
        // a maintainer response — reopen that path and drop the fork if upstream ever
        // merges the equivalent change.
        //
        // The pinned revision is the fork's `widen-swift-crypto-constraint` branch HEAD,
        // which is exactly the *previous* pin (`e9b8839f...`, upstream `develop`'s HEAD
        // as of 2026-09-08) plus only that one dependency-constraint line — not a
        // downgrade or a drift from whatever else upstream `develop` contains.
        .package(
            url: "https://github.com/tooming/KDBXKit.git",
            revision: "b010359337fef293a4a5138faba1fdf37839976f"
        ),
        // `"3.0.0"..<"5.0.0"`, not `from: "3.0.0"` (SwiftPM: `>=3.0.0, <4.0.0`, never
        // floats across a major version) — confirmed with upstream swift-crypto's own
        // README that 4.0.0's only breaking change vs. 1.x/2.x/3.x is new cases added to
        // `CryptoError`, and this codebase never exhaustively switches over that type
        // (verified: zero matches for `CryptoError` outside this codebase's own
        // `PasskeyCryptoError`). This range alone couldn't actually resolve to 4.x until
        // the KDBXKit fork above also widened — see that comment. See ROADMAP.md's
        // "Done" section for the investigation this bump is based on.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
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
