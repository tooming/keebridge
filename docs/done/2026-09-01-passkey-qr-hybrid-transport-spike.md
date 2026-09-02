# QR code scanning for adding a passkey (#7) — feasibility spike

Verdict: **not implementable by KeeBridge** as a third-party macOS Credential Provider
Extension, due to an Apple platform restriction, not a KeeBridge design choice or missing
tooling (contrast with the credit card autofill spike, which found a still-viable
alternative path — this one doesn't).

## What "QR code scanning" actually means here

Issue #7: "Some websites provide QR codes for adding the passkey." This describes WebAuthn
**hybrid transport** (formerly "caBLE") — the mechanism behind "Sign in with a passkey on
another device": a relying party's page (often on a *different* computer or browser)
displays a QR code; a phone that already holds the passkey scans it with its camera, then
completes the ceremony over a Bluetooth Low Energy (BLE) tunnel to the device showing the
QR code (spec: WebAuthn Level 3 / CTAP 2.2 hybrid transport).

For KeeBridge to "support scanning it," KeeBridge itself would need to act as the
**scanning/authenticator side** of this flow on macOS: decode the QR code (fine, ordinary
camera/image work) and then open a BLE connection advertising the CTAP2 hybrid service
data the relying party's page is listening for, to complete the handshake and sign the
assertion with a vault-stored passkey.

## The actual blocker: BLE service-data advertising is not available to third-party apps

The hybrid/caBLE handshake requires the scanning device to **advertise raw CTAP2-specific
BLE service data** (a service UUID plus a specific data payload identifying the tunnel).
On iOS/macOS, `CoreBluetooth`'s `CBPeripheralManager.startAdvertising(_:)` does not support
this: apps can only advertise `CBAdvertisementDataLocalNameKey` and
`CBAdvertisementDataServiceUUIDsKey` — **not** `CBAdvertisementDataServiceDataKey`, which is
exactly the field CTAP2 hybrid transport needs to carry its payload. Confirmed via Apple's
own Developer Forums (a third-party developer asking this exact question, and getting the
same answer: `CBPeripheralManager` cannot emit the raw bytes a CTAP hybrid advert needs —
https://forums.developer.apple.com/forums/thread/672836). This isn't a workaround-able gap
in a specific API version; it's a deliberate restriction on what `CoreBluetooth` exposes to
any third-party app on these platforms, credential provider extension or not.

This is the same *category* of platform restriction the passkey design spike already found
for AAGUID (macOS silently zeroes a third-party Credential Provider Extension's AAGUID —
Developer Forums thread 814547, referenced in `docs/done/2026-08-26-passkey-design-spike.md`):
Apple's own iCloud Keychain gets system-level capabilities a third-party extension
structurally cannot reach, regardless of entitlements requested or code written. Hybrid
transport (and by extension, its QR-code initiation step) appears to be reserved for
iCloud Keychain's own system-level implementation, not something
`ASCredentialProviderViewController`-based extensions can participate in as the
authenticator side.

## Why this isn't "hard, so skip it" — it's structurally unreachable

To be clear about the distinction from every other ROADMAP item flagged "hard to verify
headlessly": those (assertion wiring, registration wiring) are things KeeBridge's code
*can* do, just not something this headless executor can *test* without real hardware.
Hybrid transport is different — there is no code KeeBridge could write, with any amount of
entitlements or real-hardware testing, that would let a third-party `CBPeripheralManager`
advertisement carry the payload CTAP2 hybrid transport requires. The constraint is in the
platform API surface itself, not in KeeBridge's implementation or this executor's
environment.

## What KeeBridge already covers instead

KeeBridge's passkey feature (assertion + registration, both landed) already handles the
*same-device* passkey flows entirely — signing in with, and creating, a passkey directly
on the Mac KeeBridge runs on, which is the common case this project's own use (a personal
password-manager replacement, not a cross-device sync product) actually needs. Hybrid
transport specifically matters when authenticating *from* a device that doesn't have the
passkey locally (e.g. signing into a site on a friend's computer using your phone) — a
different use case from KeeBridge's core one.

## Recommendation

Retire this item as "investigated, not buildable" rather than leave it perpetually
blocked-looking in the backlog. No further KeeBridge-side design work is worth spending on
this unless Apple's `CoreBluetooth`/`AuthenticationServices` APIs change to expose hybrid
transport participation to third-party credential providers. Left a comment on #7 with
this finding for the maintainer's final call on whether to close it (not closed
automatically by this spike — the finding is about a specific implementation path being
blocked, not a judgment call this executor should make unilaterally about the issue
itself).

## PR

See the PR this file was committed alongside.
