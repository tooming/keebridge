# CLI tool feasibility spike

Closes #9 ("CLI tool" — "look into feasibility of creating a cli tool").

## Why this item, this cycle, not the topmost one

ROADMAP.md's "Now / next" lane lists credit card autofill (#3) above this. Picked
this one instead: #3 needs a Safari Web Extension (a new JS/TS tech stack this repo
has none of) and a design decision on native-messaging vs. local-decrypt before any
code is worth writing — its own issue body says as much ("Needs design"). Worse,
nothing in this repo (no conversion script, no existing card-handling code) confirms
what field names the 9 card entries in the real vault actually use, and I have no
access to that real vault — guessing at a field-name convention and shipping code
against it would be worse than not shipping. #4 (passkeys) is explicitly
"deliberately last" and has its own unresolved-platform-bug research still to do.
#9, by contrast, is scoped in ROADMAP.md itself as accepting "a written
recommendation ... not necessarily code" as a first deliverable — genuinely
buildable this cycle, headless, with no speculative reverse-engineering required.

## What already exists

`VaultProbe` (`VaultProbe/Sources/VaultProbe/main.swift`) is already, in substance,
milestone zero of a CLI tool:

- Takes a vault path as an argument or `VAULT_PATH` env var.
- Reads the master password via `getpass()` (no echo, no shell history, no argv
  leak — `ps` can't see it, unlike `swift run VaultProbe --password foo`).
- Uses `KeeBridgeCore.VaultService` directly — the *same* shared package the app
  and extension use, not a reimplementation.
- Prints entry titles/usernames/URLs and the *names* (never values) of custom
  fields — already follows this repo's secret-hygiene discipline.

It's framed as a one-shot validation tool ("milestone-1 validation tool ... before
any UI or extension code is built"), not a general-purpose CLI, but the hard parts
of "a CLI tool" — packaging (`.executableTarget` in an SPM package), the
KeeBridgeCore dependency, and safe non-echoing password entry — are already solved
and already exercised in production use (it's how the original vault was validated
before any Xcode target existed).

## Feasibility: yes, and cheap

`VaultService`'s public API already covers everything a read/write CLI needs, with
no GUI or Touch ID dependency at all (a CLI sidesteps that whole story — no
`ASCredentialProviderViewController`, no Keychain-gated biometry, just a
password/pre-hash and a `KDBXContent` held in memory for the process's lifetime):

- `listEntries` / `revealField` / `currentTOTPCode` — read side, already used by
  VaultProbe for the first two.
- `createEntry` / `updateEntry` / `deleteEntry` / `createVault` — write side
  (shipped for #1/#2), unused by VaultProbe today but directly reusable.

Since `KeeBridgeCore`'s `Package.swift` pins `.macOS(.v15)`, a CLI built on it is
macOS-only already — no cross-platform portability story is needed or expected.

## Open scope questions (for whoever grooms the follow-up items)

- **Read-only vs. read/write.** A `reveal`/`list`/`totp` CLI is the safe, obviously
  useful slice. Wiring up `createEntry`/`updateEntry`/`deleteEntry` makes it a real
  KeePassXC alternative for scripting, but raises the stakes on argument-parsing
  correctness (a typo'd `update` could corrupt the one copy of someone's live vault
  — `write()` already keeps a `.bak` sibling, which helps).
- **Output format.** VaultProbe today is print-and-read; a CLI meant to be piped
  into other tools (`jq`, shell scripts) wants a `--json` mode. Worth deciding
  before the flag surface grows organically.
- **Argument parsing.** `main.swift` currently hand-parses `CommandLine.arguments`
  (fine for one positional arg). Real subcommands (`list`, `reveal <uuid> <field>`,
  `totp <uuid>`) want a proper parser —
  [swift-argument-parser](https://github.com/apple/swift-argument-parser) is the
  obvious, well-trodden choice and composes cleanly with SPM executables.
- **Where it lives.** Recommend evolving `VaultProbe` itself into the CLI (rename
  or add subcommands to the existing target) rather than standing up a fourth
  target — it already has the right dependency shape (SPM package → KeeBridgeCore)
  and the non-echoing password entry already solved. A rename is a bigger, separate
  decision than this spike should make unilaterally.

## Recommendation

Feasible, and worth doing — KeeBridgeCore already does the hard part. Suggested
sequencing for follow-up ROADMAP items (smallest, safest first):

1. Add `swift-argument-parser` to `VaultProbe` and give it real subcommands
   (`list`, `reveal <uuid> <field>`, `totp <uuid>`), read-only, built on the
   existing `VaultService` read methods.
2. `--json` output mode for scriptability.
3. Write support (`create`/`update`/`delete` subcommands) via the already-built
   `VaultService` write methods — higher-value and higher-risk; do it once the
   read side has proven the subcommand/parsing shape out.

None of this needs GUI/Touch ID work, so it's fully verifiable through
`swift test`/`swift build` the same way `VaultProbe` already is today — no new
headless-verification gap. (Note: `VaultProbe` isn't currently wired into
`make test`/`make build` or the CI workflow — worth folding a `swift build` for it
into `make ci` when item 1 above lands, so this new surface gets a real gate.)

## PR

#12
