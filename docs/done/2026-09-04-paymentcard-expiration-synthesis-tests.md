# Test coverage for `PaymentCard.revealPaymentCardFields`'s split-field → combined `.expiration` synthesis branch

Found via the same 2026-09-04 STEP 6b re-survey as
`docs/done/2026-09-04-qr-scanner-session-cleanup.md` and
`docs/done/2026-09-04-vaultprobe-otp-write-parity.md` (the ROADMAP's "Now / next" lane had
no buildable item that cycle) — the third and last of three genuinely new findings from
that survey.

## The gap

`VaultService.revealPaymentCardFields` synthesizes a requested field from related stored
fields in two directions when it isn't stored directly:

1. Combined `Expiration Date` field → split `.expirationMonth`/`.expirationYear`, via
   `Self.paymentCardExpirationParts(expiration)`. Already tested —
   `paymentCardListingIsMetadataOnlyAndRevealIsRequestScoped` requests
   `.expirationMonth` against an entry that only has an `expirationDate` field.
2. Split `Expiration Month`/`Expiration Year` fields → combined `.expiration`
   (`result[field] = "\(month)/\(year)"`). **Not tested at all**, in either the happy
   path or the case where only one of the two split fields is present.

Direction 2 is live, secret-touching, extension-reachable code —
`KeeBridgeCardExtension`'s `content.js` requests `"expiration"` for any field matching
`autocomplete="cc-exp"`, which routes into exactly this code path for any card stored with
separate month/year fields (a plausible real import shape, e.g. some exports split them).
This repo's own convention (see the `updateEntry` custom-field data-loss fix) is to treat
an untested branch of secret/write-adjacent code as worth closing on sight, not just
noting.

## The fix

Two new `@Test` cases added to `PaymentCardTests.swift`, following this file's existing
patterns exactly (a throwaway in-memory `KDBXContent`, fake test card numbers already used
elsewhere in this file — never real card data):

- `revealPaymentCardFieldsSynthesizesCombinedExpirationFromSplitFields` — an entry with
  `Card Number`, `Expiration Month: "04"`, `Expiration Year: "2029"` but no combined
  `Expiration Date` field; requesting `.expiration` returns `"04/2029"`.
- `revealPaymentCardFieldsOmitsCombinedExpirationWhenOnlyOneSplitFieldIsPresent` — an
  entry with `Card Number` and `Expiration Month` only (still recognized as a card, since
  `isRecognizedCard` only needs `.number` plus any one of
  `.expiration`/`.expirationMonth`/`.expirationYear`/`.verificationCode`); requesting both
  `.expiration` and `.expirationMonth` confirms `.expiration` is correctly omitted (the
  `if let month = ..., let year = ...` guard's both-or-nothing behavior means no malformed
  `"04/"` value is ever emitted) while `.expirationMonth` still resolves directly.

No production code changed — the existing synthesis logic was already correct; it simply
had no test proving so.

## Verification

`swift test` (via this repo's `ci` GitHub Actions workflow, `macos-latest` — this
executor's own environment has no local Swift/Xcode toolchain). No "still needs a human
eyeball" caveat — this is pure `KeeBridgeCore` logic with full headless test coverage, no
GUI or hardware dependency.

## PR

See the PR this file was committed alongside.
