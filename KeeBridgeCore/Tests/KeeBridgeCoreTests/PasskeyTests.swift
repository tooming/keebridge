// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Passkey read-only metadata tests — build a passkey-bearing entry
// directly via KDBXKit's own KeePassXC-compatible setPasskey* methods
// (VaultService has no write-side passkey API yet, only read), write it
// to a temp vault the same way VaultService's private write() does, then
// confirm VaultService's new read-only accessors surface it correctly.
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
