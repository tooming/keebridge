// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// The post-unlock screen: searchable entry list + detail pane. Field
// *values* are never held here — VaultController.entries carries only
// non-secret metadata (see VaultLoginEntry); actual reveal happens in
// EntryDetailView, on demand, per entry.

import SwiftUI
import KeeBridgeCore

struct VaultBrowserView: View {
    @ObservedObject var controller: VaultController
    @State private var selectedUUID: String?
    @State private var searchText = ""
    @State private var showingAddEntry = false

    private var filteredEntries: [VaultLoginEntry] {
        guard !searchText.isEmpty else { return controller.entries }
        return controller.entries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
                || $0.url.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredEntries, id: \.uuid, selection: $selectedUUID) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.title).bold()
                        if entry.isPasskey {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundStyle(.secondary)
                                .help("Has a passkey")
                        }
                        if entry.isPaymentCard {
                            Image(systemName: "creditcard.fill")
                                .foregroundStyle(.secondary)
                                .help("Recognized as a payment card")
                        }
                    }
                    Text(entry.username.isEmpty ? entry.url : entry.username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $searchText, prompt: "Search")
            .navigationTitle("KeeBridge")
            .toolbar {
                ToolbarItem {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Label("Add Entry", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Button("Lock") { controller.lock() }
                }
            }
        } detail: {
            if let selectedUUID, let entry = controller.entries.first(where: { $0.uuid == selectedUUID }) {
                EntryDetailView(controller: controller, entry: entry)
                    .id(entry.uuid)
            } else {
                ContentUnavailableView("Select an Entry", systemImage: "key.fill")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            EntryEditView(controller: controller, mode: .add, onSave: {})
        }
    }
}
