# `authenticatorData` construction (`PasskeyCrypto.authenticatorData`)

Next slice of #4 (passkey support), after `docs/done/2026-08-26-passkey-cose-key.md`'s
COSE_Key public-key encoding. Builds the WebAuthn `authData` byte string itself — the
piece that goes *inside* an `attestationObject`, not the CBOR envelope
(`fmt`/`attStmt`/`authData`) wrapping it, which is still out of scope.

## The layout, resolved

WebAuthn spec §6.1 defines `authenticatorData` as a fixed-prefix, variable-suffix byte
string (confirmed via WebSearch against the spec, not memory):

| Bytes | Field | Contents |
|---|---|---|
| 32 | `rpIdHash` | SHA-256 of the (UTF-8) RP ID |
| 1 | `flags` | bit 0 = UP (user present), bit 2 = UV (user verified), bit 6 = AT (attested credential data present), bit 7 = ED (extension data present, unused here) |
| 4 | `signCount` | big-endian `UInt32` |
| variable | `attestedCredentialData` | only present when the AT flag is set (registration only, never on a later assertion) |

`attestedCredentialData` itself is:

| Bytes | Field |
|---|---|
| 16 | AAGUID |
| 2 | credential ID length, big-endian `UInt16` |
| variable | credential ID |
| variable | CBOR COSE_Key (self-delimiting — no length prefix needed after it) |

## What was added

`PasskeyCrypto.authenticatorData(relyingPartyID:signCount:userPresent:userVerified:attestedCredentialData:)`
— builds exactly the byte layout above. `userPresent`/`userVerified` default to `true`
(the caller only gets here after an actual vault unlock); pass `attestedCredentialData`
for a registration response, omit it (the default) for an assertion response.

New `PasskeyCrypto.AttestedCredentialData` struct (`aaguid`/`credentialID`/
`coseEncodedPublicKey`, all `Data`, public memberwise init) — bundles the three pieces of
attested-credential data, with `coseEncodedPublicKey` expected to be the output of the
existing `coseEncodedPublicKey(forPrivateKeyPEM:)`. Doc comment notes an all-zero AAGUID
is a legitimate, common choice (and that macOS zeroes a third-party credential provider's
AAGUID regardless, per the design spike's platform-risk finding).

New `PasskeyCryptoError.invalidAttestedCredentialData` case, thrown when:

- the AAGUID isn't exactly 16 bytes, or
- the credential ID is too long to fit the mandatory `UInt16` length prefix (> 65535 bytes).

## Tests

Six new tests in `PasskeyCryptoTests.swift`, all asserting the exact byte layout
(position-by-position, not a CBOR/structure decoder — the format is fixed and small
enough to state directly as the test oracle):

- `authenticatorDataWithoutAttestedCredentialDataHasNoATFlagAndIsExactly37Bytes` — the
  32+1+4 = 37-byte no-attested-data shape; correct `rpIdHash` (verified independently via
  `SHA256.hash`), UP/UV flags set by default, AT flag NOT set, `signCount` zero.
- `authenticatorDataFlagsReflectUserPresentAndUserVerifiedParameters` — both flag bits
  clear when both parameters are `false`.
- `authenticatorDataEncodesSignCountBigEndian` — a mixed-byte sign count round-trips in
  the correct byte order.
- `authenticatorDataWithAttestedCredentialDataSetsATFlagAndAppendsTheExpectedLayout` — AT
  flag set, total length matches, and AAGUID/credential-ID-length/credential-ID/COSE-key
  each land at the exact expected offset (COSE key generated via the real
  `coseEncodedPublicKey`, not a fixture, so this also exercises the two functions
  together).
- `authenticatorDataThrowsForAWrongSizedAAGUID` / `authenticatorDataThrowsForAnOversizedCredentialID`
  — the two validation-error paths.

## Secret hygiene

Grepped the diff for new `print`/`os_log`/`Logger` calls — none. No secret material is
handled directly here (the COSE_Key passed in is already public-key-only, produced by the
existing `coseEncodedPublicKey`); the RP ID is hashed, never stored or logged raw.

## Still open (deliberately out of scope for this PR)

- The `attestationObject` CBOR envelope (`fmt`/`attStmt`/`authData`) wrapping this byte
  string.
- The actual `ASPasskeyCredentialRequest`/`ASPasskeyRegistrationCredential`/
  `ASPasskeyAssertionCredential` implementation in `CredentialProviderViewController.swift`.
- Declaring `ProvidesPasskeys: true` in `KeeBridgeProvider/Info.plist` — still withheld.
- Reconstructing the 9 Proton-Pass-carried passkeys — still informational-only.

## PR

#24
