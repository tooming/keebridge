// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Single source of truth for identifiers shared across the KeeBridge app,
// the KeeBridgeProvider extension, and project.yml (which must be kept in
// sync with these strings by hand — Xcode entitlements/Info.plist can't
// reference Swift constants).
//
// Deliberately has NO shared Keychain access group and NO App Group: this
// Apple Developer team's automatic provisioning doesn't actually grant
// either (confirmed by inspecting the real embedded provisioning profiles
// — `com.apple.security.application-groups` was silently absent from both
// targets' granted entitlements despite being requested locally, and
// Keychain Sharing's wildcard grant didn't work in practice either). Rather
// than chase that further, the app and extension are fully independent:
// each manages its own local, unshared Keychain cache (prompting for the
// master password itself the first time it needs it), and the vault file
// reaches the sandboxed extension by the unsandboxed app writing directly
// into the extension's own sandbox container — no entitlement needed for
// that at all, since sandboxing restricts what the sandboxed process
// itself can reach, not what another same-user process writes into its
// container directory.

import Foundation

public enum KeeBridgeConfig {
    public static let keychainService = "com.martintooming.keebridge.vaultkey"

    /// Fixed Keychain "account" string for the single personal vault this
    /// app manages — there's only ever one vault, so this doesn't need to
    /// vary per-vault the way a multi-database manager would need it to.
    public static let vaultKeychainAccount = "personal-vault"

    /// Must match KeeBridgeProvider's PRODUCT_BUNDLE_IDENTIFIER in
    /// project.yml.
    public static let providerBundleID = "com.martintooming.KeeBridge.Provider"

    public static let vaultMirrorFilename = "vault.kdbx"

    /// Where the (unsandboxed) app writes the vault mirror: the
    /// extension's own sandbox container, computed from the real user
    /// home directory. Only valid when called from the unsandboxed app —
    /// see `vaultMirrorURLForExtension()` for the extension's own side.
    public static func vaultMirrorURLForApp() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/\(providerBundleID)/Data/\(vaultMirrorFilename)")
    }

    /// Where the (sandboxed) extension reads the vault mirror from: its
    /// own container root. `NSHomeDirectory()` is transparently redirected
    /// by the sandbox to the container path when called from inside a
    /// sandboxed process — this is NOT the same value `vaultMirrorURLForApp`
    /// would compute if called from the app (there, it's the real user
    /// home). Only valid when called from the extension.
    public static func vaultMirrorURLForExtension() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(vaultMirrorFilename)
    }

    /// Sidecar file, next to the mirror, recording the modification date
    /// of the mirror AT THE MOMENT the app itself last wrote it. Lets the
    /// app tell "the mirror is exactly what I last wrote" apart from
    /// "something else (the `KeeBridgeProvider` extension, or manual
    /// meddling) touched it since" — see
    /// `docs/done/2026-08-31-passkey-registration-write-path-spike.md` for
    /// why that distinction matters: the extension's mirror write (a
    /// freshly-registered passkey, once registration exists) must be
    /// merged back into the real vault before the app's next overwrite of
    /// the mirror, or it's lost. Only valid when called from the
    /// unsandboxed app, same as `vaultMirrorURLForApp()`.
    public static func vaultMirrorLastWriteMarkerURLForApp() -> URL {
        vaultMirrorURLForApp().deletingLastPathComponent()
            .appendingPathComponent("\(vaultMirrorFilename).last-app-write")
    }
}
