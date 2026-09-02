# Automatic password-save proposal (#33) — feasibility spike

Verdict: **not implementable on macOS today** — the API this feature would need is
explicitly unavailable on macOS in the current SDK, iOS/visionOS-only. This is a ROADMAP
refill (STEP 6b): "Now / next" had no other buildable code item this cycle (credit card
autofill implementation stays blocked on missing `xcodegen`; Proton Pass decommission is a
human-only action), so this newly-filed issue was investigated immediately rather than
just copied into the backlog unverified — same practice as every other spike in this
ROADMAP.

## What the issue asks for

#33: "automatic proposal of storing the password after logging into some new site" — the
same UX 1Password/Bitwarden/Safari's own AutoFill offer: after a successful login on a
site KeeBridge doesn't already have a saved credential for, proactively prompt to save the
new password into the vault, instead of requiring the user to add it by hand in
KeePassXC/the KeeBridge app.

## The relevant Apple API — and why it doesn't reach macOS

Apple added exactly this hook to `AuthenticationServices`:
`ASCredentialProviderViewController.prepareInterface(for: ASSavePasswordRequest)` and
`performWithoutUserInteractionIfPossible(savePasswordRequest:)`, plus a matching
`ASSavePasswordRequest` type (`credential`, `serviceIdentifier`, `sessionID`, `event`,
`title`, `passwordKind`). The system is meant to create one of these requests when it
detects a successful login with a password worth saving, and hand it to whichever
credential provider extension the user has chosen.

Checked directly against Apple's SDK availability annotations (via the `dotnet/macios`
binding project, which tracks `API_AVAILABLE`/`API_UNAVAILABLE` macros straight from
Apple's headers — https://github.com/dotnet/macios/wiki/AuthenticationServices-iOS-xcode26.2-b1):

```
performSavePasswordRequestWithoutUserInteractionIfPossible:
  API_AVAILABLE(ios(26.2), visionos(26.2))
  API_UNAVAILABLE(macos, tvos, watchos)
```

**`API_UNAVAILABLE(macos, ...)`** — this hook, and by extension `ASSavePasswordRequest`
itself, is explicitly not available on macOS at all, only iOS and visionOS. KeeBridge's
`KeeBridgeProvider` target is a native macOS Credential Provider Extension (not Mac
Catalyst, not iOS) — there is no code KeeBridge could write today, on any macOS version,
that receives this callback. This is the same category of platform-boundary finding as
the QR/hybrid-transport spike immediately before this one
(`docs/done/2026-09-01-passkey-qr-hybrid-transport-spike.md`) and the AAGUID-zeroing
finding from the original passkey design spike: something Apple's own
`AuthenticationServices` framework does for one platform (here, iOS/visionOS) but not the
other (macOS), regardless of what KeeBridge's own code does.

## Why this isn't the same as "genuinely hard to verify headlessly"

Every other headless-verification caveat in this ROADMAP (passkey assertion, passkey
registration) is about code KeeBridge *can* write but this executor's environment can't
exercise end-to-end. This is different: there is currently no macOS-side entry point to
call at all. A future macOS SDK could add one (the naming and shape of the iOS/visionOS
API make an eventual macOS counterpart plausible, unlike the BLE hybrid-transport case,
which is blocked by a different, more fundamental `CoreBluetooth` restriction) — this
should be re-checked whenever the project next bumps its minimum macOS deployment target,
not treated as permanently closed the way the QR spike's finding is.

## What KeeBridge already has toward this

None of this blocks the *value* the issue is after — the underlying write path
(`VaultService.createEntry`) already exists and is exercised by both the app's UI and
`VaultProbe`'s CLI. The only missing piece really is the *system-level trigger* (being
told when a new login just happened) — which currently has no macOS API to hook into.

## Recommendation

Keep this open in `ROADMAP.md` as investigated-but-blocked (not a human-action item like
Proton Pass, and not a code task to pick up next cycle like credit card autofill) — revisit
the availability check the next time this project's `MACOSX_DEPLOYMENT_TARGET`
(`project.yml`) moves forward, in case a macOS equivalent has shipped by then.

## PR

See the PR this file was committed alongside.
