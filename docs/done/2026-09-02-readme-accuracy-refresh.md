# README accuracy refresh (passwords/write/UI/passkeys are shipped, not "planned")

Discovered via a STEP 6b re-survey (`ROADMAP.md`'s "Now / next" lane had no other
buildable item left this cycle after the VaultProbe passkey-visibility PR just before this
one). A fresh read of `README.md` — the single most user/maintainer-facing file in this
repo, and one this executor had never revisited since the passkey/write-support work
landed — turned up real, non-trivial staleness:

- "What's planned" item 1, **vault write support**, and item 2, **a real
  secrets-management UI**, were both already shipped before this executor's first run
  (`ROADMAP.md`'s own "Done" pointer section: "vault write support (#1) and the full
  secrets-management UI (#2), both closed"). The README never caught up.
- "What's planned" item 4, **passkeys**, is now substantially implemented (metadata,
  crypto primitives, assertion, interactive registration, conditional/silent
  registration, visibility in both the app UI and `VaultProbe`) across many ROADMAP
  cycles — the README still described it as pure future work.
- The intro line's "(soon) card/passkey autofill" was half wrong: passkeys aren't "soon"
  anymore, only cards still are.

Left completely unmentioned in "What works today": passkeys, vault write support, and the
secrets-management UI — someone reading only the README (not `ROADMAP.md`) would come
away thinking this project is still read-only with no real UI, which hasn't been true for
a while.

## What changed

`README.md` only:

- Intro line: "(soon) card/passkey autofill" → "passkey autofill (plus, soon, credit card
  autofill)".
- "What works today": added vault write support, the secrets-management UI, and passkeys
  (with the same AAGUID-zeroing platform-risk caveat the old "What's planned" entry
  carried, plus an honest "still needs real-hardware verification" note — this project is
  built and validated headlessly).
- "What's planned": now just credit card autofill (the one genuinely-still-future item),
  with a pointer to `ROADMAP.md` for the full, current, detailed backlog instead of
  duplicating status that drifts out of sync with the README over time.

No code changed — docs-only.

## Why this scope, not more

Deliberately did not rewrite "Architecture" or "Notable non-obvious design decisions" —
re-read both against the current codebase and found them still accurate (three targets,
no shared Keychain group, the Touch ID/main-thread notes, etc. all still hold). Only "What
works today"/"What's planned" had drifted, so only those changed.

## Verification

Docs-only change, no build/test surface — reviewed by re-reading the new text against
`ROADMAP.md`'s actual `[x]`/`[ ]` state and the shipped code (`VaultController`'s write
methods, `EntryDetailView`, `CredentialProviderViewController`'s passkey overrides,
`VaultProbe`'s `passkey` subcommand) to confirm every claim added is accurate and every
claim removed was genuinely stale, not just reworded.

## PR

See the PR this file was committed alongside.
