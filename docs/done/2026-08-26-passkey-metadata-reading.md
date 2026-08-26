# Passkey read-only metadata support

Next slice of #4 (passkey support), after last cycle's design spike
(`docs/done/2026-08-26-passkey-design-spike.md`) — with a correction discovered while
scoping this one (see that file's correction banner).

## The correction: KDBXKit already has first-class passkey support

The design spike's storage-convention finding (a `webauthn.pem` file attachment) came
from general web search about KeePassXC 2.7.7 and turned out to be the wrong specific
mechanics. Reading this project's own `KDBXKit` dependency's source directly (at the
exact revision already pinned in `KeeBridgeCore/Package.swift`) found
`Sources/KDBXKit/KDBX/Entry+Passkey.swift` — KDBXKit already models KeePassXC's *actual*
convention: five custom string fields per entry (`KPEX_PASSKEY_RELYING_PARTY`,
`KPEX_PASSKEY_CREDENTIAL_ID`, `KPEX_PASSKEY_PRIVATE_KEY_PEM`, `KPEX_PASSKEY_USERNAME`,
`KPEX_PASSKEY_USER_HANDLE`), not a file attachment — and exposes ready-made accessors:
`entry.isPasskey`, `.passkeyRelyingParty`, `.passkeyUsername`, `.passkeyCredentialID`
(base64url-decoded `Data`), `.passkeyUserHandle`, `.passkeyPrivateKeyPEM` (as
`SecureBytes`), plus matching `setPasskey*` mutating setters. This is a dependency this
project already ships with — not a new library to add, and not something to guess at
from web search when the answer is sitting in the already-resolved source.

## What was added

`VaultService` gets read-only passkey support, built entirely on KDBXKit's own
accessors — no new WebAuthn/CBOR logic, no signing, matching the design spike's
"deliberately does not attempt the actual implementation" scoping:

- `VaultLoginEntry` gains an `isPasskey: Bool` field (default `false`, so existing call
  sites stay source-compatible), populated from `entry.isPasskey` in `listEntries`.
  Autofill/UI code can now tell which entries carry a passkey without a separate call.
- `VaultService.VaultPasskeyMetadata`: a new, deliberately secret-free struct
  (`relyingParty`, `username`, `credentialID` — **no private key**) plus
  `passkeyMetadata(in:entryUUID:)` / `passkeyMetadata(at:masterPassword:entryUUID:)` /
  `passkeyMetadata(at:rawKeyData:entryUUID:)`, mirroring `revealField`'s existing
  `in content:`/`at url:` convenience-pair shape exactly.

**The private key (`passkeyPrivateKeyPEM`) is deliberately not exposed anywhere in this
PR.** It stays out of `VaultService`'s surface until real assertion-signing code exists
to consume it — same reveal-on-demand discipline every other secret field in this repo
already follows (`revealField`, `currentTOTPCode`): nothing gets a reveal path before
something real needs to read it.

## Tests

New `PasskeyTests.swift`, four tests, all synthetic data (a mock PEM string, the repo's
standard fake password `"hunter2"`, a throwaway tempdir vault):

- `listEntriesFlagsPasskeyBearingEntries` — a vault with one passkey entry and one plain
  entry; confirms `isPasskey` is `true`/`false` correctly for each.
- `passkeyMetadataReadsRelyingPartyUsernameAndCredentialID` — confirms all three fields
  round-trip correctly through KDBXKit's own setters → KDBX write → `VaultService` read.
- `passkeyMetadataReturnsNilForNonPasskeyEntry` / `...ReturnsNilForUnknownUUID` — the
  nil-safety cases.

Test entries are built directly via KDBXKit's `setPasskey*` methods and written with
`KDBXWriter` (the same low-level dance `VaultService`'s own private `write()` already
uses) rather than through `VaultService`'s `EntryDraft`-shaped write API, since that API
doesn't model passkey fields yet (still out of scope — see below). This needed adding
`KDBXKit` as an explicit dependency of the `KeeBridgeCoreTests` test target
(`KeeBridgeCore/Package.swift`) — it was already resolved transitively, this just makes
it a direct, importable dependency for the test file.

## Secret hygiene

Grepped the diff for new `print`/`os_log`/`Logger` calls — none. `VaultPasskeyMetadata`
never carries the private key; `passkeyPrivateKeyPEM` (KDBXKit's own accessor, returning
`SecureBytes`) is never called anywhere in this diff.

## Still open (deliberately out of scope for this PR)

- Write-side passkey support (`setPasskey*` wired into `VaultService`'s own API, for
  creating/importing passkeys) — not attempted here, read-only first.
- The actual `ASPasskeyCredentialRequest`/`ASPasskeyRegistrationCredential`/
  `ASPasskeyAssertionCredential` implementation, CBOR `attestationObject` construction,
  and P-256/ES256 assertion signing (needs `passkeyPrivateKeyPEM`) — substantial,
  headless-hard-to-verify, its own future item(s).
- Declaring `ProvidesPasskeys: true` in `KeeBridgeProvider/Info.plist` — still not done;
  doing it before the actual request-handling exists would advertise a capability the
  extension can't yet fulfill, which is worse than not declaring it at all.
- Reconstructing the 9 Proton-Pass-carried passkeys (still a separate proprietary
  MessagePack format, still informational-only per the design spike's fallback).

## PR

#20
