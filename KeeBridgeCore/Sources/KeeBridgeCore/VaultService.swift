// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Shared vault-reading logic used by VaultProbe (validation CLI), the
// KeeBridge container app (identity-store population), and the
// KeeBridgeProvider extension (on-demand credential decryption).

import Foundation
import KDBXKit

/// Non-secret metadata about a single login entry. Deliberately excludes
/// password and any custom-field *values* — only titles/usernames/URLs and
/// custom-field *names* are ever carried in this type, since it's what gets
/// registered with ASCredentialIdentityStore (system-visible, non-secret).
public struct VaultLoginEntry: Sendable {
    public let uuid: String
    public let title: String
    public let username: String
    public let url: String
    public let customFieldKeys: [String]

    public init(uuid: String, title: String, username: String, url: String, customFieldKeys: [String]) {
        self.uuid = uuid
        self.title = title
        self.username = username
        self.url = url
        self.customFieldKeys = customFieldKeys
    }
}

public enum VaultServiceError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case openFailed(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Vault not found at \(path)"
        case .openFailed(let reason):
            return "Failed to open vault: \(reason)"
        }
    }
}

public struct VaultService: Sendable {
    public init() {}

    private static let standardKeys: Set<String> = ["Title", "UserName", "URL", "Notes", "Password"]

    // MARK: - Pre-hash (for Keychain caching)

    /// Computes the 32-byte KDBX pre-hash `R = SHA-256(SHA-256(password))`
    /// for a master password, suitable for storing in Keychain (behind a
    /// biometric access-control gate) so later unlocks don't need the
    /// plaintext password again.
    ///
    /// IMPORTANT: this is the *pre-KDF* hash, not the final unlock key.
    /// Caching it skips re-prompting for the password — it does NOT skip
    /// the Argon2id KDF pass; that still runs on every `listEntries`/
    /// `revealField` call, from either the password or the cached
    /// pre-hash, exactly as KeePassXC itself re-runs Argon2id on every
    /// unlock. That's by KDBX spec design, not an oversight here.
    public func preHashKeyData(forPassword password: String) -> Data {
        UnlockData(masterPassword: password).keyDataBytes.toData()
    }

    // MARK: - Opening

    /// Opens the vault and returns lightweight metadata for every login-type
    /// entry (title, username, URL, and the *names* of any custom fields).
    /// Never returns a field *value* other than title/username/URL, and
    /// never touches disk with anything other than the original encrypted
    /// file.
    public func listEntries(at url: URL, masterPassword: String) throws -> [VaultLoginEntry] {
        try listEntries(at: url, unlock: UnlockData(masterPassword: masterPassword))
    }

    /// Same as `listEntries(at:masterPassword:)`, but unlocking from a
    /// previously-cached pre-hash (see `preHashKeyData`) instead of a
    /// plaintext password — the path the container app and extension use
    /// after first unlock.
    public func listEntries(at url: URL, rawKeyData: Data) throws -> [VaultLoginEntry] {
        try listEntries(at: url, unlock: UnlockData(rawKeyData: rawKeyData))
    }

    private func listEntries(at url: URL, unlock: UnlockData) throws -> [VaultLoginEntry] {
        let content = try openContent(at: url, unlock: unlock)

        var results: [VaultLoginEntry] = []

        func standardValue(_ entry: KDBX.Entry, _ key: String) -> String {
            entry.strings.first(where: { $0.key == key })?.value.revealedString ?? ""
        }

        func walk(_ group: KDBX.Group) {
            for entry in group.entries {
                let title = standardValue(entry, "Title")
                let username = standardValue(entry, "UserName")
                let entryURL = standardValue(entry, "URL")
                let customKeys = entry.strings
                    .map(\.key)
                    .filter { !Self.standardKeys.contains($0) }

                results.append(VaultLoginEntry(
                    uuid: "\(entry.uuid)",
                    title: title.isEmpty ? "(untitled)" : title,
                    username: username,
                    url: entryURL,
                    customFieldKeys: customKeys
                ))
            }
            for child in group.groups {
                walk(child)
            }
        }

        walk(content.database.root.group)
        return results
    }

