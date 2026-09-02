// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// v1 scope: passwords + TOTP. Read-only against the vault — never writes.
//
// Passkey assertion (v4): completeCredential now also handles an incoming
// ASPasskeyCredentialRequest by signing with PasskeyCrypto against an
// existing entry's stored key — see completePasskeyAssertion below.
//
// Passkey registration (v5): prepareInterface(forPasskeyRegistration:)
// creates a brand-new passkey — see beginPasskeyRegistration/
// completePasskeyRegistration below. Unlike assertion, the incoming
// request carries no recordIdentifier (no vault entry has been chosen
// yet): v1 policy is auto-attach on a single URL-host match against the
// relying party ID, falling back to the same CredentialListView the
// manual password picker uses for zero/multiple matches. This is a WRITE
// (VaultService.setPasskey), unlike every other v1 flow in this file —
// straight into this extension's own sandboxed vault mirror, which the
// app's mirrorVaultToExtension merges back into the real source vault the
// next time it re-mirrors (VaultService.mergeExtensionOriginatedPasskeys).
// Conditional passkey registration (v6):
// performWithoutUserInteractionIfPossible(passkeyRegistration:) — see the
// dedicated MARK below. This opts into SupportsConditionalPasskeyRegistration
// (Info.plist), a separate capability from `ProvidesPasskeys`/
// prepareInterface(forPasskeyRegistration:) above (confirmed via Apple's
// DocC JSON API and cross-checked against Dashlane's own shipped
// implementation, github.com/Dashlane/apple-apps, for the exact override
// signature). No UI is allowed in this path at all, so it's deliberately
// far more conservative than the interactive flow about when to register
// silently — see that MARK's own doc comment for the exact conditions.
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
// - Argon2id key derivation (inside VaultService.openVault) is deliberately
//   slow CPU work with no UI dependency, and DOES need to move off main —
//   that's what workQueue is for.
//
// v3 (session content cache): the vault is opened via `openVault` at most
// once per `contentCacheTTL` window, then held in `cachedContent` — reveals
// against an already-open KDBXContent (`revealField(in:)`,
// `currentTOTPCode(in:)`) are pure in-memory operations (inner-stream-cipher
// decrypt only, not Argon2) and run directly on the main thread, no
// workQueue hop needed. This is what actually fixed "each field on a page
// takes a moment" (the earlier `cachedPreHash` fix only removed the
// repeated Touch ID *prompt* — the repeated Argon2 *cost* underneath it
// was still happening on every field until this). `isWorking` is now owned
// exclusively by the top-level flow (showUnlockOrProceed through to
// proceed(withContent:)) — the downstream complete*/showList methods don't
// set/check it themselves anymore, since they're now instant/synchronous
// once content is available and would otherwise reject themselves against
// a flag the outer flow already holds true.
//
// Reliability: repeated real-world hangs during testing outlasted several
// attempts to pin down the exact concurrency cause. Every entry point goes
// through `respond(...)`, which guarantees `completeRequest`/`cancelRequest`
// fires at most once AND within a bounded time (`watchdogSeconds`) no
// matter what happens internally — including a second overlapping
// invocation, which gets cancelled immediately instead of silently dropped.

