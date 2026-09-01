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

// MARK: - generateCredentialID

@Test func generateCredentialIDProduces16Bytes() {
    let id = PasskeyCrypto.generateCredentialID()
    #expect(id.count == 16)
}

@Test func generateCredentialIDProducesDistinctIDsEachCall() {
    let a = PasskeyCrypto.generateCredentialID()
    let b = PasskeyCrypto.generateCredentialID()
    #expect(a != b)
}

@Test func generateCredentialIDIsNotAllZero() {
    // A CSPRNG producing an all-zero 16-byte value is astronomically
    // unlikely (odds ~1 in 2^128) — a stuck/broken generator is a far
    // more plausible explanation than genuine bad luck, so this is a
    // legitimate regression check, not flakiness.
    let id = PasskeyCrypto.generateCredentialID()
    #expect(id != Data(repeating: 0, count: 16))
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

// MARK: - coseEncodedPublicKey
//
// The expected byte layout is the fixed, five-field COSE_Key CBOR map
// RFC 9053/WebAuthn define for an EC2 P-256 key (kty=2, alg=-7 (ES256),
// crv=1 (P-256), x, y) — asserted byte-by-byte below rather than via a
// CBOR decoder, since the whole structure is fixed and small enough to
// state directly as the test oracle.

@Test func coseEncodedPublicKeyProducesTheExpectedCOSE_KeyByteLayout() throws {
    let pem = PasskeyCrypto.generatePrivateKeyPEM()
    let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let raw = privateKey.publicKey.rawRepresentation
    #expect(raw.count == 64) // confirms rawRepresentation is X‖Y, no 0x04 prefix
    let x = Data(raw.prefix(32))
    let y = Data(raw.suffix(32))

    let cose = try PasskeyCrypto.coseEncodedPublicKey(forPrivateKeyPEM: pem)

    var expected = Data([0xA5]) // map, 5 entries
    expected.append(contentsOf: [0x01, 0x02]) // kty: EC2
    expected.append(contentsOf: [0x03, 0x26]) // alg: ES256 (-7)
    expected.append(contentsOf: [0x20, 0x01]) // crv: P-256
    expected.append(contentsOf: [0x21, 0x58, 0x20]) // x: bstr(32)
    expected.append(x)
    expected.append(contentsOf: [0x22, 0x58, 0x20]) // y: bstr(32)
    expected.append(y)

    #expect(cose == expected)
    #expect(cose.count == 77)
}

@Test func coseEncodedPublicKeyThrowsForAnInvalidPEM() {
    #expect(throws: (any Error).self) {
        try PasskeyCrypto.coseEncodedPublicKey(forPrivateKeyPEM: "not a real PEM")
    }
}

@Test func coseEncodedPublicKeyWithSecureBytesMatchesTheStringOverload() throws {
    let pem = PasskeyCrypto.generatePrivateKeyPEM()
    let viaString = try PasskeyCrypto.coseEncodedPublicKey(forPrivateKeyPEM: pem)
    let viaSecureBytes = try PasskeyCrypto.coseEncodedPublicKey(forPrivateKeyPEM: SecureBytes(utf8: pem))
    // Unlike signing, public-key encoding is deterministic — byte-identical.
    #expect(viaString == viaSecureBytes)
}

// MARK: - authenticatorData
//
// Expected layout per WebAuthn spec §6.1: rpIdHash (32 bytes) ‖ flags (1
// byte) ‖ signCount (4 bytes BE) ‖ attestedCredentialData (only present,
// with the AT flag bit set, when requested) — asserted byte-by-byte
// against that fixed structure.

@Test func authenticatorDataWithoutAttestedCredentialDataHasNoATFlagAndIsExactly37Bytes() throws {
    let data = try PasskeyCrypto.authenticatorData(relyingPartyID: "example.com", signCount: 0)
    #expect(data.count == 37) // 32 (hash) + 1 (flags) + 4 (signCount), no attested data

    let expectedHash = Data(SHA256.hash(data: Data("example.com".utf8)))
    #expect(data.prefix(32) == expectedHash)

    let flags = data[32]
    #expect(flags & 0x01 != 0) // UP set (default userPresent: true)
    #expect(flags & 0x04 != 0) // UV set (default userVerified: true)
    #expect(flags & 0x40 == 0) // AT NOT set — no attested credential data

    #expect(Array(data.suffix(4)) == [0x00, 0x00, 0x00, 0x00]) // signCount = 0, big-endian
}

@Test func authenticatorDataFlagsReflectUserPresentAndUserVerifiedParameters() throws {
    let data = try PasskeyCrypto.authenticatorData(
        relyingPartyID: "example.com", signCount: 0, userPresent: false, userVerified: false
    )
    let flags = data[32]
    #expect(flags & 0x01 == 0)
    #expect(flags & 0x04 == 0)
}

@Test func authenticatorDataEncodesSignCountBigEndian() throws {
    let data = try PasskeyCrypto.authenticatorData(relyingPartyID: "example.com", signCount: 0x0102_0304)
    #expect(Array(data.suffix(4)) == [0x01, 0x02, 0x03, 0x04])
}

