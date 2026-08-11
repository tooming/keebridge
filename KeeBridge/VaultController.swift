// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Owns the container app's side of the AutoFill flow: picking the vault
// file, unlocking with the master password, caching the pre-hash in this
// app's own (unshared — see KeychainStore) Keychain item, mirroring the
// vault directly into the extension's sandbox container (see
// KeeBridgeConfig.vaultMirrorURLForApp — that's what the sandboxed
// extension actually reads; this app reads the real Google-Drive-synced
// file directly, since it's deliberately unsandboxed), and pushing entries
// into ASCredentialIdentityStore. Never writes to the *source* vault —
// read-only against it, per the v1 scope decision (KeePassXC stays the
// editor).

import Foundation
import AppKit
import AuthenticationServices
import KeeBridgeCore
import os

@MainActor
final class VaultController: ObservableObject {
    // Same subsystem as the extension's Logger, different category — one
    // `log stream --predicate 'subsystem == "com.martintooming.KeeBridge"'`
    // shows both processes interleaved by timestamp.
    private let log = Logger(subsystem: "com.martintooming.KeeBridge", category: "app")

    @Published var statusMessage: String = "No vault selected."
    @Published var isUnlocked = false
    @Published var identityCount = 0
    @Published var lastError: String?
    @Published var hasVaultSelected = false
    // Kept around after unlock/refresh (previously discarded once identities
    // were registered) — the secrets-management browser UI needs this list.
    // Non-secret metadata only, same as before (title/username/url/custom
    // field names) — field *values* are still only ever revealed on demand.
    @Published var entries: [VaultLoginEntry] = []

    // Immutable + Sendable, so nonisolated: lets the heavy Argon2id/Keychain
    // work in unlock()/refreshFromCache() run off the main actor without an
    // isolation hop for every call.
    nonisolated private let vaultService = VaultService()
    nonisolated private let keychain = KeychainStore()
    private var vaultURL: URL?
    private var isWorking = false

    // In-memory only, for this process's lifetime — never persisted.
    // Without this, every refreshFromCache() (which fires on every window
    // activation, potentially frequently) hit Keychain fresh and
    // re-prompted Touch ID every single time, which is what "continuously
    // prompting for Touch ID" was — not a hang, just a missing cache the
    // extension already had and the app didn't.
    private var cachedPreHash: Data?

    // Just remembering this app's own last pick between launches — no
    // cross-process sharing needed, so plain UserDefaults.standard.
    private let defaults = UserDefaults.standard
    private let vaultPathDefaultsKey = "vaultFilePath"

    init() {
        resolveExistingPath()
    }

    // MARK: - Vault file selection

