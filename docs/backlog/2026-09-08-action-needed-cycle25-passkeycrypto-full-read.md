# [Action needed] Twenty-fifth cycle — full read of PasskeyCrypto.swift; clean

Twenty-fifth cycle this run. `ROADMAP.md`'s "Now / next" lane remains fully checked
(only `#77` unchecked, correctly skipped by STEP 3). Zero open PRs.

## What was checked

Read `KeeBridgeCore/Sources/KeeBridgeCore/PasskeyCrypto.swift` (286 lines, the
actual cryptographic implementation backing every passkey flow) start to finish,
continuing the full-linear-read pattern (`#95`/`#99`/`#100`, and cycle 24's
`VaultController.swift` read that found `#101`'s real bug).

Specifically re-derived from spec rather than trusting the existing comments:

- **COSE_Key canonical ordering**: independently sorted the five map keys
  (`kty=1`, `alg=3`, `crv=-1`, `x=-2`, `y=-3`) by their actual encoded CBOR bytes
  (`0x01, 0x03, 0x20, 0x21, 0x22`) per RFC 8949's canonical-form rule — matches
  the code's emission order exactly.
- **`cborNegative`'s encoding formula** (`0x20 | UInt8(-1 - value)`) against
  RFC 8949 major-type-1 semantics (`-1-n`) for every value actually used here
  (-1, -2, -3, -7) — correct for all four.
- **`authenticatorData`'s byte layout** (rpIdHash‖flags‖signCount‖attestedCredentialData)
  and flag bit positions (UP=bit0/0x01, UV=bit2/0x04, AT=bit6/0x40) against
  WebAuthn spec §6.1 — correct.
- **The one latent (not reachable) edge case worth naming**: `cborHead`'s 2-byte
  length form tops out at `count <= 0xFFFF`; `authenticatorData`'s own guard caps
  `credentialID` at `UInt16.max` (65535) bytes, but a credential ID anywhere near
  that size, combined with the COSE key and other fixed fields, would push the
  *total* `authenticatorData` passed to `attestationObject`'s own `cborByteString`
  over that same 0xFFFF threshold and hit `cborHead`'s `preconditionFailure`. Not
  reachable in practice — `generateCredentialID()` always produces exactly 16
  bytes, and the only other credential IDs this code ever signs against are ones
  it registered itself — and already acknowledged by the file's own comment
  ("nothing this encodes gets anywhere near 64KB"), so not a new finding, just
  independently re-confirmed as intentional rather than overlooked.
- **The signing call**: `P256.Signing.PrivateKey.signature(for:)` auto-hashes
  with SHA-256 before signing (swift-crypto's documented default for this
  overload) — matches WebAuthn §6.3.3's requirement to sign
  `authenticatorData ‖ clientDataHash` under ES256 (SHA-256 + ECDSA/P-256).

No bug found. Clean.

## No new findings

Same two open issues as recent cycles (`#77`, `#89`). Filing this rather than
fabricating make-work, per STEP 6b.
