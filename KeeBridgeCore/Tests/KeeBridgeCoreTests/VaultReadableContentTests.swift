// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Tests for VaultService.openReadOnlyContent — the metadata-only read
// path introduced for the KDBX attachment memory-footprint fix (see
// ROADMAP.md). Builds a vault with a real binary attachment directly via
// KDBXKit (VaultService's own EntryDraft-shaped write API has no
// attachment support, same limitation PasskeyTests.swift/PaymentCardTests.swift
// already work around for their own KeePassXC-only fields), so these
// tests exercise the exact scenario the ROADMAP entry describes: a vault
// carrying real attachment bytes, read by every VaultService function
// that never needed those bytes in the first place.

import Foundation
import Testing
import KDBXKit
@testable import KeeBridgeCore

private let testPassword = "hunter2"

private func tempVaultURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("keebridge-test-\(UUID().uuidString).kdbx")
}

/// Builds a vault with one entry that has a real binary attachment
/// referencing a pool slot in `innerHeader.binaryContent` — the exact
/// on-disk shape `openMetadataOnly` is documented to keep bytes off the
/// heap for. Returns the entry's UUID string and the attachment bytes
/// (so callers can assert the eager path still surfaces them unchanged).
private func makeVaultWithAttachment(at url: URL) throws -> (uuid: String, attachmentBytes: Data) {
    var content = KDBXContent.makeEmpty(databaseName: "Test Vault")
    let attachmentBytes = Data((0..<4096).map { UInt8($0 % 256) })
    content.innerHeader.binaryContent = [
        InnerHeader.BinaryContent(shouldBeProtected: false, data: attachmentBytes),
    ]

    let entryUUID = UUID()
    var entry = KDBX.Entry(
        uuid: entryUUID,
        times: KDBX.Times(),
        strings: [
            KDBX.ProtectedString(key: "Title", value: .regular("Has an attachment")),
            KDBX.ProtectedString(key: "UserName", value: .regular("alice")),
            KDBX.ProtectedString(key: "otp", value: .unprotected("otpauth://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example")),
        ]
    )
    entry.binaries = [KDBX.ProtectedBinary(key: "recovery-codes.txt", value: .ref(0))]
    content.database.root.group.entries.append(entry)

    let unlock = UnlockData(masterPassword: testPassword)
    let stream = OutputStream(toMemory: ())
    stream.open()
    try KDBXWriter(to: stream).write(content, unlockData: unlock)
    let data = try #require(stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data)
    try data.write(to: url)

    return (uuid: "\(entryUUID)", attachmentBytes: attachmentBytes)
}

@Test func openReadOnlyContentReturnsLazyContentForAnOrdinaryVault() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")

    let content = try service.openReadOnlyContent(at: url, unlock: UnlockData(masterPassword: testPassword))
    #expect(content is LazyKDBXContent)
    #expect(!(content is KDBXContent))
}

// MARK: - openReadOnlyVault — the public session-caching entry point
//
// A separate surface from `openReadOnlyContent` (package-internal, used by
// the one-off `at url:` convenience methods above): `openReadOnlyVault` is
// `public`, for callers in OTHER targets (KeeBridgeCardExtension,
// KeeBridgeProvider, the app) that want to cache a read-only-opened vault
// across a session the way they already cache `openVault`'s result, without
// paying the eager attachment-materialization cost. First consumer:
// `SafariWebExtensionHandler`, which never writes to the vault at all.

@Test func openReadOnlyVaultReturnsLazyContentMatchingOpenReadOnlyContent() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try service.createVault(at: url, masterPassword: testPassword, databaseName: "Test Vault")
    let uuid = try service.createEntry(
        .init(title: "Example", username: "alice", password: "s3cret"),
        at: url, masterPassword: testPassword
    )

    let viaMasterPassword = try service.openReadOnlyVault(at: url, masterPassword: testPassword)
    #expect(viaMasterPassword is LazyKDBXContent)

    let preHash = service.preHashKeyData(forPassword: testPassword)
    let viaRawKeyData = try service.openReadOnlyVault(at: url, rawKeyData: preHash)
    #expect(viaRawKeyData is LazyKDBXContent)

    // Both forms must agree with each other and with the `at url:`
    // convenience that already routes through the same underlying path.
    let entriesViaMasterPassword = service.listEntries(in: viaMasterPassword)
    let entriesViaRawKeyData = service.listEntries(in: viaRawKeyData)
    let entriesViaConvenience = try service.listEntries(at: url, masterPassword: testPassword)
    #expect(entriesViaMasterPassword.map(\.uuid) == [uuid])
    #expect(entriesViaRawKeyData.map(\.uuid) == [uuid])
    #expect(entriesViaConvenience.map(\.uuid) == [uuid])
}

