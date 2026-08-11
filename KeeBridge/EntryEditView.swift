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
    // True while waiting on revealEntryForEditing's background Argon2id
    // pass (edit mode only — add mode has nothing to reveal, starts blank
    // immediately). Without this the form just showed empty fields with no
    // indication anything was happening, which read as "lag"/broken rather
    // than "loading" — the Detail view already had this via its `if let
    // revealedPassword { ... } else { ProgressView() }`, this brings the
    // edit form in line with it.
    @State private var isLoading = false

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isAdd ? "Add Entry" : "Edit Entry").font(.headline)

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Decrypting…")
                    Spacer()
                }
                .frame(height: 220)
            } else {
                Form {
                    TextField("Title", text: $title)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    TextField("URL", text: $url)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                .formStyle(.grouped)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || isLoading)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { loadIfEditing() }
    }

    private func loadIfEditing() {
        guard case .edit(let uuid) = mode else { return }
        isLoading = true
        controller.revealEntryForEditing(uuid: uuid) { draft in
            isLoading = false
            guard let draft else { return }
            title = draft.title
            username = draft.username
            password = draft.password
            url = draft.url
            notes = draft.notes
        }
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
