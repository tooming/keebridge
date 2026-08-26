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
    /// the Argon2id KDF pass. Callers that need to avoid re-paying that
    /// cost on every read should call `openVault` once and reuse the
    /// returned `KDBXContent` with the `in content:` methods below, rather
    /// than calling the `at url:` convenience methods repeatedly (each of
    /// those opens fresh, KDF included, every time — correct for a single
    /// one-off read, wasteful for repeated reads in the same session).
    public func preHashKeyData(forPassword password: String) -> Data {
        UnlockData(masterPassword: password).keyDataBytes.toData()
    }

    // MARK: - Opening (the only methods that touch disk + pay the KDF cost)

    /// Decrypts and parses the vault, returning the full `KDBXContent` for
    /// the caller to hold onto and reuse with the `in content:` methods
    /// below — this is the expensive call (disk I/O + Argon2id); everything
    /// else that operates on an already-open `KDBXContent` is cheap,
    /// in-memory, and safe to call as often as needed (e.g. on every list
    /// selection) without re-paying that cost.
    public func openVault(at url: URL, masterPassword: String) throws -> KDBXContent {
        try openContent(at: url, unlock: UnlockData(masterPassword: masterPassword))
    }

    /// Same as `openVault(at:masterPassword:)`, unlocking from a
    /// previously-cached pre-hash (see `preHashKeyData`) instead of a
    /// plaintext password.
    public func openVault(at url: URL, rawKeyData: Data) throws -> KDBXContent {
        try openContent(at: url, unlock: UnlockData(rawKeyData: rawKeyData))
    }

    /// Lightweight metadata for every login-type entry in an already-open
    /// vault (title, username, URL, and the *names* of any custom fields).
    /// Never returns a field *value* other than title/username/URL. Pure
    /// in-memory walk — no I/O, no KDF, safe to call repeatedly.
    public func listEntries(in content: KDBXContent) -> [VaultLoginEntry] {
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

    /// Opens the vault fresh from disk and lists its entries in one call —
    /// convenience for one-off reads (VaultProbe, tests). Pays the full
    /// I/O + KDF cost every time; prefer `openVault` once + `listEntries(in:)`
    /// repeatedly for anything that reads more than once in a session.
    public func listEntries(at url: URL, masterPassword: String) throws -> [VaultLoginEntry] {
        listEntries(in: try openVault(at: url, masterPassword: masterPassword))
    }

    /// Same as `listEntries(at:masterPassword:)`, unlocking from a cached
    /// pre-hash instead.
    public func listEntries(at url: URL, rawKeyData: Data) throws -> [VaultLoginEntry] {
        listEntries(in: try openVault(at: url, rawKeyData: rawKeyData))
    }

    // MARK: - Field reveal (credential-selection time only)

    /// Decrypts and returns a single field's *value* for one entry, by UUID
    /// and field key, from an already-open vault. Pure in-memory walk +
    /// inner-stream-cipher decrypt (fast, not Argon2) — no I/O, no KDF.
    public func revealField(in content: KDBXContent, entryUUID: String, fieldKey: String) -> String? {
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

    /// Opens the vault fresh from disk and reveals one field in one call —
    /// convenience for one-off reads. See `revealField(in:entryUUID:fieldKey:)`
    /// for the reusable, no-KDF form.
    public func revealField(at url: URL, masterPassword: String, entryUUID: String, fieldKey: String) throws -> String? {
        revealField(in: try openVault(at: url, masterPassword: masterPassword), entryUUID: entryUUID, fieldKey: fieldKey)
    }

    /// Same as `revealField(at:masterPassword:entryUUID:fieldKey:)`, unlocking
    /// from a cached pre-hash instead.
    public func revealField(at url: URL, rawKeyData: Data, entryUUID: String, fieldKey: String) throws -> String? {
        revealField(in: try openVault(at: url, rawKeyData: rawKeyData), entryUUID: entryUUID, fieldKey: fieldKey)
    }

    // MARK: - TOTP (credential-selection time only)

    /// Reveals the `otp` field (the otpauth:// URI KeePassXC/pykeepass
    /// store TOTP secrets under — confirmed field name, see VaultService's
    /// header) and returns the current 6-digit-by-default code, from an
    /// already-open vault. `nil` if the entry has no `otp` field at all
    /// (most entries don't). Pure in-memory — no I/O, no KDF.
    public func currentTOTPCode(in content: KDBXContent, entryUUID: String) throws -> String? {
        guard let otpauthURI = revealField(in: content, entryUUID: entryUUID, fieldKey: "otp"),
              !otpauthURI.isEmpty
        else { return nil }
        let params = try TOTPGenerator.parse(otpauthURI: otpauthURI)
        return TOTPGenerator.currentCode(for: params)
    }

    /// Opens the vault fresh from disk and computes the current TOTP code
    /// in one call — convenience for one-off reads. See
    /// `currentTOTPCode(in:entryUUID:)` for the reusable, no-KDF form.
    public func currentTOTPCode(at url: URL, masterPassword: String, entryUUID: String) throws -> String? {
        try currentTOTPCode(in: try openVault(at: url, masterPassword: masterPassword), entryUUID: entryUUID)
    }

    /// Same as `currentTOTPCode(at:masterPassword:entryUUID:)`, unlocking
    /// from a cached pre-hash instead.
    public func currentTOTPCode(at url: URL, rawKeyData: Data, entryUUID: String) throws -> String? {
        try currentTOTPCode(in: try openVault(at: url, rawKeyData: rawKeyData), entryUUID: entryUUID)
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

    /// Same as `updateEntry(uuid:applying:at:rawKeyData:)`, unlocking from a
    /// plaintext master password instead — for callers with no cached
    /// pre-hash (e.g. a CLI prompting via `getpass()`, not backed by
    /// Keychain).
    public func updateEntry(uuid: String, applying draft: EntryDraft, at url: URL, masterPassword: String) throws {
        try updateEntry(uuid: uuid, applying: draft, at: url, unlock: UnlockData(masterPassword: masterPassword))
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

    /// Same as `deleteEntry(uuid:at:rawKeyData:)`, unlocking from a
    /// plaintext master password instead — for callers with no cached
    /// pre-hash (e.g. a CLI prompting via `getpass()`, not backed by
    /// Keychain).
    public func deleteEntry(uuid: String, at url: URL, masterPassword: String) throws {
        try deleteEntry(uuid: uuid, at: url, unlock: UnlockData(masterPassword: masterPassword))
    }

    private func deleteEntry(uuid: String, at url: URL, unlock: UnlockData) throws {
        var content = try openContent(at: url, unlock: unlock)
        let found = Self.removeEntry(in: &content.database.root.group, uuid: uuid)
        guard found else { throw VaultWriteError.entryNotFound(uuid) }
        try write(content, unlock: unlock, to: url)
    }

    /// Reveals an existing entry's editable fields, for populating an edit
    /// form, from an already-open vault. `nil` if no entry with that UUID
    /// exists. Pure in-memory — no I/O, no KDF.
    public func revealEntry(in content: KDBXContent, uuid: String) -> EntryDraft? {
        guard let entry = Self.findEntry(in: content.database.root.group, uuid: uuid) else {
            return nil
        }
        func value(_ key: String) -> String {
            entry.strings.first(where: { $0.key == key })?.value.revealedString ?? ""
        }
        return EntryDraft(
            title: value("Title"), username: value("UserName"), password: value("Password"),
            url: value("URL"), notes: value("Notes")
        )
    }

    /// Opens the vault fresh from disk and reveals one entry in one call —
    /// convenience for one-off reads. See `revealEntry(in:uuid:)` for the
    /// reusable, no-KDF form. Throws `.entryNotFound` if the UUID doesn't
    /// exist (unlike the `in content:` form, which returns `nil` — kept as
    /// a throw here to match this method's existing, already-tested
    /// behavior).
    public func revealEntry(uuid: String, at url: URL, rawKeyData: Data) throws -> EntryDraft {
        let content = try openVault(at: url, rawKeyData: rawKeyData)
        guard let draft = revealEntry(in: content, uuid: uuid) else {
            throw VaultWriteError.entryNotFound(uuid)
        }
        return draft
    }

    /// Same as `revealEntry(uuid:at:rawKeyData:)`, unlocking from a plaintext
    /// master password instead — for callers with no cached pre-hash (e.g. a
    /// CLI prompting via `getpass()`, not backed by Keychain). Needed so a
    /// CLI `update` command can reveal-then-merge (only overwrite the fields
    /// the caller actually specified) instead of blanking out every field
    /// `updateEntry`'s full-replace semantics don't hear about.
    public func revealEntry(uuid: String, at url: URL, masterPassword: String) throws -> EntryDraft {
        let content = try openVault(at: url, masterPassword: masterPassword)
        guard let draft = revealEntry(in: content, uuid: uuid) else {
            throw VaultWriteError.entryNotFound(uuid)
        }
        return draft
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
