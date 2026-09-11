# `routines-author-check.sh`'s own header comment claimed the bats suite didn't exist

## The bug

`scripts/routines-author-check.sh`'s header comment (lines 50-62) said, dated
"checked 2026-09-08":

> Unlike those siblings, this repo has NO `tests/drift-detectors.bats` (or any
> bats suite) -- checked 2026-09-08, confirmed by grep across the whole repo
> and the CI workflow, neither has ever referenced one despite this comment
> (copied from a sibling repo without adjusting for this) previously claiming
> otherwise. [...] see ROADMAP.md's "Now / next" for the groomed-but-not-yet-
> implemented item to actually build that suite.

That was true when written, but went stale the same day: `tests/drift-
detectors.bats` was added later on 2026-09-08 (`#93`, extended by `#94` — see
`docs/done/2026-09-08-routines-bats-suite.md`). Since then:

- The suite exists at `tests/drift-detectors.bats` (15 test cases).
- It's wired into `Makefile`'s `routines-bats-test` target, which `make ci`
  calls.
- `.github/workflows/ci.yml` installs `bats-core` and runs
  `make routines-bats-test` in its drift-checks job.
- It exercises `routines-author-check.sh` specifically through the exact
  `ROUTINES_AUTHOR_ROOT`/`_BRANCH`/`_FILES`/`_IS_CLOUD` env-var seams this
  same comment block describes existing "specifically to make this script
  fixture-testable" — i.e. the very thing the stale comment said hadn't been
  built yet had, by the time of this fix, already been built and was already
  covering this exact script's logic.

`ROADMAP.md` itself was never wrong about this — it already marks the
bats-suite item done and links `docs/done/2026-09-08-routines-bats-suite.md`.
Only this script's own internal comment kept telling a different story:
anyone reading `routines-author-check.sh` for context (a future maintainer,
or a future executor cycle) would be told a fixture-based test suite for it
doesn't exist and needs building, when one already exists and already covers
every branch of the script's logic — including this run's own `make
routines-author-check`/`bats tests/drift-detectors.bats` calls, every cycle.

## The fix

Rewrote the comment to describe the suite's actual, current existence and
coverage, and added one sentence noting how the claim went stale (accurate
when first written, outdated by later-that-day commits) so a future reader
understands why an apparently-recent "checked" date turned out to be wrong,
rather than assuming the check itself was careless.

Comment-only change — no logic in the script touched.

## Verification

- `bash scripts/routines-check.sh` — ✅ (unaffected; this script's logic is
  unchanged)
- `bash scripts/routines-author-check.sh` — ✅ (self-check: this fix touches
  the script itself, not `routines.yaml`, so the guard this script enforces
  doesn't apply to this change)
- `bats tests/drift-detectors.bats` — ✅ (15/15, identical before and after —
  confirms the comment fix didn't alter any of the script's actual behavior)
