// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Shows one entry's fields. Matches the security posture already used by
// the extension/CredentialProviderViewController — field *values* are
// revealed only when this view actually appears, never eagerly with the
// list.

import SwiftUI
import AppKit
import KeeBridgeCore

struct EntryDetailView: View {
    @ObservedObject var controller: VaultController
    let entry: VaultLoginEntry

    @State private var revealedPassword: String?
    @State private var revealedNotes: String = ""
    @State private var showPasswordPlaintext = false
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var passkeyMetadata: VaultService.VaultPasskeyMetadata?
    @State private var paymentCardMetadata: VaultPaymentCard?

    var body: some View {
        Form {
            Section {
                LabeledContent("Title", value: entry.title)

                if !entry.username.isEmpty {
                    fieldRow(label: "Username", value: entry.username, copyable: true)
                }

                if !entry.url.isEmpty {
                    fieldRow(label: "URL", value: entry.url, copyable: true)
                }

                LabeledContent("Password") {
                    HStack {
                        if let revealedPassword {
                            Text(showPasswordPlaintext ? revealedPassword : String(repeating: "•", count: max(revealedPassword.count, 8)))
                                .font(.system(.body, design: .monospaced))
                            Button {
                                showPasswordPlaintext.toggle()
                            } label: {
                                Image(systemName: showPasswordPlaintext ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            Button {
                                copyToPasteboard(revealedPassword)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }

                if !revealedNotes.isEmpty {
                    LabeledContent("Notes") {
                        Text(revealedNotes)
                    }
                }
            }

            // Read-only — passkeys are created/used via the credential
            // provider extension (see ROADMAP #4); this is visibility only,
            // the first place in the app's own UI to show that an entry
            // even has one. KeePassXC or VaultProbe were previously the
            // only ways to confirm this.
            if entry.isPasskey {
                Section("Passkey") {
                    if let passkeyMetadata {
                        if let relyingParty = passkeyMetadata.relyingParty {
                            fieldRow(label: "Relying Party", value: relyingParty, copyable: true)
                        }
                        if let username = passkeyMetadata.username {
                            fieldRow(label: "Passkey Username", value: username, copyable: true)
                        }
                        if let credentialID = passkeyMetadata.credentialID {
                            fieldRow(
                                label: "Credential ID",
                                value: credentialID.base64EncodedString(),
                                copyable: true
                            )
                        }
                    } else {
                        Text("No passkey metadata found.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Read-only, same posture as the "Passkey" section above and the
            // Safari card extension's own picker: only which field *types*
            // are present, never a card number/expiry/CVV value. Card
            // create/edit stays out of scope for this app — see ROADMAP.
            if entry.isPaymentCard {
                Section("Payment Card") {
                    if let paymentCardMetadata {
                        ForEach(paymentCardMetadata.availableFields, id: \.self) { field in
                            LabeledContent(field.displayName, value: "Present")
                        }
                    } else {
                        Text("No payment card metadata found.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry.title)
        .toolbar {
            ToolbarItem {
                Button("Edit…") { showingEdit = true }
            }
            ToolbarItem {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .onAppear { reveal() }
        .sheet(isPresented: $showingEdit) {
            EntryEditView(controller: controller, mode: .edit(entry.uuid), onSave: reveal)
        }
        .confirmationDialog(
            "Delete \"\(entry.title)\"?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                controller.deleteEntry(uuid: entry.uuid)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone from within KeeBridge — KeePassXC's own backup/history is the recovery path.")
        }
    }

    private func fieldRow(label: String, value: String, copyable: Bool) -> some View {
        LabeledContent(label) {
            HStack {
                Text(value)
                if copyable {
                    Button {
                        copyToPasteboard(value)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // Synchronous now (v3: pure in-memory against the session-cached
    // content, no Argon2). The `revealedPassword == nil` → ProgressView
    // branch above stays as a harmless defensive fallback (e.g. if
    // cachedContent is somehow nil), not because this is actually async
    // anymore.
    private func reveal() {
        showPasswordPlaintext = false
        passkeyMetadata = entry.isPasskey ? controller.passkeyMetadata(uuid: entry.uuid) : nil
        paymentCardMetadata = entry.isPaymentCard ? controller.paymentCardMetadata(uuid: entry.uuid) : nil
        guard let draft = controller.revealEntryForEditing(uuid: entry.uuid) else {
            revealedPassword = nil
            return
        }
        revealedPassword = draft.password
        revealedNotes = draft.notes
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
