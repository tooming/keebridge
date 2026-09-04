# ROADMAP

> **AUTHORITATIVE.** Read together with [`docs/WAYS-OF-WORKING.md`](docs/WAYS-OF-WORKING.md)
> (agent governance — merge/review rules) and
> [`routines/executor.prompt.md`](routines/executor.prompt.md) (the operating contract:
> STEP 1–8 loop, hard rules, self-review + self-merge contract). This file is the
> prioritized backlog; the executor reads it fresh every run and picks the topmost
> unchecked `[ ]` item in "Now / next" that doesn't already have an open PR.

## Operating rules (summary — full detail in `routines/executor.prompt.md`)

- One item per PR, branch prefix `auto/*`, target < ~400 changed lines. Split an
  oversized item into a groomed follow-up entry instead of one giant PR.
- `make ci` (`swift test` against KeeBridgeCore + an unsigned `xcodebuild` build of the
  app and both extension targets + routines drift checks) green is necessary, not
  sufficient — the self-review checklist (gate integrity, secret hygiene,
  crypto/entitlements integrity) is the real gate for this repo's specific risks.
- **Headless only.** No GUI, no Touch ID hardware in the executor's environment. Anything
  needing interactive/hardware verification to be confident it works still ships, with a
  stated "still needs a human eyeball" caveat in the PR body — never silent confidence.
- Full self-merge is authorized (`docs/WAYS-OF-WORKING.md` §0.1) — `main` has no
  deploy-on-merge, unlike the sibling repos that gate on human review.
- Secret hygiene and crypto/entitlements rules are binding hard rules, not suggestions —
  see `routines/executor.prompt.md` STEP 4 and STEP 7.

## Now / next