@Test func authenticatorDataWithAttestedCredentialDataSetsATFlagAndAppendsTheExpectedLayout() throws {
    let pem = PasskeyCrypto.generatePrivateKeyPEM()
    let coseKey = try PasskeyCrypto.coseEncodedPublicKey(forPrivateKeyPEM: pem)
    let aaguid = Data(repeating: 0, count: 16)
    let credentialID = Data([0xDE, 0xAD, 0xBE, 0xEF])

    let data = try PasskeyCrypto.authenticatorData(
        relyingPartyID: "example.com",
        signCount: 0,
        attestedCredentialData: .init(aaguid: aaguid, credentialID: credentialID, coseEncodedPublicKey: coseKey)
    )

    #expect(data[32] & 0x40 != 0) // AT flag set
    #expect(data.count == 37 + 16 + 2 + credentialID.count + coseKey.count)

    let acdStart = 37
    #expect(data[acdStart..<(acdStart + 16)] == aaguid)
    #expect(Array(data[(acdStart + 16)..<(acdStart + 18)]) == [0x00, 0x04]) // credentialIdLength = 4, BE
    #expect(data[(acdStart + 18)..<(acdStart + 18 + 4)] == credentialID)
    #expect(data.suffix(coseKey.count) == coseKey)
}

@Test func authenticatorDataThrowsForAWrongSizedAAGUID() {
    #expect(throws: (any Error).self) {
        try PasskeyCrypto.authenticatorData(
            relyingPartyID: "example.com",
            signCount: 0,
            attestedCredentialData: .init(aaguid: Data([0x00]), credentialID: Data(), coseEncodedPublicKey: Data())
        )
    }
}

@Test func authenticatorDataThrowsForAnOversizedCredentialID() {
    let tooLong = Data(repeating: 0, count: Int(UInt16.max) + 1)
    #expect(throws: (any Error).self) {
        try PasskeyCrypto.authenticatorData(
            relyingPartyID: "example.com",
            signCount: 0,
            attestedCredentialData: .init(aaguid: Data(repeating: 0, count: 16), credentialID: tooLong, coseEncodedPublicKey: Data())
        )
    }
}

// MARK: - attestationObject
//
// Expected layout per WebAuthn spec §6.5.4: a 3-entry CBOR map
// `{fmt: "none", attStmt: {}, authData: <bytes>}` — asserted byte-by-byte
// against that fixed structure, same style as coseEncodedPublicKey's test
// above.

@Test func attestationObjectProducesTheExpectedCBORByteLayoutForShortAuthData() {
    let authData = Data([0x01, 0x02, 0x03])

    let object = PasskeyCrypto.attestationObject(authenticatorData: authData)

    var expected = Data([0xA3]) // map, 3 entries
    expected.append(contentsOf: [0x63]); expected.append(Data("fmt".utf8)) // "fmt" (tstr, len 3)
    expected.append(contentsOf: [0x64]); expected.append(Data("none".utf8)) // "none" (tstr, len 4)
    expected.append(contentsOf: [0x67]); expected.append(Data("attStmt".utf8)) // "attStmt" (tstr, len 7)
    expected.append(contentsOf: [0xA0]) // {} — empty map, no attestation statement
    expected.append(contentsOf: [0x68]); expected.append(Data("authData".utf8)) // "authData" (tstr, len 8)
    expected.append(contentsOf: [0x43]); expected.append(authData) // bstr(3)

    #expect(object == expected)
}

@Test func attestationObjectUsesThe1ByteLengthPrefixFormForAuthDataOver23Bytes() throws {
    // A realistic registration authenticatorData (with attestedCredentialData)
    // is always > 23 bytes — confirms the byte-string length prefix isn't
    // just the 0–23 immediate form.
    let pem = PasskeyCrypto.generatePrivateKeyPEM()
    let coseKey = try PasskeyCrypto.coseEncodedPublicKey(forPrivateKeyPEM: pem)
    let authData = try PasskeyCrypto.authenticatorData(
        relyingPartyID: "example.com",
        signCount: 0,
        attestedCredentialData: .init(
            aaguid: Data(repeating: 0, count: 16),
            credentialID: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            coseEncodedPublicKey: coseKey
        )
    )
    #expect(authData.count > 23)

    let object = PasskeyCrypto.attestationObject(authenticatorData: authData)

    // authData is the last field — its value is the CBOR-encoded byte
    // string forming the object's tail: 1-byte-length head (0x58, count) + bytes.
    let tail = Data([0x58, UInt8(authData.count)]) + authData
    #expect(object.suffix(tail.count) == tail)
}

@Test func attestationObjectIsDeterministicForTheSameInput() {
    let authData = Data([0xAA, 0xBB])
    #expect(PasskeyCrypto.attestationObject(authenticatorData: authData) == PasskeyCrypto.attestationObject(authenticatorData: authData))
}
