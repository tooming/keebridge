# Issue #77 was silently auto-closed against its own closing PR's stated intent

## What happened

`#77` ("Executor's actual tool grant this run included RemoteTrigger-
equivalent tools, contradicting `routines/README.md`'s 'hard tool-access
limit'") is a genuine, still-unanswered question filed by a much earlier
cycle of this run: does `routines.yaml`'s `allowed_tools` field actually
gate the runtime MCP tool surface a scheduled executor session receives?
It needs an answer from whoever configures this repo's Claude Code
Remote environment — not something this repo's own code or docs can
settle on their own.

PR #106 (merged 2026-09-09) addressed the *documentation* half — softening
`routines/README.md` and `scripts/routines-author-check.sh`'s comments to
stop asserting `allowed_tools` is a *verified* hard limit, since #77 showed
it isn't. PR #106's own body is explicit that this is only a partial fix:

> **What this PR does *not* do**: Resolve #77. That still needs an answer
> from whoever configures this repo's Claude Code Remote
> environment/routine... leaving #77 open for a maintainer to chase down.

Despite that, GitHub auto-closed `#77` the moment #106 merged — both
events share the exact same timestamp (`2026-09-09T10:07:2[5-6]Z`). The
PR title contains `(#77)`, which is enough for GitHub's issue-closing
keyword linking to fire on merge, regardless of what the PR body actually
says. The underlying question was never answered; it just silently fell
out of the visible open-issues list.

Found this cycle by re-checking every issue number `ROADMAP.md`'s "Needs
maintainer/human action" section cites against its live GitHub state — the
same cross-check pattern a prior cycle already used to catch `#5` (closed,
correctly marked done in that section). Re-running it against `#77` and
`#119` this time turned up this accidental-close instead.

## The fix

- Reopened `#77` with a comment explaining why, quoting #106's own
  disclaimer, so the still-open question is visible again to whoever can
  actually answer it.
- Added a parenthetical note to `ROADMAP.md`'s existing `#77` bullet
  documenting the auto-close and reopen — not a new entry, matching this
  section's own established pattern (the `#5`/Proton Pass bullet right
  below it, and the 2026-09-10 backfill bullet's own exception notes).

`#119` was also re-checked this cycle: it's a PR number (not an issue),
already correctly closed/merged, and the bullet that cites it doesn't
claim otherwise — no action needed there.

## Verification

Doc-only change (`ROADMAP.md`) plus a GitHub API state change (reopening
an issue) — no code touched.

- `bash scripts/routines-check.sh` — ✅
- `bash scripts/routines-author-check.sh` — ✅
- `bats tests/drift-detectors.bats` — ✅ (15/15)
