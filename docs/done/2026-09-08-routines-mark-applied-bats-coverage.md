# Extend the bats suite to cover routines-mark-applied.sh, the producer half of the drift-check contract

Seventeenth cycle this run — extended the `tests/drift-detectors.bats` suite from
last cycle (`#93`) to cover the one remaining `routines/` tooling script with a matching
test seam: `scripts/routines-mark-applied.sh` (`ROUTINESMARKAPPLIED_ROOT`, mirroring
`routines-check.sh`'s `ROUTINESCHECK_ROOT` and `routines-author-check.sh`'s
`ROUTINES_AUTHOR_ROOT`). Last cycle's suite covered the two *detector* scripts;
`routines-mark-applied.sh` is the *producer* they both depend on — it writes the
`.routines-applied` snapshot `routines-check.sh` reads back. A bug there (a wrong hash,
a malformed line) would silently corrupt the very state the drift check trusts.

## What changed

Three new cases, all exercising `routines-mark-applied.sh` and `routines-check.sh`
*together* (writing a real snapshot with one, reading it back with the other) rather
than asserting on `routines-mark-applied.sh`'s own output in isolation — that's the
actual contract that matters, not either script's behavior alone:

- Writing a fresh snapshot leaves `routines-check.sh` reporting clean.
- Editing `routines.yaml`, re-running `routines-mark-applied.sh`, and reading it back
  correctly clears the "edited since last apply" state it flagged before the re-run.
- No `routines/routines.yaml` on disk writes a header-only snapshot (no data line for a
  file that doesn't exist), and `routines-check.sh` still correctly no-ops on that state.

## Verifying the new cases aren't vacuous

Same mutation-testing discipline as last cycle's suite: deliberately hardcoded a wrong
sha256 in `routines-mark-applied.sh`'s output, re-ran the suite, and confirmed exactly
the two cases that depend on the hash being correct went red — the third (no
`routines.yaml` present, so no hash is written at all) correctly stayed green. Restored
the script and confirmed all 15 cases (12 from last cycle + these 3) pass again.

## What changed

`tests/drift-detectors.bats` only — no `Makefile`/CI wiring changes needed, since
`make routines-bats-test`/`.github/workflows/ci.yml` already run the whole file.

## PR

See the PR that accompanies this file.
