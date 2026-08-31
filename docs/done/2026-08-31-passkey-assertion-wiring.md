# Passkey support: assertion (sign-in) request handling in KeeBridgeProvider

`CredentialProviderViewController` now handles an incoming `ASPasskeyCredentialRequest` —
signing in with an **existing** passkey already stored in the vault. Registration (creating
a brand-new passkey) is not part of this change; see the follow-up ROADMAP item.

## What changed

- `VaultService.revealPasskeyPrivateKeyPEM(in:entryUUID:)` — new. Reveals a passkey-bearing
  entry's private key PEM from an already-open vault, pure in-memory (no I/O, no KDF), same
  reveal-on-demand discipline as `revealField`/`currentTOTPCode`: materializes the secret
  into a plain `String` only for the caller's immediate use, never persisted or logged. This
  is the one secret `VaultService.passkeyMetadata` deliberately left out of its own surface
  (per that method's doc comment) until real signing code existed to consume it — this is
  that code.
- `CredentialProviderViewController.completeCredential` now branches on
  `credentialRequest as? ASPasskeyCredentialRequest` before the existing OTP/password
  branching. The new `completePasskeyAssertion(for:content:)`:
  1. Reads the request's `ASPasskeyCredentialIdentity` (relying party, user handle,
     credential ID, `recordIdentifier`).
  2. Reveals the matching entry's private key via the new `VaultService` method.
  3. Builds `authenticatorData` via the existing `PasskeyCrypto.authenticatorData` — no
     `attestedCredentialData` (that's registration-only, spec §6.1).
  4. Signs `authenticatorData ‖ clientDataHash` (WebAuthn spec §6.3.3) via the existing
     `PasskeyCrypto.sign`.
  5. Responds with `extensionContext.completeAssertionRequest(using:)`, wrapping the result
     in `ASPasskeyAssertionCredential`.
- Reuses the exact same `prepareInterfaceToProvideCredential`/`showUnlockOrProceed`/
  `proceed(withContent:)` path passwords and OTP already go through — confirmed against
  Apple's own DocC JSON API (`developer.apple.com/tutorials/data/documentation/...json`,
  which serves plain JSON unlike the JS-rendered HTML doc pages) that passkey assertion
  doesn't need a new override, only branching inside the existing one.

## Still not implemented (see follow-up ROADMAP item)

- Registration (creating a **new** passkey from this extension) — needs a different
  override (`prepareInterfaceForPasskeyRegistration`), a UI decision (registration has no
  existing `recordIdentifier` to key off), and `ASPasskeyRegistrationCredential` built from
  the already-existing `PasskeyCrypto.attestationObject`.
- `ProvidesPasskeys: true` in `KeeBridgeProvider/Info.plist` — deliberately **not** declared
  yet. Until registration also exists, declaring the capability would advertise something
  this extension can't fully honor; until it's declared, the system never actually routes a
  real passkey ceremony to this extension. This PR's code is therefore correct,
  headless-verifiable groundwork that is currently inert in any real system flow — same
  pattern as every prior passkey-primitive PR in this sequence.

## Verification

Headless only, per this repo's environment constraints (no GUI/hardware, no Swift toolchain
in the executor's own sandbox — `make ci`'s real gate is this repo's GitHub Actions `ci`
workflow on `macos-latest`, which runs an actual unsigned `xcodebuild` build of
`KeeBridgeProvider` and so does catch a `CredentialProviderViewController.swift` compile
error). New `VaultService` tests (`revealPasskeyPrivateKeyPEM`, three cases: happy path,
non-passkey entry, unknown UUID) run under `swift test`. The
`AuthenticationServices` types used (`ASPasskeyCredentialRequest`,
`ASPasskeyCredentialIdentity`, `ASPasskeyAssertionCredential`,
`completeAssertionRequest(using:completionHandler:)`) were confirmed against Apple's DocC
JSON API rather than guessed from memory — exact initializer signatures, property names/
types, and method names all checked before writing this code.

**Still needs a human eyeball eventually**: this is inert until the registration follow-up
lands and `ProvidesPasskeys: true` is declared — no code change in *this* PR reaches a real
Safari passkey ceremony. Once it does, the actual signing/response flow still needs a real
Safari sign-in against a real passkey-bearing entry to be fully confident — headless
`xcodebuild`/`swift test` can confirm it compiles and that the pure-data pieces
(`PasskeyCrypto`, `VaultService`) behave correctly in isolation, but not that
`AuthenticationServices` accepts the response end-to-end.

## PR

See the PR this file was committed alongside.
