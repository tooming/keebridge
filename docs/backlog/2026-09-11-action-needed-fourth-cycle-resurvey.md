# [Action needed] Fourth cycle this run — two real fixes landed, this pass found nothing further

Fourth cycle this run. The first three cycles landed real, verified work:

1. A re-survey (this run's first cycle) confirming the backlog was still genuinely
   empty, using angles none of the prior ~20 cross-run audit cycles had tried yet
   (`ContentView.swift`/`KeeBridgeApp.swift`/`LockedView.swift`, `KeychainStore.swift`,
   `KeeBridgeConfig.swift`, `VaultReadableContent.swift`, a full three-target
   `project.yml` diff) — see
   `docs/backlog/2026-09-11-action-needed-backlog-empty.md`.
2. **A real, reachable UI bug** (#113): `EntryEditView`'s QR scanner left its sheet
   open, with a dead camera feed, after scanning any QR code that wasn't a valid
   `otpauth://` URI — found via a fresh, adversarial read of `EntryEditView.swift`.
3. **A real correctness bug** (#114): `TOTPGenerator.parse`'s `algorithm` parameter
   silently fell back to SHA1 for any unrecognized value instead of rejecting it —
   the same silent-fallback-on-a-present-but-invalid-value shape already fixed twice
   in that file for `digits`/`period`.

## What this fourth cycle checked, that turned up nothing further

- **A systematic repo-wide grep for the exact bug class #114 just fixed** —
  `rawValue: ...) ?? .` (an enum conversion silently falling back to a default on an
  out-of-range-but-present value) across every production `.swift` file. Only the
  instance already fixed in `TOTPGenerator.swift` (now just a comment referencing the
  old code) matched — no second occurrence anywhere else in the codebase.
- A broader grep for every `?? ` nil-coalescing default in production Swift code,
  read individually: all are either legitimate display fallbacks (`"(none)"`, `"nil"`
  for logging), default-construction (`entry.times ?? KDBX.Times()` when creating a
  timestamp that doesn't exist yet), or deliberate reveal-then-merge patterns
  (`VaultProbe`'s `update`, `VaultController`'s `metadata.username ?? entry.username`)
  — none hide an unvalidated-but-present value the way the `algorithm` one did.
- **Full, fresh reads of `VaultBrowserView.swift` (84 lines) and
  `EntryDetailView.swift` (219 lines)** — the two remaining `KeeBridge/*.swift`
  app-layer files this run's earlier `EntryEditView.swift` read hadn't covered.
  Both are careful, already-well-iterated code (`EntryDetailView` in particular has 5
  prior ROADMAP entries against it) — no new gap found in either.
- **A full, fresh read of `PaymentCard.swift`** (226 lines), the field-alias/
  expiration-parsing logic that produced two real bugs earlier in this ROADMAP
  (origin/iframe binding, expiration-placeholder-format). Re-derived
  `paymentCardExpirationParts`'s month/year disambiguation logic by hand against
  every realistic separator/order combination (`MM/YY`, `MM/YYYY`, `YYYY-MM`,
  `MM-YYYY`, compact 4/6-digit) — all resolve correctly; the one theoretical ambiguity
  (a 2-digit year appearing BEFORE a 2-digit month, e.g. `"YY-MM"`) isn't a real-world
  card-expiration format, so it isn't a practical gap.
- **A full, fresh read of `VaultService.swift`** (864 lines, this run's first full
  read of the whole file rather than a prior cycle's read) — every write path
  (`createEntry`/`updateEntry`/`setPasskey`/`deleteEntry`/
  `mergeExtensionOriginatedPasskeys`) and read path traced end to end. Confirmed by
  reading, not assuming: `updateEntry`'s custom-field-preservation filter
  (`$0.key != "otp" || draft.otpURI == nil`) correctly composes with `draftStrings`'s
  own `otpURI`-append logic for all three states (nil=preserve, ""=remove, non-
  empty=set); `trimHistory` only trims when `Meta.historyMaxItems` is an explicit
  `.value`; `openReadOnlyContent`'s KDBX-3.x eager-parse fallback only triggers on
  exactly `.unsupportedFormatVersion(major: 3, ...)`, propagating every other error
  untouched. No new gap found.

## Current state

`ROADMAP.md`'s "Now / next" lane is fully checked off again after this run's two real
fixes; the one item under "Needs maintainer/human action" (`#77`) still correctly
needs a human. This cycle's angles (systematic same-bug-class grep, the two remaining
unread `KeeBridge/*.swift` files, fresh full reads of `PaymentCard.swift` and
`VaultService.swift`) found nothing further to act on. Filing this rather than
fabricating make-work, per `routines/executor.prompt.md` STEP 6b.
