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

- [ ] Credit card autofill via Safari Web Extension (#3) — Apple has no system extension
      point for third-party card autofill (confirmed: no `ASCreditCardCredential` type,
      no `ProvidesCreditCards` capability key). Needs a new tech stack for this project
      (JS/TS content script + background script) and a design for how the extension talks
      to the native app/extension to get card data. 9 card entries already exist in the
      vault from the original Proton export, unexposed anywhere in KeeBridge yet. Scope
      out the native-messaging vs. local-decrypt question before implementation starts —
      likely too large for one PR; expect this to split into a design/spike item first.
- [ ] Passkey support: WebAuthn provider + vault write (#4) — highest-risk, highest-effort
      item, deliberately last. Its dependency (vault write support, #1) is done. Requires
      a real CBOR-encoded `attestationObject`, P-256/ES256 assertion signing, and
      `ASPasskeyCredentialRequest`/`ASPasskeyRegistrationCredential`/
      `ASPasskeyAssertionCredential` — a materially bigger `AuthenticationServices` surface
      than passwords/OTP. There is a documented, unresolved Apple-side bug (Developer
      Forums thread 814547) that silently zeroes a third-party macOS passkey provider's
      AAGUID and misreports it as iCloud Keychain to the relying party — real platform
      risk, not hypothetical. The 9 Proton-Pass-carried passkeys in the vault are not
      directly portable (proprietary double-nested MessagePack format) — decide whether to
      reconstruct them or treat them as informational-only and re-create passkeys fresh
      per site. Expect this to need its own groomed sub-items rather than one PR.
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
- [ ] Write subcommands (`create`/`update`/`delete`) for the CLI tool, via the
      `VaultService` write methods (all now have `masterPassword` overloads) — higher-value
      and higher-risk than the read-only subcommands; do once those have proven the
      subcommand/parsing shape out (they have, see the `list`/`reveal`/`totp` items above).

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
