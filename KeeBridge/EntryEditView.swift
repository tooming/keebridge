// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Shared add/edit form, per the plan's "one form, two modes" design —
// avoids duplicating field layout between "create" and "edit".

import SwiftUI
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
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { loadIfEditing() }
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
    }

    private func save() {
        let draft = VaultService.EntryDraft(title: title, username: username, password: password, url: url, notes: notes)
        switch mode {
        case .add:
            controller.createEntry(draft)
        case .edit(let uuid):
            controller.updateEntry(uuid: uuid, applying: draft)
        }
        onSave()
    }
}
