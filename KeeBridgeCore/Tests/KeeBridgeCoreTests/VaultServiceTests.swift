// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import KeeBridgeCore

@Test func preHashIsDeterministicAndCorrectLength() {
    let service = VaultService()
    let a = service.preHashKeyData(forPassword: "hunter2")
    let b = service.preHashKeyData(forPassword: "hunter2")
    #expect(a == b)
    #expect(a.count == 32)
}

@Test func differentPasswordsProduceDifferentPreHashes() {
    let service = VaultService()
    let a = service.preHashKeyData(forPassword: "hunter2")
    let b = service.preHashKeyData(forPassword: "hunter3")
    #expect(a != b)
}

@Test func listEntriesThrowsOnMissingFile() {
    let service = VaultService()
    let missing = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID()).kdbx")
    #expect(throws: (any Error).self) {
        try service.listEntries(at: missing, masterPassword: "whatever")
    }
}

// MARK: - v3: openVault + pure in-memory reads (the session-caching fix)
//
// Confirms `openVault` once + repeated `in content:` calls produce
// identical results to the `at url:` convenience path, which pays the
// I/O + KDF cost on every call. Both paths must agree — this is the
// contract VaultController/the extension rely on when they switch from
// "re-open every time" to "open once, reuse the cached KDBXContent".

@Test func openVaultPlusInMemoryReadsMatchTheAtURLConvenience() throws {
    let service = VaultService()
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("keebridge-test-\(UUID().uuidString).kdbx")
    defer { try? FileManager.default.removeItem(at: url) }

    try service.createVault(at: url, masterPassword: "hunter2", databaseName: "Test Vault")
    let uuid = try service.createEntry(
        .init(title: "Example", username: "alice", password: "s3cret", url: "https://example.com", notes: "a note"),
        at: url, masterPassword: "hunter2"
    )

    // The convenience path (opens fresh internally).
    let viaConvenience = try service.listEntries(at: url, masterPassword: "hunter2")
    let passwordViaConvenience = try service.revealField(at: url, masterPassword: "hunter2", entryUUID: uuid, fieldKey: "Password")

    // Open once, reuse the content for both reads — no second KDF pass.
    let content = try service.openVault(at: url, masterPassword: "hunter2")
    let viaCache = service.listEntries(in: content)
    let passwordViaCache = service.revealField(in: content, entryUUID: uuid, fieldKey: "Password")

    #expect(viaCache.count == viaConvenience.count)
    #expect(viaCache.map(\.uuid) == viaConvenience.map(\.uuid))
    #expect(viaCache.map(\.title) == viaConvenience.map(\.title))
    #expect(passwordViaCache == passwordViaConvenience)
    #expect(passwordViaCache == "s3cret")
}

@Test func revealEntryInContentReturnsNilForUnknownUUID() throws {
    let service = VaultService()
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("keebridge-test-\(UUID().uuidString).kdbx")
    defer { try? FileManager.default.removeItem(at: url) }

    try service.createVault(at: url, masterPassword: "hunter2", databaseName: "Test Vault")
    let content = try service.openVault(at: url, masterPassword: "hunter2")

    #expect(service.revealEntry(in: content, uuid: UUID().uuidString) == nil)
}
