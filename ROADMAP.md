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
  KeeBridge/KeeBridgeProvider targets + routines drift checks) green is necessary, not
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
- [ ] Credit card autofill implementation (#3) — the actual Safari Web Extension target
      (new JS/TS tech stack: content script + background script +
      `SafariWebExtensionHandler` native handler), built on the design spike above.
      **Blocked in this executor's environment**: this needs a brand-new Xcode target,
      and there's no `xcodegen` binary here to regenerate `KeeBridge.xcodeproj` from
      `project.yml` after adding one — confirmed 2026-08-26 (`which xcodegen` → nothing).
      The checked-in `project.pbxproj` uses the classic explicit
      `PBXFileReference`/`PBXBuildFile` format (no modern synchronized-folder groups —
      grepped, zero matches), so hand-adding a whole new target's build phases by
      editing that file directly, with no way to validate the result short of a real
      Xcode install, is a correctness risk not worth taking headless. Content edits to
      *existing* targets' files (Swift sources, `Info.plist`, entitlements) remain
      safe and unaffected by this — see the passkey item below, which needs none of
      that. Once `xcodegen` is available in this environment (or a human adds the
      target once, by hand, in real Xcode), scope for the first PR: extend the app's
      existing mirroring (`mirrorVaultToExtension`'s sibling) to also mirror card
      entries into the new extension target's container — a focused,
      `KeeBridgeCore`/app-side slice with no new JS yet. Still unresolved (needs the
      maintainer): the actual field-name convention the 9 real card entries use.
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
- [ ] Passkey support: registration + assertion signing (#4) — highest-risk,
      highest-effort item, deliberately last, needs none of the blocked-Xcode-target
      work #3 does (all of it lands in the *existing* `KeeBridgeProvider` target +
      `KeeBridgeCore`, both already touched by the read/write/crypto slices above).
      Requires a real CBOR-encoded `attestationObject` (COSE_Key encoding for the public
      key — `PasskeyCrypto` doesn't extract/encode the public key yet, only sign; the
      `rawRepresentation`/`x963Representation` distinction on `P256.Signing.PublicKey`
      needs confirming against the WebAuthn COSE_Key spec before writing that, not
      guessed at), plus `ASPasskeyCredentialRequest`/`ASPasskeyRegistrationCredential`/
      `ASPasskeyAssertionCredential` — a materially bigger `AuthenticationServices`
      surface than passwords/OTP. Declare `ProvidesPasskeys: true` in
      `KeeBridgeProvider/Info.plist` only once this request-handling actually exists —
      declaring the capability first would advertise something the extension can't yet
      fulfill. The 9 Proton-Pass-carried passkeys stay informational-only per the design
      spike's recommendation — reconstructing them (separate proprietary double-nested
      MessagePack format) is optional, riskier follow-up, not a blocker. Expect this to
      need its own groomed sub-items rather than one PR.
- [ ] QR code scanning for adding a passkey (#7) — some sites offer a QR code to add a
      passkey; KeeBridge should support scanning it. Depends on passkey support (#4)
      existing first — not buildable until that lands.
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
