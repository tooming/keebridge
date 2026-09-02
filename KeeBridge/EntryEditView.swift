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
            QRCodeScannerView { code in
                guard (try? TOTPGenerator.parse(otpauthURI: code)) != nil else {
                    otpError = "The QR code does not contain a valid TOTP setup URI."
                    return
                }
                otpURI = code
                showingQRScanner = false
            }
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

    var body: some View {
        QRCodeCameraView(onCode: onCode)
            .frame(width: 480, height: 360)
    }
}

private struct QRCodeCameraView: NSViewRepresentable {
    var onCode: (String) -> Void

    func makeNSView(context: Context) -> QRCodeCameraPreview {
        QRCodeCameraPreview(onCode: onCode)
    }

    func updateNSView(_ nsView: QRCodeCameraPreview, context: Context) {}
}

@MainActor
private final class QRCodeCameraPreview: NSView, @MainActor AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCode: (String) -> Void
    private var didScan = false

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
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

    private func configureCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard granted, let self, let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device)
                else { return }
                self.session.beginConfiguration()
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    return
                }
                self.session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddOutput(output) else {
                    self.session.commitConfiguration()
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
        session.stopRunning()
        onCode(code)
    }
}
