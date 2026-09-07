# [Action needed] Full core-logic re-audit this cycle — still nothing new

Second cycle this run (first: [`docs/backlog/2026-09-07-action-needed-backlog-empty.md`](2026-09-07-action-needed-backlog-empty.md),
merged as #73). That first pass re-checked open PRs/issues, TODO/FIXME markers, and did
a fresh adversarial read of three smaller, previously-covered files
(`PasskeyCrypto.swift`, `KeychainStore.swift`, `KeeBridgeConfig.swift`). This second pass
goes much deeper: a fresh, line-by-line adversarial read of every one of this repo's
largest and most security/correctness-critical Swift files, specifically hunting for the
same class of bug earlier cycles found (data loss, crashes, races, security gaps) —
**~3,600 additional lines**, none of them just skimmed:

- `VaultService.swift` (864 lines) — every read/write function, the `updateEntry`
  full-replace-vs-preserve field logic (re-derived the nil-preserves/empty-removes/
  non-empty-sets truth table for `otp` by hand against `draftStrings`, still correct),
  the history-snapshot/trim logic, `mergeExtensionOriginatedPasskeys`,
  `openReadOnlyContent`'s KDBX-3.x fallback, the atomic `write` path.
- `VaultProbe.swift` (531 lines) — every subcommand's secret-hygiene discipline
  (`getpass()` usage, what gets printed vs. withheld), the `update` reveal-then-merge
  logic.
- `CredentialProviderViewController.swift` (959 lines) — the full request lifecycle
  (`beginRequest`/watchdog/`respond*` exactly-once guards), the passkey assertion and
  registration flows (including `performWithoutUserInteractionIfPossible`'s three-gate
  conservatism), the `viewDidAppear` gating fix, the static-cache reasoning.
- `VaultController.swift` (697 lines) — unlock/refresh/create/update/delete task
  shapes, the mirror write-back merge trigger (`mirrorChangedSinceLastAppWrite`), the
  atomic mirror replace, the identity-store population (password/OTP/passkey identity
  construction), the activation-observer/refresh-throttle logic.
- `PaymentCard.swift` (226 lines) — the alias-matching/normalization, the split-field
  `.expiration` synthesis (both directions), `paymentCardExpirationParts`'s
  ambiguous-format heuristics (noted as a soft, pre-existing best-effort limitation for
  genuinely ambiguous formats like a bare 2-digit-year order — not a new confirmed bug:
  no data loss or security exposure, at worst a wrong autofill value for an unusual
  expiration-field format, and no test regression from any prior cycle covers a
  "correct" answer for that ambiguous case either).
- `TOTPGenerator.swift` (166 lines) — re-derived the dynamic-truncation offset
  arithmetic (`offset + 3` max index 18, safely within HMAC-SHA1's 20-byte, SHA-256's
  32-byte, and SHA-512's 64-byte output for every algorithm this type supports) and the
  digits/period validation guards by hand — no new gap versus the existing coverage in
  `TOTPGeneratorTests.swift`.
- `VaultReadableContent.swift` (47 lines) — the protocol seam itself, confirmed narrow
  (`database` only) as documented.
- `SafariWebExtensionHandler.swift` (202 lines) — the per-request-instance static-cache
  synchronization argument (re-confirmed: every access genuinely does happen inside
  `workQueue.async`, so the `nonisolated(unsafe)` annotations are justified, not
  papering over a real race), the cache-invalidation-on-mirror-mtime-change logic, the
  Keychain-on-main-thread hop.
- `EntryEditView.swift` (232 lines) — confirmed the edit form's `otpURI` field, though
  always passed as a non-optional `String` into `EntryDraft.otpURI: String?` (so never
  literally `nil`), doesn't hit the "nil preserves" gap this could suggest at a glance:
  `loadIfEditing()` eagerly populates the field with the entry's *current* OTP value on
  open, so an untouched field round-trips the existing value instead of relying on
  nil-means-preserve semantics — verified by tracing both `loadIfEditing()` and `save()`
  together, not just one or the other.

Nothing above surfaced a new, confirmed, actionable bug. Filing this rather than
fabricating make-work, per STEP 6b: an honest `[Action needed]` PR beats a churn PR —
and an honest "here's exactly what was re-checked and why it's still clean" beats a
second PR that just repeats the first one's framing without saying what's actually new
this time.

## Still not read fresh this run (lower risk, smaller, or covered by a recent prior cycle)

`EntryDetailView.swift`, `VaultBrowserView.swift`, `ContentView.swift`,
`KeeBridgeApp.swift`, `LockedView.swift` — all app-layer SwiftUI views with no test
target (same `xcodebuild`-only verification limit as everything else in `KeeBridge/`).
`LockedView.swift`/`ContentView.swift`/`KeeBridgeApp.swift` got a fresh full read as
recently as the 2026-09-06 cycle
(`docs/backlog/2026-09-06-action-needed-backlog-empty.md`); `EntryDetailView.swift`/
`VaultBrowserView.swift` have each been touched by several recent, already-merged PRs
(passkey visibility, payment-card visibility, clipboard auto-clear) with their own
review at merge time. Left for a future cycle's re-survey rather than re-reading them
again today just to pad this list — the marginal value of a third read this same week is
low.

## Current state

Both `ROADMAP.md`'s "Now / next" lane and its "Needs maintainer/human action" section
remain empty. This cycle's audit covers effectively the entire security/correctness-
critical core of the codebase (`KeeBridgeCore` in full, `VaultProbe` in full,
`CredentialProviderViewController`, `VaultController`, `SafariWebExtensionHandler`, and
one representative app-layer view) with fresh adversarial eyes, on top of the narrower
survey #73 already did this same run. Still a caught-up backlog, not a stalled one.
