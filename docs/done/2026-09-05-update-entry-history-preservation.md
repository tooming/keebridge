# `updateEntry` never populated `entry.history`, silently breaking KeePass version history

`KDBXKit`'s own doc comment on `KDBX.Entry.history` states the contract host applications
are expected to follow:

> Past versions of this entry, oldest first. Every `entry set` or equivalent edit prepends
> a snapshot of the prior state here. The list is trimmed on save according to
> `Meta.historyMaxItems`.

`VaultService.updateEntry` never did this — it mutated `entry.strings`/`entry.times` in
place and never touched `entry.history` at all. This is a real, confirmed gap, not
speculation: KeePassXC itself (and every other well-behaved KeePass-family client) appends a
pre-edit snapshot to `entry.history` on every save, which is what powers its "View History"
feature — the ability to see and restore a previous version of an entry after editing it.
Every edit made through KeeBridge (the app's own Edit form, or `VaultProbe`'s `update`
subcommand) silently skipped this, meaning a fat-fingered edit or an accidentally-wrong
regenerated password had **no recovery path at all** except the whole-file `.bak` sibling
one save-generation back — unlike an equivalent edit made in KeePassXC, which stays
recoverable via its own version history indefinitely (subject to `historyMaxItems`
trimming).

Confirmed via the pinned KDBXKit dependency's own source (cloned read-only at
`/home/user/shadone/kdbxkit`) — this is the dependency explicitly documenting what it
expects callers to do, not an inferred or guessed convention.

## Fix

`updateEntry` now snapshots the entry's pre-edit state (with the snapshot's own `history`
cleared to `[]`, since a historical entry never carries its own nested history — KDBXKit's
own validator flags exactly this: "History has element has own History") and appends it to
`entry.history` before applying the new field values. A new `trimHistory` helper drops the
oldest snapshots once the count exceeds `Meta.historyMaxItems` (when the vault's `Meta` sets
one — left unbounded otherwise, same floor KeePassXC's own next save would apply anyway).
Deliberately doesn't also implement `Meta.historyMaxSize` (byte-size trimming) — a separate,
more involved accounting problem, noted as a follow-up rather than folded in here.

Also corrected `EntryDetailView`'s delete-confirmation copy, which claimed "KeePassXC's own
backup/history is the recovery path" for a deletion — `deleteEntry` does a hard removal with
no recycle bin (its own doc comment already says so) and never populates history before
removing an entry, so there's no KeePass version-history trail to recover a KeeBridge
deletion from; the real recovery path is the vault's own `.bak` sibling
(`VaultService.write`'s `AtomicFileWriter` backup), which the corrected text now says
directly instead of misattributing it to KeePassXC.

Found via a continued adversarial review this run (seventh finding, after #60–#66), reading
the pinned KDBXKit dependency's `KDBX.Entry`/`KDBX.Meta` source directly rather than
inferring behavior from KeeBridgeCore's own code alone — the same technique that found the
KDBX-attachment-memory-footprint spike (#65) earlier this run.

## Verification

Unlike the app-layer/JS fixes this run, `KeeBridgeCore` has a real test target `swift test`
actually exercises — two new `@Test` cases in `VaultWritingTests.swift`:
`updateEntryPreservesHistoryOfPriorStates` (two successive edits produce two ordered
history snapshots with the pre-edit field values, each with empty nested history, and
`KDBX.Entry.validate()` raises no history-related warnings) and
`updateEntryTrimsHistoryToMetaHistoryMaxItems` (three edits against a vault with
`historyMaxItems: 2` trims to the two most recent snapshots, oldest dropped). This
executor's environment has no local Swift toolchain (see
`docs/backlog/2026-09-03-action-needed-backlog-blocked.md`), so these run via this repo's
own `make test`/CI rather than locally, same workaround as every other cycle.

## PR

See the PR that accompanies this file.
