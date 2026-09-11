# The 2026-09-10 backfill doc that found this gap had the same gap itself

## The bug

`docs/done/2026-09-10-roadmap-done-docs-backfill.md` documents a fix from a
prior run: 8 `docs/done/*.md` files existed for real, already-shipped fixes
with no corresponding `ROADMAP.md` citation at all. That doc describes
diffing every filename under `docs/done/` against every path `ROADMAP.md`
actually references, backfilling the 8 real gaps found, and excluding one
false positive.

This cycle re-ran that exact same diff — every `docs/done/*.md` filename
against every `docs/done/...md` string `ROADMAP.md` contains — as a fresh
angle not yet tried this run. It turned up exactly one gap:
`docs/done/2026-09-10-roadmap-done-docs-backfill.md` itself. The PR that
added the consolidated backfill entry to `ROADMAP.md` cited all 8 backfilled
files by name, but never cited its own write-up describing that very PR —
the doc that fixed "a `docs/done/*.md` file with no `ROADMAP.md` line" was
itself, from the moment it was written, a `docs/done/*.md` file with no
`ROADMAP.md` line.

This isn't a functional bug (same as the original finding: STEP 3 only
cares about unchecked `[ ]` items, and this was never one), but it's a
real, confirmed instance of the exact convention gap
`routines/executor.prompt.md` STEP 6 describes (every delivered cycle pairs
a `ROADMAP.md` update with its `docs/done/` record) — recurring on the one
document that exists specifically to describe fixing that gap.

## The fix

Added a parenthetical note citing this file at the end of the same
`ROADMAP.md` bullet the 2026-09-10 backfill already added — not a new,
near-duplicate entry — following that bullet's own established pattern of
noting exceptions inline (it already has one, for the false-positive
`docs/done/2026-09-05-roadmap-issue-sync.md` candidate).

Re-ran the full `docs/done/*.md` ↔ `ROADMAP.md` citation diff after the
fix: zero remaining gaps in either direction.

## Verification

Doc-only change.

- `bash scripts/routines-check.sh` — ✅
- `bash scripts/routines-author-check.sh` — ✅
- `bats tests/drift-detectors.bats` — ✅ (15/15)

No Swift/JS touched — `make test`/`make build`/`make probe-build` unaffected
by this change, left to CI's own run for completeness.
