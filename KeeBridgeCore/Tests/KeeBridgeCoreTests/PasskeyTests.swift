// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Passkey metadata tests — read side (VaultService.passkeyMetadata) and
// write side (VaultService.setPasskey). The read tests build a
// passkey-bearing entry directly via KDBXKit's own KeePassXC-compatible
// setPasskey* methods, written to a temp vault the same low-level way
// VaultService's private write() does, since VaultService itself had no
// passkey write API to build one through until this file's write tests.
// Uses only synthetic data (a mock PEM string, a throwaway tempdir vault,
// the repo's standard fake password) — no real vault or credential
// material, same discipline as every other test in this package.

import Foundation
import Testing
import KDBXKit
@testable import KeeBridgeCore

private let testPassword = "hunter2"

private func tempVaultURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("keebridge-test-\(UUID().uuidString).kdbx")
}

/// Builds a vault containing one passkey-bearing entry and one plain
/// entry, written directly via KDBXKit (not through VaultService's
/// EntryDraft-shaped write API, which doesn't model passkey fields).
/// Returns the passkey entry's UUID string.
private func makeVaultWithPasskeyEntry(at url: URL) throws -> String {
    var content = KDBXContent.makeEmpty(databaseName: "Test Vault")

    let passkeyUUID = UUID()
    var passkeyEntry = KDBX.Entry(
        uuid: passkeyUUID,
        times: KDBX.Times(),
        strings: [KDBX.ProtectedString(key: "Title", value: .regular("example.com"))]
    )
    passkeyEntry.setPasskeyRelyingParty("example.com")
    passkeyEntry.setPasskeyUsername("alice@example.com")
    passkeyEntry.setPasskeyCredentialID(Data([0x01, 0x02, 0x03, 0x04]))
    passkeyEntry.setPasskeyUserHandle(Data([0xAA, 0xBB]))
    passkeyEntry.setPasskeyPrivateKeyPEM("-----BEGIN PRIVATE KEY-----\nMOCK-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----")
    content.database.root.group.entries.append(passkeyEntry)

    let plainEntry = KDBX.Entry(
        uuid: UUID(),
        times: KDBX.Times(),
        strings: [KDBX.ProtectedString(key: "Title", value: .regular("Not a passkey"))]
    )
    content.database.root.group.entries.append(plainEntry)

    let unlock = UnlockData(masterPassword: testPassword)
    let stream = OutputStream(toMemory: ())
    stream.open()
    try KDBXWriter(to: stream).write(content, unlockData: unlock)
    let data = try #require(stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)
    try data.write(to: url)

    return "\(passkeyUUID)"
}

@Test func listEntriesFlagsPasskeyBearingEntries() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let passkeyUUID = try makeVaultWithPasskeyEntry(at: url)

    let entries = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(entries.count == 2)

    let passkeyEntry = entries.first { $0.uuid == passkeyUUID }
    #expect(passkeyEntry?.isPasskey == true)

    let plainEntry = entries.first { $0.uuid != passkeyUUID }
    #expect(plainEntry?.isPasskey == false)
}

@Test func passkeyMetadataReadsRelyingPartyUsernameAndCredentialID() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let passkeyUUID = try makeVaultWithPasskeyEntry(at: url)

    let metadata = try service.passkeyMetadata(at: url, masterPassword: testPassword, entryUUID: passkeyUUID)
    #expect(metadata?.relyingParty == "example.com")
    #expect(metadata?.username == "alice@example.com")
    #expect(metadata?.credentialID == Data([0x01, 0x02, 0x03, 0x04]))
    #expect(metadata?.userHandle == Data([0xAA, 0xBB]))
}

@Test func passkeyMetadataReturnsNilForNonPasskeyEntry() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let passkeyUUID = try makeVaultWithPasskeyEntry(at: url)

    let entries = try service.listEntries(at: url, masterPassword: testPassword)
    let plainUUID = try #require(entries.first { $0.uuid != passkeyUUID }?.uuid)

    let metadata = try service.passkeyMetadata(at: url, masterPassword: testPassword, entryUUID: plainUUID)
    #expect(metadata == nil)
}

@Test func passkeyMetadataReturnsNilForUnknownUUID() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try makeVaultWithPasskeyEntry(at: url)

    let metadata = try service.passkeyMetadata(at: url, masterPassword: testPassword, entryUUID: UUID().uuidString)
    #expect(metadata == nil)
}

@Test func revealPasskeyPrivateKeyPEMReturnsTheStoredPEM() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let passkeyUUID = try makeVaultWithPasskeyEntry(at: url)

    let content = try service.openVault(at: url, masterPassword: testPassword)
    let pem = service.revealPasskeyPrivateKeyPEM(in: content, entryUUID: passkeyUUID)
    #expect(pem == "-----BEGIN PRIVATE KEY-----\nMOCK-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----")
}

