# [Action needed] Run status: one real fix landed, backlog empty again after a full resurvey

First cycle this run landed real, merged work; a second, deliberately broad resurvey
pass immediately after turned up nothing further.

## What landed

1. **`VaultController.lock()`'s explicit Lock action could be silently undone by mere
   app activation** (#158, merged). `startWatching()`'s
   `NSApplication.didBecomeActiveNotification` observer is registered from `unlock()`
   but never torn down by `lock()`, and `refreshIfStale()` (its handler) had no
   `isUnlocked` check — only a 15s throttle. So locking, then simply switching back to
   KeeBridge (no Unlock/Refresh button pressed), reached `refreshFromCache()`'s
   no-cached-key branch: a real Keychain read (Touch ID, if `.biometryCurrentSet`-
   protected) that, on success, silently re-set `isUnlocked = true` and repopulated
   `entries`/the identity store — reverting the user's own Lock action with no new
   authentication. Different from the 2026-09-11 lock-race fix's `generation` counter,
   which only discards a refresh already in flight *when* `lock()` runs — this was a
   brand-new refresh cycle that only starts *after* `lock()`, so `generation` never
   changed out from under it. Fixed with one `guard isUnlocked else { return }` at the
   top of `refreshIfStale()`; `LockedView`'s manual "Refresh from cached key" button
   deliberately keeps working (it calls `refreshFromCache()` directly, not through
   `refreshIfStale()`). See `docs/done/2026-09-13-vaultcontroller-lock-activation-refresh-fix.md`.

   Found via a fresh, full re-read of `VaultController.swift` — the ROADMAP's
   "Now / next" lane was otherwise fully checked off, so this was a STEP 6b-style
   resurvey rather than a queued item.

   **This cycle's own environment note**: this executor session runs in a Linux
   sandbox with no Xcode/`xcodebuild` at all (confirmed: no `swift`/`xcodebuild`
   binary anywhere on the container, and `xcodebuild` cannot exist on Linux
   regardless — it's macOS-only, unlike the sibling repos' clusterless/Linux-capable
   split). Ran the non-macOS-toolchain parts of `make ci` locally
   (`routines-check`/`routines-author-check`/`routines-bats-test`, all green, none
   touched by that change) and relied on the PR's own `ci.yml` run on GitHub Actions'
   `macos-latest` runner — confirmed green — as the real gate before self-merging.
   Worth flagging in case a future run also lands in a Linux-only sandbox: the
   `swift test`/`xcodebuild` verification this ROADMAP and `routines/executor.prompt.md`
   describe as always available isn't guaranteed by the executor's own environment:
   plan to rely on CI as the actual gate for any Swift change when that's the case,
   same as this cycle did.

## Second pass, immediately after: what this cycle checked, that turned up nothing

With "Now / next" empty again, re-surveyed rather than stopping:

- Full fresh reads of every file not already cited as fully read by a prior cycle:
  `unlock.js`, `ContentView.swift`, `LockedView.swift`, `VaultReadableContent.swift`,
  `background.js`, `manifest.json`, `content.js`, `SafariWebExtensionHandler.swift`,
  `VaultProbe.swift`, `CredentialProviderViewController.swift` (grown to 1031 lines
  since its last full-read cycle — re-read in full, not just the diff), `VaultBrowserView.swift`,
  `EntryEditView.swift`, `EntryDetailView.swift`, `KeeBridgeConfig.swift`,
  `KeychainStore.swift`, `VaultService.swift` (895 lines, full re-read — last fully
  read 2026-09-08/09-11 in pieces), `PaymentCard.swift`, `TOTPGenerator.swift`, and
  `PasskeyCrypto.swift`.
- One theoretical (not actionable) ambiguity noted and deliberately NOT filed as a
  bug: `PaymentCard.paymentCardExpirationParts`'s month/year disambiguation assumes
  month-first when a combined `expiration` value has two same-length numeric groups
  (e.g. a hypothetical 2-digit-year-first "YY-MM" would be misread). Not filed because
  real-world payment-card expiration dates are essentially always printed/stored
  month-first (`MM/YY` or `MM/YYYY`, matching the physical card format) — the
  assumption matches the near-universal real case, unlike the `content.js` DOM-field
  version of this same disambiguation (which has `maxLength`/placeholder context to
  use and rightly does).
- `grep -rniE 'hack|xxx|workaround|kludge|temporary fix|for now'` across every
  `.swift`/`.js`/`.py` file (excluding `docs/`) — zero hits.
- `try!`/` as! ` (force-try/force-cast) across every `.swift` file — zero hits.
- `grep -rn "TODO\|FIXME"` across every `.swift` file — zero hits (same as every
  prior cycle since the bats-suite item was groomed and shipped).
- `gh issue list --state open` equivalent (`list_issues` OPEN) — zero open issues.
- `gh pr list --state open` equivalent — zero open PRs (checked both before and after
  landing #158).

## Current state

`ROADMAP.md`'s "Now / next" lane is fully checked off again. The two items under
"Needs maintainer/human action" are unchanged and still correctly need a human, not
code:

- `#104`-class remote-branch clutter (`--no-merged` branches from past squash-merges,
  confirmed this token can't delete them — `403` on a live attempt in an earlier run).
- The `routines.yaml` `allowed_tools`/MCP-tool-surface question (`#77`, reopened after
  an accidental auto-close) — needs a human to confirm with the Claude Code / claude.ai
  routines infrastructure team, not fixable by a Swift or doc change alone.

Filing this rather than fabricating a second "finding" from nothing this cycle, per
STEP 6b — one real, merged fix plus an honest empty resurvey beats padding either.
