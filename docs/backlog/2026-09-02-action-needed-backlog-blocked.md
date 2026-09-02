# [Action needed] Every remaining `ROADMAP.md` item needs maintainer input, not more code

**Updated 2026-09-02 (later the same day)**: since this file was first filed, a *second*
executor run picked up where the first left off and found four more genuinely new,
buildable things this backlog had missed — conditional/silent passkey registration
(`performWithoutUserInteractionIfPossible(passkeyRegistration:)`, #4), passkey visibility
in `VaultProbe` (the CLI), and a `README.md` accuracy refresh (on top of finishing the
first run's own stale, unmerged self-review). None of that invalidates this file's core
finding, though — after all of that *additional* work, a fresh re-survey (same method:
open issues, TODO/FIXME grep, a re-read of every previously-unexamined source file) still
turns up nothing further. The four items below remain exactly as blocked as when this file
was first written; only the "how much has already shipped" framing needed updating.

Original framing, still accurate: this run landed several PRs (a WebAuthn credential-ID
primitive, full passkey registration wiring, a QR/hybrid-transport feasibility spike, an
automatic-password-save feasibility spike, passkey visibility in the app's own UI) before
this file was first written, and several more since (conditional passkey registration,
`VaultProbe` passkey visibility, the README refresh). After all of that, every remaining
unchecked item in `ROADMAP.md`'s "Now / next" lane is genuinely blocked on something this
executor cannot resolve by writing more code — not a shortage of effort, a real external
dependency each one is waiting on. Re-surveyed open issues (unchanged since first written),
grepped for TODO/FIXME (still none), and re-read every previously-unexamined file,
including this run's own newly-touched ones (`VaultProbe.swift`, `KeeBridgeConfig.swift`,
`EntryEditView.swift`, `README.md` itself) — nothing new turned up this time. Per STEP 6b:
an honest status update beats fabricating make-work.

## What's blocked, and what would unblock each one

1. **Credit card autofill implementation (#3)** — needs a brand-new Xcode target (a Safari
   Web Extension), which needs `xcodegen` to regenerate `KeeBridge.xcodeproj` from
   `project.yml` after adding one. Confirmed (again, this run) that `xcodegen` is not
   available in this executor's environment: `which xcodegen` → nothing, and the checked-in
   `project.pbxproj` uses the classic explicit `PBXFileReference`/`PBXBuildFile` format (no
   modern synchronized-folder groups), so hand-editing it to add a whole new target's build
   phases, with no way to validate the result short of a real Xcode install, isn't a risk
   worth taking headless.
   **Unblocks with**: either `xcodegen` becoming available in this executor's environment,
   or the maintainer adding the new Safari Web Extension target once, by hand, in real
   Xcode — after that, the scoped first PR (mirroring card entries into the new target's
   container) is safe to build headlessly, same as everything else in this repo.
   **Also still unresolved** (needs the maintainer regardless of the tooling question): the
   actual field-name convention the 9 real card entries use.

2. **Automatic password-save proposal (#33)** — the API this needs
   (`ASCredentialProviderViewController.prepareInterface(for: ASSavePasswordRequest)`) is
   `API_UNAVAILABLE(macos, tvos, watchos)` in Apple's own SDK — iOS/visionOS 26.2+ only, no
   macOS entry point exists at all (see
   `docs/done/2026-09-02-save-password-proposal-feasibility-spike.md`).
   **Unblocks with**: Apple shipping a macOS counterpart to this API in some future SDK.
   Nothing to do until then — flagged to re-check whenever the project's
   `MACOSX_DEPLOYMENT_TARGET` next moves forward. Not something the maintainer needs to act
   on now.

3. **Decommission Proton Pass — final migration step (#5)** — an interactive, local-machine
   action (Safari → Settings → Extensions to disable Proton Pass's Safari Web Extension,
   `pluginkit -m -v` to confirm no stale registration remains, deciding whether to keep or
   cancel the Proton Pass account). The headless executor cannot open Safari Settings or run
   `pluginkit` against the maintainer's own session.
   **Unblocks with**: the maintainer doing this by hand, at their convenience — password +
   TOTP autofill via KeeBridge is already confirmed working end-to-end, so this is cleanup,
   not a blocker for anything else.

4. **QR code scanning for adding a passkey (#7)** — for completeness: already investigated
   and closed as a permanent platform-level dead end (`CoreBluetooth` doesn't let any
   third-party app advertise the BLE service data WebAuthn hybrid transport needs — see
   `docs/done/2026-09-01-passkey-qr-hybrid-transport-spike.md`). Not actionable by anyone,
   maintainer included, short of Apple changing that API surface.

## The bigger picture: passkey support (#4) is now substantially complete

Worth calling out explicitly since it's been the bulk of this ROADMAP's recent work: the
core passkey feature (storage convention, read/write metadata, P-256 crypto primitives,
COSE encoding, `authenticatorData`/`attestationObject`, credential ID generation,
assertion/sign-in, both interactive AND conditional/silent registration, extension→app
write-back safety, and read-only visibility in both the app's own UI and the `VaultProbe`
CLI) is done — and `README.md` now says so accurately instead of still listing it as
future work. What remains passkey-adjacent (QR/hybrid-transport, the 9
Proton-Pass-carried passkeys' proprietary format) is either permanently blocked (item 4
above) or explicitly optional/lower-priority per the original design spike's own
recommendation — not release-blocking.

**Everything shipped this cycle still carries its own "needs a human eyeball" caveat** —
passkey registration in particular flips a real, live capability (`ProvidesPasskeys: true`)
that has never been exercised against a real Safari passkey-creation flow on real hardware,
since this executor's environment has no GUI, Touch ID, or macOS toolchain at all. Worth
prioritizing over any of the blocked items above whenever the maintainer next has hands-on
time with the app.

## Not a code problem

None of the four items above have a code path this executor could take today that wouldn't
either be guesswork on a genuinely unresolved question (the card field-name convention),
a fabricated workaround for a real platform restriction, or literally impossible to do
headlessly (an interactive Safari Settings action). Filing this rather than churning on a
non-problem.
