# README accuracy refresh (clipboard auto-clear + payment-card app-UI visibility, undocumented since shipping)

Fourth cycle this run, discovered via a STEP 6b re-survey after three audit-only cycles
(#76, #78, #79) found nothing else in the "Now / next" lane (still empty) or turned up a
genuinely new implementable item to add there. `README.md` was last touched 2026-09-02
(#46) — six days and roughly two dozen merged PRs ago (#56 through #79) — so it was worth
checking whether "What works today" had fallen behind again, the same class of gap the
2026-09-02 README refresh (`docs/done/2026-09-02-readme-accuracy-refresh.md`) fixed once
already.

Two real, shipped, user-facing behaviors turned up missing from the README:

- **Clipboard auto-clear** (#62, `docs/done/2026-09-05-clipboard-auto-clear.md`): copying
  a password from the app's entry detail view clears it from the system pasteboard after
  30 seconds, guarded by `NSPasteboard.changeCount` so it only clears if nothing else has
  overwritten the pasteboard since — a real security behavior a reader evaluating this app
  against "every other password manager in KeeBridge's own stated competitive set" (the
  original PR's own framing) would want to know is already there. Not mentioned anywhere
  in the README.
- **Payment-card visibility in the app UI / `VaultProbe`** (#3xx-era work, see
  `docs/done/2026-09-03-payment-card-visibility-in-app-ui.md`): entries recognized as
  payment cards are visible read-only (never a field value) in the app's own
  secrets-management UI and in `VaultProbe`, mirroring the passkey visibility feature the
  README already documents ("visible read-only in both the app UI and `VaultProbe`") —
  but the README's payment-cards bullet only described the Safari extension flow, not this
  app-UI/CLI visibility.

## What changed

Two bullet edits in `README.md`'s "What works today" list:

- The secrets-management-UI bullet gained a sentence describing the clipboard auto-clear
  behavior and the non-secret-field exception (username/URL/passkey metadata still copy
  without auto-clear, same distinction the app already draws everywhere else).
- The payment-cards bullet gained a clause noting card-recognized entries are visible
  read-only in the app UI and `VaultProbe`, phrased to parallel the existing passkey
  bullet's wording.

No code touched — verified both claims against the actual shipping code before writing
them (`EntryDetailView.swift`'s `copyToPasteboard(_:autoClearAfter:)` per #62's own
`docs/done` record, and `VaultLoginEntry.isPaymentCard`/`PaymentCardField.displayName`
per the payment-card-visibility record) rather than restating PR titles from memory.

Nothing else in "What works today" was found stale this pass — vault write support,
TOTP/QR import, passkeys, the Safari card-autofill flow itself, and independent Touch ID
unlock all still read accurately against current behavior.

## PR

See the PR that shipped this change for the PR number/URL.
