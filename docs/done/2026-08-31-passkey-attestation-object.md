# Passkey support: `attestationObject` CBOR envelope construction

`PasskeyCrypto` gains `attestationObject(authenticatorData:)`, wrapping the previously-built
`authenticatorData` byte string in the WebAuthn `attestationObject` CBOR envelope (spec
§6.5.4): a 3-entry map `{fmt: "none", attStmt: {}, authData: <bytes>}`.

`fmt: "none"` with an empty `attStmt` is the simplest valid self-attestation statement
format (spec §8.7, "none Attestation Statement Format") — every conformant relying party is
required to accept it. KeeBridge generates its own P-256 keys locally and holds no
hardware-attestation chain to prove, so a real attestation format (e.g. "packed") would only
assert trust that doesn't exist; "none" is the honest choice here, not a shortcut.

This is what `ASPasskeyRegistrationCredential` will need for its `rawAttestationObject` once
the remaining registration/assertion request-handling wiring lands (split off as its own
follow-up ROADMAP item — see below).

## What changed

- `PasskeyCrypto.attestationObject(authenticatorData:)` — new, pure data-framing, no new
  crypto (same "swift-crypto for crypto, hand-rolled CBOR only for data framing" split as
  the rest of `PasskeyCrypto`).
- The minimal CBOR encoder (previously only unsigned/negative single-byte integers and a
  byte-string encoder capped at a 1-byte length prefix — good enough for the fixed 5-field
  COSE_Key map, where every field is ≤32 bytes) gained:
  - Text-string encoding (CBOR major type 3), needed for the `fmt`/`attStmt`/`authData` map
    keys and the `"none"` value.
  - A shared `cborHead(major:count:)` length-prefix helper supporting the 0–23 immediate,
    1-byte, and 2-byte length forms — `authenticatorData` (especially with
    `attestedCredentialData` present) can exceed the old 255-byte cap once a real credential
    ID is included, unlike anything the COSE_Key encoder ever needed to frame.
- New tests in `PasskeyCryptoTests.swift`: exact byte-layout assertion for a short
  `authData` input (same "assert the fixed structure byte-by-byte" style as the existing
  `coseEncodedPublicKey` test), a check that the 1-byte-length-prefix form actually kicks in
  once `authData` exceeds 23 bytes (true for any real registration `authenticatorData`, since
  it always carries `attestedCredentialData`), and a determinism check.

Still not implemented: the `ASPasskeyCredentialRequest`/`ASPasskeyRegistrationCredential`/
`ASPasskeyAssertionCredential` wiring in `KeeBridgeProvider` itself — that's the materially
bigger, genuinely-hard-to-verify-headlessly half of the original ROADMAP item, split off as
its own follow-up entry (needs a real Safari passkey flow to be fully confident it works;
this repo's executor has no GUI/hardware in this environment).

## Verification

Headless only, per this repo's environment constraints — no Swift toolchain is available in
the executor's own sandbox (Linux, no `swift`/`xcodebuild`, and the outbound proxy blocks
`download.swift.org` so one can't be installed on demand either); this repo's actual `make
ci` gate runs on GitHub Actions' `macos-latest` runner on push, same as every prior cycle.
The new CBOR byte layout was hand-traced against RFC 8949 §3.1's major-type/length-prefix
encoding (byte-for-byte, matching the same fixed-header-byte style the existing
`coseEncodedPublicKey` test already uses as its oracle) before writing the tests; CI on the
opened PR is the actual gate before self-review/merge.

**Still needs a human eyeball eventually**: this CBOR envelope is inert until the follow-up
`AuthenticationServices` wiring exists and is exercised against a real Safari passkey
registration flow — no code change in *this* PR reaches anything interactive.

## PR

See the PR this file was committed alongside.
