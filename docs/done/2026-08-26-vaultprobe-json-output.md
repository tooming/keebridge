# `--json` output mode for VaultProbe

Second groomed follow-up from `docs/done/2026-08-26-cli-tool-feasibility-spike.md`'s
recommended sequencing (step 2 of 3, after `docs/done/2026-08-26-vaultprobe-subcommands.md`'s
`list`/`reveal`/`totp` subcommands).

Every subcommand now takes a `--json` flag, for piping into `jq`/scripts instead of
reading the human-readable text output:

- `list --json` → `{"entries": [{"uuid", "title", "username", "url",
  "customFieldKeys"}, ...], "customFieldKeys": [...distinct, sorted...]}`
- `reveal --json` → `{"uuid", "fieldKey", "value"}`
- `totp --json` → `{"uuid", "code"}`

Output is pretty-printed with sorted keys (`JSONEncoder`'s `.sortedKeys` option) so
`--json` output is byte-stable across runs — no dictionary-ordering nondeterminism to
trip up anyone diffing or snapshotting it.

Human-readable output (the default, no `--json`) is unchanged byte-for-byte from the
previous cycle's subcommand work — `--json` is purely additive, opt-in per invocation.

Secret hygiene is unchanged: `reveal --json`/`totp --json` still only ever emit the
one field/code the caller explicitly asked for, same as their plain-text form; `list
--json` still never includes a field *value*, only the same non-secret
title/username/URL/UUID/custom-field-*names* `list` already printed.

## Still open (deliberately out of scope for this PR)

- Write support (`create`/`update`/`delete` subcommands) — the last and
  highest-value/highest-risk item in the spike's recommended sequencing, now that both
  read-only steps (subcommands, then `--json`) have proven the shape out.

## PR

#14