@Test func revealPasskeyPrivateKeyPEMReturnsNilForNonPasskeyEntry() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let passkeyUUID = try makeVaultWithPasskeyEntry(at: url)

    let content = try service.openVault(at: url, masterPassword: testPassword)
    let entries = service.listEntries(in: content)
    let plainUUID = try #require(entries.first { $0.uuid != passkeyUUID }?.uuid)

    #expect(service.revealPasskeyPrivateKeyPEM(in: content, entryUUID: plainUUID) == nil)
}

@Test func revealPasskeyPrivateKeyPEMReturnsNilForUnknownUUID() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try makeVaultWithPasskeyEntry(at: url)

    let content = try service.openVault(at: url, masterPassword: testPassword)
    #expect(service.revealPasskeyPrivateKeyPEM(in: content, entryUUID: UUID().uuidString) == nil)
}

@Test func setPasskeyAddsPasskeyFieldsWithoutTouchingOtherFields() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    // A plain login entry, no passkey fields yet.
    let draft = VaultService.EntryDraft(title: "example.com", username: "alice", password: "s3cret")
    let uuid = try service.createEntry(draft, at: url, masterPassword: testPassword)

    try service.setPasskey(
        uuid: uuid,
        relyingParty: "example.com",
        credentialID: Data([0xAA, 0xBB]),
        privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nMOCK-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----",
        username: "alice@example.com",
        userHandle: Data([0xCC]),
        at: url, masterPassword: testPassword
    )

    let entries = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(entries.count == 1)
    #expect(entries[0].isPasskey == true)
    // The original login fields must survive setPasskey untouched.
    #expect(entries[0].title == "example.com")
    #expect(entries[0].username == "alice")
    let preHash = service.preHashKeyData(forPassword: testPassword)
    let revealed = try service.revealEntry(uuid: uuid, at: url, rawKeyData: preHash)
    #expect(revealed.password == "s3cret")

    let metadata = try service.passkeyMetadata(at: url, masterPassword: testPassword, entryUUID: uuid)
    #expect(metadata?.relyingParty == "example.com")
    #expect(metadata?.username == "alice@example.com")
    #expect(metadata?.credentialID == Data([0xAA, 0xBB]))
}

// MARK: - mergeExtensionOriginatedPasskeys
//
// Simulates the scenario `docs/done/2026-08-31-passkey-registration-write-path-spike.md`
// describes: a "source" vault and a "mirror" copy start identical, the
// mirror independently gains a passkey (standing in for what the
// extension will eventually write there directly), and the merge function
// is expected to copy just that passkey back into source without
// disturbing anything else.

@Test func mergeExtensionOriginatedPasskeysCopiesAMirrorOnlyPasskeyIntoSource() throws {
    let service = VaultService()
    let sourceURL = tempVaultURL()
    let mirrorURL = tempVaultURL()
    defer {
        try? FileManager.default.removeItem(at: sourceURL)
        try? FileManager.default.removeItem(at: mirrorURL)
    }

    try service.createVault(at: sourceURL, masterPassword: testPassword, databaseName: "Test Vault")
    let draft = VaultService.EntryDraft(title: "example.com", username: "alice", password: "s3cret")
    let uuid = try service.createEntry(draft, at: sourceURL, masterPassword: testPassword)

    // Mirror starts as an exact copy...
    try FileManager.default.copyItem(at: sourceURL, to: mirrorURL)
    // ...then independently gains a passkey (standing in for the extension's own write).
    try service.setPasskey(
        uuid: uuid, relyingParty: "example.com", credentialID: Data([0xAA, 0xBB]),
        privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nMOCK-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----",
        username: "alice@example.com", userHandle: Data([0xCC]),
        at: mirrorURL, masterPassword: testPassword
    )

    // Source doesn't have the passkey yet.
    #expect(try service.passkeyMetadata(at: sourceURL, masterPassword: testPassword, entryUUID: uuid) == nil)

    let merged = try service.mergeExtensionOriginatedPasskeys(
        fromMirrorAt: mirrorURL, intoSourceAt: sourceURL, masterPassword: testPassword
    )
    #expect(merged == 1)

    let metadata = try service.passkeyMetadata(at: sourceURL, masterPassword: testPassword, entryUUID: uuid)
    #expect(metadata?.relyingParty == "example.com")
    #expect(metadata?.username == "alice@example.com")
    #expect(metadata?.credentialID == Data([0xAA, 0xBB]))

    // Every other field on the entry must survive untouched.
    let entries = try service.listEntries(at: sourceURL, masterPassword: testPassword)
    #expect(entries.count == 1)
    #expect(entries[0].title == "example.com")
    #expect(entries[0].username == "alice")
    let revealed = try service.revealEntry(uuid: uuid, at: sourceURL, masterPassword: testPassword)
    #expect(revealed.password == "s3cret")
}

