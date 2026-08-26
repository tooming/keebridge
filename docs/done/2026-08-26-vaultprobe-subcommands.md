# Give VaultProbe real subcommands

First groomed follow-up from `docs/done/2026-08-26-cli-tool-feasibility-spike.md`'s
recommended sequencing (step 1 of 3: read-only subcommands, before `--json` output
and write support).

`VaultProbe` was a single-file tool that only ever did one thing: open a vault and
list its entries. It now has three subcommands, built on
[swift-argument-parser](https://github.com/apple/swift-argument-parser) (a new
dependency for this package only — `KeeBridgeCore`, the app, and the extension are
untouched):

- `list [vault]` — the original behavior (title/username/URL, plus now the entry
  UUID and the sorted distinct custom-field *names*), and still the default
  subcommand, so `swift run VaultProbe <path>` keeps working exactly as before.
- `reveal [vault] <uuid> <field-key>` — reveals one field's value for one entry, by
  UUID (as printed by `list`) and field key (`Password`, `UserName`, `URL`, `Notes`,
  or a custom field name). Built directly on `VaultService.revealField`.
- `totp [vault] <uuid>` — prints the current TOTP code for one entry, by UUID.
  Built directly on `VaultService.currentTOTPCode`.

The vault path is a positional argument on every subcommand, still falling back to
`$VAULT_PATH` if omitted — unchanged behavior from before. Every subcommand still
reads the master password via `getpass()` (no echo, no shell history, no argv leak)
— nothing about secret handling changed, `reveal`/`totp` intentionally print exactly
the one field the caller asked for, matching this repo's existing reveal-on-demand
discipline (the credential-provider extension and the app's Edit sheet already work
this way).

`main.swift` (Swift's special top-level-executable-code filename) is gone —
`@main`-attributed types can't coexist with a file named `main.swift` in the same
target, so the tool is now `VaultProbe.swift`.

## Closing a CI gap noticed during the spike

`VaultProbe` was never built by `make ci`/`ci.yml` — a real build break in it would
have gone unnoticed. Added a `probe-build` Make target (`cd VaultProbe && swift
build`) and wired it into both `make ci` and `.github/workflows/ci.yml` (a new step
between `make build` and `make routines-check`), so this target now gets an actual
gate going forward.

## Still open (deliberately out of scope for this PR)

- `--json` output mode (next groomed item).
- Write subcommands (`create`/`update`/`delete`) — the highest-value, highest-risk
  remaining piece; scoped as its own follow-up once this subcommand/parsing shape
  has proven out.
- No new test target was added for `VaultProbe` — its `run()` methods do real file
  I/O and interactive `getpass()`, the same shape the original single-file tool
  already had with zero test coverage. The new `probe-build` CI gate catches
  compile/type errors; behavioral verification of an interactive CLI against a real
  vault stays a manual, human step (same headless-verification limit noted for
  every GUI/hardware-dependent path in this repo).

## PR

#13
