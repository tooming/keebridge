# P-256 key generation + ECDSA signing (`PasskeyCrypto`)

Next slice of #4 (passkey support), after `docs/done/2026-08-26-passkey-write-support.md`'s
read/write metadata work. Still no CBOR/COSE/`attestationObject` construction — just the
key-generation and raw-signing primitives real WebAuthn registration/assertion code will
need to call.

## What was added

A new `PasskeyCrypto` enum (`KeeBridgeCore/Sources/KeeBridgeCore/PasskeyCrypto.swift`),
built entirely on `swift-crypto`'s `P256.Signing` API — already a dependency, no
hand-rolled crypto:

- `generatePrivateKeyPEM() -> String` — generates a fresh P-256 private key and returns
  its PEM representation.
- `sign(_:withPrivateKeyPEM:) throws -> Data` (both a `String` and a `SecureBytes`
  overload) — parses a PEM-encoded P-256 private key and signs data, returning the
  ASN.1 DER-encoded ECDSA signature — the format a WebAuthn
  `AuthenticatorAssertionResponse.signature` requires.

## The thing worth being careful about, and how it was checked

The main risk in this kind of code isn't the "does it compile" question — it's "is the
serialized key format actually the one the rest of this project's convention expects."
`VaultService.setPasskey`/KDBXKit's `KPEX_PASSKEY_PRIVATE_KEY_PEM` field is documented
as expecting **PKCS#8** PEM (`"BEGIN PRIVATE KEY"`), not the SEC1 (`"BEGIN EC PRIVATE
KEY"`) format some other libraries default to for EC keys. Rather than assume
`P256.Signing.PrivateKey.pemRepresentation` produces the right one, this was checked
directly: swift-crypto serializes P256 signing keys via `ASN1.PKCS8PrivateKey`, so
`pemRepresentation` does emit PKCS#8 — confirmed, not guessed, before writing code that
depends on it. `PasskeyCryptoTests.swift`'s first test also asserts this at the string
level (`pem.contains("BEGIN PRIVATE KEY")`, `!pem.contains("BEGIN EC PRIVATE KEY")`), so
a future swift-crypto version change that flipped this would fail CI rather than fail
silently at KeePassXC-interop time.

## What was deliberately left unimplemented (not guessed at)

`PasskeyCrypto` does **not** extract or COSE-encode the public key yet.
`P256.Signing.PublicKey` exposes three different byte representations
(`rawRepresentation`, `x963Representation`, `compactRepresentation`), and which one maps
to the WebAuthn COSE_Key encoding's expected X/Y coordinate format needs confirming
against the actual WebAuthn/COSE spec before writing that code — not assumed from
memory. Left as an explicit open item (see ROADMAP) rather than shipped on a guess.

## Tests

New `PasskeyCryptoTests.swift`, six tests, all synthetic (freshly generated keys, no
real credential material):

- `generatePrivateKeyPEMProducesAParsablePKCS8PEM` — the PKCS#8-not-SEC1 check above,
  plus round-trips the PEM through `P256.Signing.PrivateKey`'s own parser.
- `generatePrivateKeyPEMProducesDistinctKeysEachCall` — two calls produce different keys.
- `signProducesAValidSignatureForTheMatchingPublicKey` — signs, then **independently**
  verifies via `swift-crypto` directly (not `PasskeyCrypto`'s own API — it deliberately
  has no `verify()`, since KeeBridge is the WebAuthn authenticator, not the relying party
  that verifies) that the signature is valid for the message and public key.
- `signRejectsATamperedMessage` — the same verification correctly rejects a different
  message.
- `signThrowsForAnInvalidPEM`.
- `signWithSecureBytesMatchesSigningWithTheEquivalentString` — the `SecureBytes` overload
  produces a signature that verifies just as validly as the `String` overload's (ECDSA
  signing is randomized per call, so the DER bytes themselves won't match — both are
  checked for validity independently, not byte-equality).

Needed adding `swift-crypto`'s `Crypto` product as an explicit dependency of the
`KeeBridgeCoreTests` test target (`KeeBridgeCore/Package.swift`) — already resolved
transitively via `KeeBridgeCore` itself, this makes it directly importable for the test
file's independent-verification step.

## Secret hygiene

Grepped the diff for new `print`/`os_log`/`Logger` calls — none. Private key PEMs never
leave process memory; the `SecureBytes` overload reveals it only for the closure-scoped
lifetime of `withRevealedString`, never materializing a long-lived plain `String` at the
call site.

## Still open (deliberately out of scope for this PR)

- Public-key extraction + COSE_Key encoding (needs the representation question above
  resolved against the actual spec first).
- The CBOR-encoded `attestationObject` construction.
- The actual `ASPasskeyCredentialRequest`/`ASPasskeyRegistrationCredential`/
  `ASPasskeyAssertionCredential` implementation in `CredentialProviderViewController.swift`.
- Declaring `ProvidesPasskeys: true` in `KeeBridgeProvider/Info.plist` — still withheld.
- Reconstructing the 9 Proton-Pass-carried passkeys — still informational-only.

## PR

#22
