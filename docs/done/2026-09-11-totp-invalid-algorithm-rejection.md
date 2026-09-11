# `TOTPGenerator.parse`'s `algorithm` parameter silently fell back to SHA1 instead of rejecting an unrecognized value

Found via a fresh, adversarial re-read of `TOTPGenerator.swift` this cycle, applying the
same lens the earlier `digits`/`period` validation fixes in this exact file already used.

## The bug

```swift
let algorithm = TOTPParameters.HMACAlgorithm(rawValue: (query["algorithm"] ?? "SHA1").uppercased()) ?? .sha1
```

The `?? .sha1` at the end silently coerced ANY unrecognized `algorithm=` value to SHA1 —
not just when the key was absent (the intended RFC 6238/Google Authenticator default
behavior), but also when the key was **present** and named something other than
`SHA1`/`SHA256`/`SHA512` (a typo, a nonstandard export, or an adversarial/malformed QR
code). This is the exact same silent-fallback-on-an-out-of-range-but-present-value shape
`digits`/`period` were already fixed for in this file (see
`docs/done/2026-09-04-totp-parse-digits-period-validation.md`) — a `?? default` that
swallows a genuinely-provided-but-invalid value instead of rejecting it.

Unlike `digits`/`period`, this doesn't crash the process — it silently generates TOTP
codes against the WRONG algorithm for whatever the URI actually specified. The visible
symptom is a 2FA code that mysteriously fails to validate against the real service, with
nothing in KeeBridge telling the user why: the entry looks like it has a valid TOTP setup
(`parse()` succeeded), but the codes it produces are simply wrong.

## The fix

`algorithm`'s absent-key default (SHA1) is preserved, but a present-and-unrecognized value
now throws `TOTPError.invalidAlgorithm(String)` instead of silently downgrading to SHA1:

```swift
let algorithmRaw = (query["algorithm"] ?? "SHA1").uppercased()
guard let algorithm = TOTPParameters.HMACAlgorithm(rawValue: algorithmRaw) else {
    throw TOTPError.invalidAlgorithm(algorithmRaw)
}
```

Every existing call site of `TOTPGenerator.parse` already treats it as throwing
(`try`/`try?`) and doesn't pattern-match on specific `TOTPError` cases — `VaultService
.setOTP`, `VaultProbe`'s `promptAndValidateOTPURI`, and `EntryEditView`'s QR-scan/manual-
save validation all already reject any failed parse the same way, so this needed no
caller changes, same as the digits/period fix before it.

## Related coverage gap closed alongside it

While adding a rejection test for this, found that no existing test ever exercised
parsing an EXPLICIT `algorithm=SHA256`/`SHA512` value at all — every prior test either
omitted the parameter (exercising only the default-to-SHA1 path) or constructed
`TOTPParameters` directly with `.sha1`. Four new `@Test` cases in
`TOTPGeneratorTests.swift`: explicit `SHA256`, explicit `SHA512`, a lowercase algorithm
name (`sha256`, confirming the `.uppercased()` normalization still works), and the new
rejection (`algorithm=MD5`).

## Verification

`swift test`/CI-covered — this is a pure `KeeBridgeCore` logic change with full unit-test
coverage, same validation strength as the digits/period fix it mirrors.

## PR

See the PR this cycle opened (self-merged per `docs/WAYS-OF-WORKING.md` §0.1).
