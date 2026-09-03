# Payment card visibility in the app's own secrets-management UI + VaultProbe

Discovered while re-surveying for new backlog items (STEP 6b — the "Now / next" lane had no
buildable code item this cycle: the automatic-password-save item (#33) stays blocked on a
missing Apple macOS API, and Proton Pass decommission (#5) is a human-only action). A fresh
read of the recently-Copilot-landed Safari card-autofill extension and `PaymentCard.swift`
turned up the same gap passkeys had before their own visibility fix: `KDBXCore` and the
Safari extension have full payment-card recognition (`PaymentCardField`,
`VaultService.listPaymentCards`/`revealPaymentCardFields`), but neither the app's own
secrets-management UI nor `VaultProbe` had any awareness of it — the only way to confirm an
entry was recognized as a card was reading the Safari extension's own picker.

## What changed

- `VaultLoginEntry.isPaymentCard` (new, defaults `false`) — set in
  `VaultService.listEntries` via the same `PaymentCardField.isRecognizedCard` conservative
  alias-based detection the Safari extension already uses. Never exposes a card field
  value.
- `PaymentCardField.displayName` (new) — human-readable label per field case ("Card
  Number", "CVV / Security Code", ...), for read-only UI/CLI display only.
- `VaultService.paymentCardMetadata(in:entryUUID:)` / `(at:masterPassword:entryUUID:)` (new)
  — per-entry counterpart to the existing vault-wide `listPaymentCards(in:)`, same
  metadata-only scope (title + which field *types* are present, never values).
- `VaultController.paymentCardMetadata(uuid:)` (new) — thin, synchronous, in-memory
  wrapper, same shape as the existing `passkeyMetadata(uuid:)`.
- `EntryDetailView`: a new "Payment Card" section, shown only when `entry.isPaymentCard`,
  listing which field types are present ("Card Number: Present", ...) — never a value.
- `VaultBrowserView`: a small `creditcard.fill` icon next to an entry's title in the list
  when it's recognized as a payment card, alongside the existing passkey icon.
- `VaultProbe`: `list` gains `isPaymentCard` (`--json`) / a `[card]` text marker; a new
  `card <uuid>` subcommand prints title + available field types, never values — same
  read-only scope as the existing `passkey` subcommand. Eight subcommands now
  (`list`/`reveal`/`totp`/`passkey`/`card`/`create`/`update`/`delete`).

## Why this scope, not more

Read-only visibility only, mirroring the passkey-visibility precedent exactly — no new
create/edit/reveal-value path for payment cards from the app or CLI. Card field *values*
stay reachable only through the existing, already-scoped-down paths
(`revealPaymentCardFields` for the Safari extension's request-scoped fill,
`VaultProbe reveal <uuid> <field-name>` for explicit single-field CLI inspection).

## Verification

`swift test` (KeeBridgeCoreTests, new `PaymentCardTests` cases: `isPaymentCard` flag via
`listEntries`, `paymentCardMetadata` by UUID, `displayName` strings) plus an unsigned
`xcodebuild` build covering `EntryDetailView`/`VaultBrowserView`'s compile correctness and
`VaultProbe`'s own `swift build` — validated via this PR's CI run (this executor's own
environment has no local Swift/Xcode toolchain to run `make ci` directly; see the PR for
the confirmed-green check run this was gated on before merge).

**Still needs a human eyeball**: the actual visual layout (icon choice/placement, section
wording) has never been seen rendered — no GUI in this executor's environment, same
limitation the passkey-visibility PR flagged for its own icon/section choices.

## PR

See the PR this file was committed alongside.
