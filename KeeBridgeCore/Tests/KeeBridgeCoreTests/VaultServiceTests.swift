// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import KeeBridgeCore

@Test func preHashIsDeterministicAndCorrectLength() {
    let service = VaultService()
    let a = service.preHashKeyData(forPassword: "hunter2")
    let b = service.preHashKeyData(forPassword: "hunter2")
    #expect(a == b)
    #expect(a.count == 32)
}

@Test func differentPasswordsProduceDifferentPreHashes() {
    let service = VaultService()
    let a = service.preHashKeyData(forPassword: "hunter2")
    let b = service.preHashKeyData(forPassword: "hunter3")
    #expect(a != b)
}

@Test func listEntriesThrowsOnMissingFile() {
    let service = VaultService()
    let missing = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID()).kdbx")
    #expect(throws: (any Error).self) {
        try service.listEntries(at: missing, masterPassword: "whatever")
    }
}
