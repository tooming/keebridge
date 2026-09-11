# `WAYS-OF-WORKING.md` claimed the executor deletes branches on merge

## The bug

`docs/WAYS-OF-WORKING.md` §0.1 (Principle 1 — the rule that authorizes STEP
7's self-merge in the first place) said:

> Once required CI is green and its `[self-review]` comment is posted
> (`routines/executor.prompt.md` STEP 7), the executor merges — `gh pr merge
> --squash --delete-branch`.

That names a specific mechanism — the `gh` CLI, with `--delete-branch` — that
no executor run actually has the means to use. This session's own "GitHub
Integration" instructions are explicit: a cloud executor run has **no `gh`
CLI or direct GitHub API access at all**; it merges exclusively through the
GitHub MCP server's tools (`mcp__github__merge_pull_request` here), which
take a `merge_method` but have no branch-deletion parameter or equivalent
call.

The practical consequence is exactly what `ROADMAP.md`'s `#119` (filed cycle
eight of this run) already documented from the other direction: every
squash-merged `auto/*`/`plan/*` branch stays on the remote afterward, and
`git push origin --delete <branch>` on the executor's own token returns
`403`. `#119` treated this as "the token lacks permission" — true as far as
it goes, but incomplete: even setting permission aside, the documented
*process* itself (`gh pr merge --delete-branch`) was never what actually
ran, on this cycle's merges or (per `#119`'s own count of 6/6 of this run's
early merges still present remotely) any prior one either. The doc was
describing a step that had never executed, not a step that executed and then
silently failed.

## The fix

Rewrote the sentence to describe what merging actually does — squash-merge,
through whatever GitHub access the running session has (MCP tools for a
cloud run, `gh` for an interactive one) — and pointed at `#119` for the
resulting branch accumulation, instead of asserting a cleanup step that
doesn't happen. Doc-only: there is no corresponding logic change to make in
`routines/executor.prompt.md` or anywhere else, since adding a real
branch-delete call needs a GitHub token/scope that can perform one, which is
exactly `#119`'s own still-open "Needs maintainer/human action" blocker, not
something this fix can resolve on its own.

## Verification

- `bash scripts/routines-check.sh` — ✅ (unaffected)
- `bash scripts/routines-author-check.sh` — ✅ (this fix touches
  `docs/WAYS-OF-WORKING.md`, not `routines.yaml`, so the guard doesn't apply)
- `bats tests/drift-detectors.bats` — ✅ (15/15, unaffected — no script logic
  touched)
