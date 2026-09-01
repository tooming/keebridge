# Passkey support: WebAuthn credential ID generation (`PasskeyCrypto.generateCredentialID`)

Adds the one primitive registration was still missing per the ROADMAP's own note on the
blocked registration item: "still missing: generating a fresh, random WebAuthn credential
ID (a small addition, not yet written)."

## What changed

- `PasskeyCrypto.generateCredentialID() -> Data` — returns 16 random bytes (128 bits),
  generated via swift-crypto's `SymmetricKey(size: .bits128)` (CSPRNG-backed), not
  Foundation's weaker `.random(in:)`/`SystemRandomNumberGenerator` — consistent with this
  file's existing "no hand-rolled crypto" rule (same library every other `PasskeyCrypto`
  primitive already depends on, no new dependency added).
- 16 bytes matches what major platform authenticators emit in practice for a discoverable
  credential's ID. WebAuthn (spec §4, "Credential ID") doesn't mandate a fixed size, only
  that it be drawn from a strong source of entropy so a relying party can treat it as
  unguessable — a CSPRNG-backed 128-bit value satisfies that with wide margin.
- Three new tests (`KeeBridgeCoreTests/PasskeyCryptoTests.swift`), same style as this
  file's existing `generatePrivateKeyPEM` tests: exact length (16 bytes), distinctness
  across two calls, and a not-all-zero sanity check (a stuck/broken generator is a far
  more plausible explanation for an all-zero 16-byte value than genuine 1-in-2^128 bad
  luck, so this is a legitimate regression check).

## Why this alone, not the rest of registration

The registration ROADMAP item bundles several genuinely separate concerns: this crypto
primitive, `prepareInterface(forPasskeyRegistration:)`/`ASPasskeyRegistrationCredential`
wiring in `KeeBridgeProvider`, declaring `ProvidesPasskeys: true` in
`KeeBridgeProvider/Info.plist`, a still-unimplemented
`performWithoutUserInteractionIfPossible(passkeyRegistration:)` override, and an unsettled
design question (which vault entry a freshly-registered passkey attaches to, likely a
URL-host match falling back to an entry-picker UI). Splitting the crypto primitive off as
its own small, cleanly testable PR follows the same pattern every other passkey building
block in this ROADMAP has already gone through (key generation, COSE encoding,
`authenticatorData`, `attestationObject` were each their own PR) rather than bundling it
into one large, harder-to-review registration PR. The remaining registration work — the
`KeeBridgeProvider` wiring, `Info.plist` change, and the entry-attachment design decision —
stays open in `ROADMAP.md`, no longer described as needing this credential-ID piece.

## Verification

`swift test` (KeeBridgeCoreTests) covers the new function directly. No app/extension
target changes, so no `xcodebuild` surface touched by this PR.

## PR

See the PR this file was committed alongside.
