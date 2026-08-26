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
