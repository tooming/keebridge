// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// KeeBridgeConfig's URL-computing functions had no test coverage at all
// (confirmed via grep across the whole test suite) despite being the single
// source of truth for every mirror-file path VaultController,
// CredentialProviderViewController, and SafariWebExtensionHandler read from
// or write to — a wrong path here would silently break mirror sync in a way
// none of those callers' own tests would catch, since they'd all agree with
// each other and just point at the wrong place. These are pure functions
// (the only external input is `NSHomeDirectory()`, which resolves to
// whatever this process's home directory happens to be — CI's included —
// so these tests check the *relative* structure appended onto that root,
// not the root itself, matching how the functions are actually consumed:
// callers only ever care about the path relative to home).

import Foundation
import Testing
@testable import KeeBridgeCore

@Test func vaultMirrorURLForAppUsesProviderContainer() {
    let url = KeeBridgeConfig.vaultMirrorURLForApp()
    #expect(url.lastPathComponent == "vault.kdbx")
    #expect(url.deletingLastPathComponent().lastPathComponent == "Data")
    #expect(
        url.path.hasSuffix(
            "Library/Containers/com.martintooming.KeeBridge.Provider/Data/vault.kdbx"
        )
    )
}

@Test func cardVaultMirrorURLForAppUsesCardExtensionContainer() {
    let url = KeeBridgeConfig.cardVaultMirrorURLForApp()
    #expect(url.lastPathComponent == "vault.kdbx")
    #expect(
        url.path.hasSuffix(
            "Library/Containers/com.martintooming.KeeBridge.CardExtension/Data/vault.kdbx"
        )
    )
}

@Test func vaultMirrorURLForAppAndCardVaultMirrorURLForAppDivergeByBundleID() {
    // Both go through the same "Library/Containers/<bundle ID>/Data/vault.kdbx"
    // shape but must land in *different* containers -- the provider's mirror
    // and the card extension's read-only mirror are deliberately kept
    // separate (see KeeBridgeConfig.swift's own doc comment: the card
    // mirror "must never participate in the credential provider's passkey
    // write-back merge"). A copy-paste bug swapping the two bundle IDs
    // would make both functions return the same URL.
    let providerURL = KeeBridgeConfig.vaultMirrorURLForApp()
    let cardURL = KeeBridgeConfig.cardVaultMirrorURLForApp()
    #expect(providerURL != cardURL)
}

@Test func vaultMirrorURLForExtensionIsHomeDirectoryPlusFilenameOnly() {
    // Inside the sandboxed extension, NSHomeDirectory() is already redirected
    // to the container root, so this must NOT append "Library/Containers/...";
    // that Data-subdirectory shape is only correct from the app's side (see
    // vaultMirrorURLForApp above).
    let url = KeeBridgeConfig.vaultMirrorURLForExtension()
    #expect(url.lastPathComponent == "vault.kdbx")
    #expect(
        url.deletingLastPathComponent().path
            == URL(fileURLWithPath: NSHomeDirectory()).path
    )
}

@Test func cardVaultMirrorURLForExtensionIsHomeDirectoryPlusFilenameOnly() {
    let url = KeeBridgeConfig.cardVaultMirrorURLForExtension()
    #expect(url.lastPathComponent == "vault.kdbx")
    #expect(
        url.deletingLastPathComponent().path
            == URL(fileURLWithPath: NSHomeDirectory()).path
    )
}

@Test func vaultMirrorLastWriteMarkerURLForAppSitsBesideTheMirrorItDescribes() {
    let marker = KeeBridgeConfig.vaultMirrorLastWriteMarkerURLForApp()
    let mirror = KeeBridgeConfig.vaultMirrorURLForApp()
    #expect(marker.lastPathComponent == "vault.kdbx.last-app-write")
    // Must live in the exact same directory as the mirror it's tracking the
    // write time of -- a marker written somewhere else would silently never
    // match up with mirrorChangedSinceLastAppWrite's own read of it.
    #expect(marker.deletingLastPathComponent() == mirror.deletingLastPathComponent())
}
