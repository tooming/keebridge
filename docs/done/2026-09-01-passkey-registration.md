# Passkey support: registration (creating a NEW passkey from KeeBridge)

Wires `prepareInterface(forPasskeyRegistration:)` in `KeeBridgeProvider` and declares
`ProvidesPasskeys: true`, completing the passkey feature's registration half (assertion —
signing in with an *existing* stored passkey — landed earlier in this ROADMAP).

## What changed

- `CredentialProviderViewController.prepareInterface(forPasskeyRegistration:)` (new
  override, macOS 14+) — mirrors the existing `prepareInterfaceToProvideCredential(for:)`
  entry point: arms the watchdog, stores the pending request, and goes through the same
  unlock-or-proceed flow as every other credential type.
- `beginPasskeyRegistration(for:content:)` (new) — the entry-attachment policy. Filters
  the vault's entries by URL host against the incoming request's relying party ID (exact
  match or subdomain — a WebAuthn RP ID is a registrable-domain suffix of the real origin,
  spec §5.1.3, so `accounts.example.com` should match RP ID `example.com`). A single match
  auto-attaches with no extra UI; zero or multiple matches fall back to the same
  `CredentialListView` the manual password picker already uses.
- `completePasskeyRegistration(for:identity:entry:)` (new) — generates a fresh credential
  ID (`PasskeyCrypto.generateCredentialID()`) and private key
  (`PasskeyCrypto.generatePrivateKeyPEM()`), builds the COSE public key, `authenticatorData`
  (with `attestedCredentialData`, all-zero AAGUID — same rationale as assertion), and
  `attestationObject`, then **writes** the new passkey via `VaultService.setPasskey` — the
  first write this extension has ever done, straight into its own sandboxed vault mirror
  (the same file its reads already use). The app's `mirrorVaultToExtension` merges this
  back into the real source vault the next time it re-mirrors
  (`VaultService.mergeExtensionOriginatedPasskeys`, wired in the immediately-preceding
  ROADMAP item) — this write would otherwise be silently lost. Responds via
  `extensionContext.completeRegistrationRequest(using:)` with a new
  `ASPasskeyRegistrationCredential`.
- A new `respondComplete(with: ASPasskeyRegistrationCredential)` overload, same
  once-only/watchdog-cancelling shape as every other `respondComplete` overload in this
  file.
- The credential ID the incoming request's identity might carry is never trusted/reused —
  WebAuthn spec §6.3.2 step 4 has the *authenticator* (KeeBridge) pick it, so a fresh one is
  always generated.
- `KeeBridgeProvider/Info.plist`: `ProvidesPasskeys: true` added alongside the existing
  `ProvidesOneTimeCodes`/`ProvidesPasswords`. This is the single capability flag both
  registration AND the earlier-landed assertion code gate on — flipping it activates both
  at once, not just this PR's own code.

## Correction to the ROADMAP's own prior text

The registration item previously said a
`performWithoutUserInteractionIfPossible(passkeyRegistration:)` override "must exist
before `ProvidesPasskeys` is ever declared." Checked against Apple's DocC JSON API before
writing any code this cycle: that override is macOS 15+ and is required **only** when also
opting into the separate `SupportsConditionalPasskeyRegistration` capability (silent,
background passkey registration) — a distinct, still-unclaimed capability from
`ProvidesPasskeys` itself. This PR does not declare `SupportsConditionalPasskeyRegistration`,
so that override isn't needed for what shipped here. If conditional registration is ever
wanted, that override becomes a prerequisite for *that* capability specifically, not for
`ProvidesPasskeys` in general.

## Why the write goes through the mirror, not the source vault directly

The extension only ever has access to its own sandboxed vault mirror (see `README.md`'s
"No shared Keychain access group, no App Group" design note) — it has never had a way to
reach the real source vault file directly, by design. `VaultService.setPasskey` here is
called with the mirror's own URL and the extension's own cached pre-hash, identical to
every other vault-open call already in this file.

## What's still open (not this PR's scope)

- **Never exercised against a real Safari passkey-creation flow** — no GUI, no Touch ID
  hardware, no macOS available in this executor's environment (headless-only, per
  `routines/executor.prompt.md`). The entry-attachment heuristic (URL-host match, exact or
  subdomain), the picker fallback, and the full registration→write→respond pipeline are
  each individually reasoned through and consistent with the already-shipped, unit-tested
  `PasskeyCrypto` primitives and the already-landed assertion code's proven patterns, but
  this specific new code path has not run on real hardware. **This needs a human eyeball**
  on a real device before relying on it for an actual account registration.
- **The 9 Proton-Pass-carried passkeys** stay informational-only, per the original design
  spike's recommendation — reconstructing them from their separate proprietary
  double-nested MessagePack format is optional, riskier follow-up work, not required for
  this item.
- **QR code scanning for adding a passkey (#7)** is a separate ROADMAP item (hybrid/caBLE
  transport, a different mechanism from same-device registration) — not addressed here.

## Verification

Headless only, compiled-only for this PR's `KeeBridgeProvider` changes — this target has
no unit test coverage of its own (same as the earlier assertion-wiring and write-back
wiring PRs; `CredentialProviderViewController` isn't a `KeeBridgeCoreTests`-reachable
type). Correctness rests on: (1) CI's real `xcodebuild` build of the `KeeBridge`/
`KeeBridgeProvider` targets catching any compile error, (2) the underlying
`PasskeyCrypto`/`VaultService` primitives this code calls already being `swift test`
covered in their own right, and (3) careful, direct verification of the exact Apple API
shapes used here (`prepareInterface(forPasskeyRegistration:)`'s signature,
`ASPasskeyRegistrationCredential`'s initializer, `ASPasskeyCredentialIdentity`'s
properties) against Apple's own DocC JSON API before writing this code, rather than
assuming the ROADMAP's earlier notes were complete.

## PR

See the PR this file was committed alongside.
