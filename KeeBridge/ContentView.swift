// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT

import SwiftUI

struct ContentView: View {
    @StateObject private var controller = VaultController()

    var body: some View {
        Group {
            if controller.isUnlocked {
                VaultBrowserView(controller: controller)
            } else {
                LockedView(controller: controller)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