    func pickVaultFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose your vault.kdbx"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        defaults.set(url.path, forKey: vaultPathDefaultsKey)
        vaultURL = url
        hasVaultSelected = true
        statusMessage = "Vault selected: \(url.lastPathComponent). Enter master password to unlock."
    }

    private func resolveExistingPath() {
        guard let path = defaults.string(forKey: vaultPathDefaultsKey),
              FileManager.default.fileExists(atPath: path)
        else { return }

        let url = URL(fileURLWithPath: path)
        vaultURL = url
        hasVaultSelected = true
        statusMessage = "Vault: \(url.lastPathComponent). Enter master password to unlock."
    }

    // MARK: - Unlock

    // Argon2id key derivation is deliberately slow, and this app's own
    // Keychain read/write plus the file copy add more I/O on top — none of
    // that may run on the main actor, or the app's UI (and, worse, a
    // Timer-driven refresh mid-Safari-interaction) freezes exactly the way
    // the extension did before its own fix. unlock()/refreshFromCache()
    // are thin @MainActor wrappers that hop straight to a detached task for
    // the real work and only touch @Published state again once it's done.

    func unlock(password: String) {
        guard let vaultURL, !isWorking else {
            if vaultURL == nil { lastError = "Pick the vault file first." }
            return
        }
        isWorking = true
        statusMessage = "Unlocking…"

        log.notice("unlock: starting Argon2id verify on background task")
        Task.detached(priority: .userInitiated) { [vaultService, keychain, log] in
            do {
                let entries = try vaultService.listEntries(at: vaultURL, masterPassword: password)
                let preHash = vaultService.preHashKeyData(forPassword: password)
                try keychain.store(preHash)
                try Self.mirrorVaultToExtension(from: vaultURL)
                log.notice("unlock: succeeded, \(entries.count) entries, mirror written to \(KeeBridgeConfig.vaultMirrorURLForApp().path, privacy: .public)")

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.isUnlocked = true
                    self.lastError = nil
                    self.cachedPreHash = preHash
                    self.entries = entries
                    self.populateIdentityStore(entries: entries)
                    self.startWatching()
                }
            } catch {
                log.error("unlock: failed: \(String(describing: error))")
                await MainActor.run { [weak self] in
                    self?.isWorking = false
                    self?.lastError = "Unlock failed: \(error)"
                    self?.isUnlocked = false
                }
            }
        }
    }

    // MARK: - Refresh (post-unlock, no password needed)

    // Fires on didBecomeActive and from the manual button. isWorking makes
    // overlapping calls a no-op rather than stacking work; cachedPreHash
    // (set on unlock, or here on first successful Keychain read) means at
    // most one Touch ID prompt per app process lifetime, not one per call.
    func refreshFromCache() {
        guard let vaultURL, !isWorking else { return }
        isWorking = true

        if let cachedPreHash {
            refresh(vaultURL: vaultURL, preHash: cachedPreHash)
            return
        }

        Task.detached(priority: .userInitiated) { [keychain] in
            let preHash = try? keychain.read(reason: "Unlock KeeBridge to refresh saved logins")
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let preHash else {
                    self.isWorking = false
                    self.statusMessage = "No cached key yet — unlock with your master password once."
                    return
                }
                self.cachedPreHash = preHash
                self.refresh(vaultURL: vaultURL, preHash: preHash)
            }
        }
    }

    private func refresh(vaultURL: URL, preHash: Data) {
        Task.detached(priority: .userInitiated) { [vaultService] in
            do {
                // Re-read the real (Google-Drive-synced) source and
                // re-mirror it, so this also picks up edits made in
                // KeePassXC since the last refresh — not just
                // re-registering stale data.
                let entries = try vaultService.listEntries(at: vaultURL, rawKeyData: preHash)
                try Self.mirrorVaultToExtension(from: vaultURL)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.isUnlocked = true
                    self.entries = entries
                    self.populateIdentityStore(entries: entries)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isWorking = false
                    self?.lastError = "Refresh failed: \(error)"
                }
            }
        }
    }

    // MARK: - Writing (v2: create/edit/delete entries, create a new vault)

    // Same shape as unlock()/refreshFromCache(): thin @MainActor wrapper,
    // real work (Argon2id + file write) on a detached task, re-list +
    // re-mirror + re-register identities on success so the browser UI, the
    // extension, and Safari's suggestions all reflect the change immediately.

    /// Clears in-memory unlock state (not the Keychain item — "Refresh from
    /// cached key" / Touch ID still works after this). Doesn't touch the
    /// vault file or the extension's mirror; purely a UI-state reset so the
    /// browser closes and the locked screen shows again.
    func lock() {
        isUnlocked = false
        entries = []
        cachedPreHash = nil
    }

    func createNewVault(databaseName: String, masterPassword: String) {
        guard !isWorking else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = databaseName.isEmpty ? "Vault.kdbx" : "\(databaseName).kdbx"
        panel.message = "Choose where to save the new vault"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isWorking = true
        statusMessage = "Creating vault…"
        Task.detached(priority: .userInitiated) { [vaultService] in
            do {
                try vaultService.createVault(at: url, masterPassword: masterPassword, databaseName: databaseName)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.defaults.set(url.path, forKey: self.vaultPathDefaultsKey)
                    self.vaultURL = url
                    self.hasVaultSelected = true
                    self.lastError = nil
                    self.statusMessage = "Vault created: \(url.lastPathComponent). Enter your new master password to unlock."
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isWorking = false
                    self?.lastError = "Could not create vault: \(error)"
                }
            }
        }
    }

    // Each of these three follows the exact shape unlock()/refresh() use:
    // Task.detached captures only Sendable values ([vaultService]), never
    // `self` directly — every touch of `self` happens inside its own
    // `MainActor.run { [weak self] in ... }`. Deliberately NOT factored into
    // a shared `self`-bound helper: an earlier version of this file did that
    // and it silently forced a strong `self` capture on the outer detached
    // closure (referencing `self.someMethod(...)` directly in a closure body
    // captures `self`, even when only reached via a nested `await`) —
    // repetitive but correct beats DRY but capturing-self-by-accident here.

    func createEntry(_ draft: VaultService.EntryDraft) {
        guard let vaultURL, let preHash = cachedPreHash, !isWorking else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) { [vaultService] in
            do {
                _ = try vaultService.createEntry(draft, at: vaultURL, rawKeyData: preHash)
                let entries = try vaultService.listEntries(at: vaultURL, rawKeyData: preHash)
                try Self.mirrorVaultToExtension(from: vaultURL)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.entries = entries
                    self.populateIdentityStore(entries: entries)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isWorking = false
                    self?.lastError = "Could not add entry: \(error)"
                }
            }
        }
    }

    func updateEntry(uuid: String, applying draft: VaultService.EntryDraft) {
        guard let vaultURL, let preHash = cachedPreHash, !isWorking else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) { [vaultService] in
            do {
                try vaultService.updateEntry(uuid: uuid, applying: draft, at: vaultURL, rawKeyData: preHash)
                let entries = try vaultService.listEntries(at: vaultURL, rawKeyData: preHash)
                try Self.mirrorVaultToExtension(from: vaultURL)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.entries = entries
                    self.populateIdentityStore(entries: entries)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isWorking = false
                    self?.lastError = "Could not save changes: \(error)"
                }
            }
        }
    }

    func deleteEntry(uuid: String) {
        guard let vaultURL, let preHash = cachedPreHash, !isWorking else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) { [vaultService] in
            do {
                try vaultService.deleteEntry(uuid: uuid, at: vaultURL, rawKeyData: preHash)
                let entries = try vaultService.listEntries(at: vaultURL, rawKeyData: preHash)
                try Self.mirrorVaultToExtension(from: vaultURL)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.entries = entries
                    self.populateIdentityStore(entries: entries)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isWorking = false
                    self?.lastError = "Could not delete entry: \(error)"
                }
            }
        }
    }

    /// Reveals a single entry's editable fields for populating the edit
    /// form. Not run on a background task by the caller — SwiftUI forms
    /// need the value before they can render, so this is a small, deliberate
    /// exception to the "never block main on Argon2id" rule elsewhere in
    /// this file. Acceptable here: it's a single-entry reveal (already fast
    /// relative to a full listEntries), gated behind the user explicitly
    /// choosing to edit one specific entry, not something that fires
    /// automatically.
    func revealEntryForEditing(uuid: String) -> VaultService.EntryDraft? {
        guard let vaultURL, let preHash = cachedPreHash else { return nil }
        return try? vaultService.revealEntry(uuid: uuid, at: vaultURL, rawKeyData: preHash)
    }

    // MARK: - Mirroring into the extension's sandbox container

    /// Copies the source vault straight into the extension's own sandbox
    /// container. This app can read `source` directly (it's unsandboxed);
    /// the sandboxed extension can't reach `source` at all, but can freely
    /// read anything inside its own container — and since this app is
    /// unsandboxed, it can write there too (sandboxing restricts what the
    /// *sandboxed* process can reach, not what another same-user process
    /// does to that directory). Static + nonisolated: pure function of its
    /// argument, no instance state, safe to call from any thread.
    nonisolated private static func mirrorVaultToExtension(from source: URL) throws {
        let mirrorURL = KeeBridgeConfig.vaultMirrorURLForApp()
        let fm = FileManager.default
        try fm.createDirectory(at: mirrorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: mirrorURL.path) {
            try fm.removeItem(at: mirrorURL)
        }
        try fm.copyItem(at: source, to: mirrorURL)
    }

    // MARK: - ASCredentialIdentityStore

    private func populateIdentityStore(entries: [VaultLoginEntry]) {
        let store = ASCredentialIdentityStore.shared
        store.getState { [weak self] state in
            guard let self else { return }
            self.log.notice("ASCredentialIdentityStore.getState: isEnabled=\(state.isEnabled)")
            guard state.isEnabled else {
                Task { @MainActor in
                    self.statusMessage = "KeeBridge isn't enabled as an AutoFill provider yet — enable it in System Settings > Passwords."
                }
                return
            }

            let passwordIdentities: [ASPasswordCredentialIdentity] = entries.compactMap { (entry) -> ASPasswordCredentialIdentity? in
                guard !entry.url.isEmpty, !entry.username.isEmpty else { return nil }
                let serviceId = ASCredentialServiceIdentifier(identifier: entry.url, type: .URL)
                return ASPasswordCredentialIdentity(
                    serviceIdentifier: serviceId,
                    user: entry.username,
                    recordIdentifier: entry.uuid
                )
            }

            // Entries with a TOTP secret (the "otp" custom field) get an
            // additional one-time-code identity, same service/record, so
            // the system can offer OTP autofill on top of the password.
            let otpIdentities: [ASOneTimeCodeCredentialIdentity] = entries.compactMap { (entry) -> ASOneTimeCodeCredentialIdentity? in
                guard !entry.url.isEmpty, entry.customFieldKeys.contains("otp") else { return nil }
                let serviceId = ASCredentialServiceIdentifier(identifier: entry.url, type: .URL)
                return ASOneTimeCodeCredentialIdentity(
                    serviceIdentifier: serviceId,
                    label: entry.username.isEmpty ? entry.title : entry.username,
                    recordIdentifier: entry.uuid
                )
            }

            let identities: [ASCredentialIdentity] = passwordIdentities + otpIdentities
            let registeredCount = identities.count
            self.log.notice("registering \(passwordIdentities.count) password identities + \(otpIdentities.count) OTP identities")

            store.replaceCredentialIdentities(identities) { success, error in
                self.log.notice("replaceCredentialIdentities: success=\(success), count=\(registeredCount), error=\(error.map(String.init(describing:)) ?? "nil", privacy: .public)")
                Task { @MainActor in
                    if let error {
                        self.lastError = "Identity store update failed: \(error)"
                        return
                    }
                    self.identityCount = registeredCount
                    let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                    self.statusMessage = success
                        ? "Last synced \(time) — \(registeredCount) identities registered."
                        : "Identity store update reported failure."
                }
            }
        }
    }

    // MARK: - Watching for vault changes

    private var activationObserver: NSObjectProtocol?

    /// Safe to call more than once (unlock() does, every time) — always
    /// tears down the previous observer first. Without this, every
    /// unlock() stacked another NSApplication.didBecomeActiveNotification
    /// observer that was never removed, so repeated unlocks meant repeated
    /// concurrent refreshFromCache() calls on every window activation —
    /// each doing its own Argon2id run. That's what was spinning the app's
    /// CPU.
    ///
    /// No blind polling Timer on purpose (there was one — every 45s,
    /// forever — combined with no in-memory pre-hash cache at the time,
    /// that alone was a Touch ID prompt every 45 seconds for as long as
    /// the app stayed open, independent of anything happening in Safari).
    /// The identity store is already current from the last unlock/refresh;
    /// refreshing again only matters once you've actually edited the
    /// vault, which on-foreground + the manual button both cover without
    /// needing a background timer at all.
    private func startWatching() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFromCache() }
        }
    }
}
