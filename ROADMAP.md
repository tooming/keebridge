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

- [x] ~~`scripts/routines-author-check.sh`'s own header comment claimed this repo
      had no `tests/drift-detectors.bats` bats suite~~ — done, see
      `docs/done/2026-09-11-routines-author-check-stale-comment.md`. Found via a
      fresh angle this cycle: reading the three `scripts/routines-*.sh` drift
      detectors themselves (their logic had only ever been exercised through
      `bats`'s output and their own tests, never read line-by-line this run). The
      comment (lines 50-62) stated, as of "checked 2026-09-08", that the repo had
      "NO `tests/drift-detectors.bats` (or any bats suite)" and pointed at
      `ROADMAP.md`'s "Now / next" for a "groomed-but-not-yet-implemented item to
      actually build that suite" — but that suite was added the SAME DAY (`#93`/
      `#94`, see `docs/done/2026-09-08-routines-bats-suite.md`), is wired into
      both the `Makefile` (`make routines-bats-test`) and `.github/workflows/ci.yml`,
      and is exactly the suite this executor has run every single cycle of this
      run via `bats tests/drift-detectors.bats`. `ROADMAP.md` itself was already
      correctly updated (marks the bats-suite item done); only this script's own
      internal comment was stale — a real, confirmed inaccuracy (not a
      near-miss): anyone reading this script for context would be told a
      fixture-based test suite for it doesn't exist, when one does and already
      covers every branch of its logic. Fixed: rewrote the comment to describe
      the suite's actual existence/coverage, with a note on how it went stale
      (accurate when written, outdated by the same day's later commits).
      Comment-only — no logic change; all three local checks
      (`routines-check.sh`/`routines-author-check.sh`/`bats
      tests/drift-detectors.bats`) still pass identically before and after.
- [x] ~~`CredentialProviderViewController`'s "no vault mirror found" message
      dead-ended with no way to retry~~ — done, see
      `docs/done/2026-09-11-provider-no-vault-retry.md`. Found via a further
      adversarial pass over `CredentialProviderViewController.swift` this
      cycle, this time specifically re-checking every `showMessage(...)` call
      site rather than just the two `handleUnlock` failure paths #116 already
      fixed — that fix's own doc comment flagged `showMessage` as the shared
      dead-end helper, but two more call sites (`showUnlockOrProceed` and
      `openContentThenProceed`, both hit when `vaultURL` is nil — no vault
      mirror exists yet at first-ever use, or the mirror was deleted) still
      used it directly. Real, reachable gap on the same first-use path #116's
      own fix left untouched: with no vault selected in the main app yet, the
      credential provider showed a static, non-interactive "Open KeeBridge on
      this Mac and pick your vault.kdbx first." message with no button —
      Escape (abandoning the whole autofill request) was the only way out,
      even after fixing the root cause in the main app while this sheet
      stayed open. Fixed: both call sites now show a retry-capable
      `NoVaultMirrorView` ("Try Again" button) that re-runs
      `showUnlockOrProceed()`, which re-checks `vaultURL` — a computed
      property backed by a live `FileManager.fileExists` check — fresh each
      time, so it picks up a vault mirrored in after the fact. Compiled-only
      (`xcodebuild`), same as #116 and every other
      `CredentialProviderViewController.swift` change in this ROADMAP — no
      test target for this file's `NSViewController`/SwiftUI layer. Still
      needs a human eyeball in a real Safari autofill popover.
- [x] ~~`CredentialProviderViewController`'s unlock prompt dead-ended after a
      wrong master password, with no way to retry~~ — done, see
      `docs/done/2026-09-11-provider-unlock-retry.md`. Found via a fresh,
      full adversarial read of `CredentialProviderViewController.swift` (952
      lines) this cycle — first full read applying this run's
      control-flow-ordering lens to this specific file. Real, reachable gap
      (mistyping a master password is the single most common failure mode of
      this exact screen, not an edge case): `handleUnlock`'s two failure
      paths (`Argon2id`/password verification failing, and a Keychain-store
      failure after a correct password) both called `showMessage(...)`,
      which embeds a plain, non-interactive `Text` view with no password
      field and no retry button — the only way out was pressing Escape
      (cancelling the entire autofill request) and re-triggering it from
      Safari from scratch. Fixed: both paths now re-show the unlock prompt
      itself (a new `errorMessage` parameter on `showUnlockPrompt`/
      `UnlockView`, displayed above a fresh, empty password field) instead of
      a dead end, so a mistyped password is a one-click retry, same as any
      comparable credential manager's unlock screen. No new secret exposure —
      the error text shown is the exact same `error` value `showMessage`
      already displayed before this fix, just now alongside a way to retry
      instead of a dead end. Compiled-only (`xcodebuild`) — this extension
      has no test target for its `NSViewController`/SwiftUI layer, same as
      every other `CredentialProviderViewController.swift` change in this
      ROADMAP. Still needs a human eyeball: confirming the retry flow
      actually feels right in a real Safari autofill popover — this
      executor has no GUI.
- [x] ~~`TOTPGenerator.parse`'s `algorithm` parameter silently fell back to SHA1
      for any unrecognized value instead of rejecting it~~ — done, see
      `docs/done/2026-09-11-totp-invalid-algorithm-rejection.md`. Found via a
      fresh, adversarial re-read of `TOTPGenerator.swift` this cycle, with the
      same lens the earlier digits/period fixes used: `algorithm =
      HMACAlgorithm(rawValue: ...) ?? .sha1` silently coerced an unrecognized
      (but PRESENT) `algorithm=` value to SHA1, the exact
      silent-fallback-on-an-out-of-range-but-present-value shape already fixed
      for `digits`/`period` in this same file. Unlike those two, this doesn't
      crash — it silently generates codes against the wrong algorithm for
      whatever the URI actually specified, so a 2FA code would just mysteriously
      fail to validate with no indication why. Fixed by rejecting any
      `algorithm=` value that isn't SHA1/SHA256/SHA512 (still falling back to
      SHA1 only when the key is absent entirely, matching RFC 6238/Google
      Authenticator convention). Also closed a related, adjacent coverage gap
      found alongside it: no existing test ever exercised parsing an EXPLICIT
      `algorithm=SHA256`/`SHA512` value at all (only the default-to-SHA1 path
      was tested) — four new `@Test` cases cover explicit SHA256, explicit
      SHA512, a lowercase algorithm name, and the new rejection.
