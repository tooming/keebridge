# [Action needed] Twentieth cycle this run — main healthy, backlog empty

Twentieth cycle this run. `ROADMAP.md`'s "Now / next" lane is fully checked
off after this run's four real fixes (#113, #114, #116, #129).

## What this cycle checked

- STEP 1c: `main`'s latest push-triggered `ci.yml` run (this run's own #131
  merge, `79f1dda`) was `in_progress` at check time — didn't block, continued
  to STEP 2.
- STEP 2: zero open PRs.
- New GitHub issue activity: none — still only `#89`, unchanged.
- A genuinely new angle this cycle: read all three `.entitlements` files
  (`KeeBridge`, `KeeBridgeProvider`, `KeeBridgeCardExtension`) and both
  extension `Info.plist`s in full, cross-checking them against the code that
  depends on them — entitlements/capability declarations are explicitly
  called out as high-risk (not off-limits) in `routines/executor.prompt.md`'s
  hard rules, and none of this run's prior cycles had read these files
  directly.
  - `KeeBridge.entitlements` (container app): `autofill-credential-provider`
    only, deliberately no `app-sandbox` — matches `VaultController.swift`'s
    own doc comment ("this app is unsandboxed") and its use of
    `ASCredentialIdentityStore` from the main app.
  - `KeeBridgeProvider.entitlements`: both `app-sandbox` and
    `autofill-credential-provider` — correct for the actual credential
    provider extension.
  - `KeeBridgeCardExtension.entitlements`: `app-sandbox` only, no
    autofill-credential-provider entitlement — correct, it's a Safari Web
    Extension, not a credential-provider extension.
  - No App Group entitlement anywhere, consistent with the mirroring design
    (the unsandboxed app writes directly into each sandboxed extension's own
    container by path, per `VaultController.mirrorVaultToExtension`'s doc
    comment — sandboxing restricts what the sandboxed process itself can
    reach, not what another same-user process does to that directory).
  - `KeeBridgeProvider/Info.plist`'s `ASCredentialProviderExtensionCapabilities`
    (`ProvidesOneTimeCodes`/`ProvidesPasswords`/`ProvidesPasskeys`/
    `SupportsConditionalPasskeyRegistration`, all `true`) matches
    `CredentialProviderViewController`'s actual overrides one-for-one — no
    capability declared without a corresponding override, and no override
    (`completeOTPCredential`/`completePasswordCredential`/
    `beginPasskeyRegistration`/`performWithoutUserInteractionIfPossible(passkeyRegistration:)`)
    left undeclared.
  - No inconsistency found in any of the five files.
- Also read `VaultProbe.swift` (531 lines) in full with the same lens — its
  `passkey`/`card` subcommands already exist and match `EntryDetailView`'s
  own read-only, metadata-only scope; `update`'s reveal-then-merge logic
  correctly leaves `otpURI` unmerged (already documented in its own comment
  as the correct behavior, not an oversight). No gap found.

No new, confirmed, actionable finding.

## Current state

`ROADMAP.md`'s "Now / next" lane is fully checked off; "Needs
maintainer/human action" still has its two items (`#77`, and this run's own
stale-branch flag from `#119`). Filing this rather than fabricating a
twenty-first "finding" from nothing, per `routines/executor.prompt.md` STEP 6b.
