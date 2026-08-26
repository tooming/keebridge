# `masterPassword`-based `updateEntry`/`deleteEntry` overloads

Foundation piece for the CLI feasibility spike's (`docs/done/2026-08-26-cli-tool-feasibility-spike.md`)
third and final recommended step — write subcommands for `VaultProbe`.

## What was found while scoping the CLI's write subcommands

`VaultService`'s write API was asymmetric:

- `createVault`/`createEntry` — both take `masterPassword:` directly.
- `updateEntry`/`deleteEntry` — only ever took `rawKeyData:` (a cached pre-hash). No
  `masterPassword:` overload existed.

This was fine for every existing caller: the app has a cached pre-hash from Keychain by
the time its Edit/Delete UI runs. It's not fine for a CLI with no Keychain access,
prompting for the plaintext password via `getpass()` on every invocation — exactly
`VaultProbe`'s situation for the write subcommands the spike scoped.

## What changed

Two new public overloads on `VaultService`, mirroring `createEntry`'s existing
`masterPassword:`/`rawKeyData:` pair exactly (same private shared implementation,
just a different `UnlockData` constructor):

- `updateEntry(uuid:applying:at:masterPassword:)`
- `deleteEntry(uuid:at:masterPassword:)`

No behavior change to the existing `rawKeyData:` overloads or to any other method —
purely additive. Two new tests in `VaultWritingTests.swift`
(`updateEntryWithMasterPasswordOverwritesFields`,
`deleteEntryWithMasterPasswordRemovesIt`), mirroring the existing `rawKeyData:` round-trip
tests exactly but through the new overloads, both using the repo's standard synthetic
test password (`"hunter2"`) and a throwaway tempdir vault — no real vault or credential
material involved, same discipline as every other test in this file.

## Still open (deliberately out of scope for this PR)

- The actual `create`/`update`/`delete` CLI subcommands on `VaultProbe` — this PR only
  unblocks them at the `KeeBridgeCore` layer. Scoped as its own follow-up now that the
  API gap is closed.

## PR

#15
