// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Round-trip tests for the v2 write support (createVault/createEntry/
// updateEntry/deleteEntry/revealEntry) — create a temp vault, mutate it,
// re-open and assert the tree matches expectations. Every test uses its own
// temp file and cleans up after itself.

import Foundation
import Testing
@testable import KeeBridgeCore

private let testPassword = "hunter2"

private func tempVaultURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("keebridge-test-\(UUID().uuidString).kdbx")
}

@Test func createVaultProducesAnOpenableEmptyVault() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }

    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")
    #expect(FileManager.default.fileExists(atPath: url.path))

    let entries = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(entries.isEmpty)
}

@Test func createVaultRefusesToOverwriteExistingFile() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }

    try service.createVault(at: url, masterPassword: testPassword, databaseName: "First")
    #expect(throws: (any Error).self) {
        try service.createVault(at: url, masterPassword: testPassword, databaseName: "Second")
    }
}

@Test func createEntryRoundTrips() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let draft = VaultService.EntryDraft(
        title: "Example", username: "alice", password: "s3cret", url: "https://example.com", notes: "a note"
    )
    let newUUID = try service.createEntry(draft, at: url, masterPassword: testPassword)

    let entries = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(entries.count == 1)
    #expect(entries[0].uuid == newUUID)
    #expect(entries[0].title == "Example")
    #expect(entries[0].username == "alice")
    #expect(entries[0].url == "https://example.com")

    let preHash = service.preHashKeyData(forPassword: testPassword)
    let revealed = try service.revealEntry(uuid: newUUID, at: url, rawKeyData: preHash)
    #expect(revealed.password == "s3cret")
    #expect(revealed.notes == "a note")
}

@Test func revealEntryWithMasterPasswordMatchesRawKeyData() throws {
    // Same as createEntryRoundTrips' reveal check, but through the
    // masterPassword overload instead of rawKeyData — for callers with no
    // cached pre-hash (e.g. a CLI prompting via getpass(), not backed by
    // Keychain).
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let draft = VaultService.EntryDraft(
        title: "Example", username: "alice", password: "s3cret", url: "https://example.com", notes: "a note"
    )
    let newUUID = try service.createEntry(draft, at: url, masterPassword: testPassword)

    let preHash = service.preHashKeyData(forPassword: testPassword)
    let viaRawKeyData = try service.revealEntry(uuid: newUUID, at: url, rawKeyData: preHash)
    let viaMasterPassword = try service.revealEntry(uuid: newUUID, at: url, masterPassword: testPassword)

    #expect(viaMasterPassword.title == viaRawKeyData.title)
    #expect(viaMasterPassword.username == viaRawKeyData.username)
    #expect(viaMasterPassword.password == viaRawKeyData.password)
    #expect(viaMasterPassword.url == viaRawKeyData.url)
    #expect(viaMasterPassword.notes == viaRawKeyData.notes)
    #expect(viaMasterPassword.password == "s3cret")
}

@Test func revealEntryWithMasterPasswordThrowsForUnknownUUID() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    #expect(throws: (any Error).self) {
        try service.revealEntry(uuid: UUID().uuidString, at: url, masterPassword: testPassword)
    }
}

@Test func updateEntryOverwritesFields() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let original = VaultService.EntryDraft(title: "Old", username: "old-user", password: "old-pass")
    let uuid = try service.createEntry(original, at: url, masterPassword: testPassword)

    let preHash = service.preHashKeyData(forPassword: testPassword)
    let updated = VaultService.EntryDraft(title: "New", username: "new-user", password: "new-pass")
    try service.updateEntry(uuid: uuid, applying: updated, at: url, rawKeyData: preHash)

    let entries = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(entries.count == 1)
    #expect(entries[0].title == "New")
    #expect(entries[0].username == "new-user")

    let revealed = try service.revealEntry(uuid: uuid, at: url, rawKeyData: preHash)
    #expect(revealed.password == "new-pass")
}

@Test func updateEntryWithMasterPasswordOverwritesFields() throws {
    // Same as updateEntryOverwritesFields, but through the masterPassword
    // overload instead of rawKeyData — for callers with no cached pre-hash
    // (e.g. a CLI prompting via getpass(), not backed by Keychain).
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let original = VaultService.EntryDraft(title: "Old", username: "old-user", password: "old-pass")
    let uuid = try service.createEntry(original, at: url, masterPassword: testPassword)

    let updated = VaultService.EntryDraft(title: "New", username: "new-user", password: "new-pass")
    try service.updateEntry(uuid: uuid, applying: updated, at: url, masterPassword: testPassword)

    let entries = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(entries.count == 1)
    #expect(entries[0].title == "New")
    #expect(entries[0].username == "new-user")

    let preHash = service.preHashKeyData(forPassword: testPassword)
    let revealed = try service.revealEntry(uuid: uuid, at: url, rawKeyData: preHash)
    #expect(revealed.password == "new-pass")
}

