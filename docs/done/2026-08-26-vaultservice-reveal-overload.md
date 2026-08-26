# `masterPassword`-based `revealEntry` overload

Second foundation piece for the CLI feasibility spike's (`docs/done/2026-08-26-cli-tool-feasibility-spike.md`)
third and final recommended step — write subcommands for `VaultProbe`. Follows
`docs/done/2026-08-26-vaultservice-write-overloads.md` (which added `masterPassword`
overloads for `updateEntry`/`deleteEntry`).

## Why this one too

`updateEntry` does a full field replace, not a patch — it overwrites all five fields
(`title`/`username`/`password`/`url`/`notes`) with whatever `EntryDraft` it's given.
`EntryDraft`'s own defaults are empty strings. That means a CLI `update` subcommand
that only takes the flags the caller actually passed (e.g. just `--password`) and
calls `updateEntry` directly would silently blank out every other field the caller
didn't mention — real, hard-to-notice data loss.

The safe pattern (what the app's own Edit sheet already does) is reveal-then-merge:
read the entry's current fields first, apply only the caller's explicit overrides on
top, then write the merged result. That needs a `revealEntry` overload that takes a
plaintext master password — same gap as before, `revealEntry(uuid:at:rawKeyData:)`
existed, `revealEntry(uuid:at:masterPassword:)` did not.

## What changed

One new public overload, mirroring the existing `rawKeyData:` form exactly (same
`openVault`/`revealEntry(in:uuid:)` machinery, just a different unlock path):

- `revealEntry(uuid:at:url:masterPassword:)`

No behavior change to the existing `rawKeyData:` overload or any other method. Two
new tests in `VaultWritingTests.swift`
(`revealEntryWithMasterPasswordMatchesRawKeyData`,
`revealEntryWithMasterPasswordThrowsForUnknownUUID`) — the first cross-checks both
overloads return identical `EntryDraft`s for the same entry, the second confirms the
unknown-UUID throw behavior matches the `rawKeyData:` form. Same synthetic test
password (`"hunter2"`) and throwaway tempdir vault as every other test in the file.

## Still open (deliberately out of scope for this PR)

- The actual `create`/`update`/`delete` CLI subcommands on `VaultProbe`, including the
  reveal-then-merge logic in `update` this overload exists to support. Scoped as its
  own follow-up now that both `KeeBridgeCore` gaps (this one and the write-overloads
  PR before it) are closed.

## PR

#16
