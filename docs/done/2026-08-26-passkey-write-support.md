# Passkey write-side metadata support

Next slice of #4 (passkey support), after
`docs/done/2026-08-26-passkey-metadata-reading.md`'s read-only work. Still no
WebAuthn/CBOR logic — this only lets something set the fields real signing code will
eventually generate.

## What was added

`VaultService.setPasskey(uuid:relyingParty:credentialID:privateKeyPEM:username:userHandle:at:masterPassword:/rawKeyData:)`
— sets (or overwrites) an existing entry's passkey fields via KDBXKit's own
`setPasskeyRelyingParty`/`setPasskeyCredentialID`/`setPasskeyPrivateKeyPEM`/
`setPasskeyUsername`/`setPasskeyUserHandle` methods (the same `KPEX_PASSKEY_*`
KeePassXC-compatible convention the read-side slice already reads). `relyingParty`,
`credentialID`, and `privateKeyPEM` are required; `username`/`userHandle` are optional.

Built on the same `mutateEntry`/`write` machinery `updateEntry`/`deleteEntry` already
use — reused directly, no new tree-walking logic. Crucially, this **only** touches the
five passkey fields: title/username/password/URL/notes/custom fields on the entry are
left exactly as they were, unlike `updateEntry`'s full-replace semantics (the same
distinction that motivated the reveal-then-merge design in `VaultProbe`'s `update`
subcommand). This means `setPasskey` can be called on an existing login-style entry to
attach a passkey to it without disturbing its other fields, or on a fresh entry to
create a passkey-only one.

Follows this repo's established `masterPassword:`/`rawKeyData:` overload pair (same
pattern as every other write method: `createEntry`, `updateEntry`, `deleteEntry`).

## Tests

Two new tests in `PasskeyTests.swift`:

- `setPasskeyAddsPasskeyFieldsWithoutTouchingOtherFields` — creates a plain login entry
  (title/username/password), calls `setPasskey`, then confirms: `isPasskey` is now
  `true`, `passkeyMetadata` returns the right relying party/username/credential ID, and
  — the important assertion — the original title/username/password all survive
  untouched.
- `setPasskeyThrowsForUnknownUUID` — matches the existing `.entryNotFound` throw
  behavior `updateEntry`/`deleteEntry` already have tests for.

Same synthetic data discipline as every other test in this package (mock PEM string,
`"hunter2"`, throwaway tempdir vault).

## Secret hygiene

Grepped the diff for new `print`/`os_log`/`Logger` calls — none. `privateKeyPEM` is
accepted as a plain `String` parameter, same as `EntryDraft.password` already is
throughout this file — consistent with existing handling, not a new pattern.

## Still open (deliberately out of scope for this PR)

- The actual WebAuthn/CBOR registration + assertion-signing implementation in
  `CredentialProviderViewController.swift` that would generate the key material this
  method stores — the real remaining piece of #4.
- Declaring `ProvidesPasskeys: true` in `KeeBridgeProvider/Info.plist` — still withheld
  until that request-handling exists.
- Reconstructing the 9 Proton-Pass-carried passkeys — still informational-only.

## PR

#21
