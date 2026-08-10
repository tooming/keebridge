// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// v1 scope: passwords only (TOTP surfaced via the container app for manual
// copy until the ASOneTimeCodeCredential path is verified against the real
// SDK). Read-only against the vault — never writes.
//
// This extension is fully independent from the KeeBridge app — it has its
// own local (unshared) Keychain cache and its own unlock prompt the first
// time it's used, rather than relying on the app's cached key. See
// KeeBridgeConfig / KeychainStore for why: this Apple Developer team's
// automatic provisioning doesn't reliably grant cross-process Keychain
// Sharing or App Groups, so each process manages its own unlock instead of
// fighting that.
//
// Threading: two DIFFERENT things are slow here, and they need OPPOSITE
// treatment.
//
// - Keychain reads that need Touch ID (SecItemCopyMatching against a
//   .biometryCurrentSet item) must run on the MAIN thread — moving this to
//   a background queue in an earlier version caused the Touch ID sheet to
//   appear but never resolve. A biometric prompt blocking main briefly
//   while the user responds is normal, expected system UI behavior, not a
//   hang.
// - Argon2id key derivation (inside VaultService.listEntries/revealField)
//   is deliberately slow CPU work with no UI dependency, and DOES need to
//   move off main — that's what workQueue is for.
//
// Reliability: repeated real-world hangs during testing outlasted several
// attempts to pin down the exact concurrency cause (multiple XPC helper
// connections into the same process, `prepareCredentialList` and
// `prepareInterfaceToProvideCredential` apparently both firing for one
// user action, etc.). Rather than keep guessing at root cause while each
// failed guess costs a frozen Safari, every entry point now goes through
// `respond(...)`, which guarantees `completeRequest`/`cancelRequest` fires
// at most once AND within a bounded time (`watchdogSeconds`) no matter
// what happens internally — including a second overlapping invocation,
// which now gets cancelled immediately instead of silently dropped (a
// silently dropped request never resolves for ITS caller, which is a
// plausible independent explanation for Safari hanging even after the
// `isWorking` guard was added).

import AppKit
import SwiftUI
import AuthenticationServices
import KeeBridgeCore
import os

final class CredentialProviderViewController: ASCredentialProviderViewController {

    // Watch live while reproducing an issue:
    //   log stream --predicate 'subsystem == "com.martintooming.KeeBridge"' --level debug --style compact
    // (covers this extension AND the app — both use the same subsystem,
    // different categories, so one stream shows the full picture across
    // both processes in timestamp order.)
    private let log = Logger(subsystem: "com.martintooming.KeeBridge", category: "extension")

    private let vaultService = VaultService()
    private let keychain = KeychainStore()
    private let workQueue = DispatchQueue(label: "com.martintooming.KeeBridge.Provider.work", qos: .userInitiated)

    // Generous on purpose: this has to comfortably cover a human reading
    // the unlock prompt and typing a password, not just the actual
    // Argon2id/Keychain work — it only needs to be finite, not tight.
    private static let watchdogSeconds: TimeInterval = 30

    // Reads the mirror the (unsandboxed) app writes directly into this
    // extension's own sandbox container — no entitlement needed for that,
    // see KeeBridgeConfig.vaultMirrorURLForExtension.
    private var vaultURL: URL? {
        let url = KeeBridgeConfig.vaultMirrorURLForExtension()
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var pendingServiceIdentifiers: [ASCredentialServiceIdentifier] = []
    private var pendingCredentialRequest: ASCredentialRequest?

    // STATIC, not instance: confirmed via logging that the system creates
    // a fresh CredentialProviderViewController instance for every single
    // field (username, password, OTP each got their own instance) even
    // though the host PROCESS is reused across them. An instance property
    // would reset every time, defeating the whole point — this is what
    // caused Touch ID three times for one page. Kept for the lifetime of
    // the process only — never persisted to disk.
    private static var cachedPreHash: Data?

    private var isWorking = false
    private var hasResponded = false
    private var watchdogItem: DispatchWorkItem?

    // MARK: - Lifecycle (if the system tears this instance down mid-flight,
    // every [weak self] closure below silently drops its result — this is
    // how we'd actually see that happening instead of guessing).

    override func viewDidLoad() {
        super.viewDidLoad()
        // Extension hosts (Safari's credential picker) size the popover
        // from this — without it, the popover can end up zero/tiny-sized
        // and whatever we embed is technically in the view hierarchy but
        // never actually visible. This is very likely why "nothing
        // appeared" even though viewDidAppear fired in the log.
        preferredContentSize = NSSize(width: 380, height: 220)
        log.notice("viewDidLoad, preferredContentSize=\(String(describing: self.preferredContentSize))")
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        log.notice("viewWillAppear, window=\(String(describing: self.view.window))")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        log.notice("viewDidAppear, window=\(String(describing: self.view.window))")
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        log.notice("viewWillDisappear")
    }

    deinit {
        // Can't capture `self.log` in deinit safely across all Swift
        // versions — use a fresh Logger call directly.
        Logger(subsystem: "com.martintooming.KeeBridge", category: "extension")
            .error("‼️ CredentialProviderViewController DEINIT — if this fires before a response was sent, the system tore down the view controller mid-flight and no [weak self] closure could complete")
    }

    // MARK: - Manual picker (user explicitly chose "Passwords…")

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        log.notice("→ prepareCredentialList(for:) called, \(serviceIdentifiers.count) identifiers, isWorking=\(self.isWorking), hasCachedKey=\(Self.cachedPreHash != nil)")
        beginRequest()
        pendingServiceIdentifiers = serviceIdentifiers
        pendingCredentialRequest = nil
        showUnlockOrProceed()
    }

