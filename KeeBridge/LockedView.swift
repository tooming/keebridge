// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// The pre-unlock screen: pick an existing vault (or create a new one),
// unlock with the master password or the cached Keychain key.

import SwiftUI

struct LockedView: View {
    @ObservedObject var controller: VaultController
    @State private var password: String = ""
    @State private var showingCreateVault = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KeeBridge").font(.title2).bold()

            Text(controller.statusMessage)
                .foregroundStyle(.secondary)
                .font(.callout)

            if let error = controller.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Divider()

            HStack {
                Button("Choose vault.kdbx…") {
                    controller.pickVaultFile()
                }
                Button("Create New Vault…") {
                    showingCreateVault = true
                }
            }

            if controller.hasVaultSelected {
                SecureField("Master password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { unlock() }

                HStack {
                    Button("Unlock") { unlock() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(password.isEmpty)

                    Button("Refresh from cached key") {
                        controller.refreshFromCache()
                    }
                    // Enabled whenever a vault is picked, not gated on
                    // isUnlocked — the whole point of this button is to
                    // skip retyping the password using Keychain's cached
                    // key, which is exactly the case right after a fresh
                    // launch when isUnlocked is still false.
                }
            }

            if controller.isUnlocked {
                Text("\(controller.identityCount) identities registered")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .sheet(isPresented: $showingCreateVault) {
            CreateVaultSheet(controller: controller, isPresented: $showingCreateVault)
        }
    }

    private func unlock() {
        controller.unlock(password: password)
        password = ""
    }
}

private struct CreateVaultSheet: View {
    @ObservedObject var controller: VaultController
    @Binding var isPresented: Bool

    @State private var databaseName = "My Vault"
    @State private var password = ""
    @State private var confirmPassword = ""

    private var passwordsMatch: Bool { !password.isEmpty && password == confirmPassword }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create New Vault").font(.headline)

            TextField("Vault name", text: $databaseName)
                .textFieldStyle(.roundedBorder)
            SecureField("Master password", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm master password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)

            if !confirmPassword.isEmpty && !passwordsMatch {
                Text("Passwords don't match").font(.caption).foregroundStyle(.red)
            }

            Text("There's no way to recover a lost master password — write it down somewhere safe.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Create…") {
                    controller.createNewVault(databaseName: databaseName, masterPassword: password)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!passwordsMatch || databaseName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
