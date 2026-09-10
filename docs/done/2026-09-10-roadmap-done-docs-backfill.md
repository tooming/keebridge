# Backfill: 8 shipped fixes had a docs/done record but no ROADMAP.md line

Fourth re-survey angle this run, after `scripts/lib/colors.sh`'s fabricated cross-repo
comment history (#107), a second pass that found nothing further (#108), and the
Sendable-concurrency compiler warnings found via raw CI log content (#109). This time
the new angle was checking the *reverse* direction of an earlier cycle's
"roadmap-reference-audit": that cycle verified every path `ROADMAP.md` cites actually
exists on disk (forward direction). Nobody had checked the other way — that every
`docs/done/*.md` file has a corresponding `ROADMAP.md` line.

## What was found

Diffing every filename under `docs/done/` against `ROADMAP.md`'s content turned up 9
candidates with no reference. Checking each individually (not trusting the naive grep
alone):

- **8 real gaps**, all dated 2026-09-08: `refresh-throttle-isworking-fix`,
  `totp-tiny-period-overflow-fix`, `keebridgeconfig-test-coverage`,
  `readme-accuracy-refresh`, `routines-bats-comment-fix`, `routines-bats-suite`,
  `routines-mark-applied-bats-coverage`, `kdbxkit-tag-comment-refresh`. Each is a real,
  already-merged, already-shipped fix (confirmed against `git log` — e.g.
  `refreshIfStale()`'s fix and the TOTP tiny-period fix both correspond to real merged
  commits) with a complete `docs/done/` writeup, just never given a `ROADMAP.md` line
  at all.
- **1 false positive**: `docs/done/2026-09-05-roadmap-issue-sync.md`. Its content (two
  ROADMAP-vs-GitHub-issue staleness fixes, for issues #33 and #5) turned out to already
  be fully present in `ROADMAP.md` — just described inline in the existing `#33`/`#5`
  bullets, rather than cited by the doc's filename. Excluded from the backfill; nothing
  to fix there.

This isn't a code bug and doesn't cause re-work (STEP 3 only cares about unchecked
`[ ]` items, and none of these 8 were ever unchecked — they were simply invisible from
`ROADMAP.md` alone). But `ROADMAP.md`'s own header states it's "the prioritized
backlog" the executor "reads fresh every run," and `routines/executor.prompt.md`'s
STEP 6 explicitly pairs a `ROADMAP.md` update with every `docs/done/` record in the
same PR — for one calendar day's cycles, only the second half of that pairing landed.

## The fix

Added one consolidated `[x]` entry to `ROADMAP.md`'s "Now / next" section
backfilling all 8, each with a short, individually-verified (not restated from
memory) summary and its `docs/done/` citation, plus a note on the one false positive
so a future cycle doesn't re-discover and re-investigate it.

## Verification

Doc-only change. `make routines-check`/`make routines-author-check`/
`make routines-bats-test` run locally, all green (real repo state, not just the
fixtures). No Swift/JS touched — `make test`/`make build`/`make probe-build`
unaffected, left to this PR's own CI run for completeness.

## PR

See the PR that accompanies this file.
