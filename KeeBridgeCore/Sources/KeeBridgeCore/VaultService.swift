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

    // MARK: - Shared decrypt

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
}
