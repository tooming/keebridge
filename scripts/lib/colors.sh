# Shared ANSI color setup + ok()/bad() drift-check printers for the two
# routines/ drift-detector scripts (routines-check.sh, routines-author-check.sh)
# — sourced, not executed. Extracted so the identical color/printer boilerplate
# those two scripts started with only needs one edit going forward.
#
# bad() sets the SOURCING SCRIPT's own `drift` variable (plain global
# assignment, not `local` — that's what makes this safe to share: each caller
# still declares its own `drift=0` before running checks and reads `$drift`
# itself at the end, this just supplies the two printer functions).
#
# Only $G/$R/$Z and bad() are actually used by this repo's two callers today;
# kept minimal rather than carrying unused colors/helpers on spec.
if [ -t 1 ]; then
  G=$'\033[32m'; R=$'\033[31m'; Z=$'\033[0m'
else
  G=; R=; Z=
fi

ok()  { printf '  %s✓%s %s\n' "$G" "$Z" "$1"; }
bad() { printf '  %s✗%s %s\n' "$R" "$Z" "$1"; drift=1; }
