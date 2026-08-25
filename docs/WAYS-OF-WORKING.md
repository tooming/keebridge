# Ways of Working — Agent Governance

> **Scope.** How the autonomous executor operates in this repo, how its changes are
> reviewed and merged, and the kill-switch. Same governance pattern as
> [`tooming/k8s-anywhere`](https://github.com/tooming/k8s-anywhere/blob/main/docs/WAYS-OF-WORKING.md)
> and [`tooming/easysportstream`](https://github.com/tooming/easysportstream), sized down
> for a small, solo-maintained repo with one trigger and no fallback-role chain.

## 0. Principles

1. **The executor has full authority to merge its own PRs — no human merge gate** —
   *unlike `tooming/easysportstream`, which never self-merges because its `main` deploys
   to production instantly on merge. KeeBridge has no such deploy-on-merge: `main` only
   becomes a real build when someone runs Xcode/`xcodebuild` by hand, so the maintainer
   chose the same full-autonomy model as `tooming/k8s-anywhere`* (2026-08-25, explicit
   choice among a "PR-only, no self-merge" vs. "full self-merge" option). Once required CI
   is green and its `[self-review]` comment is posted (`routines/executor.prompt.md` STEP
   7), the executor merges — `gh pr merge --squash --delete-branch`. Branch protection on
   `main` is off, so nothing blocks this at the platform level; the CI-green /
   self-review bar is enforced by agent discipline, same as the sibling repos.
2. **The repo is the only rulebook the executor obeys.** It sees only what's in git, so
   `README.md`, `ROADMAP.md` (once bootstrapped — see `routines/executor.prompt.md` STEP
   1a), and this doc are the complete set of rules. A governance change takes effect only
   once merged.
3. **Security hard rules live in `routines/executor.prompt.md`, not here** (STEP 4's
   SECRET HYGIENE / CRYPTO-ENTITLEMENTS rules, STEP 7's self-review checklist) — this repo
   handles master passwords, KDF keys, and Keychain material, so those rules are the
   binding contract, not just a suggestion. Don't restate them here; edit that file if
   they need to change (no apply step — see `routines/README.md`).
4. **One item per PR**, focused and bounded (target < ~400 changed lines). Branch prefix
   `auto/*` signals origin.
5. **Who reviews an agent PR:** any human, at their discretion — self-merge means review
   is no longer a precondition, but PRs stay open to comment/revert like any other change.

## 1. Executor registry

| Role | Trigger | Owner | Purpose | Cadence | Branch prefix |
|---|---|---|---|---|---|
| Executor | see `routines/routines.yaml` | @tooming | bootstraps and then implements `ROADMAP.md` items one PR at a time, self-reviews, self-merges | 10:00 UTC daily (1/day) · Sonnet 5 | `auto/*` |

> The canonical, version-controlled definition (cron, model, prompt, tools) lives in
> [`routines/`](../routines/) and is applied via Claude Code — see
> [routines/README.md](../routines/README.md). This table is the human-readable summary.

## 2. Cost & kill-switch

- **Free quota: 5 routine runs per rolling 24h, shared across the whole account, not
  per-repo.** This trigger's single daily slot was funded by dropping
  `tooming/k8s-anywhere`'s own trigger from 4→3 runs/day (2026-08-25) — see that repo's
  `routines/routines.yaml` and `docs/WAYS-OF-WORKING.md` §5 for the other half of the
  split. Account-wide total stays at 5 fixed daily fire-times across all three repos
  combined. No headroom — raising this repo's cadence or adding a second trigger requires
  either freeing another repo's slot the same way, or enabling the paid "additional runs"
  toggle.
- **Emergency stop:** disable the routine from the [routines page](https://claude.ai/code/routines)
  (toggle off), or set `enabled: false` in `routines/routines.yaml`, apply it (see
  `routines/README.md`), and `make routines-mark-applied`.
- **Spend per run is not capped to one item** — the executor loops (STEP 8) until its own
  resource limits cut it off, same model as the sibling repos. If output ever outpaces
  what's reasonable to spot-check, the fix is the kill-switch above, not silently
  tolerating it.

## 3. Agent PR contract (definition of done)

- CI green (`make ci` — `swift test` + an unsigned `xcodebuild` build) is necessary, not
  sufficient — the self-review checklist in `routines/executor.prompt.md` STEP 7 is the
  real gate for this repo's specific risks (secret hygiene, crypto/entitlements).
- `ROADMAP.md` updated (`[x]` the item) and a `docs/done/YYYY-MM-DD-<slug>.md` record
  created in the same PR, same convention as the sibling repos.
- `[self-review]` comment posted and `self-reviewed` label applied before merge.
