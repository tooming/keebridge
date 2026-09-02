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
import KDBXKit
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

    // The decrypted vault, held for the session (v3). Without this, every
    // single read — clicking a list row, opening Edit — independently
    // re-opened the file from disk AND re-ran the full Argon2id KDF, same
    // cost as unlock() itself; that's what KeePassXC does NOT do (it derives
    // the key once and holds the decrypted database in memory), and why it
    // has no equivalent lag. `KDBXContent`'s protected fields still use
    // `.lazyInnerCipher` internally (see KDBXKit's ProtectedString.swift) —
    // caching this does not mean plaintext secrets sit in memory, only the
    // same post-KDF-pre-inner-cipher state KeePassXC itself holds. Refreshed
    // on unlock, on refreshFromCache() (manual + throttled auto), and after
    // every successful write.
    private var cachedContent: KDBXContent?

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
                let content = try vaultService.openVault(at: vaultURL, masterPassword: password)
                let entries = vaultService.listEntries(in: content)
                let preHash = vaultService.preHashKeyData(forPassword: password)
                try keychain.store(preHash)
                try Self.mirrorVaultToExtension(from: vaultURL, rawKeyData: preHash)
                log.notice("unlock: succeeded, \(entries.count) entries, mirror written to \(KeeBridgeConfig.vaultMirrorURLForApp().path, privacy: .public)")

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.isUnlocked = true
                    self.lastError = nil
                    self.cachedPreHash = preHash
                    self.cachedContent = content
                    self.entries = entries
                    self.lastRefreshDate = Date()
                    self.populateIdentityStore(entries: entries, content: content)
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
                // re-registering stale data. Re-caches cachedContent too,
                // since this is the mechanism (manual button + throttled
                // auto-refresh) that's supposed to pick up external edits.
                let content = try vaultService.openVault(at: vaultURL, rawKeyData: preHash)
                let entries = vaultService.listEntries(in: content)
                try Self.mirrorVaultToExtension(from: vaultURL, rawKeyData: preHash)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.isUnlocked = true
                    self.cachedContent = content
                    self.entries = entries
                    self.lastRefreshDate = Date()
                    self.populateIdentityStore(entries: entries, content: content)
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
        cachedContent = nil
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
                // Write path unchanged on purpose (see the v3 plan): fresh
                // open-mutate-write, not against a possibly-stale cache —
                // that's what keeps the window for clobbering a concurrent
                // KeePassXC edit small. Only the POST-write re-list below
                // uses openVault (vs. plain listEntries) so it can refresh
                // cachedContent too, for free — same Argon2 cost either way.
                _ = try vaultService.createEntry(draft, at: vaultURL, rawKeyData: preHash)
                let content = try vaultService.openVault(at: vaultURL, rawKeyData: preHash)
                let entries = vaultService.listEntries(in: content)
                try Self.mirrorVaultToExtension(from: vaultURL, rawKeyData: preHash)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.cachedContent = content
                    self.entries = entries
                    self.lastRefreshDate = Date()
                    self.populateIdentityStore(entries: entries, content: content)
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
                let content = try vaultService.openVault(at: vaultURL, rawKeyData: preHash)
                let entries = vaultService.listEntries(in: content)
                try Self.mirrorVaultToExtension(from: vaultURL, rawKeyData: preHash)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.cachedContent = content
                    self.entries = entries
                    self.lastRefreshDate = Date()
                    self.populateIdentityStore(entries: entries, content: content)
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
                let content = try vaultService.openVault(at: vaultURL, rawKeyData: preHash)
                let entries = vaultService.listEntries(in: content)
                try Self.mirrorVaultToExtension(from: vaultURL, rawKeyData: preHash)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isWorking = false
                    self.cachedContent = content
                    self.entries = entries
                    self.lastRefreshDate = Date()
                    self.populateIdentityStore(entries: entries, content: content)
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
    /// form / detail view. Plain synchronous method, on purpose (v3): an
    /// earlier version of this ran the Argon2id KDF per call — the same
    /// cost as unlock() itself — synchronously on the caller, which
    /// blocked the main thread on every single list-row click (reported as
    /// "the app is quite slow"). A subsequent fix moved it to a
    /// Task.detached + completion-closure to get it off main, which
    /// *worked* but only treated the symptom — the deeper fix (v3, see the
    /// plan) was caching the decrypted content for the session so this
    /// operation is genuinely instant (pure in-memory, no Argon2, no I/O),
    /// which makes the async indirection unnecessary complexity rather than
    /// a real requirement. This isn't flip-flopping: the earlier fix was
    /// correct for the architecture at the time; this supersedes it now
    /// that the architecture is fixed properly.
    func revealEntryForEditing(uuid: String) -> VaultService.EntryDraft? {
        guard let cachedContent else { return nil }
        return vaultService.revealEntry(in: cachedContent, uuid: uuid)
    }

    /// Read-only passkey metadata (relying party/username/credential ID —
    /// never the private key) for display in `EntryDetailView`. Same
    /// synchronous, no-Argon2, in-memory shape as `revealEntryForEditing`
    /// above — this app's UI never had any passkey visibility before this,
    /// even though the vault format, `VaultService`, and the extension have
    /// supported passkeys for several ROADMAP cycles now; KeePassXC or
    /// `VaultProbe` were the only ways to even confirm an entry had one.
    func passkeyMetadata(uuid: String) -> VaultService.VaultPasskeyMetadata? {
        guard let cachedContent else { return nil }
        return vaultService.passkeyMetadata(in: cachedContent, entryUUID: uuid)
    }

    // MARK: - Mirroring into the extension's sandbox container

    /// Copies the source vault straight into the extension's own sandbox
    /// container. This app can read `source` directly (it's unsandboxed);
    /// the sandboxed extension can't reach `source` at all, but can freely
    /// read anything inside its own container — and since this app is
    /// unsandboxed, it can write there too (sandboxing restricts what the
    /// *sandboxed* process can reach, not what another same-user process
    /// does to that directory). Static + nonisolated: pure function of its
    /// arguments, no instance state, safe to call from any thread.
    ///
    /// Extension→app write-back (see
    /// `docs/done/2026-08-31-passkey-registration-write-path-spike.md`):
    /// before overwriting the mirror, checks whether it changed
    /// independently of this app's own last write to it (mtime compared
    /// against `KeeBridgeConfig.vaultMirrorLastWriteMarkerURLForApp()`,
    /// the sidecar this function itself maintains) — if so, something the
    /// extension wrote there (a freshly-registered passkey, once
    /// registration exists) would otherwise be silently lost the moment
    /// this overwrite happens, so it's merged into `source` first via
    /// `VaultService.mergeExtensionOriginatedPasskeys`. Best-effort: a
    /// merge failure is logged, not thrown — this app's own write must
    /// still land even if the merge-back can't complete (e.g. a corrupt
    /// or unreadable mirror), same as the mirror having simply never
    /// existed yet.
    nonisolated private static func mirrorVaultToExtension(from source: URL, rawKeyData: Data) throws {
        let mirrorURL = KeeBridgeConfig.vaultMirrorURLForApp()
        let markerURL = KeeBridgeConfig.vaultMirrorLastWriteMarkerURLForApp()
        let fm = FileManager.default
        try fm.createDirectory(at: mirrorURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fm.fileExists(atPath: mirrorURL.path), mirrorChangedSinceLastAppWrite(mirrorURL: mirrorURL, markerURL: markerURL) {
            let log = Logger(subsystem: "com.martintooming.KeeBridge", category: "app")
            do {
                let merged = try VaultService().mergeExtensionOriginatedPasskeys(
                    fromMirrorAt: mirrorURL, intoSourceAt: source, rawKeyData: rawKeyData
                )
                if merged > 0 {
                    log.notice("mirrorVaultToExtension: merged \(merged) extension-originated passkey(s) back into the source vault")
                }
            } catch {
                log.error("mirrorVaultToExtension: merge-back failed, proceeding with mirror overwrite anyway: \(String(describing: error))")
            }
        }

        if fm.fileExists(atPath: mirrorURL.path) {
            try fm.removeItem(at: mirrorURL)
        }
        try fm.copyItem(at: source, to: mirrorURL)
        recordLastAppWrite(mirrorURL: mirrorURL, markerURL: markerURL)
    }

    /// True when the mirror's current modification date doesn't match
    /// what `recordLastAppWrite` recorded after this app's own last write
    /// to it — i.e. something else touched the file since. `false`
    /// (nothing to merge) whenever either date is unavailable: no marker
    /// yet (first mirror ever, or it was deleted) has nothing to compare
    /// against, and an unreadable mirror mtime means the merge attempt
    /// below would fail anyway. A small tolerance absorbs sub-second
    /// precision loss from the marker's text round-trip.
    nonisolated private static func mirrorChangedSinceLastAppWrite(mirrorURL: URL, markerURL: URL) -> Bool {
        guard let markerData = try? Data(contentsOf: markerURL),
              let recordedString = String(data: markerData, encoding: .utf8),
              let recorded = TimeInterval(recordedString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let actual = try? mirrorURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return false }
        return abs(actual.timeIntervalSince1970 - recorded) > 1.0
    }

    /// Records the mirror's OWN resulting modification date right after
    /// this app just wrote it — not simply "now", since `copyItem` may
    /// preserve `source`'s original date rather than stamping the copy
    /// with the current time. Reading the mirror's actual post-write date
    /// back keeps this self-consistent with what
    /// `mirrorChangedSinceLastAppWrite` later compares it against,
    /// regardless of which behavior `copyItem` actually has. Best-effort:
    /// failing to record this just means the next call treats the mirror
    /// as "changed" and does a (harmless, no-op) merge check.
    nonisolated private static func recordLastAppWrite(mirrorURL: URL, markerURL: URL) {
        guard let mtime = try? mirrorURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return }
        try? Data(String(mtime.timeIntervalSince1970).utf8).write(to: markerURL, options: .atomic)
    }

    // MARK: - ASCredentialIdentityStore

    /// `content` is needed only to look up each passkey-bearing entry's
    /// relying party/credential ID/user handle (`VaultService.passkeyMetadata`
    /// — pure in-memory, no Argon2/I/O) — every call site already has it in
    /// scope from the same `openVault`/mirror step that produced `entries`.
    private func populateIdentityStore(entries: [VaultLoginEntry], content: KDBXContent) {
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

            // Passkey-bearing entries, likewise. Previously missing
            // entirely: `CredentialProviderViewController.completePasskeyAssertion`
            // has been able to sign an assertion since the assertion-wiring
            // ROADMAP item landed, but without a matching identity
            // registered here, the system has no way to know KeeBridge
            // holds a passkey for a given relying party/credential ID in
            // the first place, so it could never actually route an
            // `ASPasskeyCredentialRequest` to this app for one — same
            // requirement real third-party credential providers document
            // ("without this, iOS won't offer our credential provider
            // during sign-in") and the same thing Proton Pass's own macOS
            // credential provider does for its passkeys. `userHandle` is
            // non-optional on `ASPasskeyCredentialIdentity`, so an entry
            // missing it (shouldn't happen for anything this app itself
            // registered, but the 9 informational-only Proton-Pass-carried
            // passkeys never got real key material at all) is skipped
            // rather than guessed at.
            let passkeyIdentities: [ASPasskeyCredentialIdentity] = entries.compactMap { (entry) -> ASPasskeyCredentialIdentity? in
                guard entry.isPasskey,
                      let metadata = self.vaultService.passkeyMetadata(in: content, entryUUID: entry.uuid),
                      let relyingParty = metadata.relyingParty,
                      let credentialID = metadata.credentialID,
                      let userHandle = metadata.userHandle
                else { return nil }
                return ASPasskeyCredentialIdentity(
                    relyingPartyIdentifier: relyingParty,
                    userName: metadata.username ?? entry.username,
                    credentialID: credentialID,
                    userHandle: userHandle,
                    recordIdentifier: entry.uuid
                )
            }

            let identities: [ASCredentialIdentity] = passwordIdentities + otpIdentities + passkeyIdentities
            let registeredCount = identities.count
            self.log.notice("registering \(passwordIdentities.count) password identities + \(otpIdentities.count) OTP identities + \(passkeyIdentities.count) passkey identities")

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
            Task { @MainActor in self?.refreshIfStale() }
        }
    }

    private var lastRefreshDate: Date?
    // didBecomeActiveNotification turned out to fire on internal focus
    // changes too — not just switching back from another app, but opening/
    // interacting with KeeBridge's own sheets (confirmed via the log:
    // identity-store repopulation firing every few seconds while just
    // sitting in the Edit sheet). Every firing republished `entries`
    // (@Published), forcing the actively-open, actively-being-typed-in
    // form to re-render repeatedly — reported as "the edit window has
    // noticeable lag." Throttling to once per 15s keeps the actual intent
    // (pick up edits made in KeePassXC while you were away) without the
    // refresh firing on every internal UI interaction. The manual "Refresh
    // from cached key" button calls refreshFromCache() directly and stays
    // unthrottled — that's explicit user intent, always honor it.
    private static let refreshThrottleInterval: TimeInterval = 15

    private func refreshIfStale() {
        if let lastRefreshDate, Date().timeIntervalSince(lastRefreshDate) < Self.refreshThrottleInterval {
            return
        }
        lastRefreshDate = Date()
        refreshFromCache()
    }
}
