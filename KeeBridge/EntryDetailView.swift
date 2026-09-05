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
                                copyToPasteboard(revealedPassword, autoClearAfter: Self.passwordClipboardAutoClearDelay)
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
            // Deliberately doesn't say "KeePassXC's own backup/history is the
            // recovery path" (the previous wording) — that overstated the
            // actual guarantee. deleteEntry does a hard removal with no
            // recycle bin (see its own doc comment) and never populates the
            // entry's history before deleting it, so there's no KeePass
            // version-history trail to recover from for a deletion made
            // through KeeBridge specifically. The vault's own `.bak` sibling
            // (VaultService.write's AtomicFileWriter backup, one save
            // generation back) is the real recovery path.
            Text("This can't be undone from within KeeBridge, and there's no recycle bin here yet — the vault's own \".bak\" file (written next to it on every save) is the only recovery path, one save generation back.")
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

    // How long a copied password stays on the system pasteboard before this
    // view clears it again. Only the password's own copy button passes this
    // — the username/URL/passkey-metadata copy buttons (fieldRow's
    // `copyable: true`) are non-secret and deliberately don't auto-clear,
    // same distinction KeeBridge already draws everywhere else between
    // secret and non-secret fields. 30s matches the common default other
    // password managers (1Password, Bitwarden) use for this.
    private static let passwordClipboardAutoClearDelay: TimeInterval = 30

    /// Copies `string` to the system pasteboard — any other app on the Mac
    /// can read it until it's overwritten or cleared, so a copied PASSWORD
    /// sitting there indefinitely (the previous behavior: no auto-clear at
    /// all) is a real, silent exposure window, not a hypothetical one. Pass
    /// `autoClearAfter` for secret material to schedule clearing it again
    /// after that delay — but only if the pasteboard still holds exactly
    /// what THIS call put there: `NSPasteboard.changeCount` increments on
    /// every write from any app, so capturing it right after our own write
    /// and comparing it again at clear time (rather than unconditionally
    /// calling `clearContents()`) is the standard, AppKit-documented way to
    /// avoid wiping out something the user copied from elsewhere in the
    /// meantime.
    private func copyToPasteboard(_ string: String, autoClearAfter clearDelay: TimeInterval? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        guard let clearDelay else { return }
        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) {
            guard NSPasteboard.general.changeCount == changeCount else { return }
            NSPasteboard.general.clearContents()
        }
    }
}
