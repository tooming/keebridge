# Fix a stale comment claiming test coverage that never existed, groom the real gap

Fifteenth cycle this run. Checked a genuinely new angle: whether every claim this repo's
own code comments make about its tooling is actually true, starting with
`scripts/routines-author-check.sh`'s header, which says it "mirrors the readme-check /
roadmap-check / routines-check drift guards" from the sibling repos "+ bats coverage in
`tests/drift-detectors.bats`."

## What was checked

`grep -rn "drift-detectors\|\.bats\b"` across the entire repository, including
`.github/workflows/ci.yml` and the `Makefile` — zero hits for any `.bats` file, any bats
invocation, or any CI step that would run one. `tests/drift-detectors.bats` does not
exist and has never been referenced anywhere except that one stale comment. The comment
was very likely copied from the equivalent script in a sibling repo (`tooming/k8s-anywhere`
or `toomingsolutions/easysportstream`, both explicitly named as the pattern source in
this repo's `routines/` docs) when `routines-author-check.sh` was first written, and
never adjusted for the fact that this repo doesn't actually have that test suite.

Both drift-detector scripts already carry environment-variable test seams purpose-built
for exactly this kind of fixture-based testing — `ROUTINESCHECK_ROOT` in
`routines-check.sh`, `ROUTINES_AUTHOR_ROOT`/`_BRANCH`/`_FILES`/`_IS_CLOUD` in
`routines-author-check.sh` — confirming the intent was real, just never finished.

## What changed

- `scripts/routines-author-check.sh`'s header comment corrected to state the actual
  situation plainly (no bats suite exists, the claim was inherited from a sibling repo's
  comment without adjustment, the script is still exercised for real via `make
  routines-author-check` against actual repo state, just not via dedicated unit tests
  yet). Comment-only change — verified with `bash -n` (syntax) and running both scripts
  directly (still exit 0, same output) before and after.
- New `ROADMAP.md` "Now / next" item grooming the actual gap (a real `bats` suite for
  both drift-detector scripts) for a future cycle: not implemented this cycle because
  `bats` isn't installed in this executor's local environment (nothing to validate
  syntax or logic against before pushing) and CI's `macos-latest` runner would likely
  need its own `brew install bats-core` step added — its own small piece of scope, and a
  real suite deserves fixture trees for multiple scenarios per script rather than being
  rushed through blind.

## PR

See the PR that accompanies this file.
