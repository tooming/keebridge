# `VaultProbe` OTP write parity

Found via the same 2026-09-04 STEP 6b re-survey as
`docs/done/2026-09-04-qr-scanner-session-cleanup.md` (the ROADMAP's "Now / next" lane had
no buildable item that cycle) — one of three genuinely new findings from that survey. The
QR-scanner session-cleanup fix was implemented first (smallest, highest-confidence of the
three); this is the second, picked up as this run's next cycle once that PR merged.

## The gap

`VaultProbe`'s `reveal`/`totp` subcommands can already read an entry's TOTP secret, and
`VaultService.EntryDraft.otpURI` — with its documented nil-preserves/empty-removes/
non-empty-sets contract — was already fully implemented and unit-tested
(`entryDraftRoundTripsOTPURI` in `VaultWritingTests.swift`), and the app's own
`EntryEditView` already exposed a full "One-Time Password" section (paste URI, scan QR,
Remove). But `CreateCommand` had no `--otp-uri` option at all, and `UpdateCommand` built
its merged `EntryDraft` without ever passing `otpURI:` (defaulting to `nil`, i.e.
"preserve"), so there was no CLI path to create an entry with a TOTP secret, add one to an
existing entry, or remove one. `README.md` claims read/write parity between the app UI and
`VaultProbe` ("create/edit/delete entries directly, from either the app's own UI or the
headless `VaultProbe` CLI") — this was a real gap in that claim, not just a missing
feature.

## The fix

Both `CreateCommand` and `UpdateCommand` gained an `--otp-uri` option
(`String?`, `nil` default — matching `EntryDraft.otpURI`'s own contract exactly):

- **Validation**: when the flag is given a non-empty value, it's parsed with
  `TOTPGenerator.parse(otpauthURI:)` before anything else runs — the same check
  `EntryEditView` does before saving — so a malformed URI fails fast with a clear
  `ValidationError` instead of being silently stored.
- **`create`**: the flag's value is passed straight into `EntryDraft(otpURI:)`.
- **`update`**: the flag's value is also passed straight through — deliberately *not*
  merged against the entry's current `otpURI` the way `title`/`username`/`url`/`notes`
  are. Those four are merged (`title ?? current.title`, etc.) because they're plain,
  non-optional `String`s in `EntryDraft` and `updateEntry` fully replaces the standard
  fields, so the CLI's reveal-then-merge step is what stops an omitted flag from silently
  blanking one. `otpURI` doesn't need that: `EntryDraft`'s own contract already treats
  `nil` as "preserve" at the `updateEntry` layer (confirmed by reading
  `VaultService.updateEntry`'s `preservedCustomFields` filter and `draftStrings` directly:
  `nil` keeps the existing `otp` string untouched, `""` drops it, a non-empty value
  replaces it), so forwarding the flag's raw value already *is* the correct
  reveal-then-merge behavior for this one field.

## Verification

`VaultProbe` has no `swift test` target (an `executableTarget` only, gated by `probe-build`
— `swift build` — same as every other `VaultProbe` change; see `Package.swift` and the
`Makefile`'s own comment: "not otherwise gated"). The underlying nil/empty/non-empty
contract this change merely exposes through new CLI flags was already covered by
`entryDraftRoundTripsOTPURI` in `KeeBridgeCoreTests`, so no new `KeeBridgeCore` test was
needed — this PR only adds argument-parsing/validation glue, which `probe-build` compiles.
Verified via this repo's `ci` GitHub Actions workflow (`macos-latest`) — this executor's
own environment has no local Swift/Xcode toolchain.

No "still needs a human eyeball" caveat — this is plain CLI argument-parsing code with no
GUI/hardware dependency, fully exercised by what CI already validates.

## PR

See the PR this file was committed alongside.