    // MARK: - Field reveal (credential-selection time only)

    /// Decrypts and returns a single field's *value* for one entry, by UUID
    /// and field key, unlocking with a plaintext master password. Used at
    /// credential-selection time only — never called for bulk listing.
    public func revealField(at url: URL, masterPassword: String, entryUUID: String, fieldKey: String) throws -> String? {
        try revealField(at: url, unlock: UnlockData(masterPassword: masterPassword), entryUUID: entryUUID, fieldKey: fieldKey)
    }

    /// Same as `revealField(at:masterPassword:entryUUID:fieldKey:)`, but
    /// unlocking from a cached pre-hash — the path the extension uses after
    /// Keychain/biometric rehydration.
    public func revealField(at url: URL, rawKeyData: Data, entryUUID: String, fieldKey: String) throws -> String? {
        try revealField(at: url, unlock: UnlockData(rawKeyData: rawKeyData), entryUUID: entryUUID, fieldKey: fieldKey)
    }

    private func revealField(at url: URL, unlock: UnlockData, entryUUID: String, fieldKey: String) throws -> String? {
        let content = try openContent(at: url, unlock: unlock)

        var found: String?

        func walk(_ group: KDBX.Group) {
            if found != nil { return }
            for entry in group.entries where "\(entry.uuid)" == entryUUID {
                if let field = entry.strings.first(where: { $0.key == fieldKey }) {
                    field.value.withRevealedString { plaintext in
                        found = plaintext
                    }
                }
                return
            }
            for child in group.groups {
                walk(child)
            }
        }

        walk(content.database.root.group)
        return found
    }

    // MARK: - TOTP (credential-selection time only)

    /// Reveals the `otp` field (the otpauth:// URI KeePassXC/pykeepass
    /// store TOTP secrets under — confirmed field name, see VaultService's
    /// header) and returns the current 6-digit-by-default code. `nil` if
    /// the entry has no `otp` field at all (most entries don't).
    public func currentTOTPCode(at url: URL, masterPassword: String, entryUUID: String) throws -> String? {
        try currentTOTPCode(at: url, unlock: UnlockData(masterPassword: masterPassword), entryUUID: entryUUID)
    }

    /// Same as `currentTOTPCode(at:masterPassword:entryUUID:)`, unlocking
    /// from a cached pre-hash instead.
    public func currentTOTPCode(at url: URL, rawKeyData: Data, entryUUID: String) throws -> String? {
        try currentTOTPCode(at: url, unlock: UnlockData(rawKeyData: rawKeyData), entryUUID: entryUUID)
    }

    private func currentTOTPCode(at url: URL, unlock: UnlockData, entryUUID: String) throws -> String? {
        guard let otpauthURI = try revealField(at: url, unlock: unlock, entryUUID: entryUUID, fieldKey: "otp"),
              !otpauthURI.isEmpty
        else { return nil }
        let params = try TOTPGenerator.parse(otpauthURI: otpauthURI)
        return TOTPGenerator.currentCode(for: params)
    }

    // MARK: - Writing (v2 — createVault/createEntry/updateEntry/deleteEntry)

    /// Fields for creating or editing a login-style entry. Deliberately the
    /// same five fields `listEntries`/`revealField` already deal with —
    /// card/note entry types stay KeePassXC-only for now (see the
    /// secrets-management-UI plan's "first pass" scope).
    public struct EntryDraft: Sendable {
        public var title: String
        public var username: String
        public var password: String
        public var url: String
        public var notes: String

        public init(title: String = "", username: String = "", password: String = "", url: String = "", notes: String = "") {
            self.title = title
            self.username = username
            self.password = password
            self.url = url
            self.notes = notes
        }
    }

    public enum VaultWriteError: Error, CustomStringConvertible {
        case entryNotFound(String)
        case writeFailed(String)

        public var description: String {
            switch self {
            case .entryNotFound(let uuid): return "No entry with UUID \(uuid) found in the vault"
            case .writeFailed(let reason): return "Failed to write vault: \(reason)"
            }
        }
    }

