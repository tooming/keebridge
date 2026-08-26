// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// PasskeyCrypto tests. Verification uses swift-crypto directly (not
// PasskeyCrypto's own API, which deliberately only signs — KeeBridge is
// the WebAuthn authenticator, not the relying party that verifies) to
// independently confirm a produced signature is actually valid for the
// matching public key, and that generatePrivateKeyPEM's PEM format
// round-trips through P256.Signing.PrivateKey's own PEM parser (the main
// risk this file exists to catch: a subtly wrong PEM format would build
// and even "work" locally but fail interop with KeePassXC or any real
// WebAuthn relying party). All keys/signatures here are freshly generated
// per test — no real credential material.

import Crypto
import Foundation
import KDBXKit
import Testing
@testable import KeeBridgeCore

@Test func generatePrivateKeyPEMProducesAParsablePKCS8PEM() throws {
    let pem = PasskeyCrypto.generatePrivateKeyPEM()
    #expect(pem.contains("BEGIN PRIVATE KEY"))
    #expect(!pem.contains("BEGIN EC PRIVATE KEY")) // SEC1 format, NOT what KeePassXC expects here

    // Must round-trip through swift-crypto's own PEM parser.
    _ = try P256.Signing.PrivateKey(pemRepresentation: pem)
}

@Test func generatePrivateKeyPEMProducesDistinctKeysEachCall() {
    let a = PasskeyCrypto.generatePrivateKeyPEM()
    let b = PasskeyCrypto.generatePrivateKeyPEM()
    #expect(a != b)
}

@Test func signProducesAValidSignatureForTheMatchingPublicKey() throws {
    let pem = PasskeyCrypto.generatePrivateKeyPEM()
    let message = Data("authenticatorData || clientDataHash".utf8)

    let derSignature = try PasskeyCrypto.sign(message, withPrivateKeyPEM: pem)

    // Verify independently via swift-crypto, not via PasskeyCrypto itself.
    let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let signature = try P256.Signing.ECDSASignature(derRepresentation: derSignature)
    #expect(privateKey.publicKey.isValidSignature(signature, for: message))
}

@Test func signRejectsATamperedMessage() throws {
    let pem = PasskeyCrypto.generatePrivateKeyPEM()
    let message = Data("original message".utf8)
    let tampered = Data("tampered message".utf8)

    let derSignature = try PasskeyCrypto.sign(message, withPrivateKeyPEM: pem)
    let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let signature = try P256.Signing.ECDSASignature(derRepresentation: derSignature)
    #expect(!privateKey.publicKey.isValidSignature(signature, for: tampered))
}

@Test func signThrowsForAnInvalidPEM() {
    #expect(throws: (any Error).self) {
        try PasskeyCrypto.sign(Data("x".utf8), withPrivateKeyPEM: "not a real PEM")
    }
}

@Test func signWithSecureBytesMatchesSigningWithTheEquivalentString() throws {
    let pem = PasskeyCrypto.generatePrivateKeyPEM()
    let message = Data("secure bytes variant".utf8)

    let viaString = try PasskeyCrypto.sign(message, withPrivateKeyPEM: pem)
    let viaSecureBytes = try PasskeyCrypto.sign(message, withPrivateKeyPEM: SecureBytes(utf8: pem))

    // ECDSA signing is randomized (a fresh nonce per signature), so the
    // two DER blobs won't be byte-identical — instead confirm both are
    // independently valid for the same key and message.
    let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
    #expect(privateKey.publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: viaString), for: message))
    #expect(privateKey.publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: viaSecureBytes), for: message))
}
