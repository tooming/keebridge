// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT

import SwiftUI

struct ContentView: View {
    @StateObject private var controller = VaultController()
    @State private var password: String = ""

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

            Button("Choose vault.kdbx…") {
                controller.pickVaultFile()
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
        .frame(minWidth: 420)
    }

    private func unlock() {
        controller.unlock(password: password)
        password = ""
    }
}

#Preview {
    ContentView()
}
