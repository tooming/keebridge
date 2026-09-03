# [Action needed] Refresh: the remaining `ROADMAP.md` items still need maintainer input

This run (2026-09-03) landed one genuinely new item first — payment card visibility in the
app's own secrets-management UI and `VaultProbe` (see
`docs/done/2026-09-03-payment-card-visibility-in-app-ui.md`), found via the same re-survey
method this file's earlier versions describe (open issues, TODO/FIXME grep, a fresh read of
every source file). After that landed, a full re-survey — including files no prior run had
re-read end-to-end (`CredentialProviderViewController.swift`, `VaultController.swift` in
full, `KeychainStore.swift`, `KeeBridgeConfig.swift`, `TOTPGenerator.swift`, the Safari card
extension's `SafariWebExtensionHandler.swift`/`content.js`/`background.js`/`unlock.js`,
`LockedView.swift`, `ContentView.swift`) — turned up nothing further that's both genuinely
new and safely buildable this cycle. This file replaces (does not merely restate)
`docs/backlog/2026-09-02-action-needed-backlog-blocked.md`: one of that file's four blocked
items has since shipped and is removed below; the other three are unchanged.

## What's changed since the 2026-09-02 version

1. **Credit card autofill (#3) is no longer blocked — it shipped.** The prior file's #1
   blocker (`xcodegen` unavailable, needed to add a new Xcode target by hand) turned out not
   to matter: a separate contribution (GitHub Copilot, PR #45, landed 2026-09-02) added the
   `KeeBridgeCardExtension` Safari Web Extension target directly to
   `KeeBridge.xcodeproj/project.pbxproj` and `project.yml`, with native local KDBX decrypt,
   an independent biometric Keychain cache, and conservative card-field aliases. `ROADMAP.md`
   already reflects this as `[x]`. This executor's own follow-up work on top of it (payment
   card visibility, this run) found the implementation solid on a full read — no defects,
   no gaps beyond the visibility one just fixed.
2. Everything else below is materially unchanged from the 2026-09-02 version — re-confirmed,
   not re-discovered.

## New this run: this executor's environment has no local Swift/Xcode toolchain at all

Worth surfacing on its own, separate from the ROADMAP items below: this run's execution
environment (Claude Code's "Anthropic cloud (Default)" environment,
`routines/routines.yaml`'s configured `environment_id`) is a bare Linux container with
**no `swift`, no `xcodebuild`, and no `xcodegen`** — not merely missing `xcodegen` as the
2026-09-02 file found, but missing the entire toolchain `make ci` needs. `KeeBridgeCore`'s
own `Package.swift` declares `platforms: [.macOS(.v15)]` and depends on `Security`/
`LocalAuthentication`, so `swift test` cannot run on Linux for this package even with Swift
itself installed — this is a hard platform requirement, not a missing-package gap.

This did not block this run's actual delivery: `make ci`'s real gate (this repo's `ci`
GitHub Actions workflow, which runs on `macos-latest`) still ran and passed against PR #51,
same as it would from any contributor's machine — this executor validated by pushing the
branch, opening the PR, and polling the check run via the GitHub API rather than running
`swift test`/`xcodebuild` locally. Flagging this because it's a discrepancy from prior runs'
own notes (which describe running `xcodebuild` directly) and because it means **local
iteration speed is gone** for this executor specifically: every code change now costs one
full `macos-latest` CI round-trip (~8 minutes for this repo) to validate, rather than a
local recompile. Not a blocker, just a cost — and worth knowing if a future run seems slower
per cycle than earlier ones.

**Unblocks with**: nothing required — this is informational. If a future environment
happens to include the Swift/Xcode toolchain, local iteration resumes automatically (no code
change needed on either side); this note is here so that isn't mistaken for a regression.

## What's still blocked, and what would unblock each one

1. **Automatic password-save proposal (#33)** — the API this needs
   (`ASCredentialProviderViewController.prepareInterface(for: ASSavePasswordRequest)`) is
   `API_UNAVAILABLE(macos, tvos, watchos)` in Apple's own SDK — iOS/visionOS 26.2+ only, no
   macOS entry point exists at all (see
   `docs/done/2026-09-02-save-password-proposal-feasibility-spike.md`).
   **Unblocks with**: Apple shipping a macOS counterpart to this API in some future SDK.
   Nothing to do until then — flagged to re-check whenever the project's
   `MACOSX_DEPLOYMENT_TARGET` next moves forward.
2. **Decommission Proton Pass — final migration step (#5)** — an interactive, local-machine
   action (Safari → Settings → Extensions to disable Proton Pass's Safari Web Extension,
   `pluginkit -m -v` to confirm no stale registration remains, deciding whether to keep or
   cancel the Proton Pass account). The headless executor cannot open Safari Settings or run
   `pluginkit` against the maintainer's own session.
   **Unblocks with**: the maintainer doing this by hand, at their convenience — password +
   TOTP autofill via KeeBridge is already confirmed working end-to-end, so this is cleanup,
   not a blocker for anything else.
3. **QR code scanning for adding a passkey (#7)** — already investigated and closed as a
   permanent platform-level dead end (`CoreBluetooth` doesn't let any third-party app
   advertise the BLE service data WebAuthn hybrid transport needs — see
   `docs/done/2026-09-01-passkey-qr-hybrid-transport-spike.md`). Not actionable by anyone,
   maintainer included, short of Apple changing that API surface. (Unrelated to, and not to
   be confused with, the separately-shipped QR *TOTP setup* import in `EntryEditView` —
   that's a different, already-working feature.)

## Not a code problem

None of the three items above have a code path this executor could take today that wouldn't
either be a fabricated workaround for a real platform restriction or literally impossible to
do headlessly (an interactive Safari Settings action). Filing this rather than churning on a
non-problem, per STEP 6b.
