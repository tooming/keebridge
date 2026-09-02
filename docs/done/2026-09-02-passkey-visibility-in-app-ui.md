# Passkey visibility in the app's own secrets-management UI

Discovered while re-surveying for new backlog items (STEP 6b — the "Now / next" lane had
no other buildable code item this cycle: credit card autofill stays blocked on missing
`xcodegen`, the newly-investigated automatic-password-save item (#33) is blocked on an
Apple macOS API gap, and Proton Pass decommission is a human-only action). A fresh read of
`KeeBridge/EntryDetailView.swift`/`VaultBrowserView.swift`/`VaultController.swift` — files
this executor hadn't looked at recently — turned up a real gap: passkey support has been
built out across several ROADMAP cycles now (metadata reading, write support, crypto
primitives, assertion, registration), but the app's own secrets-management UI had zero
passkey awareness. The only way to even confirm an entry had a passkey was KeePassXC or
`VaultProbe`'s CLI.

## What changed

- `VaultController.passkeyMetadata(uuid:)` (new) — thin, synchronous, in-memory wrapper
  around `VaultService.passkeyMetadata(in:entryUUID:)`, same shape as the existing
  `revealEntryForEditing(uuid:)`. Read-only: relying party, username, credential ID — never
  the private key, matching this codebase's existing secret-hygiene classification for
  these fields (see `VaultService.VaultPasskeyMetadata`'s own doc comment).
- `EntryDetailView`: a new "Passkey" section, shown only when `entry.isPasskey`, displaying
  relying party / passkey username / credential ID (base64, copyable) — populated in the
  existing `reveal()` on-appear hook, same discipline as every other field in this view.
- `VaultBrowserView`: a small `person.badge.key.fill` icon next to an entry's title in the
  list when it carries a passkey, so passkey-bearing entries are visible without opening
  each one individually.

## Why this scope, not more

Read-only visibility only — creating/using passkeys stays exclusively the credential
provider extension's job (ROADMAP #4), matching this project's existing "KeePassXC/the
extension write, the app mirrors and displays" pattern. No new write path, no editing of
passkey fields from the app UI.

## Verification

Headless only — `EntryDetailView`/`VaultBrowserView` have no unit test target (SwiftUI
views, same as every other file in the `KeeBridge` app target), so correctness rests on:
(1) CI's `xcodebuild` build catching any compile error, (2) `VaultController.passkeyMetadata`
being a thin, directly-inspectable wrapper around an already-`swift test`-covered
`VaultService` method, and (3) careful reading of the existing `EntryDetailView`/
`fieldRow`/`LabeledContent` patterns already proven in this file for every other field.

**Still needs a human eyeball**: the actual visual layout (icon choice/placement, section
ordering) has never been seen rendered — no GUI in this executor's environment. The SF
Symbol name `person.badge.key.fill` is used elsewhere in Apple's own passkey-related UI
(Passwords app/Keychain Access) to the best of this executor's knowledge, but wasn't
visually confirmed to exist/render correctly.

## PR

See the PR this file was committed alongside.