    /// Creates a brand-new, empty vault at `url` (KDBX 4.1, Argon2id
    /// defaults, via KDBXKit's own `KDBXContent.makeEmpty`), encrypted
    /// under `masterPassword`. Fails if a file already exists at `url` —
    /// this is "start a fresh vault", not "overwrite an existing one".
    public func createVault(at url: URL, masterPassword: String, databaseName: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw VaultWriteError.writeFailed("A file already exists at \(url.path)")
        }
        let content = KDBXContent.makeEmpty(databaseName: databaseName)
        try write(content, unlock: UnlockData(masterPassword: masterPassword), to: url)
    }

    /// Adds a new entry to the vault's root group. Returns the new entry's
    /// UUID (as a string, matching `VaultLoginEntry.uuid`'s format).
    public func createEntry(_ draft: EntryDraft, at url: URL, rawKeyData: Data) throws -> String {
        try createEntry(draft, at: url, unlock: UnlockData(rawKeyData: rawKeyData))
    }

    public func createEntry(_ draft: EntryDraft, at url: URL, masterPassword: String) throws -> String {
        try createEntry(draft, at: url, unlock: UnlockData(masterPassword: masterPassword))
    }

    private func createEntry(_ draft: EntryDraft, at url: URL, unlock: UnlockData) throws -> String {
        var content = try openContent(at: url, unlock: unlock)
        let newUUID = UUID()
        let now = Date()
        let entry = KDBX.Entry(
            uuid: newUUID,
            times: KDBX.Times(creationTime: now, lastModificationTime: now),
            strings: draftStrings(draft)
        )
        content.database.root.group.entries.append(entry)
        try write(content, unlock: unlock, to: url)
        return "\(newUUID)"
    }

    /// Overwrites an existing entry's fields in place. Throws
    /// `.entryNotFound` if no entry with that UUID exists anywhere in the
    /// tree (searched recursively, same as `listEntries`/`revealField`).
    public func updateEntry(uuid: String, applying draft: EntryDraft, at url: URL, rawKeyData: Data) throws {
        try updateEntry(uuid: uuid, applying: draft, at: url, unlock: UnlockData(rawKeyData: rawKeyData))
    }

    private func updateEntry(uuid: String, applying draft: EntryDraft, at url: URL, unlock: UnlockData) throws {
        var content = try openContent(at: url, unlock: unlock)
        let found = Self.mutateEntry(in: &content.database.root.group, uuid: uuid) { entry in
            entry.strings = self.draftStrings(draft)
            var times = entry.times ?? KDBX.Times()
            times.lastModificationTime = Date()
            entry.times = times
        }
        guard found else { throw VaultWriteError.entryNotFound(uuid) }
        try write(content, unlock: unlock, to: url)
    }

    /// Removes an entry entirely (not a move to a recycle bin — v1 doesn't
    /// model one). Throws `.entryNotFound` if the UUID doesn't exist.
    public func deleteEntry(uuid: String, at url: URL, rawKeyData: Data) throws {
        try deleteEntry(uuid: uuid, at: url, unlock: UnlockData(rawKeyData: rawKeyData))
    }

    private func deleteEntry(uuid: String, at url: URL, unlock: UnlockData) throws {
        var content = try openContent(at: url, unlock: unlock)
        let found = Self.removeEntry(in: &content.database.root.group, uuid: uuid)
        guard found else { throw VaultWriteError.entryNotFound(uuid) }
        try write(content, unlock: unlock, to: url)
    }

    /// Reveals an existing entry's editable fields, for populating an edit
    /// form. Like `revealField`, this is a credential-selection-time-only
    /// operation — never called for bulk listing.
    public func revealEntry(uuid: String, at url: URL, rawKeyData: Data) throws -> EntryDraft {
        try revealEntry(uuid: uuid, at: url, unlock: UnlockData(rawKeyData: rawKeyData))
    }

    private func revealEntry(uuid: String, at url: URL, unlock: UnlockData) throws -> EntryDraft {
        let content = try openContent(at: url, unlock: unlock)
        guard let entry = Self.findEntry(in: content.database.root.group, uuid: uuid) else {
            throw VaultWriteError.entryNotFound(uuid)
        }
        func value(_ key: String) -> String {
            entry.strings.first(where: { $0.key == key })?.value.revealedString ?? ""
        }
        return EntryDraft(
            title: value("Title"), username: value("UserName"), password: value("Password"),
            url: value("URL"), notes: value("Notes")
        )
    }

    // MARK: - Write-side tree helpers

    /// Builds the standard five-field `strings` array for an entry.
    /// Password is `.unprotected` (despite the name — see
    /// `KDBX.ProtectedString.Value`'s doc comment: this is the case that
    /// gets written with `Protected="True"`, i.e. inner-cipher encrypted
    /// on disk, matching KeePass's `MemoryProtectionConfig.protectPassword`
    /// default). The rest are `.regular` (plaintext in the XML), matching
    /// standard KeePass/KeePassXC behavior for non-secret fields.
    private func draftStrings(_ draft: EntryDraft) -> [KDBX.ProtectedString] {
        [
            KDBX.ProtectedString(key: "Title", value: .regular(draft.title)),
            KDBX.ProtectedString(key: "UserName", value: .regular(draft.username)),
            KDBX.ProtectedString(key: "Password", value: .unprotected(draft.password)),
            KDBX.ProtectedString(key: "URL", value: .regular(draft.url)),
            KDBX.ProtectedString(key: "Notes", value: .regular(draft.notes)),
        ]
    }

    private static func findEntry(in group: KDBX.Group, uuid: String) -> KDBX.Entry? {
        for entry in group.entries where "\(entry.uuid)" == uuid { return entry }
        for child in group.groups {
            if let found = findEntry(in: child, uuid: uuid) { return found }
        }
        return nil
    }

    /// Finds the entry with `uuid` anywhere in the tree and applies `mutate`
    /// to it in place. Returns whether an entry was found.
    private static func mutateEntry(in group: inout KDBX.Group, uuid: String, mutate: (inout KDBX.Entry) -> Void) -> Bool {
        for i in group.entries.indices where "\(group.entries[i].uuid)" == uuid {
            mutate(&group.entries[i])
            return true
        }
        for i in group.groups.indices {
            if mutateEntry(in: &group.groups[i], uuid: uuid, mutate: mutate) { return true }
        }
        return false
    }

    /// Finds and removes the entry with `uuid` anywhere in the tree.
    /// Returns whether an entry was found (and removed).
    private static func removeEntry(in group: inout KDBX.Group, uuid: String) -> Bool {
        if let index = group.entries.firstIndex(where: { "\($0.uuid)" == uuid }) {
            group.entries.remove(at: index)
            return true
        }
        for i in group.groups.indices {
            if removeEntry(in: &group.groups[i], uuid: uuid) { return true }
        }
        return false
    }

    // MARK: - Shared decrypt/encrypt

    private func openContent(at url: URL, unlock: UnlockData) throws -> KDBXContent {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VaultServiceError.fileNotFound(url.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VaultServiceError.openFailed("could not read file: \(error)")
        }
        do {
            return try KDBXReader.parse(data, unlockData: unlock)
        } catch {
            throw VaultServiceError.openFailed("\(error)")
        }
    }

    /// Serializes `content` and writes it atomically to `url`, keeping a
    /// `.bak` sibling of whatever was there before. Pattern taken directly
    /// from KDBXKit's own CLI (`Sources/KDBXCLICore/VaultWriting.swift`).
    private func write(_ content: KDBXContent, unlock: UnlockData, to url: URL) throws {
        let stream = OutputStream(toMemory: ())
        stream.open()
        do {
            try KDBXWriter(to: stream).write(content, unlockData: unlock)
        } catch {
            throw VaultWriteError.writeFailed("\(error)")
        }
        guard let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
            throw VaultWriteError.writeFailed("memory stream returned no data after KDBXWriter finished")
        }
        do {
            try AtomicFileWriter.write(data, to: url, backup: true)
        } catch {
            throw VaultWriteError.writeFailed("\(error)")
        }
    }
}
