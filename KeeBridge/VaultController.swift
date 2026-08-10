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