- [x] ~~Credit card autofill: native-messaging vs. local-decrypt design spike (#3)~~ —
      done, see `docs/done/2026-08-26-card-autofill-design-spike.md`. Recommendation:
      local-decrypt via the same "unsandboxed app mirrors into the sandboxed extension's
      own container" pattern already proven for `KeeBridgeProvider` — no App Group
      needed (this team's provisioning doesn't reliably grant one anyway, per
      `README.md`). `browser.runtime.connectNative`/`SFSafariApplication.dispatchMessage`
      stay available for lock-state signaling, not for shuttling card data itself.
- [x] ~~Credit card autofill implementation (#3)~~ — bundled Safari Web Extension target
      with native local KDBX decrypt, independent biometric Keychain cache, conservative
      card-field aliases, injected user-initiated picker, and requested-field-only fill.
      The app writes a separate read-only mirror straight from the source vault so this
      path cannot interfere with the provider mirror's passkey merge-back. Still needs
      real Safari/Touch ID verification because CI is headless.
- [ ] Automatic proposal of storing the password after logging into a new site (#33) —
      investigated (STEP 6b refill, ROADMAP lane was otherwise empty this cycle), see
      `docs/done/2026-09-02-save-password-proposal-feasibility-spike.md`.
      **BLOCKED on Apple's platform, not on KeeBridge or this environment**: the API this
      needs, `ASCredentialProviderViewController.prepareInterface(for: ASSavePasswordRequest)`/
      `performWithoutUserInteractionIfPossible(savePasswordRequest:)`, is
      `API_UNAVAILABLE(macos, tvos, watchos)` in Apple's own SDK — iOS/visionOS 26.2+
      only, confirmed against Apple's `API_AVAILABLE`/`API_UNAVAILABLE` annotations (via
      the `dotnet/macios` binding project, which mirrors them directly from Apple's
      headers). `KeeBridgeProvider` is a native macOS extension, so there is currently no
      macOS entry point to receive this callback at all — unlike every other
      headless-verification caveat in this ROADMAP, this isn't about code KeeBridge could
      write but this executor can't test; there is no code to write yet. The underlying
      write path this feature would need (`VaultService.createEntry`) already exists.
      Unlike the QR/hybrid-transport finding below, this one may become buildable later
      if Apple ships a macOS counterpart — re-check next time `project.yml`'s
      `MACOSX_DEPLOYMENT_TARGET` moves forward.
- [x] ~~QR scanner's `AVCaptureSession` never stopped if the scan sheet is dismissed
      without a successful scan~~ — done, see
      `docs/done/2026-09-04-qr-scanner-session-cleanup.md`. Found via a STEP 6b re-survey
      (`EntryEditView.swift`'s first full read by any run): `QRCodeCameraPreview.session.
      stopRunning()` was only ever called from the scan-success path in
      `metadataOutput(_:didOutput:from:)` — dismissing the "Scan QR Code…" sheet any other
      way (Escape, click-outside, the parent form's Cancel) left the `AVCaptureSession`
      running indefinitely with no view left to show it, keeping the camera active and the
      system's camera-in-use indicator lit. Fixed by implementing
      `QRCodeCameraView.dismantleNSView(_:coordinator:)` (the `NSViewRepresentable`
      teardown hook SwiftUI calls when the represented view leaves the hierarchy) to stop
      the session unconditionally. Compiled-only (`xcodebuild`) — `KeeBridge`'s SwiftUI/
      AppKit views have no test target, same as every other app-layer change in this
      ROADMAP; confirming the camera indicator actually turns off needs real hardware,
      flagged as a "still needs a human eyeball" caveat in the PR per the HEADLESS ONLY
      rule.
- [ ] `VaultProbe` OTP write parity — `CreateCommand`/`UpdateCommand` have no `--otp-uri`
      flag, so there is no CLI path to create an entry with a TOTP secret, add one to an
      existing entry, or remove one, even though `VaultService.EntryDraft.otpURI` and its
      nil-preserves/empty-removes/non-empty-sets contract are already fully implemented
      and unit-tested (`entryDraftRoundTripsOTPURI` in `VaultWritingTests.swift`) and the
      app's own `EntryEditView` already exposes a full OTP section. `reveal`/`totp` can
      already read OTP secrets; `create`/`update` can't write them. Also a doc-accuracy
      gap: `README.md` claims read/write parity between the app UI and `VaultProbe` that
      doesn't actually hold for this field. Found via the same 2026-09-04 STEP 6b
      re-survey as the item above. Small — add `--otp-uri` to both commands, threading
      straight into `EntryDraft(otpURI:)` (already-tested nil/empty/non-empty semantics
      need no new logic).
- [ ] Test coverage for `PaymentCard.revealPaymentCardFields`'s split-field → combined
      `.expiration` synthesis branch (`result[field] = "\(month)/\(year)"` when an entry
      has separate `Expiration Month`/`Expiration Year` fields but no combined
      `Expiration Date` field) — this is live, secret-touching, extension-reachable code
      (`KeeBridgeCardExtension`'s `content.js` requests `"expiration"` for any
      `autocomplete="cc-exp"` field) with zero test coverage; only the opposite
      direction (combined field → split `.expirationMonth`/`.expirationYear`) is
      currently tested (`paymentCardListingIsMetadataOnlyAndRevealIsRequestScoped` in
      `PaymentCardTests.swift`). Found via the same 2026-09-04 STEP 6b re-survey. Small,
      test-only — add `@Test` case(s) to `PaymentCardTests.swift`.
- [x] ~~Passkey support: storage convention + platform-risk design spike (#4)~~ — done,
      see `docs/done/2026-08-26-passkey-design-spike.md`, **corrected next cycle**: the
      storage-convention finding there (a `webauthn.pem` file attachment) was wrong —
      this project's own `KDBXKit` dependency already models KeePassXC's *actual*
      convention (five `KPEX_PASSKEY_*` custom string fields, source at
      `Sources/KDBXKit/KDBX/Entry+Passkey.swift`), see
      `docs/done/2026-08-26-passkey-metadata-reading.md`. The AAGUID platform-risk
      finding (Developer Forums thread 814547, possibly an intentional Apple privacy
      choice rather than a third-party-specific bug) is unaffected and still stands.
- [x] ~~Passkey support: read-only metadata (#4)~~ — done, see
      `docs/done/2026-08-26-passkey-metadata-reading.md`. `VaultLoginEntry` gained
      `isPasskey`; new `VaultService.passkeyMetadata`/`VaultPasskeyMetadata` expose
      relying party/username/credential ID (never the private key) via KDBXKit's
      already-built `KDBX.Entry` passkey accessors — no new WebAuthn/CBOR logic yet.
- [x] ~~Passkey support: write-side metadata (`VaultService.setPasskey`) (#4)~~ — done,
      see `docs/done/2026-08-26-passkey-write-support.md`. Sets relying party/credential
      ID/private key PEM/username/user handle on an existing entry via KDBXKit's own
      `setPasskey*` methods, leaving every other field (title, username, password, URL,
      notes) untouched — unlike `updateEntry`'s full-replace semantics. Still no
      WebAuthn/CBOR logic; this only stores whatever key material real signing code
      will eventually generate.
- [x] ~~Passkey support: P-256 key generation + ECDSA signing (`PasskeyCrypto`) (#4)~~ —
      done, see `docs/done/2026-08-26-passkey-crypto.md`. `PasskeyCrypto.generatePrivateKeyPEM()`/
      `.sign(_:withPrivateKeyPEM:)`, built entirely on `swift-crypto`'s `P256.Signing` —
      no hand-rolled crypto. Confirmed (not assumed) `P256.Signing.PrivateKey.pemRepresentation`
      emits PKCS#8 PEM, matching what `VaultService.setPasskey`/KDBXKit's
      `KPEX_PASSKEY_PRIVATE_KEY_PEM` convention expects. Still no CBOR/COSE/
      `attestationObject` construction — just the key-gen/signing primitives real
      registration/assertion code will call.
- [x] ~~Passkey support: COSE_Key public-key encoding (`PasskeyCrypto.coseEncodedPublicKey`) (#4)~~
      — done, see `docs/done/2026-08-26-passkey-cose-key.md`. Confirmed
      `P256.Signing.PublicKey.rawRepresentation` is raw `X‖Y` (64 bytes, no `0x04`
      prefix — `x963Representation` is the one that prepends it), then hand-encodes the
      fixed five-field COSE_Key CBOR map (`kty`=2 EC2, `alg`=-7 ES256, `crv`=1 P-256,
      `x`/`y`) per RFC 9053 — the exact structure a WebAuthn `attestationObject` embeds
      as its credential public key. Still no `attestationObject`/`authData` envelope
      construction — just this one CBOR map.
- [x] ~~Passkey support: `authenticatorData` construction (`PasskeyCrypto.authenticatorData`) (#4)~~
      — done, see `docs/done/2026-08-26-passkey-authenticator-data.md`. Builds the WebAuthn
      §6.1 `authData` byte string (`rpIdHash` ‖ `flags` ‖ `signCount` ‖ optional
      `attestedCredentialData`) — the byte string that goes *inside* an `attestationObject`,
      not the CBOR envelope itself. Takes the previously-built COSE_Key bytes as one opaque
      piece of the (also new) `AttestedCredentialData` struct.
- [x] ~~Passkey support: `attestationObject` CBOR envelope construction
      (`PasskeyCrypto.attestationObject`) (#4)~~ — done, see
      `docs/done/2026-08-31-passkey-attestation-object.md`. Wraps `authenticatorData`'s
      output in the 3-entry `{fmt, attStmt, authData}` CBOR map per WebAuthn §6.5.4, using
      `fmt: "none"`/empty `attStmt` (the simplest valid self-attestation — KeeBridge has no
      hardware-attestation chain to prove). The minimal CBOR encoder gained text-string
      (major type 3) support and a general length-prefix helper (byte strings could
      already exceed the old 255-byte-only cap once `attestedCredentialData` is included).
      Groomed off this item's original bullet, which was flagged as needing its own
      sub-items rather than one PR — see the follow-up bullet immediately below for the
      remaining, genuinely-hard-to-verify-headlessly half.
- [x] ~~Passkey support: `ASPasskeyCredentialRequest` assertion (sign-in) handling in
      `KeeBridgeProvider`, against an EXISTING stored passkey (#4)~~ — done, see
      `docs/done/2026-08-31-passkey-assertion-wiring.md`. `CredentialProviderViewController.completeCredential`
      now branches on `credentialRequest as? ASPasskeyCredentialRequest`, reveals the
      matching entry's private key via the new `VaultService.revealPasskeyPrivateKeyPEM`,
      builds `authenticatorData` (no `attestedCredentialData` — assertion-only), signs
      `authenticatorData ‖ clientDataHash` with `PasskeyCrypto.sign`, and responds via
      `extensionContext.completeAssertionRequest(using:)` with an
      `ASPasskeyAssertionCredential`. Reuses the exact same
      `prepareInterfaceToProvideCredential`/`showUnlockOrProceed` path passwords/OTP
      already go through — no new override needed for assertion specifically (confirmed
      against Apple's own DocC JSON API, not guessed). Still inert in a real system flow:
      see the follow-up bullet immediately below for why, and for the remaining,
      genuinely-hard-to-verify-headlessly half.
- [x] ~~Extension→app write-back MERGE PRIMITIVE: `VaultService.mergeExtensionOriginatedPasskeys` (#4)~~
      — done, see `docs/done/2026-08-31-passkey-write-back-merge-primitive.md`. Found while
      scoping passkey registration, NOT previously identified by the original design spike:
      `README.md`'s mirroring is strictly ONE-WAY (the unsandboxed app writes the vault into
      `KeeBridgeProvider`'s own sandbox container; nothing ever reads a change back the
      other way), so an extension-originated write (e.g. a freshly-registered passkey)
      would silently vanish the next time the app re-mirrors — see
      `docs/done/2026-08-31-passkey-registration-write-path-spike.md` for the full
      data-integrity finding. This new `KeeBridgeCore` function copies just the passkey
      fields from a mirror-copy entry onto the matching-UUID source-vault entry (narrow,
      not a general three-way merge — same "touch only the five passkey fields" contract
      `setPasskey` already has), fully unit-tested via `swift test` (happy path, idempotent
      re-run, no-op on a passkey-free mirror, and a defensive no-create-on-source case).
      Still NOT wired into anything that calls it — see the follow-up bullet immediately
      below.
- [x] ~~Wire `mergeExtensionOriginatedPasskeys` into `VaultController.mirrorVaultToExtension` (#4)~~
      — done, see `docs/done/2026-09-01-passkey-writeback-wiring.md`.
      `mirrorVaultToExtension` now takes a `rawKeyData:` parameter (threaded through all 5
      call sites: `unlock`/`refresh`/`createEntry`/`updateEntry`/`deleteEntry`, which all
      already had `preHash` in scope) and, before overwriting the mirror, checks whether it
      changed independently of the app's own last write via mtime (compared against a new
      sidecar marker file, `KeeBridgeConfig.vaultMirrorLastWriteMarkerURLForApp()`) — if so,
      calls `mergeExtensionOriginatedPasskeys` first. Best-effort: a merge failure is
      logged, never thrown, so the app's own write still lands even if the merge-back can't
      complete. Compiled-only (`xcodebuild`), not `swift test`-covered — `VaultController`
      has no test target, same as before this change. **Still open**: hasn't been exercised
      against a real concurrent-edit scenario (the source vault changing externally, e.g.
      via KeePassXC, in the same window) — the merge primitive re-opens the source fresh at
      merge time so this composes correctly in principle (no UUID collision risk), but only
      reasoned about, not tested against a live race. Not a blocker for registration itself
      (that's a separate, pre-existing risk class this change doesn't make worse), but worth
      a human's eventual attention.
- [x] ~~Passkey support: WebAuthn credential ID generation (`PasskeyCrypto.generateCredentialID`) (#4)~~
      — done, see `docs/done/2026-09-01-passkey-credential-id.md`. 16 random bytes via
      swift-crypto's CSPRNG-backed `SymmetricKey`, not Foundation's weaker
      `.random(in:)` — the one primitive the registration item below was still missing.
- [x] ~~Passkey support: registration (creating a NEW passkey from KeeBridge) (#4)~~ —
      done, see `docs/done/2026-09-01-passkey-registration.md`.
      `prepareInterface(forPasskeyRegistration:)` in `KeeBridgeProvider`, using every
      `PasskeyCrypto` primitive built so far, writes the new key material via
      `VaultService.setPasskey` into the extension's own vault mirror (merged back into
      the source vault by the write-back path wired in above), and responds with
      `ASPasskeyRegistrationCredential`. `ProvidesPasskeys: true` is now declared in
      `KeeBridgeProvider/Info.plist` — this also activates the previously-inert passkey
      *assertion* code from earlier in this ROADMAP, since both flows gate on the same
      capability flag. Entry attachment: auto-attach on a single URL-host match against
      the relying party ID (exact or subdomain), falling back to the existing
      `CredentialListView` picker for zero/multiple matches. **Correction to this item's
      earlier text**: `performWithoutUserInteractionIfPossible(passkeyRegistration:)` is
      NOT a prerequisite for declaring `ProvidesPasskeys` — confirmed via Apple's DocC
      JSON API, it's only required for the separate, still-unclaimed
      `SupportsConditionalPasskeyRegistration` capability (silent/background
      registration), which this item does not opt into. Genuinely hard to verify
      headlessly (needs a real Safari passkey-creation flow on real hardware) — flagged
      as a "still needs a human eyeball" caveat in the PR. The 9 Proton-Pass-carried
      passkeys stay informational-only per the design spike's recommendation —
      reconstructing them (separate proprietary double-nested MessagePack format) is
      optional, riskier follow-up, not a blocker.
- [x] ~~QR code scanning for adding a passkey (#7)~~ — investigated now that passkey
      support (#4) has landed, see
      `docs/done/2026-09-01-passkey-qr-hybrid-transport-spike.md`. **Verdict: not
      implementable**, not just hard-to-verify-headlessly — this is WebAuthn hybrid
      transport (caBLE), which requires advertising raw CTAP2 BLE service data via
      `CBPeripheralManager`, an API surface `CoreBluetooth` does not expose to
      third-party apps on iOS/macOS at all (confirmed via Apple's own Developer Forums).
      Same category of platform restriction as the AAGUID-zeroing finding from the
      original passkey design spike — reserved for iCloud Keychain's own system-level
      implementation, not something a third-party `ASCredentialProviderViewController`
      extension can reach with any amount of entitlements or real-hardware testing.
      KeeBridge's landed same-device assertion/registration flows already cover this
      project's actual use case. Left a comment on #7 with this finding; not closed
      automatically — that's the maintainer's call.
- [x] ~~CLI tool feasibility spike (#9)~~ — done, see
      `docs/done/2026-08-26-cli-tool-feasibility-spike.md`. Verdict: feasible and cheap —
      `VaultProbe` already solves the hard parts (KeeBridgeCore integration, non-echoing
      password entry). Follow-up items below are the groomed sequencing it recommended.
- [x] ~~Give `VaultProbe` real subcommands (`list`, `reveal <uuid> <field>`, `totp <uuid>`)~~
      — done, see `docs/done/2026-08-26-vaultprobe-subcommands.md`. Now built on
      `swift-argument-parser`; `make ci`/`ci.yml` gained a `probe-build` step so this
      target is actually gated going forward.
- [x] ~~`--json` output mode for the CLI tool above~~ — done, see
      `docs/done/2026-08-26-vaultprobe-json-output.md`. Every subcommand now takes
      `--json`.
- [x] ~~Add `masterPassword`-based `updateEntry`/`deleteEntry` overloads to
      `VaultService`~~ — done, see `docs/done/2026-08-26-vaultservice-write-overloads.md`.
      Foundation piece discovered while scoping the CLI's write subcommands below: only
      `rawKeyData`-based overloads existed (fine for the app, which has a cached
      pre-hash; not fine for a CLI prompting via `getpass()` with no Keychain). `create`
      already had both forms; `update`/`delete` now do too.
- [x] ~~Add a `masterPassword`-based `revealEntry` overload to `VaultService`~~ — done,
      see `docs/done/2026-08-26-vaultservice-reveal-overload.md`. Second foundation piece
      for the CLI's `update` subcommand: needed so it can reveal-then-merge (only
      overwrite the fields the caller actually specified) instead of blanking every field
      `updateEntry`'s full-replace semantics don't otherwise hear about.
- [x] ~~Write subcommands (`create`/`update`/`delete`) for the CLI tool~~ — done, see
      `docs/done/2026-08-26-vaultprobe-write-subcommands.md`. `update` reveals-then-merges
      so an omitted flag keeps its existing value; the entry's password is never a CLI
      argument on either `create` or `update` (`--set-password` triggers a separate
      `getpass()` prompt instead); `delete` requires `--yes`. This closes out the CLI
      feasibility spike's (#9) full recommended sequencing — `VaultProbe` now has all six
      subcommands (`list`/`reveal`/`totp`/`create`/`update`/`delete`), `--json` on every
      one, and a real `probe-build` CI gate.
- [x] ~~Passkey visibility in the app's own secrets-management UI~~ — done, see
      `docs/done/2026-09-02-passkey-visibility-in-app-ui.md`. Discovered via a STEP 6b
      re-survey (fresh read of `EntryDetailView`/`VaultBrowserView`/`VaultController`):
      passkey support has been built out for several cycles now, but the app's own UI had
      zero visibility into it — KeePassXC/`VaultProbe` were the only ways to confirm an
      entry had one. Read-only: a "Passkey" section in `EntryDetailView` (relying
      party/username/credential ID, never the private key) plus a small icon on
      passkey-bearing rows in `VaultBrowserView`'s list. No new write path — creating/using
      passkeys stays the credential provider extension's job (#4).
- [x] ~~Conditional (silent/background) passkey registration (#4)~~ — done, see
      `docs/done/2026-09-02-conditional-passkey-registration.md`. Discovered via a STEP 6b
      re-survey: the interactive registration PR's header comment had flagged
      `performWithoutUserInteractionIfPossible(passkeyRegistration:)`/
      `SupportsConditionalPasskeyRegistration` as a deliberately-deferred, "still-unclaimed"
      capability, not a permanently-out-of-scope one. Confirmed via Apple's DocC JSON API
      (macOS 15.0+, matching `project.yml`'s deployment target already) and cross-checked
      against Dashlane's own shipped implementation
      (`github.com/Dashlane/apple-apps`) for the exact override signature
      (`ASPasskeyCredentialRequest`, not the more general `ASCredentialRequest` the
      interactive override takes). `CredentialProviderViewController` now overrides it,
      conservatively: registers only when the vault is already unlocked in memory (never
      attempts Keychain/Touch ID — no UI is permitted in this path at all), exactly one
      vault entry's URL host matches the relying party ID, and that entry has no passkey
      yet; anything else cancels with `.userInteractionRequired` so the system falls back
      to the normal interactive flow. Reuses the existing `completePasskeyRegistration`
      write path unchanged. Extracted the host-matching filter (`matchingEntries`) so the
      interactive and conditional flows share one implementation instead of two copies.
      **Genuinely unverifiable headlessly, more so than the interactive flow**: this path
      only ever fires from a real site's conditional-mediation WebAuthn call, which needs
      real Safari + a real relying party + real hardware to trigger at all — flagged as a
      "still needs a human eyeball" caveat in the PR, same as the interactive registration
      item.
- [x] ~~Passkey visibility in `VaultProbe` (the CLI tool)~~ — done, see
      `docs/done/2026-09-02-vaultprobe-passkey-visibility.md`. Discovered via a STEP 6b
      re-survey: `VaultProbe` had zero passkey awareness — the same gap the app's own UI
      had before it (#4's earlier "visibility" item), just in the CLI instead. `list` now
      marks passkey-bearing entries (`isPasskey` in `--json`, a `[passkey]` marker in the
      text output); a new `passkey <uuid>` subcommand prints relying party/username/
      credential ID — never the private key, same read-only scope
      `VaultService.revealPasskeyPrivateKeyPEM` is deliberately excluded from here too.
      Seven subcommands now (`list`/`reveal`/`totp`/`passkey`/`create`/`update`/`delete`).
- [x] ~~README accuracy refresh~~ — done, see
      `docs/done/2026-09-02-readme-accuracy-refresh.md`. Discovered via a STEP 6b
      re-survey: `README.md`'s "What's planned" still listed vault write support and the
      secrets-management UI as future work — both closed before this executor's first run
      — and described passkeys as pure future work too, despite many cycles of shipped
      passkey support. "What works today"/"What's planned" rewritten to match reality;
      "What's planned" now just points at `ROADMAP.md` plus the one genuinely-remaining
      item (credit card autofill). Docs-only, no code changed.
- [x] ~~Register passkey identities in `ASCredentialIdentityStore` (#4)~~ — done, see
      `docs/done/2026-09-02-passkey-identity-store-registration.md`. Discovered via a
      fresh, full read of `VaultController.swift` — a file previously read only in part.
      `populateIdentityStore` registered password and OTP identities but, despite several
      cycles of shipped passkey assertion/registration code, never any
      `ASPasskeyCredentialIdentity` — meaning the system had no way to know KeeBridge holds
      a passkey for a given site at all, so it could never route a WebAuthn assertion
      request to this app for one. Confirmed via real third-party credential-provider
      source (including Proton Pass's own macOS `AutoFillEngine`) that registering these
      identities is the standard, necessary mechanism, not optional polish. Fixed:
      `populateIdentityStore` now also builds one `ASPasskeyCredentialIdentity` per
      passkey-bearing entry (relying party/username/credential ID/user handle, via a
      `VaultService.passkeyMetadata` lookup — no new secret exposure, `userHandle` is
      WebAuthn-opaque non-PII metadata by spec, same classification as `credentialID`).
      `VaultService.VaultPasskeyMetadata` gained the `userHandle` field this needed
      (previously only exposed relying party/username/credential ID); `VaultProbe`'s
      `passkey` subcommand shows it too, for parity. Likely fixes passkey sign-in
      end-to-end rather than just adding a nice-to-have — still needs a human eyeball to
      confirm on real hardware, same headless-verification limit every passkey item in
      this ROADMAP carries.
- [x] ~~Fix `updateEntry` silently deleting an entry's TOTP/passkey fields on
      every edit~~ — done, see
      `docs/done/2026-09-02-update-entry-custom-field-data-loss-fix.md`. **Real data-loss
      bug**, not a hypothetical: `VaultService.updateEntry` replaced `entry.strings`
      wholesale with just the five standard fields (title/username/password/url/notes),
      so editing ANY entry's title/username/etc. through the app's own Edit form, or the
      CLI's `update` subcommand, silently deleted that entry's `otp` TOTP secret and/or
      passkey (`KPEX_PASSKEY_*`) fields the moment it was saved. Present since write
      support (#1) originally shipped, pre-executor; completely untested — `VaultProbe`'s
      `update` reveal-then-merge only ever considered the five standard fields too, so it
      never protected against this either. Fixed: `updateEntry` now preserves every field
      it doesn't know about, only fully replacing the five standard ones (its documented
      contract for those). New regression test
      (`updateEntryPreservesPasskeyAndOtherCustomFields`) exercises this via the real
      `setPasskey`/`updateEntry`/`passkeyMetadata` path. Discovered via a fresh, full read
      of `VaultService.swift`'s write section — no run had read it end-to-end before.

- [x] ~~Payment card visibility in the app's own secrets-management UI + `VaultProbe`~~ —
      done, see `docs/done/2026-09-03-payment-card-visibility-in-app-ui.md`. Discovered via
      a STEP 6b re-survey: the recently-landed Safari card-autofill extension and
      `PaymentCard.swift` had full payment-card recognition, but neither the app's own UI
      nor `VaultProbe` had any visibility into it — the same gap passkeys had before their
      own visibility fix. `VaultLoginEntry` gained `isPaymentCard`; `EntryDetailView`/
      `VaultBrowserView` show a read-only "Payment Card" section/icon (which field types
      are present, never values); `VaultProbe` gained a `card` subcommand and a `list`
      marker, same metadata-only scope as the existing `passkey` subcommand.

## Needs maintainer/human action (not code)

- [ ] Decommission Proton Pass — final migration step (#5) — password + TOTP autofill via
      KeeBridge is confirmed working end-to-end; this is the last step of the original
      migration. Disable Proton Pass's Safari Web Extension (Safari → Settings →
      Extensions — Proton has no native `ASCredentialProviderViewController` extension, so
      there's no System Settings AutoFill toggle to hunt for), re-scan `pluginkit -m -v`
      to confirm no stale registration remains, and decide whether to keep or cancel the
      Proton Pass account. This is an interactive, local-machine action — the headless
      executor cannot open Safari Settings or run `pluginkit` against the maintainer's own
      session. If this is ever the topmost remaining item with nothing else buildable,
      surface it via an `[Action needed]` PR (STEP 6b) rather than fabricating code work
      for it.

## Done

See `docs/done/` for one record per item shipped by the executor (created going forward,
starting with the first post-bootstrap cycle). Pre-executor history — vault write support
(#1) and the full secrets-management UI (#2), both closed — is tracked in the closed
GitHub issues and the git log (`99239da Add vault write support and a secrets-management
UI` and follow-on commits).