@Test func updateEntryPreservesPasskeyAndOtherCustomFields() throws {
    // Regression test: updateEntry used to replace entry.strings wholesale
    // with just the five standard fields (title/username/password/url/
    // notes), which silently deleted any OTHER field already on the entry
    // — a TOTP `otp` secret, a passkey's `KPEX_PASSKEY_*` fields, anything
    // — the moment that entry was edited through the app's own Edit form
    // or the CLI's `update` subcommand. Neither of those callers'
    // reveal-then-merge logic protected against this either, since both
    // only ever considered the five standard fields. Exercises the fix via
    // an existing custom-field write path (`setPasskey`) rather than
    // poking at KDBXKit directly, since it's the real-world scenario this
    // regressed.
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let uuid = try service.createEntry(.init(title: "Old", username: "old-user"), at: url, masterPassword: testPassword)
    try service.setPasskey(
        uuid: uuid, relyingParty: "example.com", credentialID: Data([0x01, 0x02]),
        privateKeyPEM: "-----BEGIN PRIVATE KEY-----\nMOCK-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----",
        at: url, masterPassword: testPassword
    )

    let updated = VaultService.EntryDraft(title: "New", username: "new-user")
    try service.updateEntry(uuid: uuid, applying: updated, at: url, masterPassword: testPassword)

    let entries = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(entries.count == 1)
    #expect(entries[0].title == "New")
    #expect(entries[0].username == "new-user")
    #expect(entries[0].isPasskey == true)

    let metadata = try service.passkeyMetadata(at: url, masterPassword: testPassword, entryUUID: uuid)
    #expect(metadata?.relyingParty == "example.com")
    #expect(metadata?.credentialID == Data([0x01, 0x02]))
}

@Test func entryDraftRoundTripsOTPURI() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let otpURI = "otpauth://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    let uuid = try service.createEntry(.init(title: "Example", otpURI: otpURI), at: url, masterPassword: testPassword)

    #expect(try service.revealEntry(uuid: uuid, at: url, masterPassword: testPassword).otpURI == otpURI)
    #expect(try service.currentTOTPCode(at: url, masterPassword: testPassword, entryUUID: uuid) != nil)

    try service.updateEntry(uuid: uuid, applying: .init(title: "Renamed"), at: url, masterPassword: testPassword)
    #expect(try service.revealEntry(uuid: uuid, at: url, masterPassword: testPassword).otpURI == otpURI)

    try service.updateEntry(
        uuid: uuid, applying: .init(title: "Updated", otpURI: ""), at: url, masterPassword: testPassword
    )
    #expect(try service.currentTOTPCode(at: url, masterPassword: testPassword, entryUUID: uuid) == nil)
}

@Test func updateEntryThrowsForUnknownUUID() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let preHash = service.preHashKeyData(forPassword: testPassword)
    #expect(throws: (any Error).self) {
        try service.updateEntry(uuid: UUID().uuidString, applying: .init(title: "x"), at: url, rawKeyData: preHash)
    }
}

@Test func deleteEntryRemovesIt() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let uuid1 = try service.createEntry(.init(title: "Keep"), at: url, masterPassword: testPassword)
    let uuid2 = try service.createEntry(.init(title: "Delete me"), at: url, masterPassword: testPassword)
    #expect(try service.listEntries(at: url, masterPassword: testPassword).count == 2)

    let preHash = service.preHashKeyData(forPassword: testPassword)
    try service.deleteEntry(uuid: uuid2, at: url, rawKeyData: preHash)

    let remaining = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(remaining.count == 1)
    #expect(remaining[0].uuid == uuid1)
}

@Test func deleteEntryThrowsForUnknownUUID() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let preHash = service.preHashKeyData(forPassword: testPassword)
    #expect(throws: (any Error).self) {
        try service.deleteEntry(uuid: UUID().uuidString, at: url, rawKeyData: preHash)
    }
}

@Test func deleteEntryWithMasterPasswordRemovesIt() throws {
    // Same as deleteEntryRemovesIt, but through the masterPassword overload.
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let uuid1 = try service.createEntry(.init(title: "Keep"), at: url, masterPassword: testPassword)
    let uuid2 = try service.createEntry(.init(title: "Delete me"), at: url, masterPassword: testPassword)
    #expect(try service.listEntries(at: url, masterPassword: testPassword).count == 2)

    try service.deleteEntry(uuid: uuid2, at: url, masterPassword: testPassword)

    let remaining = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(remaining.count == 1)
    #expect(remaining[0].uuid == uuid1)
}

@Test func multipleEntriesSurviveMultipleWrites() throws {
    // Guards against a subtle bug class: each write regenerates salts
    // (KDBXWriter's default), so this exercises that repeated
    // open-mutate-write cycles against the SAME file keep working, not just
    // a single write.
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    var uuids: [String] = []
    for i in 0..<5 {
        let uuid = try service.createEntry(.init(title: "Entry \(i)"), at: url, masterPassword: testPassword)
        uuids.append(uuid)
    }

    let entries = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(entries.count == 5)
    #expect(Set(entries.map(\.uuid)) == Set(uuids))
}
