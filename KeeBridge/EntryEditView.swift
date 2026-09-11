// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Shared add/edit form, per the plan's "one form, two modes" design —
// avoids duplicating field layout between "create" and "edit".

import SwiftUI
import AVFoundation
import KeeBridgeCore

enum EntryEditMode {
    case add
    case edit(String)  // entry UUID
}

struct EntryEditView: View {
    @ObservedObject var controller: VaultController
    let mode: EntryEditMode
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var notes = ""
    @State private var otpURI = ""
    @State private var showingQRScanner = false
    @State private var otpError: String?

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isAdd ? "Add Entry" : "Edit Entry").font(.headline)

            Form {
                TextField("Title", text: $title)
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                TextField("URL", text: $url)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                Section("One-Time Password") {
                    TextField("otpauth:// URI", text: $otpURI)
                    HStack {
                        Button("Scan QR Code…") { showingQRScanner = true }
                        if !otpURI.isEmpty {
                            Button("Remove", role: .destructive) { otpURI = "" }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if save() {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { loadIfEditing() }
        .sheet(isPresented: $showingQRScanner) {
            QRCodeScannerView(
                onCode: { code in
                    // Close the sheet on EITHER outcome, not just success.
                    // `metadataOutput` already stops the capture session (and marks
                    // `didScan`) the instant it recognizes any QR code, valid or
                    // not, before this closure gets a chance to validate it — so
                    // by the time an invalid code reaches here, the camera feed is
                    // already dead. Leaving the sheet open in that case stranded
                    // the user looking at a frozen, black preview with the error
                    // alert on top and no way to retry short of Escape/
                    // click-outside (there's no Cancel button in this sheet):
                    // dismissing here matches the success path and lets them just
                    // click "Scan QR Code…" again for a fresh camera session.
                    showingQRScanner = false
                    guard (try? TOTPGenerator.parse(otpauthURI: code)) != nil else {
                        otpError = "The QR code does not contain a valid TOTP setup URI."
                        return
                    }
                    otpURI = code
                },
                onFailure: { message in
                    // Same dead-end shape as the invalid-QR-code case above, one
                    // level earlier: camera permission denied, no camera present,
                    // or session setup failing all used to hit a silent `return`
                    // inside `configureCamera()` — the sheet stayed open showing
                    // a permanently blank preview with zero explanation and (still)
                    // no Cancel button, so the only way out was guessing to press
                    // Escape or click outside. Surfacing the failure here closes
                    // the sheet and explains why, the same way an invalid scan
                    // already does.
                    showingQRScanner = false
                    otpError = message
                }
            )
        }
        .alert("Unable to Add One-Time Password", isPresented: Binding(
            get: { otpError != nil },
            set: { if !$0 { otpError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(otpError ?? "")
        }
    }

    // Synchronous now (v3: revealEntryForEditing is pure in-memory against
    // the session-cached content, no Argon2 — see VaultController's doc
    // comment on that method for why this used to need a loading state and
    // doesn't anymore).
    private func loadIfEditing() {
        guard case .edit(let uuid) = mode,
              let draft = controller.revealEntryForEditing(uuid: uuid)
        else { return }
        title = draft.title
        username = draft.username
        password = draft.password
        url = draft.url
        notes = draft.notes
        otpURI = draft.otpURI ?? ""
    }

    private func save() -> Bool {
        if !otpURI.isEmpty {
            guard (try? TOTPGenerator.parse(otpauthURI: otpURI)) != nil else {
                otpError = "Enter a valid TOTP setup URI or scan its QR code."
                return false
            }
        }
        let draft = VaultService.EntryDraft(
            title: title, username: username, password: password, url: url, notes: notes, otpURI: otpURI
        )
        switch mode {
        case .add:
            controller.createEntry(draft)
        case .edit(let uuid):
            controller.updateEntry(uuid: uuid, applying: draft)
        }
        onSave()
        return true
    }
}

private struct QRCodeScannerView: View {
    var onCode: (String) -> Void
    var onFailure: (String) -> Void

    var body: some View {
        QRCodeCameraView(onCode: onCode, onFailure: onFailure)
            .frame(width: 480, height: 360)
    }
}

private struct QRCodeCameraView: NSViewRepresentable {
    var onCode: (String) -> Void
    var onFailure: (String) -> Void

    func makeNSView(context: Context) -> QRCodeCameraPreview {
        QRCodeCameraPreview(onCode: onCode, onFailure: onFailure)
    }

    func updateNSView(_ nsView: QRCodeCameraPreview, context: Context) {}

    // SwiftUI calls this when the represented NSView leaves the hierarchy — e.g. the
    // scanner sheet is dismissed (Escape, click-outside, or the parent form's Cancel)
    // without a QR code ever being recognized. Without this, `metadataOutput`'s
    // scan-success path was the ONLY place that called `session.stopRunning()`, so an
    // abandoned scan left the capture session running indefinitely: the camera stays
    // active and the system's camera-in-use indicator stays lit for a view that's no
    // longer on screen.
    static func dismantleNSView(_ nsView: QRCodeCameraPreview, coordinator: ()) {
        nsView.stopSession()
    }
}

@MainActor
private final class QRCodeCameraPreview: NSView, @MainActor AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCode: (String) -> Void
    private let onFailure: (String) -> Void
    private var didScan = false

    init(onCode: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
        self.onCode = onCode
        self.onFailure = onFailure
        super.init(frame: .zero)
        wantsLayer = true
        configureCamera()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach { $0.frame = bounds }
    }

    // Every failure branch below used to just `return`, leaving `EntryEditView`'s
    // sheet open on a permanently blank preview with no explanation and no Cancel
    // button — see `EntryEditView.body`'s `onFailure` doc comment for the fix this
    // closure enables. `didScan` guards against calling `onFailure` after a scan
    // already succeeded (shouldn't be reachable — nothing here runs again once
    // `stopSession()` has been called — but cheap insurance against ever firing
    // both callbacks for one sheet).
    private func configureCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, !self.didScan else { return }
                guard granted else {
                    self.onFailure("Camera access is required to scan a QR code. Enable it in System Settings > Privacy & Security > Camera.")
                    return
                }
                guard let device = AVCaptureDevice.default(for: .video) else {
                    self.onFailure("No camera is available on this Mac.")
                    return
                }
                guard let input = try? AVCaptureDeviceInput(device: device) else {
                    self.onFailure("Could not access the camera.")
                    return
                }
                self.session.beginConfiguration()
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    self.onFailure("Could not use the camera for scanning.")
                    return
                }
                self.session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddOutput(output) else {
                    self.session.commitConfiguration()
                    self.onFailure("Could not use the camera for scanning.")
                    return
                }
                self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                self.session.commitConfiguration()
                let preview = AVCaptureVideoPreviewLayer(session: self.session)
                preview.videoGravity = .resizeAspectFill
                self.layer?.addSublayer(preview)
                preview.frame = self.bounds
                self.session.startRunning()
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didScan, let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else {
            return
        }
        didScan = true
        stopSession()
        onCode(code)
    }

    /// Idempotent — `AVCaptureSession.stopRunning()` is safe to call on an
    /// already-stopped (or never-started, e.g. camera permission denied) session.
    func stopSession() {
        session.stopRunning()
    }
}
