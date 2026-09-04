# `TOTPGenerator.parse`'s `.invalidURI`/`.invalidBase32Secret` error branches had zero test coverage

Found via a third survey pass this run — a doc-accuracy/test-coverage lens, distinct from
the two earlier adversarial-logic-bug passes that already closed out six other findings
this cycle (see `docs/done/2026-09-04-totp-parse-digits-period-validation.md`,
`docs/done/2026-09-04-card-picker-cross-origin-iframe-block.md`,
`docs/done/2026-09-04-card-extension-static-cache.md`, and the earlier first-pass trio).

## The gap

`TOTPError` has six cases: `invalidURI`, `unsupportedType`, `missingSecret`,
`invalidBase32Secret`, plus `invalidDigits`/`invalidPeriod` (added earlier this run, with
thorough regression tests — see the digits/period fix's own record). Before this change,
`TOTPGeneratorTests.swift` covered `unsupportedType` (`rejectsNonTotpURI`, a
scheme-`otpauth`-but-host-`hotp` URI) and `missingSecret` (`rejectsMissingSecret`), but
had zero tests exercising `invalidURI` (a scheme that isn't `otpauth` at all — the
*first* guard in `parse()`, distinct from `unsupportedType`'s second guard) or
`invalidBase32Secret` (a `secret=` value containing characters outside this type's Base32
alphabet).

This sits right next to the digits/period crash fix this run already made to the same
function, on the same class of code (secret-parsing input validation reachable from every
OTP write/read path: `EntryEditView`'s QR-scan and manual-entry validation, `VaultProbe`'s
`promptAndValidateOTPURI`, `VaultService`'s OTP handling). Unlike digits/period, these two
branches don't crash — both cleanly `throw` — so this isn't a bug fix, it's closing a
coverage gap on exactly the kind of code this ROADMAP already treats as worth verifying
thoroughly.

## The fix

Two new `@Test` cases in `TOTPGeneratorTests.swift`, no production code changed (the
existing guards were already correct):

- `rejectsNonOtpauthScheme` — a `https://totp/...` URI (scheme isn't `otpauth`), which
  exercises the *first* `guard` in `parse()` (`components.scheme == "otpauth"`),
  distinct from the already-tested `rejectsNonTotpURI` (scheme is `otpauth`, host isn't
  `totp` — the *second* guard).
- `rejectsInvalidBase32Secret` — a `secret=11118` value. `1` isn't in this type's Base32
  alphabet (RFC 4648's is A–Z and 2–7; the digits 0/1/8/9 are deliberately excluded to
  avoid visual confusion with O/I/B/S/Z in real authenticator apps), so `base32Decode`
  returns `nil` and `parse()` must throw rather than silently produce a garbage or empty
  secret.

## Verification

`swift test`, via this repo's `ci` GitHub Actions workflow (`macos-latest`) — this
executor's own environment has no local Swift/Xcode toolchain. No "still needs a human
eyeball" caveat — pure `KeeBridgeCore` logic with full headless test coverage, no GUI or
hardware dependency.

## PR

See the PR this file was committed alongside.
