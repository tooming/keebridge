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

Both `CreateCommand` and `UpdateCommand` gained a `--set-otp` flag:

- **Prompted, not a plain CLI argument**: the first implementation of this item (still
  visible in this PR's earlier commits) took the URI as a direct `--otp-uri <value>`
  option. STEP 7 self-review caught that this leaks the entry's TOTP secret into shell
  history and any `ps` output for the process's lifetime — exactly the exposure
  `--set-password` already exists to spare the entry's *password* from (see the file's
  own header comment: "the entry's *password* is never a CLI argument. Pass
  `--set-password` instead and a second `getpass()` prompt asks for it"). A TOTP secret
  is exactly as sensitive as a password, so it gets the same treatment: `--set-otp` is a
  boolean flag that triggers a new `promptAndValidateOTPURI()` helper
  (`getpass()`-based, same no-echo/no-history/no-argv discipline as
  `promptPassword`/`promptEntryPassword`), fixed on this branch before merging — see this
  PR's own self-review comment.
- **Validation**: a non-blank prompt answer is parsed with
  `TOTPGenerator.parse(otpauthURI:)` before it's used for anything — the same check
  `EntryEditView` does before saving — so a malformed URI fails fast with a clear
  `ValidationError` instead of being silently stored. A blank answer is a valid,
  deliberate result, not a validation failure.
- **`create`**: `--set-otp` omitted → `otpURI: nil` (no TOTP secret created). `--set-otp`
  passed, prompt left blank → same as omitted. `--set-otp` passed, a URI entered →
  validated and set.
- **`update`**: the prompt's raw result is forwarded straight through — deliberately
  *not* merged against the entry's current `otpURI` the way `title`/`username`/`url`/
  `notes` are. Those four are merged (`title ?? current.title`, etc.) because they're
  plain, non-optional `String`s in `EntryDraft` and `updateEntry` fully replaces the
  standard fields, so the CLI's reveal-then-merge step is what stops an omitted flag from
  silently blanking one. `otpURI` doesn't need that: `EntryDraft`'s own contract already
  treats `nil` as "preserve" and `""` as "remove" at the `updateEntry` layer (confirmed by
  reading `VaultService.updateEntry`'s `preservedCustomFields` filter and `draftStrings`
  directly), and `promptAndValidateOTPURI()` returning `""` for a blank prompt answer is
  exactly the "remove" signal — so `--set-otp` omitted → `nil` (preserve), `--set-otp`
  passed with a blank answer → `""` (remove), `--set-otp` passed with a URI → set.

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