- [x] ~~`EntryEditView`'s QR scanner left its sheet open, with a dead camera
      feed, after scanning a QR code that wasn't a valid TOTP setup URI~~ —
      done, see `docs/done/2026-09-11-qr-scanner-invalid-code-sheet-close.md`.
      Found via a fresh, adversarial re-read of `EntryEditView.swift` this
      cycle. Real, reachable gap (any QR code that isn't an `otpauth://` URI
      triggers it, not a rare edge case): `QRCodeCameraPreview.metadataOutput`
      stops the capture session and marks `didScan` the instant it recognizes
      ANY QR code, valid or not, before the outer closure gets a chance to
      validate it — so by the time an invalid code reached
      `EntryEditView`'s `onCode` handler, the camera was already dead, but
      the handler only set `showingQRScanner = false` on the success path,
      leaving an invalid scan stranded on a frozen, black preview (with the
      error alert on top) and no explicit way to retry short of
      Escape/click-outside (this sheet has no Cancel button). Fixed by
      dismissing the sheet on either outcome, matching the success path, so
      a rejected scan just closes cleanly and the user can click "Scan QR
      Code…" again for a fresh camera session. One-line behavioral change
      (moved `showingQRScanner = false` above the validation guard).
      Compiled-only (`xcodebuild`) — this SwiftUI/AppKit view has no test
      target, same as every other app-layer change in this ROADMAP.
- [x] ~~Add a `bats` test suite for the `routines/` drift-detector scripts~~ — groomed
      last cycle, implemented this cycle once `bats` turned out to be installable in
      this executor's own environment (`apt-get install bats`, Linux — the repo's own
      CI still runs on `macos-latest` via a new `brew install bats-core` step, this was
      just for local validation before pushing, a first for a `routines/`-tooling change
      this run). New `tests/drift-detectors.bats`: 6 cases for `routines-check.sh`
      (no-op with no `routines/` dir, clean/hash-matches, missing snapshot, not-yet-
      applied, edited-since-apply, snapshot references a deleted file) and 6 for
      `routines-author-check.sh` (untouched routines.yaml stays clean regardless of
      branch, executor-branch block, cloud-identity block, interactive-session pass,
      a *custom* `branch_prefix` read from the fixture's own `routines.yaml` — not
      hardcoded `auto/` — correctly gates instead of the default, and the
      `routines/`-prefixed path shape a real `git diff --name-only` actually produces).
      Sanity-checked the suite isn't vacuous by deliberately breaking
      `routines-check.sh`'s final `exit $drift` and confirming exactly the tests that
      depend on reaching that line went red, then restored it. Wired into
      `make routines-bats-test` and `make ci`, plus `.github/workflows/ci.yml`'s own
      job. All 12 cases pass locally against the real scripts, both before and after
      this cycle's own `routines-author-check.sh` comment fix from last cycle.
