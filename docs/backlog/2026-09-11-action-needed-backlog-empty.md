# [Action needed] Backlog still empty — a sixth resurvey angle, nothing new

First cycle of this run. `ROADMAP.md`'s "Now / next" lane is fully checked off (last
real, merged work: 2026-09-10, #107–#110 — `scripts/lib/colors.sh`'s fabricated
cross-repo history, two Swift 6 Sendable-concurrency warnings, and a `docs/done/`↔
`ROADMAP.md` backfill). The one item under "Needs maintainer/human action" (`#77`,
whether `allowed_tools` actually gates the runtime MCP tool surface) is explicitly not
code and still correctly needs a human, not another code cycle. Before falling back to
re-filing the same notice, this cycle tried genuinely different angles than the last
five runs' worth of audits.

## What was checked this cycle

- **Full reads of three small app-layer files with no dedicated audit note of their
  own in `ROADMAP.md`/`docs/`**: `KeeBridge/ContentView.swift` (17 lines — a plain
  `isUnlocked` ? `VaultBrowserView` : `LockedView` switch, nothing to find),
  `KeeBridge/KeeBridgeApp.swift` (9 lines — the `@main` entry point, nothing to find),
  and `KeeBridge/LockedView.swift` (including its nested `CreateVaultSheet`) — the
  vault-picker/unlock/create-vault UI. `LockedView.unlock()` clears its local
  `password` `@State` right after calling `controller.unlock(password:)`, matching
  this codebase's existing (not-exotic-memory-zeroing) secret-field convention
  elsewhere; `CreateVaultSheet`'s password/confirm-password fields follow the same
  pattern as every other plain-`String` secret field in this app (`EntryEditView`
  included) — not a regression, not a new gap, just confirmed consistent.
- **`KeeBridgeCore/Sources/KeeBridgeCore/KeychainStore.swift`** (117 lines) — full
  read. `store`/`read`/`delete`'s query construction, the `.biometryCurrentSet` access
  control, and `kSecUseDataProtectionKeychain`'s macOS-specific necessity (already
  documented in the file's own comments and in `README.md`) all check out. No
  injectable seam for testing (calls the real Security framework directly) — same,
  previously-investigated-and-accepted limitation as before, not a new finding.
- **`KeeBridgeCore/Sources/KeeBridgeCore/KeeBridgeConfig.swift`** (97 lines) — full
  read. Every mirror-path/Keychain-identifier constant cross-checked against
  `project.yml`'s actual bundle IDs (`com.martintooming.KeeBridge.Provider`,
  `...CardExtension`) — both match exactly, no drift.
- **`KeeBridgeCore/Sources/KeeBridgeCore/VaultReadableContent.swift`** (48 lines,
  introduced by the attachment memory-footprint refactor but never itself re-read
  adversarially since) — full read. The protocol has no requirements beyond
  `var database: KDBX { get }`, both conformances (`KDBXContent`, `LazyKDBXContent`)
  are simple marker extensions with no logic to get wrong; matches its own doc
  comment's description exactly.
- **`project.yml` vs. every physical `Info.plist`/`.entitlements` file** (all three
  targets: `KeeBridge`, `KeeBridgeProvider`, `KeeBridgeCardExtension`) — re-diffed by
  hand, property by property, not assumed clean from the last drift fix (#65, which
  only covered `KeeBridgeProvider`'s two passkey capability flags). All three targets'
  generated vs. physical files match exactly today; no second instance of the #65
  drift class found in the other two targets.
- **`.github/workflows/ci.yml`** — re-read in full. Pinned action SHA, job steps,
  `bats-core` install guard, and the `push`/`pull_request` trigger scoping are all
  still internally consistent with their own explanatory comments.
- **Issue `#89`** (`manual-step`, `KeeBridgeCore`/`VaultProbe` `Package.resolved`
  reproducibility) re-checked, including its full comment history: still genuinely
  blocked upstream on `shadone/KDBXKit#6` (confirmed via a fresh fetch this cycle —
  still open, unreviewed, unmerged). Nothing actionable from inside this repo until
  that merges; both `Package.resolved` files still correctly pin `swift-crypto`
  `3.15.1` today, matching what KDBXKit's own current manifest constraint allows.
- Re-confirmed live GitHub state: zero open PRs, exactly one open issue (`#89`, as
  above), zero `TODO`/`FIXME` markers repo-wide (unchanged from prior cycles' checks).

## Current state

Sixth consecutive genuinely-checked-fresh survey (after the five cycles logged in
`docs/backlog/2026-09-08-action-needed-run-status.md` and
`docs/backlog/2026-09-10-action-needed-second-resurvey.md`/
`2026-09-10-action-needed-run-status.md`), using angles none of those had used yet
(the three previously-unaudited small app-layer files, `KeychainStore.swift`,
`KeeBridgeConfig.swift`, `VaultReadableContent.swift`, and a full three-target
`project.yml`-vs.-physical-file diff rather than just the one target the last drift
fix covered) — no new, confirmed, actionable finding. Filing this rather than
fabricating make-work, per `routines/executor.prompt.md` STEP 6b.
