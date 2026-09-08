#!/usr/bin/env bats
# Fixture-based tests for scripts/routines-check.sh and
# scripts/routines-author-check.sh, using the env-var seams each script's own
# header documents (ROUTINESCHECK_ROOT; ROUTINES_AUTHOR_ROOT/_BRANCH/_FILES/
# _IS_CLOUD) — see ROADMAP.md's "Now / next" entry this closes and each
# script's own comments for why those seams exist. No real git history is
# needed: every fixture is a throwaway tempdir built fresh per test.
#
# Run with: bats tests/drift-detectors.bats  (needs bats-core; on macOS CI,
# installed via `brew install bats-core` — see .github/workflows/ci.yml).

SCRIPTS="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"

setup() {
  ROOT="$(mktemp -d)"
  mkdir -p "$ROOT/routines"
}

teardown() {
  rm -rf "$ROOT"
}

sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }

write_routines_yaml() {
  # $1: branch_prefix value (defaults to "auto/" if omitted)
  local prefix="${1:-auto/}"
  cat > "$ROOT/routines/routines.yaml" <<EOF
routines:
  - name: fixture executor
    branch_prefix: $prefix   # trailing comment, like the real file
EOF
}

# --- routines-check.sh ---

@test "routines-check: no routines/ directory is a no-op (exit 0)" {
  rm -rf "$ROOT/routines"
  ROUTINESCHECK_ROOT="$ROOT" run "$SCRIPTS/routines-check.sh"
  [ "$status" -eq 0 ]
}

@test "routines-check: clean state (hash matches snapshot) exits 0" {
  write_routines_yaml
  echo "routines/routines.yaml sha256=$(sha_of "$ROOT/routines/routines.yaml")" > "$ROOT/.routines-applied"
  ROUTINESCHECK_ROOT="$ROOT" run "$SCRIPTS/routines-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"in sync with last apply"* ]]
}

@test "routines-check: missing .routines-applied fails" {
  write_routines_yaml
  ROUTINESCHECK_ROOT="$ROOT" run "$SCRIPTS/routines-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *".routines-applied does not exist"* ]]
}

@test "routines-check: routines.yaml not yet in the snapshot fails" {
  write_routines_yaml
  : > "$ROOT/.routines-applied"
  ROUTINESCHECK_ROOT="$ROOT" run "$SCRIPTS/routines-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not in .routines-applied"* ]]
}

@test "routines-check: routines.yaml edited since last apply fails" {
  write_routines_yaml
  echo "routines/routines.yaml sha256=0000000000000000000000000000000000000000000000000000000000000000" > "$ROOT/.routines-applied"
  ROUTINESCHECK_ROOT="$ROOT" run "$SCRIPTS/routines-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has been edited since last apply"* ]]
}

@test "routines-check: snapshot references a file no longer on disk fails" {
  write_routines_yaml
  {
    echo "routines/routines.yaml sha256=$(sha_of "$ROOT/routines/routines.yaml")"
    echo "routines/deleted-routine.yaml sha256=deadbeef"
  } > "$ROOT/.routines-applied"
  ROUTINESCHECK_ROOT="$ROOT" run "$SCRIPTS/routines-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"deleted-routine.yaml is in .routines-applied but no longer on disk"* ]]
}

# --- routines-author-check.sh ---

@test "routines-author-check: routines.yaml not among changed files is clean regardless of branch" {
  write_routines_yaml
  ROUTINES_AUTHOR_ROOT="$ROOT" ROUTINES_AUTHOR_BRANCH="auto/anything" \
    ROUTINES_AUTHOR_FILES=$'ROADMAP.md\ndocs/done/whatever.md' \
    run "$SCRIPTS/routines-author-check.sh"
  [ "$status" -eq 0 ]
}

@test "routines-author-check: executor-branch change touching routines.yaml is blocked" {
  write_routines_yaml
  ROUTINES_AUTHOR_ROOT="$ROOT" ROUTINES_AUTHOR_BRANCH="auto/some-slug" \
    ROUTINES_AUTHOR_FILES="routines/routines.yaml" \
    run "$SCRIPTS/routines-author-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"matches the executor prefix"* ]]
}

@test "routines-author-check: cloud-identity-flagged change touching routines.yaml is blocked" {
  write_routines_yaml
  ROUTINES_AUTHOR_ROOT="$ROOT" ROUTINES_AUTHOR_BRANCH="plan/not-auto-prefixed" \
    ROUTINES_AUTHOR_FILES="routines/routines.yaml" ROUTINES_AUTHOR_IS_CLOUD=1 \
    run "$SCRIPTS/routines-author-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cloud identity"* ]]
}

@test "routines-author-check: interactive session (non-executor branch, no cloud flag) touching routines.yaml is clean" {
  write_routines_yaml
  ROUTINES_AUTHOR_ROOT="$ROOT" ROUTINES_AUTHOR_BRANCH="martin/manual-edit" \
    ROUTINES_AUTHOR_FILES="routines/routines.yaml" \
    run "$SCRIPTS/routines-author-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no executor-authored routine edits"* ]]
}

@test "routines-author-check: honors a custom branch_prefix from routines.yaml, not a hardcoded auto/" {
  write_routines_yaml "bot/"
  # "auto/..." is NOT the configured prefix here, so this branch alone must
  # NOT trigger the block -- only the cloud-identity flag does.
  ROUTINES_AUTHOR_ROOT="$ROOT" ROUTINES_AUTHOR_BRANCH="auto/would-have-matched-the-default" \
    ROUTINES_AUTHOR_FILES="routines/routines.yaml" \
    run "$SCRIPTS/routines-author-check.sh"
  [ "$status" -eq 0 ]

  ROUTINES_AUTHOR_ROOT="$ROOT" ROUTINES_AUTHOR_BRANCH="bot/matches-the-custom-prefix" \
    ROUTINES_AUTHOR_FILES="routines/routines.yaml" \
    run "$SCRIPTS/routines-author-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"matches the executor prefix 'bot/'"* ]]
}

@test "routines-author-check: detects routines.yaml touched via a routines/-prefixed path" {
  write_routines_yaml
  # ROUTINES_AUTHOR_FILES entries come from a real \`git diff --name-only\`,
  # which reports paths relative to the repo root (i.e. "routines/routines.yaml"),
  # not bare "routines.yaml" -- exercise that exact shape.
  ROUTINES_AUTHOR_ROOT="$ROOT" ROUTINES_AUTHOR_BRANCH="auto/some-slug" \
    ROUTINES_AUTHOR_FILES="routines/routines.yaml" \
    run "$SCRIPTS/routines-author-check.sh"
  [ "$status" -eq 1 ]
}
