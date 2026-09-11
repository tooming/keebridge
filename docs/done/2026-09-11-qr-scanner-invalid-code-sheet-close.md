# QR scanner sheet stayed open, with a dead camera feed, after an invalid scan

`EntryEditView`'s "Scan QR Code…" flow (used to add/replace an entry's TOTP setup URI)
left its scanner sheet open — showing a frozen, black camera preview — after
recognizing a QR code that wasn't a valid `otpauth://` setup URI. Found via a fresh,
adversarial re-read of `EntryEditView.swift` (this executor's environment has no GUI,
so app-layer bugs like this are found by reading, not clicking through the UI).

## The bug

`QRCodeCameraPreview.metadataOutput(_:didOutput:from:)` stops the `AVCaptureSession`
and sets `didScan = true` the instant it recognizes **any** QR code — before the
`onCode` closure it then invokes has any chance to validate the code's content. That
closure lives in `EntryEditView`:

```swift
QRCodeScannerView { code in
    guard (try? TOTPGenerator.parse(otpauthURI: code)) != nil else {
        otpError = "The QR code does not contain a valid TOTP setup URI."
        return
    }
    otpURI = code
    showingQRScanner = false
}
```

Only the success path set `showingQRScanner = false`. So scanning any non-TOTP QR
code (a URL, a business card, literally any other QR code — not a rare edge case)
left the sheet on screen with a camera feed that had already stopped, the error
alert appearing on top of it, and — since this sheet has no Cancel button — no
obvious way to retry short of pressing Escape or clicking outside the sheet (both of
which do work, per the sheet-dismissal cleanup this file's `dismantleNSView` already
handles, but neither is a discoverable affordance).

## The fix

Move `showingQRScanner = false` above the validation guard, so the sheet closes on
either outcome — matching what already happens on success. A rejected scan now
closes cleanly (with the explanatory alert still shown, unaffected by this change,
attached to `EntryEditView` itself rather than the now-dismissed sheet), and the user
can just click "Scan QR Code…" again, which creates a fresh
`QRCodeCameraPreview`/`AVCaptureSession` instance same as any other re-open of that
sheet.

## Verification

This is a SwiftUI/AppKit app-layer file with no test target (same as every other
`KeeBridge/*.swift` change in this ROADMAP) — verified by reading, and will be
confirmed compiling via this PR's own unsigned `xcodebuild` CI run. Genuinely
unverifiable end-to-end without a real camera and a real invalid QR code in front of
it — this executor's environment has no GUI or camera hardware — flagged as a "still
needs a human eyeball" caveat in the PR, same limit every camera/hardware-adjacent
change in this ROADMAP carries.

## PR

See the PR this cycle opened (self-merged per `docs/WAYS-OF-WORKING.md` §0.1).