@Test func mergeExtensionOriginatedPasskeysIsIdempotent() throws {
    let service = VaultService()
    let sourceURL = tempVaultURL()
    let mirrorURL = tempVaultURL()
    defer {
        try? FileManager.default.removeItem(at: sourceURL)
        try? FileManager.default.removeItem(at: mirrorURL)
    }

    try service.createVault(at: sourceURL, masterPassword: testPassword, databaseName: "Test Vault")
    let draft = VaultService.EntryDraft(title: "example.com", username: "alice", password: "s3cret")
    let uuid = try service.createEntry(draft, at: sourceURL, masterPassword: testPassword)
    try FileManager.default.copyItem(at: sourceURL, to: mirrorURL)
    try service.setPasskey(
        uuid: uuid, relyingParty: "example.com", credentialID: Data([0xAA, 0xBB]),
        privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nMOCK-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----",
        at: mirrorURL, masterPassword: testPassword
    )

    let firstMerge = try service.mergeExtensionOriginatedPasskeys(
        fromMirrorAt: mirrorURL, intoSourceAt: sourceURL, masterPassword: testPassword
    )
    #expect(firstMerge == 1)

    // Nothing new in the mirror the second time — must be a no-op.
    let secondMerge = try service.mergeExtensionOriginatedPasskeys(
        fromMirrorAt: mirrorURL, intoSourceAt: sourceURL, masterPassword: testPassword
    )
    #expect(secondMerge == 0)
}

@Test func mergeExtensionOriginatedPasskeysReturnsZeroWhenMirrorHasNoPasskeys() throws {
    let service = VaultService()
    let sourceURL = tempVaultURL()
    let mirrorURL = tempVaultURL()
    defer {
        try? FileManager.default.removeItem(at: sourceURL)
        try? FileManager.default.removeItem(at: mirrorURL)
    }

    try service.createVault(at: sourceURL, masterPassword: testPassword, databaseName: "Test Vault")
    _ = try service.createEntry(
        VaultService.EntryDraft(title: "example.com", username: "alice", password: "s3cret"),
        at: sourceURL, masterPassword: testPassword
    )
    try FileManager.default.copyItem(at: sourceURL, to: mirrorURL)

    let merged = try service.mergeExtensionOriginatedPasskeys(
        fromMirrorAt: mirrorURL, intoSourceAt: sourceURL, masterPassword: testPassword
    )
    #expect(merged == 0)
}

@Test func mergeExtensionOriginatedPasskeysIgnoresAMirrorEntryAbsentFromSource() throws {
    let service = VaultService()
    let sourceURL = tempVaultURL()
    let mirrorURL = tempVaultURL()
    defer {
        try? FileManager.default.removeItem(at: sourceURL)
        try? FileManager.default.removeItem(at: mirrorURL)
    }

    try service.createVault(at: sourceURL, masterPassword: testPassword, databaseName: "Test Vault")
    try FileManager.default.copyItem(at: sourceURL, to: mirrorURL)

    // An entry that exists ONLY in the mirror (the extension can't create
    // entries today, but this is defensive, not assumed-impossible).
    let mirrorOnlyUUID = try service.createEntry(
        VaultService.EntryDraft(title: "only-in-mirror.com", username: "bob", password: "hunter2"),
        at: mirrorURL, masterPassword: testPassword
    )
    try service.setPasskey(
        uuid: mirrorOnlyUUID, relyingParty: "only-in-mirror.com", credentialID: Data([0x01]),
        privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nMOCK-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----",
        at: mirrorURL, masterPassword: testPassword
    )

    let merged = try service.mergeExtensionOriginatedPasskeys(
        fromMirrorAt: mirrorURL, intoSourceAt: sourceURL, masterPassword: testPassword
    )
    #expect(merged == 0)
    // Source must still have no entries at all — nothing got created.
    #expect(try service.listEntries(at: sourceURL, masterPassword: testPassword).isEmpty)
}

@Test func setPasskeyThrowsForUnknownUUID() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    #expect(throws: (any Error).self) {
        try service.setPasskey(
            uuid: UUID().uuidString,
            relyingParty: "example.com",
            credentialID: Data([0x01]),
            privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nMOCK\n-----END PRIVATE KEY-----",
            at: url, masterPassword: testPassword
        )
    }
}
