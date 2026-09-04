# `TOTPGenerator.parse` didn't validate `digits`/`period`, letting a malformed otpauth:// URI crash the process later

Found via a second, adversarial re-survey pass this run (after the first pass's three
findings — QR-scanner session cleanup, `VaultProbe` OTP write parity, PaymentCard
expiration-synthesis test coverage — all shipped and merged, closing out that survey's
findings). This pass specifically re-read already-visited `KeeBridgeCore`/extension files
hunting for logic bugs and edge cases rather than "what's missing" — see this file's PR
for the other two findings that survey turned up (a card-autofill origin-binding security
gap, and a plausible-but-unconfirmed instance-vs-static cache bug in
`SafariWebExtensionHandler`), both queued as new `ROADMAP.md` items rather than shipped
this cycle.

## The bug

`TOTPGenerator.parse(otpauthURI:)` parsed `digits` and `period` from the URI's query
string with a silent numeric fallback and **no range check**:

```swift
let digits = Int(query["digits"] ?? "") ?? 6
let period = TimeInterval(query["period"] ?? "") ?? 30
```

Both feed math in `currentCode(for:at:)`/`code(for:counter:)` that traps — a Swift runtime
crash, not a throwable error, so no surrounding `do`/`catch` can stop it — on
out-of-range input:

- `period <= 0` (or the non-finite values `TimeInterval("inf")`/`TimeInterval("nan")`
  parse to successfully, which a naive `?? 30` fallback does **not** catch since parsing
  those strings doesn't fail): `UInt64(date.timeIntervalSince1970 / parameters.period)`
  converts an infinite or NaN `Double` to `UInt64`, which traps.
- `digits <= 0`: `pow(10.0, Double(digits))` yields `0` or a fraction, so `modulus` becomes
  `0`, and `truncated % modulus` traps (division/modulo by zero).
- `digits >= 10`: `10^digits` exceeds `UInt32.max` (10^9 fits, 10^10 doesn't), so
  `UInt32(pow(10.0, Double(digits)))` traps (out-of-range `Double`-to-`UInt32`
  conversion).

Every existing call site treats a successful `parse()` as "this OTP URI is safe to
store" — `EntryEditView.swift`'s QR-scan acceptance and manual-save validation
(`try? TOTPGenerator.parse(...) != nil`), `VaultProbe`'s `promptAndValidateOTPURI`, and
`VaultService.setOTP`'s own validation path all only check that parsing succeeds. A
malformed or adversarial `otpauth://` URI (a plausible real vector — a printed or posted
"scan to add 2FA" QR code someone scans in good faith) with e.g. `period=0` or
`digits=10` would sail through every one of those checks, get persisted into the vault,
and then crash whichever process next tries to actually compute a code for it:
`KeeBridgeProvider/CredentialProviderViewController.swift`'s `completeOTPCredential`
(crashing the credential-provider extension mid-autofill, inside a `do`/`catch` that
cannot stop a trap), `VaultProbe`'s `totp` subcommand, or the app's own UI if the code is
ever displayed live.

`TOTPGeneratorTests.swift` had zero coverage for `digits`/`period` out of range before
this fix — only the RFC 6238 test vectors and default-parameter cases were tested,
confirming the gap was real, not just theoretical.

## The fix

`parse()` now validates both immediately after resolving them (whether from an explicit
query value or the RFC 6238/Google Authenticator default):

- `digits` must be in `1...9` — 9 is the largest digit count whose `10^digits` modulus
  still fits `UInt32` (`code(for:counter:)`'s modulus math). Two new `TOTPError` cases,
  `.invalidDigits`/`.invalidPeriod`, both with a descriptive `CustomStringConvertible`
  message (matching this type's existing error-message convention).
- `period` must be `> 0` **and** `.isFinite` — the explicit `isFinite` check matters
  because `period > 0` alone doesn't reject `+infinity` (it's greater than zero), and
  Foundation's `TimeInterval(String)` initializer successfully parses the literal
  strings `"inf"`/`"nan"` to non-finite `Double`s, so those need catching separately
  from a plain range comparison.

No caller changes were needed — every existing call site was already either
`try`-propagating (so it now correctly throws instead of crashing) or `try?`-checking for
`nil` (so it now correctly rejects the malformed URI instead of accepting it and deferring
the crash to later). This is a pure strengthening of `parse()`'s own contract, fully
backward-compatible with every valid URI already in use.

Six new `@Test` cases in `TOTPGeneratorTests.swift`: the `digits == 9` boundary (accepted),
`digits == 10` (rejected), `digits` zero/negative (rejected), `period` zero/negative
(rejected), and `period` as the literal strings `"inf"`/`"-inf"`/`"nan"` (rejected) —
confirming the exact non-finite-string-parsing gap a naive fallback would have missed.

## Verification

`swift test`, via this repo's `ci` GitHub Actions workflow (`macos-latest`) — this
executor's own environment has no local Swift/Xcode toolchain. No "still needs a human
eyeball" caveat — this is pure `KeeBridgeCore` logic with full headless test coverage
(including the exact trap conditions this fix closes), no GUI or hardware dependency.

## PR

See the PR this file was committed alongside.
