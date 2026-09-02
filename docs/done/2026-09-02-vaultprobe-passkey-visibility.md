# Passkey visibility in VaultProbe (the CLI tool)

Discovered via a STEP 6b re-survey (`ROADMAP.md`'s "Now / next" lane had no other
buildable item left this cycle after the conditional-passkey-registration item above). A
fresh read of `VaultProbe/Sources/VaultProbe/VaultProbe.swift` turned up the same gap the
app's own secrets-management UI had before an earlier cycle fixed it (see
`docs/done/2026-09-02-passkey-visibility-in-app-ui.md`): passkey support has been built
out across many ROADMAP cycles now (metadata reading, write support, crypto primitives,
assertion, registration, conditional registration, app-UI visibility), but `VaultProbe`
still had zero passkey awareness — `list` didn't mark passkey-bearing entries, and there
was no way to inspect one's metadata short of opening the vault in KeePassXC or the app.

## What changed

- `ListCommand`: `JSONEntry` gained `isPasskey: Bool` (from the already-existing
  `VaultLoginEntry.isPasskey`); the human-readable text output appends a `[passkey]`
  marker after the UUID for entries that have one.
- New `PasskeyCommand` (`vaultprobe passkey <uuid>`): prints relying party, username, and
  credential ID (base64) for one entry via the already-existing
  `VaultService.passkeyMetadata(at:masterPassword:entryUUID:)` — same shape as the
  existing `totp` subcommand. Errors (`ValidationError`) if the entry doesn't exist or has
  no passkey, same pattern `reveal`/`totp` already use.
- `VaultProbe`'s subcommand list and file-header doc comment updated: seven subcommands
  now (`list`/`reveal`/`totp`/`passkey`/`create`/`update`/`delete`).

## Why this scope, not more

Strictly read-only, mirroring `EntryDetailView`'s own passkey section exactly: relying
party, username, credential ID — **never** the private key.
`VaultService.revealPasskeyPrivateKeyPEM` exists solely for the credential provider
extension's actual WebAuthn signing at assertion/registration time (see its own doc
comment), not for general inspection — deliberately not exposed via any CLI subcommand,
matching this codebase's existing "reveal-on-demand, narrowest possible surface" secret-
hygiene discipline. No new write path, no change to any existing subcommand's behavior
beyond the new `isPasskey` field/marker on `list`.

## Verification

Headless-friendly, more so than most items in this ROADMAP: `VaultProbe` is a plain SPM
executable with no `AuthenticationServices`/AppKit/extension dependency, so `make
probe-build` (`swift build` — already a real CI gate per `ci.yml`) fully exercises this
change's compile correctness. No unit test target exists for `VaultProbe` itself (same as
before this change — its subcommands are thin, directly-inspectable wrappers around
already-`swift test`-covered `VaultService`/`KDBXKit` methods, same reasoning the earlier
CLI-subcommand ROADMAP items used). Not run against a real vault file in this executor's
environment (no interactive TTY for `getpass()` here either), but the code path is a
straight, minimal-risk analog of the already-shipped `totp` subcommand.

## PR

See the PR this file was committed alongside.
