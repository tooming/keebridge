# Fix: an extremely small (but positive, finite) TOTP `period` still crashed `currentCode`

Twenty-sixth cycle this run. Found via a continued full-linear-file-read audit
(same technique as `#95`/`#99`/`#100`/`#102`, and cycle 24's `VaultController.swift`
read that found `#101`'s real bug) — this time `TOTPGenerator.swift` (166 lines).

## The bug

`parse(otpauthURI:)` already guards `period > 0` and `period.isFinite` — added in a
prior cycle specifically because `currentCode(for:at:)` force-converts
`timeIntervalSince1970 / period` to `UInt64`, and a non-positive or non-finite
period traps that conversion (an uncatchable Swift runtime crash, not a throwable
error) the next time the code is actually used, rather than at parse time. That
guard missed one member of the exact same failure class: a period that's positive
*and* finite but small enough that the division still overflows `UInt64.max`
(~1.8e19) before the conversion. For any realistic `Date` (2026's
`timeIntervalSince1970` ≈ 1.77e9), a period around `1e-10` or smaller is already
past that threshold — `otpauth://...&period=0.0000000001` parsed successfully,
then crashed the app/extension the moment that code was actually displayed or
autofilled, the same "sails through `parse()`, traps deep inside `currentCode`"
shape this file's own regression-test comments describe for the cases it already
covers.

## The fix

Tightened the guard from `period > 0` to `period >= 1` (still combined with
`period.isFinite`, needed independently since `+inf >= 1` is true). No real
`otpauth://` URI — RFC 6238's own default included — ever specifies a sub-second
period, so this rejects nothing meaningful while keeping the quotient for any
realistic date many orders of magnitude below the overflow ceiling.

## Verification

Added `rejectsPeriodTooSmallToAvoidUInt64Overflow` (a `period=0.0000000001` URI
must throw, not crash) and `acceptsPeriodAtTheOneSecondBoundary` (the new lower
bound doesn't reject a real period) to `TOTPGeneratorTests.swift` — this one *is*
covered by `swift test`/CI, unlike the app-layer fix two cycles ago, since
`TOTPGenerator` lives in the `KeeBridgeCore` SPM package.

## PR

See the PR that accompanies this file.