@Test func openReadOnlyContentCapturesAttachmentMetadataWithoutRetainingBytes() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let (_, attachmentBytes) = try makeVaultWithAttachment(at: url)

    let content = try service.openReadOnlyContent(at: url, unlock: UnlockData(masterPassword: testPassword))
    let lazy = try #require(content as? LazyKDBXContent)

    // Metadata (size, hash) is captured...
    #expect(lazy.binaries.count == 1)
    #expect(lazy.binaries[0].sizeBytes == attachmentBytes.count)
    // ...but `LazyKDBXContent` has no field carrying the decrypted bytes
    // at all (unlike `KDBXContent.innerHeader.binaryContent[i].data`) —
    // a structural guarantee, not just a runtime check, that this path
    // never materializes them.
    #expect(lazy.innerHeader.binaryContent.isEmpty)
}

@Test func readOnlyFunctionsAgreeBetweenEagerAndMetadataOnlyOpens() throws {
    let service = VaultService()
    let url = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let (uuid, attachmentBytes) = try makeVaultWithAttachment(at: url)

    // Sanity: the eager path really does carry the attachment bytes —
    // otherwise this test wouldn't be exercising anything.
    let eager = try service.openVault(at: url, masterPassword: testPassword)
    #expect(eager.innerHeader.binaryContent.first?.data == attachmentBytes)

    // Every VaultService read function must agree regardless of which
    // path opened the vault.
    let lazyEntries = try service.listEntries(at: url, masterPassword: testPassword)
    let eagerEntries = service.listEntries(in: eager)
    #expect(lazyEntries.map(\.uuid) == eagerEntries.map(\.uuid))
    #expect(lazyEntries.map(\.title) == eagerEntries.map(\.title))
    #expect(lazyEntries.map(\.username) == eagerEntries.map(\.username))

    let lazyUsername = try service.revealField(at: url, masterPassword: testPassword, entryUUID: uuid, fieldKey: "UserName")
    #expect(lazyUsername == service.revealField(in: eager, entryUUID: uuid, fieldKey: "UserName"))
    #expect(lazyUsername == "alice")

    let lazyTOTP = try service.currentTOTPCode(at: url, masterPassword: testPassword, entryUUID: uuid)
    let eagerTOTP = try service.currentTOTPCode(in: eager, entryUUID: uuid)
    #expect(lazyTOTP == eagerTOTP)
    #expect(lazyTOTP?.count == 6)

    let lazyDraft = try service.revealEntry(uuid: uuid, at: url, masterPassword: testPassword)
    let eagerDraft = try #require(service.revealEntry(in: eager, uuid: uuid))
    #expect(lazyDraft.title == eagerDraft.title)
    #expect(lazyDraft.username == eagerDraft.username)
}

@Test func openReadOnlyContentFallsBackToEagerParseForUnsupportedFormatVersionOnly() throws {
    let service = VaultService()

    // A non-3.x, non-KDBX error (garbage bytes) must NOT be swallowed by
    // the 3.x fallback — it should still surface as a normal open failure,
    // proving the fallback is scoped to `unsupportedFormatVersion(major:
    // 3, ...)` specifically rather than catching everything.
    let garbageURL = tempVaultURL()
    defer { try? FileManager.default.removeItem(at: garbageURL) }
    try Data([0x00, 0x01, 0x02, 0x03]).write(to: garbageURL)

    #expect(throws: (any Error).self) {
        _ = try service.openReadOnlyContent(at: garbageURL, unlock: UnlockData(masterPassword: testPassword))
    }
}

@Test func openReadOnlyContentThrowsFileNotFoundForMissingVault() {
    let service = VaultService()
    let missing = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID()).kdbx")
    #expect(throws: (any Error).self) {
        _ = try service.openReadOnlyContent(at: missing, unlock: UnlockData(masterPassword: "whatever"))
    }
}
