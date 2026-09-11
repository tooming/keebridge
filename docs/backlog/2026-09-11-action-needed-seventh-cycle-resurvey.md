# [Action needed] Seventh cycle this run — card extension web surface re-read fresh, nothing new

Seventh cycle this run. Prior cycles landed three real fixes (#113 QR scanner sheet,
#114 TOTP algorithm validation, #116 unlock-prompt retry) and three honest re-surveys
(#112, #115, #117 — the last confirming #116's fix had no sibling instance elsewhere).

## What this seventh cycle checked

Applied this run's control-flow-ordering/error-path lens (the one that found #113 and
#116) to the card extension's web surface, last given a full read by a prior run's
cycle on 2026-09-08 (`docs/backlog/2026-09-08-action-needed-web-extension-audit.md`)
with a different focus (frame-trust guard, expiration-format synthesis, native-message
allowlist):

- **`content.js`** (325 lines) — re-read fully. `openPicker`'s three failure branches
  (`locked`/`missingMirror`/generic-unavailable) all leave a discoverable retry path
  (the trigger button stays visible; clicking it again re-opens the picker and retries
  `listCards`) — not a dead end the way `CredentialProviderViewController`'s pre-#116
  `showMessage` was, since there's no separate "cancel the whole request" concept here.
  `fillCard`'s failure path explicitly re-enables its button (`button.disabled =
  false`) for an in-place retry. `renderUnlock`'s "Open secure unlock page" success
  path closes the picker (correct — the actual unlock happens in a separate tab from
  here on, not this popover). Re-verified `formatValue`'s expiration disambiguation
  logic by hand once more (independently of `PaymentCard.swift`'s Swift-side
  counterpart, checked cycle four) — still correct for every realistic separator/order
  combination.
- **`background.js`** (21 lines) — re-read fully. The `unlock` action's sender-origin
  gate (`sender.url !== browser.runtime.getURL("unlock.html")`) still correctly means
  only the extension's own bundled unlock page — never `content.js` running on an
  arbitrary website — can ever send a raw vault password through
  `sendNativeMessage`.
- **`unlock.js`** — re-confirmed (already checked cycle six for the retry-flow lens
  specifically): a failed unlock attempt re-enables its submit button and returns
  focus to the password field, already the correct retry behavior.
- Fetched and re-grepped this run's own PR #116 CI build log for `warning:` — no new
  compiler warnings from that PR's `UnlockView`/`showUnlockPrompt` changes (the two
  pre-existing, deliberately-documented Sendable warnings from
  `SafariWebExtensionHandler.swift` are unrelated to this file and unaffected).

No new, confirmed, actionable finding.

## Current state

`ROADMAP.md`'s "Now / next" lane is fully checked off again after this run's three
real fixes; the one item under "Needs maintainer/human action" (`#77`) still
correctly needs a human. Filing this rather than fabricating an eighth "finding" from
nothing, per `routines/executor.prompt.md` STEP 6b.
