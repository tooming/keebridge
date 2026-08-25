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