    // MARK: - Automatic fill (system asks for a credential with no UI shown yet)

    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        log.notice("→ provideCredentialWithoutUserInteraction(for:) called — always cancels to force the interactive path")
        // Unlocking always needs Touch ID (or, on first use, typing the
        // master password), both of which need UI. Tell the system to
        // fall back to the interactive path instead. No watchdog needed —
        // this responds immediately, synchronously.
        respondCancel(.userInteractionRequired)
    }

    // MARK: - Interactive fill (system has already decided UI is allowed)

    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
        log.notice("→ prepareInterfaceToProvideCredential(for:) called, isWorking=\(self.isWorking), hasCachedKey=\(Self.cachedPreHash != nil)")
        beginRequest()
        pendingCredentialRequest = credentialRequest
        pendingServiceIdentifiers = []
        showUnlockOrProceed()
    }

    // MARK: - Request lifecycle (every entry point always gets a response)

    /// Called at the top of every override that starts real work. Resets
    /// per-request state and arms the watchdog — from here on, SOMETHING
    /// will call respondComplete/respondCancel within watchdogSeconds no
    /// matter what happens in between.
    private func beginRequest() {
        hasResponded = false
        watchdogItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.log.error("⏱ watchdog fired after \(Self.watchdogSeconds)s — forcing a cancel response")
            self?.respondCancel(.failed)
        }
        watchdogItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.watchdogSeconds, execute: item)
        log.debug("watchdog armed for \(Self.watchdogSeconds)s")
    }

    private func respondComplete(with credential: ASPasswordCredential) {
        guard !hasResponded else {
            log.error("respondComplete called AFTER already responded — ignored (this would have been a crash-risk double-complete)")
            return
        }
        hasResponded = true
        watchdogItem?.cancel()
        isWorking = false
        log.notice("✓ completeRequest(withSelectedCredential:) — user=\(credential.user, privacy: .private)")
        extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
    }

    private func respondComplete(with credential: ASOneTimeCodeCredential) {
        guard !hasResponded else {
            log.error("respondComplete(OTP) called AFTER already responded — ignored")
            return
        }
        hasResponded = true
        watchdogItem?.cancel()
        isWorking = false
        log.notice("✓ completeOneTimeCodeRequest(using:) — OTP code")
        extensionContext.completeOneTimeCodeRequest(using: credential, completionHandler: nil)
    }

    private func respondCancel(_ code: ASExtensionError.Code) {
        guard !hasResponded else {
            log.error("respondCancel(\(code.rawValue)) called AFTER already responded — ignored")
            return
        }
        hasResponded = true
        watchdogItem?.cancel()
        isWorking = false
        log.notice("✗ cancelRequest — code=\(code.rawValue)")
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }

    private func respondCancel(withError error: Error) {
        guard !hasResponded else {
            log.error("respondCancel(withError:) called AFTER already responded — ignored")
            return
        }
        hasResponded = true
        watchdogItem?.cancel()
        isWorking = false
        log.error("✗ cancelRequest — error=\(String(describing: error))")
        extensionContext.cancelRequest(withError: error)
    }

    // MARK: - Unlock (own local cache, own prompt on first use)

    private func showUnlockOrProceed() {
        guard !isWorking else {
            // A second invocation landed while the first was still in
            // flight. Don't silently drop it — that leaves ITS caller
            // waiting forever. Reject it explicitly; the first invocation
            // (still running) is unaffected and will complete normally.
            log.error("showUnlockOrProceed re-entered while isWorking=true — rejecting this invocation")
            respondCancel(.failed)
            return
        }

        if let cachedPreHash = Self.cachedPreHash {
            log.debug("using in-memory cached pre-hash, skipping Keychain/Touch ID entirely")
            proceed(withPreHash: cachedPreHash)
            return
        }
        guard vaultURL != nil else {
            log.error("no vault mirror found at \(KeeBridgeConfig.vaultMirrorURLForExtension().path) — telling user to open KeeBridge first")
            showMessage("Open KeeBridge on this Mac and pick your vault.kdbx first.")
            return
        }

        isWorking = true
        // Deliberately ON the main thread — this triggers the Touch ID
        // sheet, which needs to run here to attach to the extension's
        // window correctly (see the threading note at the top of this
        // file). It blocks main only for as long as the user takes to
        // respond, same as any normal biometric prompt.
        log.notice("calling keychain.read() on main thread — this is where the Touch ID sheet should appear")
        let preHash = try? keychain.read(reason: "Unlock KeeBridge to autofill")
        log.notice("keychain.read() returned, gotKey=\(preHash != nil)")
        isWorking = false
        if let preHash {
            Self.cachedPreHash = preHash
            proceed(withPreHash: preHash)
        } else {
            showUnlockPrompt()
        }
    }

    private func showUnlockPrompt() {
        log.notice("no cached Keychain item — showing own unlock prompt (first use on this device)")
        embed(UnlockView { [weak self] password in
            self?.handleUnlock(password: password)
        })
    }

    private func handleUnlock(password: String) {
        guard let vaultURL, !isWorking else { return }
        isWorking = true
        showMessage("Unlocking…")
        log.notice("handleUnlock: starting Argon2id verify on background queue")

        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Verify the password actually opens the vault before
                // caching its pre-hash — never cache an unverified key.
                // Argon2id KDF — background thread, no UI dependency.
                _ = try self.vaultService.listEntries(at: vaultURL, masterPassword: password)
                let preHash = self.vaultService.preHashKeyData(forPassword: password)
                self.log.notice("handleUnlock: Argon2id verify succeeded, hopping to main to store in Keychain")
                DispatchQueue.main.async {
                    do {
                        // Keychain write, deliberately on main (see the
                        // threading note at the top of this file) — no
                        // Touch ID prompt on write, but keep every
                        // Keychain call on the same thread on principle.
                        try self.keychain.store(preHash)
                        self.isWorking = false
                        Self.cachedPreHash = preHash
                        self.log.notice("handleUnlock: stored, proceeding")
                        self.proceed(withPreHash: preHash)
                    } catch {
                        self.isWorking = false
                        self.log.error("handleUnlock: Keychain store failed: \(String(describing: error))")
                        self.showMessage("Couldn't cache unlock: \(error)")
                    }
                }
            } catch {
                self.log.error("handleUnlock: Argon2id verify failed (wrong password?): \(String(describing: error))")
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.showMessage("Couldn't unlock: \(error)")
                }
            }
        }
    }

    private func proceed(withPreHash preHash: Data) {
        log.debug("proceed(withPreHash:) — havePendingCredentialRequest=\(self.pendingCredentialRequest != nil)")
        if let credentialRequest = pendingCredentialRequest {
            completeCredential(for: credentialRequest, preHash: preHash)
        } else {
            showList(preHash: preHash)
        }
    }

    // MARK: - Completing a specific credential request

    private func completeCredential(for credentialRequest: ASCredentialRequest, preHash: Data) {
        log.notice("completeCredential: recordIdentifier=\(credentialRequest.credentialIdentity.recordIdentifier ?? "nil", privacy: .public), isOTP=\(credentialRequest.credentialIdentity is ASOneTimeCodeCredentialIdentity)")
        guard let vaultURL, let recordIdentifier = credentialRequest.credentialIdentity.recordIdentifier else {
            log.error("completeCredential: missing vaultURL or recordIdentifier — cancelling")
            respondCancel(.credentialIdentityNotFound)
            return
        }
        guard !isWorking else {
            log.error("completeCredential re-entered while isWorking=true — rejecting")
            respondCancel(.failed)
            return
        }
        isWorking = true

        if credentialRequest.credentialIdentity is ASOneTimeCodeCredentialIdentity {
            completeOTPCredential(vaultURL: vaultURL, recordIdentifier: recordIdentifier, preHash: preHash)
        } else {
            completePasswordCredential(
                vaultURL: vaultURL, recordIdentifier: recordIdentifier, preHash: preHash,
                username: credentialRequest.credentialIdentity.user
            )
        }
    }

    private func completePasswordCredential(vaultURL: URL, recordIdentifier: String, preHash: Data, username: String) {
        showMessage("Filling…")
        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Argon2id run — off main thread on purpose.
                let password = try self.vaultService.revealField(
                    at: vaultURL, rawKeyData: preHash, entryUUID: recordIdentifier, fieldKey: "Password"
                )
                self.log.notice("completePasswordCredential: revealField returned, found=\(password != nil)")
                DispatchQueue.main.async {
                    guard let password else {
                        self.respondCancel(.credentialIdentityNotFound)
                        return
                    }
                    self.respondComplete(with: ASPasswordCredential(user: username, password: password))
                }
            } catch {
                self.log.error("completePasswordCredential: revealField threw: \(String(describing: error))")
                DispatchQueue.main.async {
                    self.respondCancel(withError: error)
                }
            }
        }
    }

    private func completeOTPCredential(vaultURL: URL, recordIdentifier: String, preHash: Data) {
        showMessage("Generating code…")
        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Argon2id run to decrypt the "otp" field, then RFC 6238 —
                // both cheap, but still off main thread on principle.
                let code = try self.vaultService.currentTOTPCode(at: vaultURL, rawKeyData: preHash, entryUUID: recordIdentifier)
                self.log.notice("completeOTPCredential: currentTOTPCode returned, found=\(code != nil)")
                DispatchQueue.main.async {
                    guard let code else {
                        self.respondCancel(.credentialIdentityNotFound)
                        return
                    }
                    self.respondComplete(with: ASOneTimeCodeCredential(code: code))
                }
            } catch {
                self.log.error("completeOTPCredential: threw: \(String(describing: error))")
                DispatchQueue.main.async {
                    self.respondCancel(withError: error)
                }
            }
        }
    }

    // MARK: - Manual list

    private func showList(preHash: Data) {
        guard let vaultURL, !isWorking else { return }
        isWorking = true
        showMessage("Loading…")

        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                let entries = try self.vaultService.listEntries(at: vaultURL, rawKeyData: preHash)
                DispatchQueue.main.async {
                    self.isWorking = false
                    let matchingHosts = Set(self.pendingServiceIdentifiers.compactMap { URL(string: $0.identifier)?.host ?? $0.identifier })
                    let matching = matchingHosts.isEmpty
                        ? entries
                        : entries.filter { entry in
                            guard let host = URL(string: entry.url)?.host else { return false }
                            return matchingHosts.contains(host)
                        }
                    self.preferredContentSize = NSSize(width: 380, height: 360)
                    self.embed(CredentialListView(entries: matching.isEmpty ? entries : matching) { [weak self] entry in
                        self?.completeSelection(entry: entry, preHash: preHash)
                    })
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.showMessage("Could not open vault: \(error)")
                }
            }
        }
    }

    private func completeSelection(entry: VaultLoginEntry, preHash: Data) {
        guard let vaultURL, !isWorking else { return }
        isWorking = true
        showMessage("Filling…")

        workQueue.async { [weak self] in
            guard let self else { return }
            let password = try? self.vaultService.revealField(
                at: vaultURL, rawKeyData: preHash, entryUUID: entry.uuid, fieldKey: "Password"
            )
            DispatchQueue.main.async {
                guard let password else {
                    self.isWorking = false
                    return
                }
                self.respondComplete(with: ASPasswordCredential(user: entry.username, password: password))
            }
        }
    }

    // MARK: - UI plumbing

    private func embed(_ view: some View) {
        log.debug("embed: swapping view controller content, view.bounds=\(String(describing: self.view.bounds)), window=\(String(describing: self.view.window))")
        for child in children {
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let hosting = NSHostingController(rootView: AnyView(view))
        addChild(hosting)
        // Auto Layout constraints, not a one-time `frame = self.view.bounds`
        // assignment: embed() runs BEFORE viewWillAppear (confirmed in the
        // log), i.e. before the system has actually sized this popover, so
        // capturing bounds once here could easily grab a zero/stale size.
        // Constraints keep tracking the real size as it becomes available.
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
        ])
    }

    private func showMessage(_ text: String) {
        log.notice("UI ← \"\(text, privacy: .public)\"")
        embed(Text(text).padding().frame(minWidth: 300))
    }
}

private struct UnlockView: View {
    let onSubmit: (String) -> Void
    @State private var password: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Unlock KeeBridge").bold()
            SecureField("Master password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSubmit(password) }
            Button("Unlock") { onSubmit(password) }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
        }
        .padding()
        .frame(minWidth: 320)
    }
}

private struct CredentialListView: View {
    let entries: [VaultLoginEntry]
    let onSelect: (VaultLoginEntry) -> Void

    var body: some View {
        List(entries, id: \.uuid) { entry in
            Button {
                onSelect(entry)
            } label: {
                VStack(alignment: .leading) {
                    Text(entry.title).bold()
                    Text(entry.username).font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
