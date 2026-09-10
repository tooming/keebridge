# Fix: `scripts/lib/colors.sh` documented a cross-repo history that never happened here

Found during a STEP 6b re-survey. Roughly 20+ prior cycles had already given every
Swift source file, the card extension's JS/HTML/manifest, entitlements/`project.yml`/
`project.pbxproj`, `.gitignore`, error-handling patterns (`try?`/empty `catch`),
`ROADMAP.md`'s own cross-references, and dependency freshness a fresh adversarial read
with nothing new to show for it — so this cycle tried a genuinely different angle
instead of a 21st re-read of already-clean Swift/JS: the small bash tooling under
`scripts/` that backs `make routines-check`/`make routines-author-check`.

## What was wrong

`scripts/lib/colors.sh` — sourced by `routines-check.sh` and `routines-author-check.sh`
for shared ANSI color variables and `ok()`/`bad()` printers — carried an extensive
comment block narrating an "extraction" of `ok()`/`bad()`/`skip()`/`phase()` out of
"~19 scripts" (`argocd-crd-ssa-check.sh`, `helm-chart-pin-check.sh`,
`lab-health-check.sh`, `mimir-readonly-root-check.sh`,
`rollouts-plugin-list-check.sh`, `dr-bluegreen.sh`, `dr-bluegreen-promote.sh`,
`dr-test.sh`, `validate-terraform.sh`, `lint.sh`, `scripts/lib/yq.sh`,
`scripts/ok-bad-lib-check.sh`) plus a reference to "issue #957" and an
"auto/scripts-drift-var-rename" change.

**None of those files, or that issue number, exist anywhere in this repository** —
confirmed via `grep -rn` across the whole tree. This reads like leftover content
carried over from the sibling `tooming/k8s-anywhere` repo (which genuinely does have
Argo CD/Helm/Terraform-adjacent scripts and this same governance pattern — see
`docs/WAYS-OF-WORKING.md`'s explicit cross-reference to it) that never got adapted to
KeeBridge's own, much smaller reality when this file was first written. Checked
whether this was a recent regression: it isn't — `git log --follow` /
`git rev-list --max-parents=0 HEAD` confirm this content has been present since this
repo's root commit (`0d94f91`), just never previously flagged by any of the many
audit cycles that focused on Swift/JS logic rather than this bash tooling's own
comments.

Beyond the misleading comments, the file also had real dead code as a direct
consequence of the same copy-paste: `ok()`, `skip()`, `phase()`, and the `$Y`/`$B`
color variables were all defined but never called or referenced by either of this
repo's two actual callers (confirmed by grepping both `routines-check.sh` and
`routines-author-check.sh`) — only `$G`/`$R`/`$Z` and `bad()` were live.

## The fix

- Rewrote `scripts/lib/colors.sh`'s header comment to describe this repo's own two
  callers, not a fabricated ~19-script cross-repo extraction history.
- Trimmed the file to what's actually used: `$G`/`$R`/`$Z` and `ok()`/`bad()`. Dropped
  `$Y`/`$B`/`skip()`/`phase()` — dead weight with no current or documented future
  caller in this repo.
- `routines-check.sh` and `routines-author-check.sh` each had one success-path
  `printf` that already hand-duplicated `ok()`'s exact output — switched both to
  actually call `ok()` instead, so the function that's kept has a real caller rather
  than being dead code itself. Output text is byte-identical (same `✓`/color
  formatting), confirmed against `tests/drift-detectors.bats`'s existing substring
  assertions on both success messages (`"in sync with last apply"` /
  `"no executor-authored routine edits"`).

No behavior change for either script's pass/fail logic — this is a comment-accuracy +
dead-code cleanup, not a functional fix.

## Verification

- `bats tests/drift-detectors.bats` — all 15 existing cases green (bats installed via
  `apt-get install bats`, same as a prior cycle's precedent; this executor's own
  environment has no local Swift/Xcode toolchain, so `make test`/`make build`/
  `make probe-build` are validated by this PR's GitHub Actions run instead, same
  documented limit as every other cycle).
- `make routines-check` and `GITHUB_REF_NAME=main make routines-author-check` run
  directly against this repo's real, current state — both print their real `✓` line
  via the now-actually-used `ok()`, not just the bats fixtures.

Bash-only change; no Swift, secret-handling, or entitlements/crypto surface touched.

## PR

See the PR that accompanies this file.
