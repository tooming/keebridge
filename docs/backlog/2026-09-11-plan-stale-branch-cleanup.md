# [Plan] ~100 merged-by-content branches are never actually deleted — needs a human, not a code fix

Eighth cycle this run. Prior cycles landed three real fixes (#113, #114, #116) and
four honest re-surveys confirming an otherwise-empty backlog. This cycle tried a
genuinely different kind of check: repo administrative hygiene, rather than another
source-code read.

## What was found

`git branch -r --no-merged origin/main` lists 104 remote branches whose content is
already on `main` (every `auto/*`/`plan/*`/`copilot/*` branch this repo has ever
merged) but which git's own ancestry check doesn't recognize as merged, because
`--squash` merges (this repo's convention, per `docs/WAYS-OF-WORKING.md` §0.1)
produce a brand-new commit on `main` that isn't a descendant of the original branch
tip.

Confirmed live, not assumed, that this isn't self-correcting:

- Checked whether GitHub's own "auto-delete head branches" repo setting is doing
  this for us: it isn't. All 6 branches THIS RUN merged (cycles 1-7, `git ls-remote
  --heads origin` re-checked just now) are still present remotely.
- Confirmed the executor's own token can't delete them either: `git push origin
  --delete auto/action-needed-backlog-empty-0911` (this run's own first merged
  branch) returned `HTTP 403` earlier this run.

So every executor cycle that merges a PR adds one more branch to a pile that nothing
currently cleans up — real, growing repo clutter, though not a correctness or
security issue (every branch's content is already safely on `main`).

## Why this is filed as "needs maintainer/human action," not implemented now

Mass-deleting ~100 git refs is exactly the class of hard-to-reverse, outward-facing
action that calls for the repository owner's explicit go-ahead, not a scheduled
executor's own judgment call — deleting a branch is recoverable (GitHub keeps a
"restore branch" affordance for a while, and the reflog exists briefly on top of
that), but it's still irreversible enough, and affects enough of the repo's history
surface at once, that doing it unprompted would be presumptuous. Filed as a new
`ROADMAP.md` "Needs maintainer/human action" item instead, with the two concrete
fixes a human has available:

1. Enable "Automatically delete head branches" in this repo's Settings → General →
   Pull Requests — fixes every FUTURE merge, but not the ~100 that already
   accumulated.
2. Explicitly authorize a future executor run (or do it by hand) to bulk-delete
   every branch already confirmed merged by content.

## Current state

`ROADMAP.md` now has two items under "Needs maintainer/human action": the existing
`#77` (`allowed_tools`/MCP-surface question) and this new one. Both are explicitly
not code — the "Now / next" lane (actual implementable backlog) remains fully
checked off after this run's three real fixes.