import AppKit
import SwiftUI
import AuthenticationServices
import KeeBridgeCore
import KDBXKit
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
    private var pendingPasskeyRegistrationRequest: ASCredentialRequest?

    // STATIC, not instance: confirmed via logging that the system creates
    // a fresh CredentialProviderViewController instance per field (username,
    // password, OTP each got their own instance) even though the host
    // PROCESS is reused across them. An instance property would reset every
    // time, defeating the whole point — this is what caused Touch ID three
    // times for one page. Kept for the lifetime of the process only — never
    // persisted to disk.
    private static var cachedPreHash: Data?

    // The decrypted vault, held for up to contentCacheTTL (v3). Same
    // static-not-instance reasoning as cachedPreHash. Bounded, unlike
    // cachedPreHash: the extension has no explicit refresh trigger a user
    // can reach for (the app has a manual button), so without *some* bound
    // a long-lived Safari session could keep serving vault data from
    // before the last KeePassXC edit indefinitely. Expiring this alone
    // costs one background Argon2 pass to refresh, not a new Touch ID
    // prompt, as long as cachedPreHash is still warm.
    private static var cachedContent: KDBXContent?
    private static var cachedContentDate: Date?
    private static let contentCacheTTL: TimeInterval = 5 * 60

    private static func validCachedContent() -> KDBXContent? {
        guard let content = cachedContent, let date = cachedContentDate,
              Date().timeIntervalSince(date) < contentCacheTTL
        else { return nil }
        return content
    }

    private var isWorking = false
    private var hasResponded = false
    private var watchdogItem: DispatchWorkItem?

    // v3 fallout, found via real-world testing: once reveals became
    // sub-millisecond (session-cached content, no per-field Argon2), a
    // fresh request could call completeRequest() before the system had
    // even finished PRESENTING this view controller's popover — confirmed
    // in the log (✓ completeRequest fired, THEN viewWillAppear/
    // viewDidAppear, then nothing: no viewWillDisappear, no deinit, the
    // popover just sat there empty/black forever). The pre-v3 code never
    // hit this because the ~3s+ Argon2id pass always gave the popover
    // plenty of time to finish appearing first — this bug always existed,
    // v3 just made it fast enough to matter. Fix: only actually invoke
    // completeRequest/cancelRequest for the auto-fill-a-specific-credential
    // path once viewDidAppear has actually fired; the 30s watchdog is
    // already a real backstop if it somehow never does. Deliberately NOT
    // applied to every respond call — provideCredentialWithoutUserInteraction's
    // cancel legitimately fires with no view ever appearing at all, and
    // completeSelection (the manual list) is inherently already-visible
    // (the user just clicked in it), so gating those would only add a
    // pointless delay or, worse, a real hang.
    private var hasAppeared = false
    private var afterAppear: (() -> Void)?

    private func runAfterAppear(_ action: @escaping () -> Void) {
        if hasAppeared {
            action()
        } else {
            afterAppear = action
        }
    }

    // MARK: - Lifecycle (if the system tears this instance down mid-flight,
    // every [weak self] closure below silently drops its result — this is
    // how we'd actually see that happening instead of guessing).

    override func viewDidLoad() {
        super.viewDidLoad()
        // Extension hosts (Safari's credential picker) size the popover
        // from this — without it, the popover can end up zero/tiny-sized
        // and whatever we embed is technically in the view hierarchy but
        // never actually visible.
        preferredContentSize = NSSize(width: 380, height: 220)
        // A bare NSView with no explicit background can render as a solid
        // black rectangle in this popover host before anything is embedded
        // (e.g. during the first-load Argon2id wait, before openContentThenProceed
        // finishes) — seen for real during v3 testing. Costs nothing to set
        // even though most fills now complete before this would ever be
        // visible.
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        log.notice("viewDidLoad, preferredContentSize=\(String(describing: self.preferredContentSize))")
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        log.notice("viewWillAppear, window=\(String(describing: self.view.window))")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        log.notice("viewDidAppear, window=\(String(describing: self.view.window))")
        hasAppeared = true
        if let afterAppear {
            self.afterAppear = nil
            afterAppear()
        }
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
        log.notice("→ prepareCredentialList(for:) called, \(serviceIdentifiers.count) identifiers, isWorking=\(self.isWorking), hasCachedContent=\(Self.validCachedContent() != nil)")
        beginRequest()
        pendingServiceIdentifiers = serviceIdentifiers
        pendingCredentialRequest = nil
        pendingPasskeyRegistrationRequest = nil
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
        log.notice("→ prepareInterfaceToProvideCredential(for:) called, isWorking=\(self.isWorking), hasCachedContent=\(Self.validCachedContent() != nil)")
        beginRequest()
        pendingCredentialRequest = credentialRequest
        pendingPasskeyRegistrationRequest = nil
        pendingServiceIdentifiers = []
        showUnlockOrProceed()
    }

    // MARK: - Passkey registration (system asks us to create a NEW passkey)

    @available(macOS 14.0, *)
    override func prepareInterface(forPasskeyRegistration registrationRequest: any ASCredentialRequest) {
        log.notice("→ prepareInterface(forPasskeyRegistration:) called, isWorking=\(self.isWorking), hasCachedContent=\(Self.validCachedContent() != nil)")
        beginRequest()
        pendingPasskeyRegistrationRequest = registrationRequest
        pendingCredentialRequest = nil
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

    @available(macOS 14.0, *)
    private func respondComplete(with credential: ASPasskeyAssertionCredential) {
        guard !hasResponded else {
            log.error("respondComplete(passkey assertion) called AFTER already responded — ignored")
            return
        }
        hasResponded = true
        watchdogItem?.cancel()
        isWorking = false
        log.notice("✓ completeAssertionRequest(using:) — passkey assertion")
        extensionContext.completeAssertionRequest(using: credential, completionHandler: nil)
    }

    private func respondComplete(with credential: ASPasskeyRegistrationCredential) {
        guard !hasResponded else {
            log.error("respondComplete(passkey registration) called AFTER already responded — ignored")
            return
        }
        hasResponded = true
        watchdogItem?.cancel()
        isWorking = false
        log.notice("✓ completeRegistrationRequest(using:) — passkey registration")
        extensionContext.completeRegistrationRequest(using: credential, completionHandler: nil)
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

        if let content = Self.validCachedContent() {
            log.debug("using in-memory cached content, skipping Keychain/Touch ID/Argon2id entirely")
            proceed(withContent: content)
            return
        }
        guard vaultURL != nil else {
            log.error("no vault mirror found at \(KeeBridgeConfig.vaultMirrorURLForExtension().path) — telling user to open KeeBridge first")
            showMessage("Open KeeBridge on this Mac and pick your vault.kdbx first.")
            return
        }

        // From here on, isWorking stays true continuously until either
        // proceed(withContent:) hands off to a terminal respond*() call, or
        // we fall back to showUnlockPrompt() (legitimately idle, waiting on
        // the user to type a password) — NOT toggled off and back on
        // between phases, since the content-open step below is a real
        // asynchronous gap (unlike the old all-synchronous handoff), and a
        // false isWorking during that gap would let a second invocation
        // slip in and start a redundant, concurrent content-open.
        isWorking = true

        if let cachedPreHash = Self.cachedPreHash {
            log.debug("have cached pre-hash but no valid cached content — opening vault in background, no Touch ID needed")
            openContentThenProceed(preHash: cachedPreHash)
            return
        }

        // No cached key at all — Touch ID, main thread.
        log.notice("calling keychain.read() on main thread — this is where the Touch ID sheet should appear")
        let preHash = try? keychain.read(reason: "Unlock KeeBridge to autofill")
        log.notice("keychain.read() returned, gotKey=\(preHash != nil)")
        if let preHash {
            Self.cachedPreHash = preHash
            openContentThenProceed(preHash: preHash)
        } else {
            isWorking = false
            showUnlockPrompt()
        }
    }

    /// Opens the vault (background thread — Argon2id, must stay off main)
    /// from an already-known pre-hash, caches the result, then proceeds.
    /// Caller must already have `isWorking = true` set.
    private func openContentThenProceed(preHash: Data) {
        guard let vaultURL else {
            isWorking = false
            showMessage("Open KeeBridge on this Mac and pick your vault.kdbx first.")
            return
        }
        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                let content = try self.vaultService.openVault(at: vaultURL, rawKeyData: preHash)
                self.log.notice("openContentThenProceed: opened+cached content, \(self.vaultService.listEntries(in: content).count) entries")
                DispatchQueue.main.async {
                    Self.cachedContent = content
                    Self.cachedContentDate = Date()
                    self.proceed(withContent: content)
                }
            } catch {
                self.log.error("openContentThenProceed: openVault failed: \(String(describing: error))")
                DispatchQueue.main.async {
                    self.respondCancel(withError: error)
                }
            }
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
                // Argon2id KDF — background thread, no UI dependency.
                // openVault also verifies the password is correct (throws
                // if not) and gives us the content to cache directly, no
                // separate verify-then-open round trip needed.
                let content = try self.vaultService.openVault(at: vaultURL, masterPassword: password)
                let preHash = self.vaultService.preHashKeyData(forPassword: password)
                self.log.notice("handleUnlock: Argon2id verify succeeded, hopping to main to store in Keychain")
                DispatchQueue.main.async {
                    do {
                        // Keychain write, deliberately on main (see the
                        // threading note at the top of this file) — no
                        // Touch ID prompt on write, but keep every
                        // Keychain call on the same thread on principle.
                        try self.keychain.store(preHash)
                        Self.cachedPreHash = preHash
                        Self.cachedContent = content
                        Self.cachedContentDate = Date()
                        self.log.notice("handleUnlock: stored, proceeding")
                        self.proceed(withContent: content)
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

    private func proceed(withContent content: KDBXContent) {
        log.debug("proceed(withContent:) — havePendingCredentialRequest=\(self.pendingCredentialRequest != nil), havePendingPasskeyRegistrationRequest=\(self.pendingPasskeyRegistrationRequest != nil)")
        if #available(macOS 14.0, *), let registrationRequest = pendingPasskeyRegistrationRequest {
            // Same viewDidAppear gating as the completeCredential branch
            // below — beginPasskeyRegistration may complete synchronously
            // (single auto-attach match) or show a picker first, either
            // way only safe once the popover has actually finished
            // presenting.
            runAfterAppear { [weak self] in
                self?.beginPasskeyRegistration(for: registrationRequest, content: content)
            }
        } else if let credentialRequest = pendingCredentialRequest {
            // Gated on viewDidAppear — see the hasAppeared/afterAppear doc
            // comment near their declaration for why: completeCredential
            // ends in completeRequest(), which the system apparently
            // can't handle gracefully if it arrives before this view
            // controller has finished presenting.
            runAfterAppear { [weak self] in
                self?.completeCredential(for: credentialRequest, content: content)
            }
        } else {
            showList(content: content)
        }
    }

    // MARK: - Completing a specific credential request
    //
    // Pure in-memory reveals now (v3) — instant, safe directly on main
    // thread, no workQueue hop needed. isWorking is NOT set/checked in
    // these anymore: it's owned by the top-level flow above, which is
    // already true by the time any of these run.

    private func completeCredential(for credentialRequest: ASCredentialRequest, content: KDBXContent) {
        log.notice("completeCredential: recordIdentifier=\(credentialRequest.credentialIdentity.recordIdentifier ?? "nil", privacy: .public), isOTP=\(credentialRequest.credentialIdentity is ASOneTimeCodeCredentialIdentity)")

        if #available(macOS 14.0, *), let passkeyRequest = credentialRequest as? ASPasskeyCredentialRequest {
            completePasskeyAssertion(for: passkeyRequest, content: content)
            return
        }

        guard let recordIdentifier = credentialRequest.credentialIdentity.recordIdentifier else {
            log.error("completeCredential: missing recordIdentifier — cancelling")
            respondCancel(.credentialIdentityNotFound)
            return
        }

        if credentialRequest.credentialIdentity is ASOneTimeCodeCredentialIdentity {
            completeOTPCredential(content: content, recordIdentifier: recordIdentifier)
        } else {
            completePasswordCredential(
                content: content, recordIdentifier: recordIdentifier,
                username: credentialRequest.credentialIdentity.user
            )
        }
    }

    // MARK: - Passkey assertion (v4 — signing in with an EXISTING stored passkey)
    //
    // Registration (creating a new passkey) is not handled here — see the
    // header comment. This only ever reads (`revealPasskeyPrivateKeyPEM`),
    // never writes.

    @available(macOS 14.0, *)
    private func completePasskeyAssertion(for request: ASPasskeyCredentialRequest, content: KDBXContent) {
        guard let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity,
              let recordIdentifier = identity.recordIdentifier
        else {
            log.error("completePasskeyAssertion: missing passkey credential identity/recordIdentifier — cancelling")
            respondCancel(.credentialIdentityNotFound)
            return
        }
        guard let privateKeyPEM = vaultService.revealPasskeyPrivateKeyPEM(in: content, entryUUID: recordIdentifier) else {
            log.error("completePasskeyAssertion: no stored private key for this entry — cancelling")
            respondCancel(.credentialIdentityNotFound)
            return
        }

        do {
            // No attestedCredentialData on an assertion (spec §6.1) — that's
            // registration-only. signCount 0: see authenticatorData's own
            // doc comment for why that's a legitimate, common choice.
            let authenticatorData = try PasskeyCrypto.authenticatorData(
                relyingPartyID: identity.relyingPartyIdentifier, signCount: 0
            )
            // WebAuthn spec §6.3.3: the signed message is
            // authenticatorData ‖ clientDataHash.
            let signature = try PasskeyCrypto.sign(
                authenticatorData + request.clientDataHash, withPrivateKeyPEM: privateKeyPEM
            )
            log.notice("completePasskeyAssertion: signed — relyingParty=\(identity.relyingPartyIdentifier, privacy: .public)")
            respondComplete(with: ASPasskeyAssertionCredential(
                userHandle: identity.userHandle,
                relyingParty: identity.relyingPartyIdentifier,
                signature: signature,
                clientDataHash: request.clientDataHash,
                authenticatorData: authenticatorData,
                credentialID: identity.credentialID
            ))
        } catch {
            log.error("completePasskeyAssertion: threw: \(String(describing: error))")
            respondCancel(withError: error)
        }
    }

    // MARK: - Passkey registration (v5 — creating a NEW passkey)
    //
    // See the header comment for the overall policy. Unlike every other
    // v1 flow, this WRITES (VaultService.setPasskey) — into this
    // extension's own sandboxed vault mirror, same file `vaultURL`/
    // cachedPreHash already point at for reads.

    /// Vault entries whose URL host matches `rpID` — same host-matching
    /// idea `prepareCredentialList`'s manual list uses for service
    /// identifiers, plus a subdomain check: a WebAuthn relying party ID is
    /// a registrable domain suffix of the actual origin (spec §5.1.3), so
    /// a vault entry's URL host is often a subdomain of it (e.g. host
    /// "accounts.example.com" for rpID "example.com"), not an exact
    /// match. Shared between the interactive registration flow below and
    /// the conditional/silent one further down.
    private func matchingEntries(forRelyingPartyID rpID: String, in entries: [VaultLoginEntry]) -> [VaultLoginEntry] {
        entries.filter { entry in
            guard let host = URL(string: entry.url)?.host else { return false }
            return host == rpID || host.hasSuffix("." + rpID)
        }
    }

    @available(macOS 14.0, *)
    private func beginPasskeyRegistration(for request: ASCredentialRequest, content: KDBXContent) {
        guard let passkeyRequest = request as? ASPasskeyCredentialRequest,
              let identity = passkeyRequest.credentialIdentity as? ASPasskeyCredentialIdentity
        else {
            log.error("beginPasskeyRegistration: unexpected request/identity type — cancelling")
            respondCancel(.failed)
            return
        }

        let entries = vaultService.listEntries(in: content)
        let rpID = identity.relyingPartyIdentifier
        let matching = matchingEntries(forRelyingPartyID: rpID, in: entries)

        if matching.count == 1 {
            completePasskeyRegistration(for: passkeyRequest, identity: identity, entry: matching[0])
        } else {
            // Zero or multiple matches — ask the user, same picker the
            // manual password list uses. isWorking=false here for the same
            // reason showList sets it: legitimately idle, waiting on a
            // click, not mid-request-processing.
            log.notice("beginPasskeyRegistration: \(matching.count) URL-host matches for rpID=\(rpID, privacy: .public) — showing picker")
            isWorking = false
            preferredContentSize = NSSize(width: 380, height: 360)
            embed(CredentialListView(entries: matching.isEmpty ? entries : matching) { [weak self] entry in
                self?.completePasskeyRegistration(for: passkeyRequest, identity: identity, entry: entry)
            })
        }
    }

    @available(macOS 14.0, *)
    private func completePasskeyRegistration(
        for request: ASPasskeyCredentialRequest, identity: ASPasskeyCredentialIdentity, entry: VaultLoginEntry
    ) {
        guard let vaultURL, let preHash = Self.cachedPreHash else {
            log.error("completePasskeyRegistration: missing vault URL/cached key — cancelling")
            respondCancel(.failed)
            return
        }

        // WebAuthn spec §6.3.2 step 4: the AUTHENTICATOR (us) picks the
        // credential ID — never trust/reuse whatever (if anything) the
        // system populated on the incoming identity for a not-yet-existing
        // credential.
        let credentialID = PasskeyCrypto.generateCredentialID()
        let privateKeyPEM = PasskeyCrypto.generatePrivateKeyPEM()

        do {
            let coseKey = try PasskeyCrypto.coseEncodedPublicKey(forPrivateKeyPEM: privateKeyPEM)
            let authenticatorData = try PasskeyCrypto.authenticatorData(
                relyingPartyID: identity.relyingPartyIdentifier,
                signCount: 0,
                attestedCredentialData: .init(
                    // All-zero AAGUID — see AttestedCredentialData's own
                    // doc comment (PasskeyCrypto.swift) for why that's a
                    // legitimate, common choice, not a placeholder left
                    // unfinished.
                    aaguid: Data(repeating: 0, count: 16),
                    credentialID: credentialID,
                    coseEncodedPublicKey: coseKey
                )
            )
            let attestationObject = PasskeyCrypto.attestationObject(authenticatorData: authenticatorData)

            try vaultService.setPasskey(
                uuid: entry.uuid,
                relyingParty: identity.relyingPartyIdentifier,
                credentialID: credentialID,
                privateKeyPEM: privateKeyPEM,
                username: identity.userName,
                userHandle: identity.userHandle,
                at: vaultURL,
                rawKeyData: preHash
            )
            // That write landed in the mirror on disk, not in the
            // in-memory Self.cachedContent this request read from —
            // invalidate the cache so the next reveal within
            // contentCacheTTL re-reads from disk (cheap: cachedPreHash is
            // still warm, no repeat Touch ID) instead of silently serving
            // pre-registration content.
            Self.cachedContent = nil
            Self.cachedContentDate = nil

            log.notice("completePasskeyRegistration: registered — relyingParty=\(identity.relyingPartyIdentifier, privacy: .public)")
            respondComplete(with: ASPasskeyRegistrationCredential(
                relyingParty: identity.relyingPartyIdentifier,
                clientDataHash: request.clientDataHash,
                credentialID: credentialID,
                attestationObject: attestationObject
            ))
        } catch {
            log.error("completePasskeyRegistration: threw: \(String(describing: error))")
            respondCancel(withError: error)
        }
    }

    // MARK: - Conditional passkey registration (v6 — silent/background, macOS 15+)
    //
    // SupportsConditionalPasskeyRegistration (Info.plist) opts into this as
    // a separate capability from ProvidesPasskeys/prepareInterface(forPasskeyRegistration:)
    // above (confirmed via Apple's DocC JSON API and cross-checked against
    // Dashlane's own shipped implementation, github.com/Dashlane/apple-apps —
    // same override, same ASPasskeyCredentialRequest parameter type). The
    // system calls this INSTEAD of the interactive path when a site's
    // conditional-mediation WebAuthn call might be satisfiable silently
    // (e.g. right after a password-only sign-in on a site that also
    // supports passkeys).
    //
    // No UI is permitted here at all — Apple's docs are explicit: "This
    // request cannot show UI; ASExtensionErrorCodeUserInteractionRequired
    // is treated like any other error." Cancelling with exactly that code
    // tells the system to fall back to the normal interactive flow instead
    // of failing the whole page.
    //
    // Deliberately conservative: this WRITES a brand-new WebAuthn
    // credential with no human in the loop, so getting the conditions
    // wrong risks silently creating passkeys the user never asked for.
    // Registers only when ALL of:
    //   1. The vault is ALREADY unlocked in memory (Self.validCachedContent())
    //      — never attempts Keychain/Touch ID or the master-password
    //      prompt, since neither can show UI either; this only ever fires
    //      within an existing contentCacheTTL window from some earlier,
    //      human-triggered unlock.
    //   2. Exactly ONE existing entry's URL host matches the relying party
    //      ID (matchingEntries, same rule the interactive flow above
    //      uses) — zero or multiple matches means "not confident enough,"
    //      and unlike the interactive flow there's no picker to fall back
    //      to here, so this cancels instead.
    //   3. That matched entry does NOT already have a passkey — never
    //      silently replace or duplicate an existing one.
    // Meeting all three reuses the exact same write path
    // (completePasskeyRegistration) the interactive flow already uses.
    @available(macOS 15.0, *)
    override func performWithoutUserInteractionIfPossible(passkeyRegistration registrationRequest: ASPasskeyCredentialRequest) {
        log.notice("→ performWithoutUserInteractionIfPossible(passkeyRegistration:) called")
        beginRequest()
        guard let identity = registrationRequest.credentialIdentity as? ASPasskeyCredentialIdentity else {
            log.error("performWithoutUserInteractionIfPossible(passkeyRegistration:): unexpected credential identity type — cancelling")
            respondCancel(.userInteractionRequired)
            return
        }
        guard let content = Self.validCachedContent() else {
            log.notice("performWithoutUserInteractionIfPossible(passkeyRegistration:): no in-memory unlocked vault — cancelling, no Keychain/Touch ID attempted")
            respondCancel(.userInteractionRequired)
            return
        }

        let rpID = identity.relyingPartyIdentifier
        let matching = matchingEntries(forRelyingPartyID: rpID, in: vaultService.listEntries(in: content))
        guard matching.count == 1, vaultService.passkeyMetadata(in: content, entryUUID: matching[0].uuid) == nil else {
            log.notice("performWithoutUserInteractionIfPossible(passkeyRegistration:): \(matching.count) URL-host matches (need exactly 1, no existing passkey) for rpID=\(rpID, privacy: .public) — cancelling")
            respondCancel(.userInteractionRequired)
            return
        }

        completePasskeyRegistration(for: registrationRequest, identity: identity, entry: matching[0])
    }

    private func completePasswordCredential(content: KDBXContent, recordIdentifier: String, username: String) {
        let password = vaultService.revealField(in: content, entryUUID: recordIdentifier, fieldKey: "Password")
        log.notice("completePasswordCredential: revealField returned, found=\(password != nil)")
        guard let password else {
            respondCancel(.credentialIdentityNotFound)
            return
        }
        respondComplete(with: ASPasswordCredential(user: username, password: password))
    }

    private func completeOTPCredential(content: KDBXContent, recordIdentifier: String) {
        do {
            let code = try vaultService.currentTOTPCode(in: content, entryUUID: recordIdentifier)
            log.notice("completeOTPCredential: currentTOTPCode returned, found=\(code != nil)")
            guard let code else {
                respondCancel(.credentialIdentityNotFound)
                return
            }
            respondComplete(with: ASOneTimeCodeCredential(code: code))
        } catch {
            log.error("completeOTPCredential: threw: \(String(describing: error))")
            respondCancel(withError: error)
        }
    }

    // MARK: - Manual list

    private func showList(content: KDBXContent) {
        // Transitioning to "list shown, waiting on the user to pick one" —
        // legitimately idle, not mid-request-processing anymore.
        isWorking = false
        let entries = vaultService.listEntries(in: content)
        let matchingHosts = Set(pendingServiceIdentifiers.compactMap { URL(string: $0.identifier)?.host ?? $0.identifier })
        let matching = matchingHosts.isEmpty
            ? entries
            : entries.filter { entry in
                guard let host = URL(string: entry.url)?.host else { return false }
                return matchingHosts.contains(host)
            }
        preferredContentSize = NSSize(width: 380, height: 360)
        embed(CredentialListView(entries: matching.isEmpty ? entries : matching) { [weak self] entry in
            self?.completeSelection(entry: entry, content: content)
        })
    }

    private func completeSelection(entry: VaultLoginEntry, content: KDBXContent) {
        guard let password = vaultService.revealField(in: content, entryUUID: entry.uuid, fieldKey: "Password") else { return }
        respondComplete(with: ASPasswordCredential(user: entry.username, password: password))
    }

    // MARK: - UI plumbing

    private func embed(_ view: some View) {
        log.debug("embed: swapping view controller content, view.bounds=\(String(describing: self.view.bounds)), window=\(String(describing: self.view.window))")
        for child in children {
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        // .onExitCommand catches the Escape key regardless of which subview
        // currently has focus (including the search field's text editor) —
        // without it, Escape had no handler anywhere in this popover and
        // silently did nothing instead of cancelling the request.
        let hosting = NSHostingController(rootView: AnyView(
            view.onExitCommand { [weak self] in
                self?.handleEscape()
            }
        ))
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

    private func handleEscape() {
        log.notice("⎋ Escape pressed — cancelling")
        respondCancel(.userCanceled)
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

    @State private var query: String = ""

    private var filtered: [VaultLoginEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(query)
                || entry.username.localizedCaseInsensitiveContains(query)
                || entry.url.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(filtered, id: \.uuid) { entry in
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
    }
}
