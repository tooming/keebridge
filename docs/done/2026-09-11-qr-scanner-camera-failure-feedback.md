# QR scanner's camera-setup failures left a silent, blank sheet open

## The bug

`docs/done/2026-09-11-qr-scanner-invalid-code-sheet-close.md` fixed the case
where the QR scanner recognized a code that wasn't a valid TOTP setup URI —
before that fix, the scanner sheet stayed open on a frozen, dead camera
preview with no way to retry short of Escape. This cycle found a sibling
dead end one step earlier in the same flow: `QRCodeCameraPreview.
configureCamera()` has four places where camera setup can fail —

1. `AVCaptureDevice.requestAccess(for: .video)` completes with `granted ==
   false` (the user denied camera access, or hasn't been asked yet and
   declines the system prompt).
2. `AVCaptureDevice.default(for: .video)` returns `nil` (no camera on this
   Mac at all).
3. `try? AVCaptureDeviceInput(device: device)` fails.
4. `session.canAddInput(input)` or `session.canAddOutput(output)` returns
   `false`.

Every one of these just `return`ed with no further action. The scanner sheet
(`QRCodeScannerView`, 480×360, no Cancel button by design — see the existing
comment on the invalid-code fix) stayed open showing a permanently blank
`NSView`: no camera feed, no error text, nothing. This is a real, reachable
first-use path, not a rare edge case: anyone who clicks "Scan QR Code…"
before ever granting this app Camera access — the common case, since nothing
in the app requests that access proactively — hits case 1 immediately, with
zero indication of what went wrong or what to do about it. The only way out
was guessing to press Escape or click outside the sheet.

## The fix

Threaded a new `onFailure: (String) -> Void` closure alongside the existing
`onCode` through `QRCodeScannerView` → `QRCodeCameraView` (the
`NSViewRepresentable`) → `QRCodeCameraPreview` (the `NSView` itself), and
call it with a specific message at each of the four failure branches instead
of a silent `return`. `EntryEditView`'s `.sheet` closure for `onFailure`
closes the sheet and sets the existing `otpError` state — the exact same
dismiss-and-explain mechanism the invalid-QR-code fix already uses for its
own alert, so this reuses `EntryEditView`'s existing `.alert(...)` rather
than adding a second one.

`didScan` (already existed, for the metadata-output delegate) is also
checked before calling `onFailure`, as cheap insurance against ever firing
both `onCode` and `onFailure` for the same sheet — not something the current
code path can actually reach (nothing in `configureCamera()`'s completion
handler runs again after a scan succeeds), but a one-line guard costs
nothing and rules it out structurally rather than by inspection alone.

## Verification

Compiled-only (`xcodebuild build`, unsigned, via CI's `macos-latest`
runner) — this executor has no local Swift toolchain, GUI, or camera
hardware. `EntryEditView.swift` has no test target (SwiftUI view code +
`AVCaptureSession`, and simulating camera-permission states isn't practical
headlessly) — same limitation the invalid-QR-code fix already noted.

Still needs a human eyeball: confirming each message reads correctly in
context and that the sheet actually closes (rather than, say, silently
retrying) when camera permission is denied on real hardware.
