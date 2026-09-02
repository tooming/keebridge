# Fix: `updateEntry` silently deleted TOTP/passkey fields on every edit

Discovered via a fresh, full read of `KeeBridgeCore/Sources/KeeBridgeCore/VaultService.swift`'s
write section (`createVault`/`createEntry`/`updateEntry`/`setPasskey`/`deleteEntry`) — this
run's fifth consecutive re-survey, and no run before it had read this ~700-line file
end-to-end. This is a genuine data-loss bug, not a hypothetical edge case.

## The bug

`VaultService.updateEntry`'s private implementation did:

```swift
entry.strings = self.draftStrings(draft)
```

`draftStrings(draft)` returns exactly five `KDBX.ProtectedString`s: `Title`, `UserName`,
`Password`, `URL`, `Notes`. Assigning straight to `entry.strings` **replaces the entry's
entire field list**, not just those five. Any other field already on the entry — most
importantly the `otp` field (the TOTP secret KeePassXC/Proton Pass store there,
`VaultService.currentTOTPCode` reads it) and the five `KPEX_PASSKEY_*` passkey fields
(`VaultService.setPasskey`/`passkeyMetadata`) — was silently wiped out the instant that
entry was edited.

This is reachable from real, everyday use, not just a theoretical code path:

- **The app's own Edit form** (`EntryEditView` → `VaultController.updateEntry` →
  `VaultService.updateEntry`): editing an entry's title, username, password, URL, or notes
  — literally anything the Edit sheet lets you change — and clicking Save would delete
  that entry's TOTP secret and/or passkey if it had one.
- **`VaultProbe`'s `update` subcommand**: its own doc comment claims "an omitted flag
  keeps its existing value," and its reveal-then-merge logic genuinely does that — but
  only for the five standard fields it knows about. It reveals via `revealEntry`, which
  itself only ever returns those five fields (by design, matching `EntryDraft`'s shape) —
  so the merge had no way to know about, let alone preserve, an `otp` or passkey field.
  Passed straight through to the same `updateEntry` that then deleted it.

Present since write support (#1) originally shipped — pre-executor — and never caught:
zero tests in `VaultWritingTests.swift` exercised `updateEntry` against an entry carrying
any custom field, and the CLI/app-level reveal-then-merge "safety net" both independently
assumed the standard five fields are the only ones that matter, so neither would have
caught this even with more testing at that layer alone.

## What changed

`VaultService.updateEntry`'s private implementation now preserves every field it doesn't
explicitly know about:

```swift
let preservedCustomFields = entry.strings.filter { !Self.standardKeys.contains($0.key) }
entry.strings = self.draftStrings(draft) + preservedCustomFields
```

`updateEntry`'s public doc comment updated to state the corrected contract explicitly:
full-replace semantics for the five standard fields (unchanged — an omitted `EntryDraft`
field still blanks that standard field, same as before), but every other field is now
preserved untouched. This is a `VaultService`-layer fix, so both the app's Edit form and
`VaultProbe`'s `update` subcommand are fixed automatically — neither needed its own
change, since both already funnel through this one method.

New regression test, `updateEntryPreservesPasskeyAndOtherCustomFields` (`VaultWritingTests.swift`):
creates an entry, attaches a passkey via the existing `setPasskey` write path, calls
`updateEntry` to change the title/username, then asserts (via `listEntries`'s `isPasskey`
flag and `passkeyMetadata`) that the passkey survived. Chosen over poking at KDBXKit
directly (the way `PasskeyTests.swift`'s helper does) because it exercises the exact
real-world regression scenario end-to-end through `VaultService`'s own public API.

## Why this scope, not more

Did not also add a generic "arbitrary custom field" write API to `VaultService` —
out of scope for a bug fix, and the existing `setPasskey`-style narrow, field-specific
write methods are this codebase's established pattern for anything beyond the five
standard fields; a generic one would be a separate, deliberate design decision, not
something to slip into a fix PR.

## Verification

`swift test` — `updateEntryPreservesPasskeyAndOtherCustomFields` fails against the
pre-fix code (confirmed by reasoning through the old implementation: `entry.strings =
draftStrings(draft)` unconditionally drops the passkey fields the test's `setPasskey` call
just added) and passes against the fix. Every pre-existing `updateEntry` test
(`updateEntryOverwritesFields`, `updateEntryWithMasterPasswordOverwritesFields`,
`updateEntryThrowsForUnknownUUID`) still passes unchanged — the five-standard-fields
full-replace behavior they assert is untouched by this fix, only fields outside that set
are now preserved.

## PR

See the PR this file was committed alongside.
