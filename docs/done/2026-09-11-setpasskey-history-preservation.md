# setPasskey and the extension-merge path never populated entry.history

## The bug

`VaultService.updateEntry` was fixed on 2026-09-05
(`docs/done/2026-09-05-update-entry-history-preservation.md`) to snapshot
an entry's pre-edit state into `entry.history` before applying changes —
KDBXKit's own doc comment on `KDBX.Entry.history` states the contract
plainly: "every entry set or equivalent edit prepends a snapshot of the
prior state here," matching KeePassXC's own "View History" behavior. That
fix was scoped to `updateEntry` (plus a doc-comment correction on
`deleteEntry`'s recovery-path claim) — it never touched this file's other
two entry-mutating write paths, `setPasskey` and the private merge
function inside `mergeExtensionOriginatedPasskeys`, which had the exact
same gap all along.

`setPasskey`'s own doc comment says "Sets (**or overwrites**) an existing
entry's passkey fields in place" — overwriting an entry that already has
a passkey is an anticipated, realistic case (re-registering after a
private key is lost or revoked), not a hypothetical. Both `setPasskey`
and the merge function mutated an entry's five `KPEX_PASSKEY_*` fields
directly, with no history snapshot at all: overwriting an existing
passkey destroyed the OLD credential ID and private key PEM permanently,
with no recovery path whatsoever — not even via KeePassXC's own "View
History" the way an `updateEntry` edit's prior state already is since the
2026-09-05 fix.

The merge function's `!sourceAlreadyMatches` guard only skips a merge
when the source entry already carries the EXACT mirror credential; a
source entry whose existing passkey merely *differs* from the mirror's
(a real, if narrow, scenario — e.g. the source independently got a
passkey, then the mirror later gets a different one from the extension)
still gets silently overwritten by the merge, with the same total loss of
the prior credential.

Found this cycle by reading `VaultService.swift` in full (not yet read
this run) as a fresh angle, immediately after a full read of
`VaultController.swift` turned up the unrelated `lock()`-race bug fixed
in `#150` — checking every other entry-mutating write path in this file
against the exact convention the 2026-09-05 fix already established and
tested for `updateEntry`, rather than assuming that fix's scope was
complete.

## The fix

Added the identical history-snapshot pattern `updateEntry` already uses —
snapshot the pre-mutation entry state (history cleared on the snapshot,
matching KDBXKit's own validator expectation), append it to
`entry.history`, then trim against `Meta.historyMaxItems` — to both
`setPasskey`'s private implementation and the merge function's per-entry
mutation closure (using the *source* vault's own `historyMaxItems`, since
that's where the write lands).

Two new `@Test` cases in `PasskeyTests.swift`, run via `swift test`/CI
(this package has a real test target, unlike this run's app/extension-
layer UI fixes):

- `setPasskeyPreservesHistoryOfPriorState` — two `setPasskey` calls on the
  same entry; asserts `entry.history` has both the pre-passkey state and
  the first (now overwritten) credential/PEM, no nested history, no
  KDBXKit validator warnings.
- `mergeExtensionOriginatedPasskeysPreservesHistoryWhenOverwritingADifferentPasskey` —
  source gets one passkey directly, the mirror (copied afterward) gets a
  *different* one, merge runs; asserts the source's history preserves the
  original credential's state after the merge overwrites it.

## Verification

- `bash scripts/routines-check.sh` — ✅
- `bash scripts/routines-author-check.sh` — ✅
- `bats tests/drift-detectors.bats` — ✅ (15/15)

No entitlements or crypto primitives touched — `PasskeyCrypto` itself is
unchanged; this only affects which entry-mutation write paths in
`VaultService.swift` also record `entry.history`. `swift test`/CI will
run the two new cases; this executor has no local Swift toolchain to run
them itself.
