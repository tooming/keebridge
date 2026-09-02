# Register passkey identities in ASCredentialIdentityStore

Discovered via a fresh, full read of `KeeBridge/VaultController.swift` — this run's fourth
consecutive re-survey turned up nothing new from issues/TODO/FIXME/README, so this cycle
went deeper: a complete read (not just the passkey-metadata slice touched by an earlier
cycle) of a core app file no run had read end-to-end before.

## The gap

`VaultController.populateIdentityStore(entries:)` builds `ASPasswordCredentialIdentity`
and `ASOneTimeCodeCredentialIdentity` arrays from the vault's entries and registers them
via `ASCredentialIdentityStore.shared.replaceCredentialIdentities(_:)` — the mechanism
that tells the system "KeeBridge can provide autofill for these accounts." Despite several
ROADMAP cycles shipping real passkey assertion (`CredentialProviderViewController.completePasskeyAssertion`)
and registration code, this method built **no `ASPasskeyCredentialIdentity` entries at
all**.

This matters because `ASCredentialIdentityStore` registration isn't just a "nice to have
for suggestions" — for a third-party credential provider extension, it's the mechanism by
which the system learns the provider holds a *specific* passkey for a *specific* relying
party/credential ID at all. Without a matching registered identity, the system has no way
to construct an `ASPasskeyCredentialRequest` naming that credential and route it to
KeeBridge's `CredentialProviderViewController` — meaning the previously-shipped
`completePasskeyAssertion` code, however correct in isolation, most likely could never
actually fire in a real Safari passkey sign-in.

## Evidence, not just inference

Cross-checked this against real, shipped third-party credential-provider source (not
assumed from the DocC page alone, which didn't state the routing requirement explicitly):

- A comment directly in a real device-bound-passkey demo's `CredentialProviderViewController.swift`:
  `// Without this, iOS won't offer our credential provider during sign-in` — immediately
  above its own `ASPasskeyCredentialIdentity` construction + `replaceCredentialIdentities` call.
- **Proton Pass's own macOS desktop app** (`ProtonMail/WebClients`,
  `applications/pass-desktop/macOS/Packages/AutoFillEngine`) — the same category of app as
  KeeBridge, a real shipped third-party macOS credential provider — builds
  `ASPasskeyCredentialIdentity` entries and calls `replaceCredentialIdentities` for its
  passkeys, exactly the pattern this fix adds.
- Bitwarden's `AutofillCredentialService.swift` and several other independent open-source
  credential-provider implementations (`KeeForge`, `passwd-sso`, `react-native-passkey-autofill`,
  `local-passkey-manager`) all do the same thing.

## What changed

- `VaultService.VaultPasskeyMetadata` (KeeBridgeCore): gained a `userHandle: Data?` field,
  populated from `KDBX.Entry.passkeyUserHandle` in `passkeyMetadata(in:entryUUID:)`. This
  data was already stored/read elsewhere (`mergeExtensionOriginatedPasskeys` already reads
  `passkeyUserHandle`) but never exposed through the metadata struct the app/CLI actually
  read from. Non-secret: per the WebAuthn spec itself, a user handle is an opaque
  identifier that "MUST NOT contain personally identifying information" — same
  classification this codebase already gives `credentialID`. Added with a defaulted
  `nil` parameter so the one existing construction call site didn't need to change
  independently of this fix.
- `VaultController.populateIdentityStore` now also builds one `ASPasskeyCredentialIdentity`
  per passkey-bearing entry (via the existing `VaultService.passkeyMetadata` lookup — pure
  in-memory, no Argon2/I/O) and includes them in the array passed to
  `replaceCredentialIdentities`. Skips an entry defensively if any of relying
  party/credential ID/user handle is missing (shouldn't happen for anything this app
  itself registered via `setPasskey`, but the 9 informational-only Proton-Pass-carried
  passkeys never got real key material, so they'd naturally be skipped rather than
  registered with garbage data).
- `VaultProbe`'s `passkey` subcommand also prints `userHandle` now, for parity with the
  app UI and because the underlying metadata struct now carries it.

## Why this scope, not more

No new write path, no new crypto, no change to `completePasskeyAssertion`/
`completePasskeyRegistration` themselves — this only feeds the system the identity
information those existing, already-correct code paths need to actually be reachable.
Deliberately did not add `rank` tuning or any other `ASPasskeyCredentialIdentity` property
beyond what's required — no basis in this codebase yet for prioritizing one passkey over
another.

## Verification

Headless: `KeeBridgeCore`'s `swift test` covers the new `userHandle` field end-to-end
(`PasskeyTests.swift`, extended to set and assert it via KDBXKit's own
`setPasskeyUserHandle`/read path — synthetic data only, same discipline as every other
test in this package). The `VaultController` change itself has no unit test target (same
as before — SwiftUI/AppKit app-target code, `xcodebuild`-only), so its correctness rests
on: a real compile against `AuthenticationServices`' actual `ASPasskeyCredentialIdentity`
initializer (a wrong signature fails the build, not silently), and the cross-referenced
real-world implementations above for the initializer shape and the "why this is needed"
reasoning.

**Still needs a human eyeball**: whether this actually makes Safari route a real passkey
sign-in to KeeBridge can only be confirmed on real hardware with a real relying party —
same limitation as every passkey item in this ROADMAP. Unlike most of them, though, this
one is a plausible explanation for passkey sign-in *not* having worked yet, not just an
additional capability layered on already-working functionality — worth prioritizing
whenever the maintainer next has hands-on time with the app.

## PR

See the PR this file was committed alongside.
