# Wire `mergeExtensionOriginatedPasskeys` into `VaultController.mirrorVaultToExtension`

Wires the write-back merge primitive from
`docs/done/2026-08-31-passkey-write-back-merge-primitive.md` into the app's actual mirror
write path, closing the data-integrity gap
`docs/done/2026-08-31-passkey-registration-write-path-spike.md` found: without this, anything
the extension writes into its own vault mirror (a freshly-registered passkey, once
registration exists) would be silently lost the next time the app re-mirrors.

## What changed

- `KeeBridgeConfig.vaultMirrorLastWriteMarkerURLForApp()` — new. A sidecar file, next to the
  mirror, recording the mirror's own modification date at the moment the app itself last
  wrote it.
- `VaultController.mirrorVaultToExtension(from:rawKeyData:)` — gained a `rawKeyData:`
  parameter (threaded through all 5 call sites: `unlock`, `refresh`, `createEntry`,
  `updateEntry`, `deleteEntry` — all of which already had `preHash` in scope, no new Keychain
  reads needed). Before overwriting the mirror, it now:
  1. Checks whether the mirror's current mtime differs from what the marker sidecar recorded
     (`mirrorChangedSinceLastAppWrite`) — a mismatch means something (the extension) touched
     the mirror independently of the app's own last write.
  2. If so, calls `VaultService.mergeExtensionOriginatedPasskeys` to copy any
     extension-originated passkey fields back into the real source vault BEFORE the
     overwrite. Best-effort: a merge failure is logged (`os.Logger`, category `"app"`), never
     thrown — the app's own write must still land even if the merge-back can't complete
     (e.g. a corrupt or unreadable mirror), same as if the mirror had simply never existed.
  3. After the overwrite, records the mirror's new resulting mtime via `recordLastAppWrite`
     — deliberately reads the mirror's own post-copy mtime back rather than just stamping
     "now", since `copyItem`'s date-preservation behavior isn't something this code should
     have to assume either way to stay self-consistent.
- mtime-based detection, not content hashing — no new crypto dependency needed in the app
  target, and mtime is sufficient: any real write (extension or otherwise) updates it via
  normal OS file-write semantics.

## Still open (not this PR's scope)

- **Concurrent-edit interaction with the real source vault** — if the source vault ALSO
  changed externally (e.g. edited in KeePassXC, synced via Google Drive) in the same window
  the extension wrote to the mirror, this hasn't been exercised against a live race. The
  merge primitive re-opens the source fresh at merge time, so in principle this composes
  correctly (KDBX UUIDs rule out collisions), but that's reasoning, not a tested guarantee.
  This is a pre-existing risk class for the whole mirror/write architecture, not one this
  change introduces or worsens — flagged for a human's eventual attention rather than
  blocking this PR.
- **Passkey registration itself** — this item only makes writing from the extension SAFE; it
  doesn't add any new way for the extension to actually write a passkey yet. That's the
  separate, still-blocked registration ROADMAP item.

## Verification

Headless only, and compiled-only for the `VaultController` half specifically —
`VaultController`/the `KeeBridge` app target has no unit test target in this repo (same as
before this change), so correctness here rests on: (1) CI's real `xcodebuild` build of the
`KeeBridge` target catching any compile error, and (2) careful reasoning about the existing
call sites (verified each of the 5 already has `preHash` in scope before adding the new
parameter, rather than assuming it). The `KeeBridgeConfig` addition is a pure URL-computing
function, consistent with its two siblings, neither of which have dedicated tests either.

**Still needs a human eyeball eventually**: this has never run against a real vault/mirror on
a real machine — the mtime-comparison logic, the marker sidecar's read/write round-trip, and
the merge-then-overwrite ordering are all reasoned through carefully but not exercised
end-to-end outside of `mergeExtensionOriginatedPasskeys` itself (which IS `swift test`
covered, in the prior PR).

## PR

See the PR this file was committed alongside.
