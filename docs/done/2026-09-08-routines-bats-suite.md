# Add a bats test suite for the routines/ drift-detector scripts

Sixteenth cycle this run — picked up the topmost unchecked `ROADMAP.md` item, groomed by
the previous cycle (`#92`): a real `bats` test suite for `scripts/routines-check.sh` and
`scripts/routines-author-check.sh`, whose header comment used to (falsely) claim one
already existed.

## Why this could actually be implemented this cycle, not just groomed further

Last cycle's grooming assumed the blocker was "no `bats` available to validate against."
That assumption turned out to be only half true: this executor's own environment is
Linux, and `bats` is a plain `apt-get install`able package there — a first for any
`routines/`-tooling change this run, every other cycle touching Swift or the CI-only
pieces had no way to self-validate before pushing. Installed it, wrote the suite, ran it
for real, iterated locally, and only then pushed — a stronger validation loop than this
run's other cycles got to use.

## What the suite covers

`tests/drift-detectors.bats`, 12 cases total, each building its own throwaway `mktemp -d`
fixture (no real git history needed, using the env-var seams both scripts' headers
already documented: `ROUTINESCHECK_ROOT`; `ROUTINES_AUTHOR_ROOT`/`_BRANCH`/`_FILES`/
`_IS_CLOUD`):

**`routines-check.sh`** (6 cases): no `routines/` directory is a no-op; a clean state
(hash matches the snapshot) passes; a missing `.routines-applied` fails; `routines.yaml`
not yet recorded in the snapshot fails; `routines.yaml` edited since the last apply
(hash mismatch) fails; a snapshot entry pointing at a file no longer on disk fails.

**`routines-author-check.sh`** (6 cases): `routines.yaml` untouched stays clean
regardless of branch; an executor-branch (`auto/*`) change touching it is blocked; a
change flagged with the cloud-identity signal is blocked even off an `auto/*` branch; an
interactive session (neither signal) touching it stays clean; a *custom*
`branch_prefix` read from the fixture's own `routines.yaml` is honored instead of a
hardcoded `auto/` (tests both that the real default no longer matches and that the
custom prefix does); the `routines/`-prefixed path shape a real `git diff --name-only`
actually emits is detected (not just a bare `routines.yaml`).

## Verifying the suite isn't vacuous

Before wiring it into CI, deliberately broke `routines-check.sh` (replaced its final
`exit $drift` with a hardcoded `exit 0`) and re-ran the suite: exactly the three tests
whose failure path routes through that line went red (`not ok`), the other three (whose
failure paths `exit 1` earlier, before that line) correctly stayed green — confirming
the suite actually exercises real script behavior, not just its own fixtures agreeing
with themselves. Restored the script and confirmed all 12 pass again before proceeding.

## What changed

- New `tests/drift-detectors.bats`.
- `Makefile`: new `routines-bats-test` target, added to `make ci`.
- `.github/workflows/ci.yml`: a `brew install bats-core` step (guarded with
  `command -v bats ||` in case a future runner image ships it preinstalled) plus
  `make routines-bats-test` added to the job.

## PR

See the PR that accompanies this file.
