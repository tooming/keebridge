# QR scanner's `AVCaptureSession` never stopped if the scan sheet is dismissed without a successful scan

Found via a STEP 6b re-survey (the ROADMAP's "Now / next" lane had no buildable item this
cycle — the sole unchecked item, automatic password-save proposal (#33), is blocked on an
Apple platform limitation with no macOS entry point at all, so there was no code to write
for it). A dedicated Explore survey did a fresh, full, end-to-end read of every source file
not yet confirmed fully read by a prior run's own notes (per
`docs/backlog/2026-09-03-action-needed-backlog-blocked.md`), and this was one of three
genuinely new findings — the smallest and highest-confidence of the three, so it's the one
this cycle implements. The other two are queued as new `[ ]` `Now / next` items in
`ROADMAP.md` for a future cycle.

## The bug

`EntryEditView.swift`'s "Scan QR Code…" flow (used to import a TOTP setup URI) presents a
`QRCodeScannerView` in a `.sheet`, backed by an `NSViewRepresentable` (`QRCodeCameraView`)
wrapping an `AVCaptureSession`-driven `NSView` (`QRCodeCameraPreview`).

The only place that ever called `session.stopRunning()` was the scan-success path in
`metadataOutput(_:didOutput:from:)`. If the user opened the scanner and then dismissed the
sheet any other way — Escape, clicking outside it, or the parent form's own Cancel — before
a QR code was ever recognized, nothing stopped the session. `QRCodeCameraPreview` had no
`deinit` and `QRCodeCameraView` implemented none of `NSViewRepresentable`'s teardown hooks,
so the `AVCaptureSession` kept running indefinitely, with no view left on screen to show its
output: the camera stayed active and the system's camera-in-use indicator stayed lit for a
UI element the user had already dismissed. A real correctness/privacy bug, not just
untested code — the same class of issue this ROADMAP has flagged as worth fixing on sight
before (e.g. the `updateEntry` custom-field data-loss fix), just in the
resource-leak/privacy direction instead of data loss.

## The fix

Implemented `QRCodeCameraView.dismantleNSView(_:coordinator:)` — the `NSViewRepresentable`
hook SwiftUI calls when the represented `NSView` leaves the view hierarchy (sheet dismissal
included) — to call a new `QRCodeCameraPreview.stopSession()` unconditionally.
`stopSession()` is also now what the scan-success path calls, so there's exactly one
code path that stops the session rather than two. `AVCaptureSession.stopRunning()` is
documented as safe to call on an already-stopped or never-started session (e.g. camera
permission was denied before `startRunning()` ever ran), so no extra guard state was
needed.

## Verification

Compiled-only (`xcodebuild -project KeeBridge.xcodeproj -scheme KeeBridge ... build`,
unsigned, via CI on `macos-latest` — this executor's own environment has no local
Swift/Xcode toolchain, per the prior run's own note in
`docs/backlog/2026-09-03-action-needed-backlog-blocked.md`). `KeeBridge`'s SwiftUI/AppKit
view layer has no test target (same as `VaultController.swift` and every other app-layer
change in this ROADMAP), so this is not `swift test`-covered.

**Still needs a human eyeball**: confirming the system camera-in-use indicator actually
turns off after dismissing the scanner without scanning needs a real macOS session with
camera hardware — this executor's environment is headless with no camera. The fix is
straightforward enough (a single, well-documented SwiftUI teardown hook calling the same
idempotent `stopRunning()` the success path already relied on) that it's shipped with high
confidence anyway, per this repo's HEADLESS ONLY rule: ship with whatever headless
verification is possible, flag what still needs eyes.

## PR

See the associated pull request for this branch (`auto/qr-scanner-session-cleanup`).
