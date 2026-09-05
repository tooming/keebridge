# ROADMAP.md was stale against two already-closed GitHub issues

Cross-checked every closed GitHub issue `ROADMAP.md` references against its actual current
state (this run's sixth pass this cycle, after #60–#65) and found two real mismatches:

1. **#33** (automatic password-save proposal) — closed by the maintainer on 2026-09-02 as
   `completed`, the same day `docs/done/2026-09-02-save-password-proposal-feasibility-spike.md`
   landed. `ROADMAP.md`'s "Now / next" line for it had been left unchecked (`[ ]`) since
   then — the *only* unchecked line in that section, meaning every single run's STEP 3 kept
   re-deriving "the topmost unchecked item is blocked, fall through to STEP 6b" from
   scratch, when the state was already fully documented and the underlying GitHub issue
   already reflected it as done.
2. **#5** (Decommission Proton Pass, final migration step) — closed by the maintainer on
   2026-09-03 as `completed`: they did the interactive Safari Settings/`pluginkit` steps
   themselves. `ROADMAP.md`'s "Needs maintainer/human action (not code)" section still
   described this as a pending action item.

Neither is a code bug — this is the same class of "keep the docs honest" hygiene as the
2026-09-02 README accuracy refresh (`docs/done/2026-09-02-readme-accuracy-refresh.md`), just
against `ROADMAP.md`/GitHub issue state instead of `README.md`/shipped-feature state. Worth
fixing on its own: `ROADMAP.md`'s own header states "the executor reads it fresh every run
and picks the topmost unchecked `[ ]` item" — a stale unchecked line is exactly the kind of
drift that costs every future cycle a few seconds of re-deriving something already known,
compounding over the life of this project.

## Fix

Marked both `[x]` with a short note on why, preserving their substantive content (the
BLOCKED explanation for #33 remains fully accurate and useful — the underlying platform
limitation hasn't changed, only the tracking state was stale).

## Verification

Docs-only change (`ROADMAP.md`). `make routines-check`/`make routines-author-check` run
locally and green; no Swift/JS touched.

## PR

See the PR that accompanies this file.
