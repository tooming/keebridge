# Write subcommands for VaultProbe: create, update, delete

Third and final step of the CLI feasibility spike's
(`docs/done/2026-08-26-cli-tool-feasibility-spike.md`) recommended sequencing, built
on the two foundation PRs before it
(`docs/done/2026-08-26-vaultservice-write-overloads.md`,
`docs/done/2026-08-26-vaultservice-reveal-overload.md`). `VaultProbe` now has all six
subcommands the spike scoped: `list`/`reveal`/`totp` (read) and `create`/`update`/`delete`
(write).

## The three commands

- `create [vault] [--title] [--username] [--url] [--notes] [--set-password]` — creates a
  new entry via `VaultService.createEntry(masterPassword:)`, prints the new UUID.
- `update [vault] <uuid> [--title] [--username] [--url] [--notes] [--set-password]` —
  reveals the entry's current fields first (`revealEntry(masterPassword:)`), then merges:
  any flag you pass overrides that field, anything you omit keeps its existing value.
  `updateEntry` itself replaces all five fields at once — without this reveal-then-merge
  step, an `update <uuid> --username bob` with no other flags would silently blank out
  the title/password/URL/notes. This is exactly what the two foundation PRs unblocked.
- `delete [vault] <uuid> --yes` — deletes via `VaultService.deleteEntry(masterPassword:)`.
  Refuses to run without `--yes` (a `ValidationError`, same clean-exit path
  `ArgumentParser` already uses elsewhere in this tool) — irreversible, no recycle bin,
  matching `VaultService.deleteEntry`'s own doc comment.

All three take `--json` (consistent with the read subcommands), emitting `{"uuid": ...}`
(`create`/`update`) or `{"uuid": ..., "deleted": true}` (`delete`).

## Secret hygiene: the entry's password is never a CLI argument

`title`/`username`/`url`/`notes` are ordinary `@Option` flags — non-secret, matching how
`list` already prints title/username/URL in the clear, and how the KDBX format itself
only inner-stream-cipher-protects the `Password` field (confirmed in
`VaultService.draftStrings`'s doc comment — `Notes` is `.regular`, plaintext in the XML,
same as `Title`/`UserName`/`URL`; only `Password` gets the protected treatment).

The entry's *password* is different: it's exactly the kind of secret material this repo's
hard rules say never to expose somewhere it wasn't already handled, and a CLI flag would
leak it into shell history and `ps` output the same way a `--password` flag for the vault's
own master password would (which is precisely why `VaultProbe` prompts for that via
`getpass()` instead, from day one). So `create`/`update` don't take a password flag at
all — `--set-password` is a boolean trigger for a second, distinctly-prompted `getpass()`
call (`promptEntryPassword()`, separate from `promptPassword(for:)` so the two prompts are
never confused). Omitting `--set-password` means "no password" on `create` and "keep the
existing password unchanged" on `update`.

## Still open (deliberately out of scope for this PR)

Nothing further from the original spike's sequencing — this closes it out. Any future
CLI work (e.g. bulk operations, a config file, shell completion) would be a fresh,
separately-scoped item.

## PR

#17
