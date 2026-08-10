// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Biometric-gated storage for the vault's KDBX pre-hash (see
// VaultService.preHashKeyData). Deliberately NOT shared between the app and
// extension via a Keychain access group — this team's automatic
// provisioning doesn't reliably grant Keychain Sharing (confirmed against
// the real embedded provisioning profile), so each process (app,
// extension) uses its own default, unshared Keychain item instead and
// unlocks independently.

import Foundation
import Security
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

public enum KeychainStoreError: Error, CustomStringConvertible {
    case unhandledStatus(OSStatus)
    case unexpectedData
    case accessControlCreationFailed

    public var description: String {
        switch self {
        case .unhandledStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "Keychain error \(status): \(message)"
        case .unexpectedData:
            return "Keychain item had unexpected data format"
        case .accessControlCreationFailed:
            return "Could not create SecAccessControl (biometryCurrentSet)"
        }
    }
}

public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = KeeBridgeConfig.keychainService) {
        self.service = service
    }

    /// Stores `data` (the 32-byte KDBX pre-hash) behind a
    /// `.biometryCurrentSet` access-control gate. Overwrites any existing
    /// item for this account — access-control attributes can't be updated
    /// in place, so this deletes first.
    public func store(_ data: Data, account: String = KeeBridgeConfig.vaultKeychainAccount) throws {
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.biometryCurrentSet],
            nil
        ) else {
            throw KeychainStoreError.accessControlCreationFailed
        }

        SecItemDelete(baseQuery(account: account) as CFDictionary)

        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessControl as String] = access

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }
    }

    /// Reads back the pre-hash, prompting Touch ID (via `reason`) if the
    /// item's access control requires it. Returns `nil` if no item exists
    /// yet — i.e. the vault has never been unlocked on this device.
    public func read(account: String = KeeBridgeConfig.vaultKeychainAccount, reason: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true

        #if canImport(LocalAuthentication)
        let context = LAContext()
        context.localizedReason = reason
        query[kSecUseAuthenticationContext as String] = context
        #endif

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainStoreError.unexpectedData }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unhandledStatus(status)
        }
    }

    public func delete(account: String = KeeBridgeConfig.vaultKeychainAccount) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // No kSecAttrAccessGroup — each process (app, extension) uses
            // its own default group. See the file header for why.
            // macOS-specific: SecAccessControl-protected items (ours is
            // .biometryCurrentSet) only exist in the newer Data Protection
            // Keychain, not the legacy file-based one Security framework
            // calls default to on macOS (unlike iOS, where this is the
            // only keychain and the key is a no-op). Omitting this causes
            // SecItemAdd/SecItemCopyMatching to fail with errSecMissing
            // Entitlement (-34018) — confirmed against the real build.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
