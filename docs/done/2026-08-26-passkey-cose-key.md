# COSE_Key public-key encoding (`PasskeyCrypto.coseEncodedPublicKey`)

Next slice of #4 (passkey support), after `docs/done/2026-08-26-passkey-crypto.md`'s
key-generation/signing primitives. Resolves the exact open question that PR flagged:
which `P256.Signing.PublicKey` byte representation maps to WebAuthn's COSE_Key encoding.
Still no full `attestationObject`/`authData` envelope construction — just the one CBOR
map that goes *inside* one.

## The question, resolved

`P256.Signing.PublicKey` exposes three representations: `rawRepresentation`,
`x963Representation`, `compactRepresentation`. Confirmed (via swift-crypto/CryptoKit
documentation, not memory):

- `x963Representation` — 65 bytes: `0x04` (ANSI X9.63 uncompressed-point marker) `‖ X ‖
  Y`, each coordinate 32 bytes.
- `rawRepresentation` — 64 bytes: **just** `X ‖ Y`, no leading marker byte.

For a WebAuthn COSE_Key, the `x`/`y` parameters are the bare 32-byte coordinates with no
marker — so `rawRepresentation`, split at the 32-byte midpoint, is exactly right.
`coseEncodedPublicKey` guards this with an explicit `raw.count == 64` check (throws
rather than silently misencoding if a future swift-crypto version ever changed this).

## What was added

`PasskeyCrypto.coseEncodedPublicKey(forPrivateKeyPEM:)` (`String` and `SecureBytes`
overloads, matching `sign`'s existing shape) — CBOR-encodes the credential public key as
the fixed five-field COSE_Key map RFC 9053 defines for an EC2 key:

| Key | Value | Meaning |
|---|---|---|
| 1 (`kty`) | 2 | EC2 |
| 3 (`alg`) | -7 | ES256 |
| -1 (`crv`) | 1 | P-256 |
| -2 (`x`) | 32-byte bstr | X coordinate |
| -3 (`y`) | 32-byte bstr | Y coordinate |

These integer values are IANA-registered COSE constants (RFC 9053 §7.1/§7.2, and ES256
is cited everywhere in the WebAuthn spec itself) — stable, not something a library
version bump could silently change, unlike the PEM-format question the previous PR had
to check.

Includes a minimal, deliberately-not-general CBOR encoder (`cborUnsigned`/
`cborNegative`/`cborByteString`, private to `PasskeyCrypto`) — just the two integer forms
and the one byte-string length form (1-byte length prefix, up to 255 bytes) this fixed
five-field map ever needs. Not a dependency worth adding a CBOR library for.

## Tests

Three new tests in `PasskeyCryptoTests.swift`:

- `coseEncodedPublicKeyProducesTheExpectedCOSE_KeyByteLayout` — asserts the **exact**
  byte sequence, position by position, against the fixed structure above (not a CBOR
  decoder — the whole map is fixed and small enough to state directly as the test
  oracle), and separately confirms `rawRepresentation.count == 64` (the assumption the
  whole encoding depends on).
- `coseEncodedPublicKeyThrowsForAnInvalidPEM`.
- `coseEncodedPublicKeyWithSecureBytesMatchesTheStringOverload` — byte-identical (unlike
  signing, public-key encoding has no randomness).

## Secret hygiene

Grepped the diff for new `print`/`os_log`/`Logger` calls — none. This encodes a *public*
key — not secret material — but still follows the same `SecureBytes`-in/closure-scoped-
reveal pattern as `sign` for consistency and because the PEM it's derived from is secret.

## Still open (deliberately out of scope for this PR)

- The `authData` byte layout (RP ID hash, flags, sign count, AAGUID, credential ID, then
  this COSE_Key) and the `attestationObject` CBOR envelope (`fmt`/`attStmt`/`authData`)
  wrapping it.
- The actual `ASPasskeyCredentialRequest`/`ASPasskeyRegistrationCredential`/
  `ASPasskeyAssertionCredential` implementation in `CredentialProviderViewController.swift`.
- Declaring `ProvidesPasskeys: true` in `KeeBridgeProvider/Info.plist` — still withheld.
- Reconstructing the 9 Proton-Pass-carried passkeys — still informational-only.

## PR

#23
