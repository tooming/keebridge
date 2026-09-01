# Extension→app write-back merge primitive: `VaultService.mergeExtensionOriginatedPasskeys`

The core, testable primitive for the data-integrity gap found in
`docs/done/2026-08-31-passkey-registration-write-path-spike.md`: `KeeBridgeProvider`'s vault
mirror is a throwaway, one-way copy the app freely overwrites on every write, so anything
the extension itself writes there (a freshly-registered passkey, once registration exists)
needs to be copied back into the real vault BEFORE the next overwrite, or it's lost for
good.

This PR ships only the merge function itself — pure `KeeBridgeCore`, fully covered by
`swift test`. It is not called from anywhere yet; see the follow-up ROADMAP item for wiring
it into `VaultController.mirrorVaultToExtension`, which is compiled-only (`xcodebuild`), not
`swift test`-covered, and needs its own design pass (when to check, where to persist "what
the app last wrote").

## What changed

- `VaultService.mergeExtensionOriginatedPasskeys(fromMirrorAt:intoSourceAt:rawKeyData:)` (+
  a `masterPassword:` overload) — new. Opens both the mirror and the source vault with the
  same key (they're literal copies of the same underlying vault, never independently
  created databases), walks the mirror's entries, and for each passkey-bearing entry whose
  credential ID differs from (or is absent from) the matching-UUID source entry, copies
  just the five passkey fields onto the source entry via the same field-setter calls
  `setPasskey` already uses internally. Writes the source vault back to disk only if at
  least one entry actually merged (the common case — nothing to merge — costs a read of
  both vaults and no write).
- Deliberately narrow, not a general three-way merge: an entry present in the mirror but
  absent from the source is skipped, not created (not possible today since the extension
  can't create entries — see the registration ROADMAP item — but handled defensively
  rather than assumed away). Every other field on a merged entry (title, username,
  password, URL, notes, any other custom field) is left exactly as the source vault
  already has it.
- Four new tests in `PasskeyTests.swift`: a mirror-only passkey gets copied into source
  (with every other field on the entry verified untouched), a second identical merge is a
  true no-op (`0` returned, idempotent), a mirror with no passkeys at all returns `0`, and
  a passkey on a mirror-only entry (absent from source) is ignored rather than creating a
  new source entry.

## Verification

`swift test` covers this function completely — unlike the eventual `VaultController`
wiring, this primitive has no dependency on `AppKit`/sandboxing/file-mtime semantics, so it
is not one of this repo's usual "headless can't fully verify" cases. Every test constructs
two real, on-disk KDBX vaults (a synthetic `"hunter2"` master password, mock non-real PEM
key material, same discipline as every other test in this package) and exercises the merge
against them directly.

## PR

See the PR this file was committed alongside.