- [x] ~~Evaluate upgrading `swift-crypto` from the `3.x` series to `4.x`~~ — investigated
      last cycle (kept unimplemented pending a real API-diff read, not a Swift toolchain
      limitation as first assumed — CI itself has one), implemented this cycle once that
      diff was actually read. Upstream `swift-crypto`'s own README states plainly: 4.0.0's
      *only* breaking change vs. 1.x/2.x/3.x is new cases added to the `CryptoError` enum,
      and the maintainers' own recommended dependency range widens across the boundary
      (`"1.0.0" ..< "5.0.0"`) rather than pinning below it. Verified this codebase never
      exhaustively switches over Swift Crypto's `CryptoError` (zero matches — the only
      `*Error` type this codebase pattern-matches on is its own `PasskeyCryptoError`), so
      the one stated breaking change cannot affect it. Combined with the prior cycle's
      findings (Swift 6.0+ requirement already met under `SWIFT_VERSION: "6.1"`, no RSA
      usage so the one security-hardening commit not yet in a `3.x` tag doesn't apply
      either way), this cleared the bar for a same-cycle bump rather than another
      "groomed, not implemented" cycle: `KeeBridgeCore/Package.swift`'s constraint widened
      from `from: "3.0.0"` (`>=3.0.0, <4.0.0`) to `"3.0.0"..<"5.0.0"`, letting SwiftPM
      resolve to the newest `4.x`. `make ci` (`swift test` + the unsigned `xcodebuild`
      build) is the real validation this actually compiles and passes against `4.x`'s
      API — see `docs/done/2026-09-08-swift-crypto-4x-upgrade.md`.
      **Correction (next cycle, same run):** the PR's own self-review claimed CI had
      "built against the newly-resolved swift-crypto 4.x package" — that was wrong. Both
      `KeeBridgeCore/Package.resolved` and `VaultProbe/Package.resolved` were already
      committed, pinning `swift-crypto` at `3.15.1`; SwiftPM only re-resolves a pinned
      dependency when the existing pin stops satisfying the manifest's constraint, and
      `3.15.1` still satisfies `"3.0.0"..<"5.0.0"` — so widening the range alone changed
      nothing about what actually got built. CI's earlier green run validated the *widened
      constraint compiles*, not a real `4.x` build. See
      `docs/done/2026-09-08-swift-crypto-lockfile-refresh.md` for the actual fix (deleting
      both lockfiles to force a genuine fresh resolution) and the manual-step issue filed
      for restoring a committed, reproducible lockfile now correctly pinning `4.x`.
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
- [x] ~~Automatic proposal of storing the password after logging into a new site (#33)~~ —
      investigated (STEP 6b refill, ROADMAP lane was otherwise empty this cycle), see
      `docs/done/2026-09-02-save-password-proposal-feasibility-spike.md`. Marked `[x]` here
      (this run) to match GitHub: the maintainer closed #33 as completed on 2026-09-02, the
      same day this investigation landed — the ROADMAP line had been left unchecked since
      then, so every run's STEP 3 kept re-deriving "topmost unchecked item is blocked" from
      scratch instead of the state already being reflected here. This is a doc-sync fix, not
      a new finding about the feature itself, which is still exactly as blocked as described
      below.
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
- [x] ~~`TOTPGenerator.parse`'s `.invalidURI`/`.invalidBase32Secret` error branches had
      zero test coverage~~ — done, see
      `docs/done/2026-09-04-totp-parse-error-coverage.md`. Found via a third survey pass
      this run (a doc-accuracy/test-coverage lens, distinct from the two earlier
      adversarial-logic-bug passes that already closed out six other findings this
      cycle). `TOTPError` has six cases total; `.unsupportedType`/`.missingSecret` were
      tested, and `.invalidDigits`/`.invalidPeriod` gained thorough coverage earlier this
      run, but `.invalidURI` (a non-`otpauth` scheme) and `.invalidBase32Secret` (a
      `secret=` value with characters outside this type's RFC 4648 alphabet) never had a
      test of their own. Test-only, no production code changed — the existing guards
      were already correct, just unverified. Two new `@Test` cases in
      `TOTPGeneratorTests.swift`.
- [x] ~~`TOTPGenerator.parse` didn't validate `digits`/`period`, letting a malformed
      otpauth:// URI crash the process later~~ — done, see
      `docs/done/2026-09-04-totp-parse-digits-period-validation.md`. Found via a STEP 6b
      re-survey (second pass, adversarial re-read of already-visited files — the prior
      cycle's first-pass re-survey had already closed out the "Now / next" lane with
      three other findings, all merged, before this one turned up). Real crash bug, not
      hypothetical: `digits`/`period` were parsed with a silent numeric fallback and no
      range check, so an out-of-range value (e.g. from an adversarial or malformed QR
      code) sailed through `parse()` only to trap — a Swift runtime crash, not a
      throwable error — the next time `currentCode`/`code(for:counter:)` actually used
      it (`UInt64` conversion of a non-finite `Double` for `period <= 0`; integer
      overflow or division-by-zero in the digits-to-modulus math for out-of-range
      `digits`). Every existing `try?`/`try` call site (`EntryEditView.swift`'s QR-scan
      and manual-save validation, `VaultProbe`'s `promptAndValidateOTPURI`,
      `VaultService.setOTP`) already treats a successful `parse()` as "safe to store,"
      so this closes the crash vector at every one of them, in one place, with no
      caller changes needed.
- [x] ~~**Security: card autofill has no origin/host binding anywhere in the stack**~~ —
      done, see `docs/done/2026-09-04-card-picker-cross-origin-iframe-block.md`. Any page
      (including a third-party iframe, since `manifest.json` injects `content.js` into
      `<all_urls>` with `"all_frames": true`) could list and reveal full payment-card
      data (number/CVV/expiration/holder) for any card in the vault, via
      `KeeBridgeCardExtension`. Found via a STEP 6b re-survey (2026-09-04,
      second/adversarial pass). **Corrected on implementation**: this item's own
      original text proposed threading `origin` through `PaymentCard.swift`/
      `background.js`/`SafariWebExtensionHandler.swift` to filter cards by a per-entry
      URL, mirroring `CredentialProviderViewController`'s host-matching pattern — on
      implementation this turned out to be the wrong shape of fix, not just a bigger
      one: unlike a login credential, a payment card has no natural single "site" (a
      Visa is legitimately reused across many unrelated merchants), so per-card
      origin-filtering would either break the feature for every untagged card or (if it
      fell back to "show all" on zero matches, as `showList` does for its
      OS-trusted-signal case) not actually close the gap at all, since an attacker's
      iframe origin would simply never match anything. The actual fix: gate `content.js`
      itself so it never activates (no trigger, no picker, no way to ever reach
      `listCards`/`fillCard`) inside a cross-origin iframe — `manifest.json` has no
      `externally_connectable`, so a webpage's own script cannot call this extension's
      messaging API directly; the only path in is `content.js`'s own injected instance,
      so gating its activation by frame trust (top-level, or an iframe same-origin with
      the top-level page) is a complete, non-bypassable fix, not defense-in-depth on top
      of a bigger one. ~20 changed lines in `content.js` only — no native/Swift changes
      needed. Headless-verification caveat: CI has no JS lint/test step (only the Swift
      targets are built/tested), so this was verified by careful reading of the
      WebExtension frame/Same-Origin-Policy semantics involved (`window.top`'s
      reference is always safely readable even cross-origin; only its `.location`
      properties are SOP-restricted, which is exactly what the trust check relies on),
      not `make ci` — flagged as a "still needs a human eyeball" caveat in the PR.
- [x] ~~`SafariWebExtensionHandler`'s Keychain/content cache (`cachedPreHash`,
      `cachedContent`, `cachedContentDate`, `cachedMirrorDate`) was declared as plain
      instance `var`s, not `static`~~ — done, see
      `docs/done/2026-09-04-card-extension-static-cache.md`. Originally flagged
      PLAUSIBLE, not confirmed headlessly, pending exactly this kind of verification.
      **Confirmed before implementing** (not applied on pattern-matching alone): Apple's
      own App Extension Programming Guide describes a non-UI app extension being
      instantiated to handle one request and then terminated, Safari Web Extension
      native messaging (`sendNativeMessage`, which `background.js` uses — this extension
      never opens a `connectNative` port) spins up a fresh extension process per
      message, and an independent developer report specifically about
      `SafariWebExtensionHandler` ("SafariWebExtensionHandler creates new object for
      every request", Apple Developer Forums thread 696134) describes exactly this —
      three independent sources converging on the same conclusion, the same standard
      this ROADMAP already applies to other platform-behavior questions it can't test on
      real hardware. Fixed: all four cache fields are now `static var`
      (`CredentialProviderViewController`'s exact established pattern, including its
      `Self.`-qualified read/write convention), so the cache now actually persists
      across the fresh instance each `listCards`/`fillCard`/`unlock` request gets,
      instead of silently resetting on every single one. All cache access already ran
      through the handler's existing `static` serial `workQueue`, so making the cache
      itself `static` introduces no new thread-safety surface — access was already
      serialized onto one queue, now just visibly shared state instead of accidentally
      non-shared state.
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
- [x] ~~`VaultProbe` OTP write parity~~ — done, see
      `docs/done/2026-09-04-vaultprobe-otp-write-parity.md`. `CreateCommand`/
      `UpdateCommand` had no way to set an entry's TOTP secret, so there was no CLI path
      to create an entry with one, add one to an existing entry, or remove one, even
      though `VaultService.EntryDraft.otpURI` and its
      nil-preserves/empty-removes/non-empty-sets contract were already fully implemented
      and unit-tested (`entryDraftRoundTripsOTPURI` in `VaultWritingTests.swift`) and the
      app's own `EntryEditView` already exposed a full OTP section. Fixed: both commands
      now take `--set-otp` (a `getpass()`-prompted flag, not a plain option — self-review
      caught that a direct `--otp-uri <value>` CLI argument, this item's original design,
      would leak the entry's TOTP secret into shell history/`ps` output, the exact class
      of exposure `--set-password` already exists to avoid for the entry's password;
      fixed before merging by mirroring that same prompt-based pattern instead), threaded
      straight into `EntryDraft(otpURI:)`, validated via `TOTPGenerator.parse` when the
      prompt answer is non-blank. `update` forwards the prompt's raw result (nil when
      `--set-otp` wasn't passed at all) with no extra reveal-then-merge logic, since
      `EntryDraft`'s own nil-preserves/empty-removes contract already does the right
      thing at the `updateEntry` layer. Also fixes the doc-accuracy gap this item
      flagged: `README.md`'s claim of read/write parity between the app UI and
      `VaultProbe` now actually holds for this field.
- [x] ~~Test coverage for `PaymentCard.revealPaymentCardFields`'s split-field → combined
      `.expiration` synthesis branch~~ — done, see
      `docs/done/2026-09-04-paymentcard-expiration-synthesis-tests.md`. This branch
      (`result[field] = "\(month)/\(year)"` when an entry has separate `Expiration
      Month`/`Expiration Year` fields but no combined `Expiration Date` field) is live,
      secret-touching, extension-reachable code (`KeeBridgeCardExtension`'s `content.js`
      requests `"expiration"` for any `autocomplete="cc-exp"` field) that had zero test
      coverage — only the opposite direction (combined field → split
      `.expirationMonth`/`.expirationYear`) was previously tested. Fixed: two new
      `@Test` cases in `PaymentCardTests.swift` — the happy path (both split fields
      present → correctly combined) and a defensive case (only one split field present →
      `.expiration` correctly omitted rather than emitting a malformed `"04/"` value,
      confirming the `if let month = ..., let year = ...` guard's both-or-nothing
      behavior).
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
- [x] ~~Manual credential picker (`CredentialProviderViewController.completeSelection`)
      never responded at all for an entry with no `Password` field~~ — done, see
      `docs/done/2026-09-05-manual-picker-missing-password-response.md`. Found via a fresh,
      adversarial re-read of `CredentialProviderViewController.swift` (previously read in
      full by earlier cycles, but not with a "does every exit path actually respond" lens).
      Real, reachable gap, not hypothetical: the manual "Passwords…" list shows every vault
      entry, including passkey-only entries with no traditional login at all, so picking one
      from that list silently returned with no `respond*()` call — the popover just sat
      there until this file's own 30s watchdog eventually forced a generic `.failed` cancel,
      contradicting the "always responds, promptly" guarantee this file's own header comment
      describes. `completePasswordCredential` (the interactive-request counterpart handling
      the identical condition) already called `respondCancel(.credentialIdentityNotFound)`
      correctly; `completeSelection` just never got the same treatment. Fixed to match.
- [x] ~~Vault mirror files (`VaultController.mirrorVaultToExtension`/
      `mirrorVaultToExtensions`) were replaced non-atomically, racing both extensions'
      independent reads~~ — done, see `docs/done/2026-09-05-vault-mirror-atomic-replace.md`.
      Found via a fresh, adversarial re-read of `VaultController.swift`, cross-checked
      against `VaultService.write`'s own existing atomic-write precedent for the source
      vault. Real, reachable race, not hypothetical: the old `removeItem`+`copyItem`
      sequence left a window where the mirror path was either momentarily missing or only
      partially written, and both `CredentialProviderViewController` and
      `SafariWebExtensionHandler` read that exact path independently, any time a mirror
      refresh (`refreshIfStale()`, fired on every app foreground) lands mid-flight — exactly
      the normal "switch back to Safari" autofill workflow, not a rare edge case. Fixed with
      a new `atomicallyReplaceMirror(at:withContentsOf:)` helper: copy to a temp file in the
      same directory, then swap it into place via `FileManager.replaceItemAt`/`moveItem`
      (both backed by an atomic same-volume `rename()`) instead of remove-then-copy — a
      concurrent reader now always sees either the complete old file or the complete new
      one, never a missing/partial one.
- [x] ~~Copied passwords stayed on the system pasteboard indefinitely, with no auto-clear~~
      — done, see `docs/done/2026-09-05-clipboard-auto-clear.md`. Found via a fresh,
      adversarial re-read of `EntryDetailView.swift` (third finding this run, after #60/#61).
      Real, not hypothetical, for a credential manager: the pasteboard is readable by any
      other app until overwritten or cleared, and every comparable password manager
      (1Password, Bitwarden, KeePassXC) auto-clears it after a short delay for exactly this
      reason — KeeBridge never had. Fixed: `copyToPasteboard` gained an optional
      `autoClearAfter:` delay, applied only to the password's own copy button (30s) —
      captures `NSPasteboard.changeCount` right after writing and only clears later if
      nothing else has touched the pasteboard since, per `NSPasteboard`'s own documented
      mechanism for this. Non-secret copy buttons (username/URL/passkey metadata) are
      unaffected. Still needs a human eyeball to confirm the actual clipboard behavior on
      real hardware — this executor has no GUI.
- [x] ~~`project.yml` was missing two passkey capability flags a real `xcodegen generate`
      would silently regress~~ — done, see
      `docs/done/2026-09-05-project-yml-passkey-capabilities-drift.md`. Found via a fresh,
      adversarial read of `project.yml` cross-checked against the physical
      `KeeBridgeProvider/Info.plist` (fourth finding this run, after #60/#61/#62 — the first
      to look at build config rather than application logic). Real drift, confirmed via git
      history: `project.yml`'s `ASCredentialProviderExtensionCapabilities` block only
      declared `ProvidesPasswords`/`ProvidesOneTimeCodes`, while the physical `Info.plist`
      (what Xcode's build actually reads today, so no CURRENT build is affected) also has
      `ProvidesPasskeys`/`SupportsConditionalPasskeyRegistration` — added directly to the
      physical file by two earlier passkey-registration PRs that never updated `project.yml`
      to match. Since XcodeGen regenerates `info.path` from `info.properties` on every
      `xcodegen generate` run (`README.md`'s own documented first setup step), this was a
      live regression trap: the next regenerate would silently overwrite `Info.plist` with
      the two-flag version, disabling passkey assertion routing and both registration flows
      with no error anywhere to catch it. Fixed by adding the two missing flags to
      `project.yml` so it matches the physical file exactly. Config-only, no behavior change
      today. Still needs a human eyeball: actually running `xcodegen generate` to confirm it
      now reproduces `Info.plist` instead of regressing it — this executor has no
      `xcodegen` binary.
- [x] ~~Card expiration autofill assumed "MM/YYYY" for any placeholder mentioning "yyyy"~~ —
      done, see `docs/done/2026-09-05-card-expiration-placeholder-format.md`. Found via a
      second, independent adversarial review pass this run (fifth finding, after
      #60/#61/#62/#63, all already merged). Real, reachable formatting bug in
      `content.js`'s `formatValue()`: the combined `.expiration` field's `"yyyy"` branch only
      checked substring presence, ignoring the placeholder's actual token order/separator —
      a `"YYYY-MM"` field got `"04/2027"` (wrong order AND separator), a `"MM-YYYY"` field
      got the wrong separator. Fixed to derive both from the placeholder itself.
      Went beyond the usual "verified by reading" for `content.js` (no JS lint/test in CI):
      extracted `formatValue` into a standalone Node.js test harness with minimal DOM stubs
      and ran 10 concrete cases (including every previously-correct one, regression-checked)
      — all pass. Still needs a human eyeball in real Safari, same limit every `content.js`
      change in this ROADMAP carries.
- [x] ~~Read-only vault opens materialize every binary attachment's decrypted bytes, even
      though nothing in this app ever reads one~~ — **part (1) of 2 done**, see
      `docs/done/2026-09-06-vault-readable-content-refactor.md`. This is the narrow
      VaultService-internal refactor the prior grooming pass (this same bullet, previous
      cycle) recommended splitting off first: a new `VaultReadableContent` protocol
      (`var database: KDBX { get }`), conformed by both KDBXKit's eager `KDBXContent` and
      its metadata-only `LazyKDBXContent`, that every one of `VaultService`'s read-only
      functions (`listEntries`, `revealField`, `currentTOTPCode`, `passkeyMetadata`,
      `revealPasskeyPrivateKeyPEM`, `revealEntry`, and `PaymentCard.swift`'s
      `listPaymentCards`/`revealPaymentCardFields`/`paymentCardMetadata`) is now generic
      over instead of pinned to `KDBXContent` — confirmed by reading every one of their
      bodies that none touch `.header`/`.innerHeader`/`.parserWarnings`, only `.database`.
      A new `VaultService.openReadOnlyContent` (internal, tested directly) opens via
      `KDBXReader.openMetadataOnly` — no binary attachment bytes ever materialized — with
      an eager-parse fallback on exactly `KDBXReader.Error.unsupportedFormatVersion(major:
      3, ...)`, matching `openMetadataOnly`'s own documented guidance for KDBX 3.x sources.
      Every one-off `at url:` read convenience (`listEntries(at:...)`,
      `revealField(at:...)`, `currentTOTPCode(at:...)`, `passkeyMetadata(at:...)`,
      `paymentCardMetadata(at:...)`, `revealEntry(uuid:at:...)`) now routes through it —
      `VaultProbe`'s six read subcommands and every `KeeBridgeCoreTests` file exercising
      those call sites (`PasskeyTests.swift`, existing `VaultServiceTests.swift` parity
      test) get the memory-footprint fix immediately, no caller changes needed beyond the
      generic signature. Every WRITE path (`createEntry`/`updateEntry`/`deleteEntry`/
      `mergeExtensionOriginatedPasskeys`, and the session-cached `openVault(at:...)` the
      app/`KeeBridgeProvider`/`KeeBridgeCardExtension` hold onto) is UNCHANGED — still the
      eager `KDBXContent` path, exactly as scoped. New `VaultReadableContentTests.swift`
      builds a vault with a real binary attachment (via KDBXKit's own
      `InnerHeader.BinaryContent`/`KDBX.ProtectedBinary`, the same low-level construction
      pattern `PasskeyTests.swift` already uses for KDBXKit-only fields — no fixture file
      needed) and asserts every read function agrees between the eager and metadata-only
      paths, plus that the returned `LazyKDBXContent` captures attachment metadata
      (size/hash) without a `.data` field to retain the bytes on at all — a structural
      guarantee, not just a runtime check.
      **Part (2), NOT done here** — see the follow-up bullet immediately below: threading
      this lighter path through `VaultController`/`CredentialProviderViewController`/
      `SafariWebExtensionHandler`'s own session caches, where the real end-to-end memory
      win lives (every actual autofill request still goes through the unchanged eager
      `openVault`, today).
- [x] ~~Thread the metadata-only read path into `SafariWebExtensionHandler`'s session
      cache~~ — **part (2a) of 3 done** (the first, smallest slice of the item this
      grooms from), see `docs/done/2026-09-06-card-extension-read-only-vault.md`. Traced
      `SafariWebExtensionHandler`'s full call graph first (not assumed): it is 100%
      read-only — `listPaymentCards`/`revealPaymentCardFields` only, zero
      `createEntry`/`updateEntry`/`deleteEntry`/`setPasskey` calls anywhere in the file —
      the cleanest-boundary, lowest-risk of the three original consumers, so it went
      first. Discovered while implementing: `VaultService.openReadOnlyContent` is
      package-internal, invisible from `KeeBridgeCardExtension`'s separate module, so a
      new **public** `VaultService.openReadOnlyVault(at:masterPassword/rawKeyData:)` pair
      was needed first (thin wrappers around `openReadOnlyContent`, same shape as the
      existing public `openVault(at:...)`) — this is the reusable entry point the
      remaining two consumers below will call too. `SafariWebExtensionHandler
      .cachedContent`/`unlockedContent`/`cache(content:...)` switched from `KDBXContent`
      to `any VaultReadableContent`; both `openVault` call sites switched to
      `openReadOnlyVault`; the now-unused `import KDBXKit` removed.
- [x] ~~Thread the metadata-only read path into `VaultController`'s session cache~~ —
      **part (2b) of 3 done**, see `docs/done/2026-09-06-app-read-only-vault.md`. Traced
      `VaultController`'s full call graph first (not assumed): all 5 of its
      `vaultService.openVault(at:...)` call sites (`unlock`, `refresh`, and the
      post-write re-list in each of `createEntry`/`updateEntry`/`deleteEntry`) are
      themselves READ-ONLY re-opens — every actual WRITE goes through
      `vaultService.createEntry`/`updateEntry`/`deleteEntry` directly (unaffected,
      untouched, still the eager path internally), and `cachedContent` is only ever
      assigned from one of those 5 read re-opens, never from a write call's own return
      value (writes return a UUID or nothing). So this consumer turned out to have NONE
      of the write-path complexity the original grooming note worried about — every
      `openVault` call switched cleanly to `openReadOnlyVault`, `cachedContent` switched
      from `KDBXContent?` to `(any VaultReadableContent)?`, and `populateIdentityStore
      (entries:content:)` (the one place taking `content` as an explicit parameter, used
      only via the already-generic `passkeyMetadata(in:...)`) switched its parameter type
      to match. The now-unused `import KDBXKit` removed. No test target for this file
      (SwiftUI/AppKit app layer) — verified by `xcodebuild` compiling it, same as every
      other app-layer change in this ROADMAP.
- [x] ~~Thread the metadata-only read path into `CredentialProviderViewController`'s
      session cache~~ — **part (2c) of 3 done — the attachment memory-footprint item's
      full 3-part split is now complete**, see
      `docs/done/2026-09-06-provider-read-only-vault.md`. Traced the full call graph
      first, same discipline as (2a)/(2b), NOT assumed to be as clean as part (2b) turned
      out to be given this file's larger size (952 lines) and extra flows (password/OTP/
      passkey assertion, interactive AND conditional passkey registration, the manual
      picker) — but it turned out just as clean: both `openVault` call sites
      (`openContentThenProceed`/`handleUnlock`) are read-only unlocks, and every one of
      the 8 functions taking `content` as a parameter (`proceed(withContent:)`,
      `completeCredential`, `completePasskeyAssertion`, `beginPasskeyRegistration`,
      `completePasswordCredential`, `completeOTPCredential`, `showList`,
      `completeSelection`) only ever reads through it (`listEntries`/`revealField`/
      `currentTOTPCode`/`revealPasskeyPrivateKeyPEM`/`passkeyMetadata`, all already
      generic). This file's one WRITE (`completePasskeyRegistration`'s
      `vaultService.setPasskey`) doesn't take `content` as a parameter at all — it opens
      its own fresh copy internally via `vaultURL`/`cachedPreHash`, and the existing code
      already explicitly invalidates (not re-caches) `Self.cachedContent` right after
      that write, exactly the "never write through this cache" pattern parts (2a)/(2b)
      both had. `cachedContent`/`validCachedContent()` switched from `KDBXContent?` to
      `(any VaultReadableContent)?`; both `openVault` call sites switched to
      `openReadOnlyVault`; all 8 `content:` parameter types switched to
      `any VaultReadableContent`; the now-unused `import KDBXKit` removed. No test target
      for this file — compiled-only, `xcodebuild`-verified, same as (2b).
- [x] ~~`updateEntry` never populated `entry.history`, silently breaking KeePass version
      history~~ — done, see `docs/done/2026-09-05-update-entry-history-preservation.md`.
      Found via a continued adversarial review this run (seventh finding, after #60–#66),
      reading the pinned KDBXKit dependency's own source directly. Real, confirmed gap, not
      speculation: KDBXKit's own doc comment on `KDBX.Entry.history` states "every entry set
      or equivalent edit prepends a snapshot of the prior state here," matching KeePassXC's
      actual behavior (its "View History" feature) — `updateEntry` mutated fields in place
      and never touched `history` at all, so every edit made through KeeBridge (the app's
      Edit form or `VaultProbe`'s `update`) had no recovery path beyond the whole-file `.bak`
      one save-generation back, unlike an equivalent KeePassXC edit. Fixed: `updateEntry` now
      snapshots the pre-edit state into `entry.history` (nested history cleared, matching
      KDBXKit's own validator expectation) before applying changes, trimmed against
      `Meta.historyMaxItems` when set. Also corrected `EntryDetailView`'s delete-confirmation
      copy, which misattributed "KeePassXC's own backup/history" as the recovery path for a
      deletion — `deleteEntry` has no recycle bin and never populates history before
      removing an entry, so the real recovery path (the vault's own `.bak` sibling) is what
      the text says now. Two new `@Test` cases in `VaultWritingTests.swift`, actually run via
      `swift test`/CI (unlike this run's app-layer/JS fixes) — history-snapshot ordering/
      field-fidelity/no-nested-history/no-validator-warnings, and `historyMaxItems`
      trimming.
- [x] ~~`scripts/lib/colors.sh`'s doc comments described a duplication-extraction
      history across files that don't exist anywhere in this repo~~ — done, see
      `docs/done/2026-09-10-routines-colors-lib-cleanup.md`. Found during a STEP 6b
      re-survey once the Swift/JS-focused audit angles (already covered exhaustively
      by 20+ prior cycles — full-core reads, entitlements/pbxproj/gitignore/error-
      handling/web-extension sweeps) turned up nothing new yet again, so this cycle
      tried a genuinely fresh angle instead: the small bash `scripts/` tooling
      supporting `routines-check.sh`/`routines-author-check.sh`. `scripts/lib/colors.sh`
      (this repo's root commit, `0d94f91` — confirmed via `git log --follow`/
      `git rev-list --max-parents=0`, so this is long-standing content, not a recent
      regression) carried ~30 lines of comments narrating an "extraction" of `ok()`/
      `bad()`/`skip()`/`phase()` out of "~19 scripts" including
      `argocd-crd-ssa-check.sh`, `helm-chart-pin-check.sh`, `dr-bluegreen.sh`,
      `validate-terraform.sh`, and "issue #957" — none of which exist anywhere in
      KeeBridge (confirmed via a repo-wide grep). This reads like leftover content
      from the sibling `k8s-anywhere` repo (which does have Argo CD/Helm/Terraform
      scripts, per `docs/WAYS-OF-WORKING.md`'s cross-reference) that was never adapted
      to this repo's own, much smaller reality: only two scripts source this file, and
      between them they use exactly `$G`/`$R`/`$Z` and `bad()` — `$Y`/`$B` and
      `ok()`/`skip()`/`phase()` were live but entirely uncalled dead code, confirmed by
      grepping both callers. Fixed: trimmed the file to what this repo actually uses
      and rewrote the header comment to describe this repo's own two callers, not a
      fabricated cross-repo history. Also switched `routines-check.sh`/
      `routines-author-check.sh`'s two success-path `printf`s (which already
      duplicated `ok()`'s exact behavior by hand) to actually call `ok()`, so the
      kept function has a real caller instead of being dead code itself — output text
      unchanged, confirmed via the existing `tests/drift-detectors.bats` substring
      assertions on both success messages. Verified via `bats tests/drift-detectors.bats`
      (all 15 cases green, this executor's environment has `bats` installable via
      `apt-get` same as prior cycles) and running `make routines-check`/
      `make routines-author-check` directly against this repo's own real state (both
      print the real `✓` line via the now-actually-used `ok()`). Bash-only change, no
      Swift touched — `make test`/`make build`/`make probe-build` are unaffected and
      unexercised locally (no Swift toolchain in this executor's own environment, same
      documented limit as every other cycle), left to this PR's GitHub Actions run.
- [x] ~~Real Swift 6 Sendable/concurrency compiler warnings were going unnoticed because
      no prior cycle ever read this repo's raw CI build logs, only pass/fail~~ — done,
      see `docs/done/2026-09-10-sendable-concurrency-warnings.md`. Found via a third
      re-survey angle this run (after the `scripts/lib/colors.sh` fix, #107, and a
      second pass that found nothing further, #108): fetched and grepped the actual
      GitHub Actions build log content for `warning:` — a signal no prior cycle had
      checked, since `make ci`'s pass/fail conclusion doesn't surface non-fatal
      compiler warnings at all. Found exactly 4 real warnings across the whole build
      (`VaultController.swift`, `SafariWebExtensionHandler.swift`) plus 3 unrelated
      Xcode-tooling `appintentsmetadataprocessor` notices — legitimate Swift 6 strict-
      concurrency diagnostics about non-`Sendable` types crossing into `@Sendable`
      closures, not fatal (`make ci` was already green), but real, confirmed-by-
      inspection hygiene gaps. Fixed two of the four, confirmed by actually re-running
      this PR's own CI and re-grepping its logs (not assumed from the diff alone —
      caught and corrected one wrong assumption along the way, see below):
      `@preconcurrency import AuthenticationServices` in `VaultController.swift` (the
      exact fix the compiler's own diagnostic note suggested, for the
      `ASCredentialIdentityStore`/`store` capture — confirmed gone from the rebuilt
      log) and, in `SafariWebExtensionHandler.swift`, marking the class
      `@unchecked Sendable` for the `self` capture — confirmed safe by inspection
      first: every stored instance property is an immutable `let` of an already-
      `Sendable` type (`VaultService`/`KeychainStore` are `Sendable` structs, `Logger`
      is `Sendable`), and the only actual mutable state is the `static` cache fields
      already carrying their own `nonisolated(unsafe)` + `workQueue`-serialization
      justification from an earlier cycle — also confirmed gone from the rebuilt log.
      **Two warnings left, deliberately, not silently**: the same closure's capture of
      `message: [String: Any]` (`Any` can never be proven `Sendable` by the type
      system, and this payload's shape comes straight from `SFExtensionMessageKey` —
      Safari's own JS-bridged dictionary — not something changeable without a larger
      message-type redesign outside this item's scope) and `context:
      NSExtensionContext`. The latter was initially "fixed" with
      `@preconcurrency import Foundation`, mirroring the `AuthenticationServices`
      pattern — but re-checking this PR's own rebuilt CI log after pushing showed the
      warning was still there. Root cause: that warning comes from `DispatchQueue.
      async`'s own `@Sendable` closure requirement (declared in the `Dispatch`
      module), not from an API `Foundation` itself declares, so `@preconcurrency
      import Foundation` had nothing to suppress — reverted rather than leaving an
      ineffective, scope-widening import in place. A real fix would mean retroactively
      declaring Apple's own `NSExtensionContext` `@unchecked Sendable`, which needs
      stronger evidence of its actual thread-safety than this cycle could confirm — so
      left as a genuine, documented gap rather than a guessed-at conformance. Net
      result, confirmed via the actual rebuilt log content: 4 real warnings → 2. No
      behavior change either way — every change here is a compile-time-only
      diagnostic annotation, `make ci` stayed green throughout.
- [x] **Backfill: 8 already-shipped, already-merged fixes from 2026-09-08 had a
      `docs/done/*.md` record but no `ROADMAP.md` line at all** — found via a fourth
      re-survey angle this run (after `scripts/lib/colors.sh`, #107; a second pass
      finding nothing, #108; and the Sendable-concurrency warnings, #109): checking
      the *reverse* direction of the earlier "roadmap-reference-audit" cycle, which
      only verified every path `ROADMAP.md` cites actually exists on disk. Nobody had
      checked the other way — every `docs/done/*.md` file actually has a
      corresponding `ROADMAP.md` line — until this cycle diffed the two directories
      against every reference `ROADMAP.md` makes. This file's own header states "the
      executor reads it fresh every run and picks the topmost unchecked `[ ]` item";
      it doesn't cause re-work when the missing entries are already `[x]`-shaped
      work, but it is a real, confirmed gap against this repo's own documented
      convention (STEP 6 of `routines/executor.prompt.md`: every delivered cycle
      updates `ROADMAP.md` *and* creates a `docs/done/` record, in the same PR) —
      these 8 got the second half without the first, for one calendar day's worth of
      cycles. (A ninth candidate, `docs/done/2026-09-05-roadmap-issue-sync.md`,
      turned out to be a false positive on the naive filename grep — its content is
      already fully present, just inline rather than cited by filename, in this
      section's existing `#33`/`#5` bullets above.) Backfilling the real 8 here,
      each verified against its actual `docs/done/` content before summarizing
      (not restated from memory):
      - ~~`refreshIfStale()`'s throttle timestamp could absorb a legitimate
        refresh~~ — see `docs/done/2026-09-08-refresh-throttle-isworking-fix.md`.
        Real UX-staleness bug (not security/data-loss): the throttle stamp was set
        even on a call `refreshFromCache()`'s own `isWorking` guard immediately
        no-op'd, delaying how soon an external vault edit (e.g. via KeePassXC) would
        show up. Fixed by removing the premature stamp — every path that actually
        performs a sync already stamps it in its own completion.
      - ~~An extremely small (but positive, finite) TOTP `period` still crashed
        `currentCode`~~ — see
        `docs/done/2026-09-08-totp-tiny-period-overflow-fix.md`. A period like
        `1e-10` passed the existing `period > 0 && period.isFinite` guard but still
        overflowed `UInt64` in the `timeIntervalSince1970 / period` conversion
        inside `currentCode`/`code(for:counter:)` — an uncatchable runtime crash,
        not a throwable error. Tightened the guard to `period >= 1`; two new
        `@Test` cases, `swift test`/CI-covered.
      - ~~Zero test coverage for `KeeBridgeConfig`'s mirror-path functions~~ — see
        `docs/done/2026-09-08-keebridgeconfig-test-coverage.md`. Six new tests
        confirming the app/provider/card-extension mirror paths and the write-time
        marker path land in the correct, distinct locations — a copy-paste bundle-ID
        swap here would have broken mirror sync with every caller silently agreeing
        on the wrong path. (`KeychainStore.swift`, the file's other coverage gap,
        was investigated and left alone: it calls the real Security framework
        directly with no injectable seam, so meaningful testing needs either real
        Keychain access or Touch ID hardware, neither available here.)
      - ~~README's "What works today" had fallen behind shipped behavior again~~ —
        see `docs/done/2026-09-08-readme-accuracy-refresh.md`. Two real, shipped,
        user-facing behaviors were undocumented: clipboard auto-clear (30s, guarded
        by `NSPasteboard.changeCount`) and payment-card visibility in the app UI/
        `VaultProbe`. Both claims verified against actual shipping code before
        writing them, not restated from PR titles.
      - ~~`scripts/routines-author-check.sh`'s header claimed a `bats` test suite
        existed when it didn't~~ — see
        `docs/done/2026-09-08-routines-bats-comment-fix.md`. The claim was very
        likely inherited from a sibling repo's equivalent script and never adjusted
        — same class of copy-paste-without-adaptation as this run's own
        `scripts/lib/colors.sh` finding (#107), just caught two days earlier.
        Comment corrected to state the real situation; the actual gap (a real bats
        suite) groomed into `ROADMAP.md` for the next two items to implement.
      - ~~Add a `bats` test suite for the `routines/` drift-detector scripts~~ — see
        `docs/done/2026-09-08-routines-bats-suite.md`. `tests/drift-detectors.bats`,
        12 cases across both drift-check scripts, wired into `make ci`/CI.
        Deliberately broke `routines-check.sh`'s own exit-code line first and
        confirmed exactly the tests that depend on it went red, to prove the suite
        isn't vacuous, before restoring it.
      - ~~Extend the bats suite to cover `routines-mark-applied.sh`~~ — see
        `docs/done/2026-09-08-routines-mark-applied-bats-coverage.md`. Three more
        cases exercising the *producer* script (`routines-mark-applied.sh`) and a
        *detector* script together, not either in isolation — the actual contract
        that matters. Same before/after mutation-testing discipline as the suite
        it extends.
      - ~~`KDBXKit` dependency comment said "no tagged release yet," but tags now
        exist upstream~~ — see `docs/done/2026-09-08-kdbxkit-tag-comment-refresh.md`.
        Confirmed by cloning upstream (not guessed): the pin is 41 commits *ahead*
        of the newest tag (`v1.3.0`), so this is a stale-comment fix, not a
        version-downgrade risk — the pinned revision itself is unchanged.

## Needs maintainer/human action (not code)

- [ ] `104` remote branches are `--no-merged` against `origin/main` even though
      their content has already landed via squash-merge — this is not fixable by a
      code change, and the executor's own token can't do it either (confirmed live
      this run: `git push origin --delete <branch>` on this run's own just-merged
      branch returned HTTP 403). Found this run's 8th cycle, checking `git ls-remote`
      against every branch this run itself merged (6/6 still present remotely,
      unauto-deleted) — every `auto/*`/`plan/*`/`copilot/*` branch this repo has ever
      merged via squash accumulates the same way, since squash-merge produces a new
      commit not reachable from the original branch tip, so `--no-merged` never
      recognizes it as merged regardless of GitHub's own repo-settings "auto-delete
      head branches" toggle (which, per this run's direct evidence, either isn't
      enabled here or doesn't apply to this token's merges). Not a security or
      correctness issue — every one of these branches' content is already on `main`
      — but it's real repo clutter that will keep growing by ~1-2 branches per
      executor cycle indefinitely. Two independent fixes, either needs a human: (1)
      a repo owner can enable "Automatically delete head branches" in Settings →
      General → Pull Requests, which would apply to all FUTURE merges (this run's
      own past branches would still need a one-time bulk cleanup), or (2) explicitly
      authorize a future executor run to bulk-delete every branch confirmed merged
      by content (not just by git ancestry) — this executor deliberately did NOT do
      that unprompted this cycle, since mass-deleting ~100 refs is exactly the kind
      of hard-to-reverse, outward-facing action that needs the maintainer's
      go-ahead first, not the executor's own judgment call.
- [ ] Confirm whether `routines.yaml`'s `allowed_tools` actually gates the MCP tool
      surface a scheduled executor run receives (#77). Found this cycle, re-surveying
      `routines/` for the first time since it was written: `routines/README.md` and
      `scripts/routines-author-check.sh`'s comments both assert the executor runs with
      `allowed_tools = [Bash, Read, Write, Edit, Glob, Grep]` — "no `RemoteTrigger`" —
      calling this "a hard tool-access limit, not a scope choice" that's the real
      enforcement behind forbidding executor-authored `routines.yaml` edits. This run's
      actual session tool list included a full `mcp__Claude_Code_Remote__*` suite
      (`create_trigger`/`update_trigger`/`delete_trigger`/`fire_trigger`/`list_triggers`/
      `send_later`) — functionally the "RemoteTrigger" capability the docs say isn't
      granted, confirmed live by successfully calling `send_later` earlier this run.
      Nothing was mutated (I did not call `update_trigger`/`create_trigger`/
      `delete_trigger` against this repo's own trigger,
      `trig_01Uz7L38vBHmKpg7fd6Hm7Qx`), but neither `routines-check.sh` nor
      `routines-author-check.sh` would have caught it if I had — both are git-diff-based
      checks against `routines.yaml`'s file content, not a runtime restriction, so a
      direct tool call bypasses them entirely. This needs a human to confirm with the
      Claude Code / claude.ai routines infrastructure whether `allowed_tools` is meant to
      gate the runtime MCP tool surface and, if so, why it apparently didn't this run —
      not something fixable by a Swift change or a doc edit alone until the actual
      mechanism is confirmed. See #77 for full detail.
- [x] ~~Decommission Proton Pass — final migration step (#5)~~ — done, by the maintainer's
      own hand: #5 was closed (`state_reason: completed`) on 2026-09-03. Marked `[x]` here
      (found via this run's GitHub-issue cross-check — every closed issue this ROADMAP
      references was re-verified against its actual current state) to match; this section
      had been left stale since the closure, still describing the interactive Safari
      Settings/`pluginkit` steps as pending. Password + TOTP autofill via KeeBridge is
      confirmed working end-to-end; this was the last step of the original Proton Pass
      migration, and it's done.

## Done

See `docs/done/` for one record per item shipped by the executor (created going forward,
starting with the first post-bootstrap cycle). Pre-executor history — vault write support
(#1) and the full secrets-management UI (#2), both closed — is tracked in the closed
GitHub issues and the git log (`99239da Add vault write support and a secrets-management
UI` and follow-on commits).
