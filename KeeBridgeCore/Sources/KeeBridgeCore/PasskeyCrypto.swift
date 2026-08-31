// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// P-256 key generation, ECDSA signing, and COSE_Key public-key encoding
// for passkey support, built entirely on swift-crypto (already a
// KeeBridgeCore dependency) — no hand-rolled crypto (the CBOR encoding
// below is data-framing, not cryptography). Produces/consumes PKCS#8 PEM
// private keys: the exact format `KDBX.Entry.setPasskeyPrivateKeyPEM`
// expects (confirmed — `P256.Signing.PrivateKey.pemRepresentation`
// serializes via `ASN1.PKCS8PrivateKey`, matching KeePassXC's own
// `KPEX_PASSKEY_PRIVATE_KEY_PEM` convention exactly, not the SEC1/"EC
// PRIVATE KEY" format some other libraries default to).
//
// Also builds the WebAuthn `attestationObject` CBOR envelope itself
// (`fmt`/`attStmt`/`authData`) that wraps `authenticatorData` — using
// `fmt: "none"` with an empty `attStmt`, the simplest valid
// self-attestation (spec §8.7), since KeeBridge generates its own P-256
// keys locally and has no hardware attestation chain to prove. Still no
// `ASPasskeyCredentialRequest`/`ASPasskeyRegistrationCredential`/
// `ASPasskeyAssertionCredential` wiring — that's the remaining,
// GUI-dependent slice, tracked separately in the ROADMAP entry for #4.

import Crypto
import Foundation
import KDBXKit

public enum PasskeyCrypto {
    public enum PasskeyCryptoError: Error, CustomStringConvertible {
        case invalidPrivateKeyPEM(String)
        case invalidAttestedCredentialData(String)

        public var description: String {
            switch self {
            case .invalidPrivateKeyPEM(let reason):
                return "Invalid P-256 private key PEM: \(reason)"
            case .invalidAttestedCredentialData(let reason):
                return "Invalid attested credential data: \(reason)"
            }
        }
    }

    /// The AAGUID, credential ID, and COSE-encoded public key an
    /// authenticator reports for a newly registered credential — the
    /// `attestedCredentialData` section of `authenticatorData`, present
    /// only on registration (never on a later assertion).
    public struct AttestedCredentialData: Sendable {
        /// Authenticator Attestation GUID — 16 bytes. All-zero is a
        /// legitimate, common choice for an authenticator that doesn't
        /// want to identify its specific model (and macOS silently zeroes
        /// a third-party credential provider's AAGUID anyway, per the
        /// passkey design spike's platform-risk finding — see
        /// `docs/done/2026-08-26-passkey-design-spike.md`).
        public let aaguid: Data
        public let credentialID: Data
        /// CBOR COSE_Key bytes, as produced by `coseEncodedPublicKey`.
        public let coseEncodedPublicKey: Data

        public init(aaguid: Data, credentialID: Data, coseEncodedPublicKey: Data) {
            self.aaguid = aaguid
            self.credentialID = credentialID
            self.coseEncodedPublicKey = coseEncodedPublicKey
        }
    }

    /// Generates a fresh P-256 private key and returns its PKCS#8 PEM
    /// representation, ready to pass directly to
    /// `VaultService.setPasskey(privateKeyPEM:)`.
    public static func generatePrivateKeyPEM() -> String {
        P256.Signing.PrivateKey().pemRepresentation
    }

    /// Parses a PKCS#8 PEM-encoded P-256 private key (as produced by
    /// `generatePrivateKeyPEM()`, or read back via
    /// `VaultService.passkeyMetadata`/KDBXKit's `passkeyPrivateKeyPEM`) and
    /// signs `data`, returning the ASN.1 DER-encoded ECDSA signature — the
    /// format a WebAuthn `AuthenticatorAssertionResponse.signature` requires.
    public static func sign(_ data: Data, withPrivateKeyPEM pem: String) throws -> Data {
        try privateKey(fromPEM: pem).signature(for: data).derRepresentation
    }

    /// Same as `sign(_:withPrivateKeyPEM:)`, taking the private key's PEM
    /// as `SecureBytes` (as returned by KDBXKit's
    /// `KDBX.Entry.passkeyPrivateKeyPEM`) instead of a `String` — reveals
    /// it only for the lifetime of this call via `SecureBytes`'s own
    /// closure-scoped `withRevealedString`, rather than the caller
    /// materialising it into a long-lived plain `String` itself.
    public static func sign(_ data: Data, withPrivateKeyPEM pem: SecureBytes) throws -> Data {
        try pem.withRevealedString { pemString in
            try sign(data, withPrivateKeyPEM: pemString)
        }
    }

    /// The credential public key for a PKCS#8 PEM-encoded P-256 private
    /// key, CBOR-encoded as a COSE_Key map (RFC 9053 §7.1, EC2 key type) —
    /// the exact structure a WebAuthn `attestationObject`'s
    /// `authData.attestedCredentialData.credentialPublicKey` field embeds.
    /// Five entries: `kty` (2 = EC2), `alg` (-7 = ES256), `crv` (1 =
    /// P-256), `x`/`y` (the 32-byte coordinates, from
    /// `PublicKey.rawRepresentation` — confirmed to be raw `X‖Y` with no
    /// leading `0x04` byte, unlike `x963Representation`, which prepends
    /// one).
    public static func coseEncodedPublicKey(forPrivateKeyPEM pem: String) throws -> Data {
        let raw = try privateKey(fromPEM: pem).publicKey.rawRepresentation
        guard raw.count == 64 else {
            throw PasskeyCryptoError.invalidPrivateKeyPEM(
                "expected a 64-byte P-256 public key (X‖Y, no prefix), got \(raw.count) bytes"
            )
        }
        let x = raw.prefix(32)
        let y = raw.suffix(32)

        // COSE_Key map, entries in canonical (ascending encoded-key-byte)
        // order: kty=2, alg=-7, crv=1, x=<32 bytes>, y=<32 bytes>.
        var cbor = Data([0xA5]) // map, 5 entries
        cbor.append(cborUnsigned(1)); cbor.append(cborUnsigned(2)) // kty: EC2
        cbor.append(cborUnsigned(3)); cbor.append(cborNegative(-7)) // alg: ES256
        cbor.append(cborNegative(-1)); cbor.append(cborUnsigned(1)) // crv: P-256
        cbor.append(cborNegative(-2)); cbor.append(cborByteString(Data(x))) // x
        cbor.append(cborNegative(-3)); cbor.append(cborByteString(Data(y))) // y
        return cbor
    }

    /// Same as `coseEncodedPublicKey(forPrivateKeyPEM:)`, taking
    /// `SecureBytes` instead of a `String` — see `sign(_:withPrivateKeyPEM:)`
    /// (`SecureBytes` overload) for why.
    public static func coseEncodedPublicKey(forPrivateKeyPEM pem: SecureBytes) throws -> Data {
        try pem.withRevealedString { try coseEncodedPublicKey(forPrivateKeyPEM: $0) }
    }

    /// Builds a WebAuthn `authenticatorData` byte string (spec §6.1):
    /// `rpIdHash` (SHA-256 of `relyingPartyID`) ‖ `flags` ‖ `signCount` ‖
    /// `attestedCredentialData` (only present, and only then, when
    /// `attestedCredentialData` is non-nil — set the AT flag bit
    /// accordingly). Pass `attestedCredentialData` for a registration
    /// response, omit it for a later assertion response (which never
    /// repeats the credential's AAGUID/ID/public key).
    ///
    /// - Parameters:
    ///   - relyingPartyID: e.g. `"example.com"` — hashed, never stored raw.
    ///   - signCount: the authenticator's signature counter. `0` is a
    ///     valid, common choice for platform authenticators that don't
    ///     track per-credential use counts (relying parties are required
    ///     by spec to tolerate a counter that never increases).
    ///   - userPresent: sets the UP flag bit. Should be `true` whenever
    ///     the user actually interacted (e.g. unlocked the vault) to get here.
    ///   - userVerified: sets the UV flag bit. Should be `true` only when
    ///     the interaction involved actual user verification (e.g. Touch
    ///     ID/master-password entry), not mere presence.
    public static func authenticatorData(
        relyingPartyID: String,
        signCount: UInt32,
        userPresent: Bool = true,
        userVerified: Bool = true,
        attestedCredentialData: AttestedCredentialData? = nil
    ) throws -> Data {
        var data = Data(SHA256.hash(data: Data(relyingPartyID.utf8)))

        var flags: UInt8 = 0
        if userPresent { flags |= 0x01 } // bit 0: UP
        if userVerified { flags |= 0x04 } // bit 2: UV
        if attestedCredentialData != nil { flags |= 0x40 } // bit 6: AT
        data.append(flags)

        withUnsafeBytes(of: signCount.bigEndian) { data.append(contentsOf: $0) }

        if let acd = attestedCredentialData {
            guard acd.aaguid.count == 16 else {
                throw PasskeyCryptoError.invalidAttestedCredentialData(
                    "AAGUID must be exactly 16 bytes, got \(acd.aaguid.count)"
                )
            }
            guard acd.credentialID.count <= Int(UInt16.max) else {
                throw PasskeyCryptoError.invalidAttestedCredentialData(
                    "credential ID too long (\(acd.credentialID.count) bytes, max \(UInt16.max))"
                )
            }
            data.append(acd.aaguid)
            withUnsafeBytes(of: UInt16(acd.credentialID.count).bigEndian) { data.append(contentsOf: $0) }
            data.append(acd.credentialID)
            data.append(acd.coseEncodedPublicKey) // CBOR is self-delimiting; no length prefix needed
        }

        return data
    }

    /// Wraps `authenticatorData` (as built by `authenticatorData(relyingPartyID:signCount:...)`)
    /// in the WebAuthn `attestationObject` CBOR envelope (spec §6.5.4): a
    /// 3-entry map `{fmt, attStmt, authData}`. Uses `fmt: "none"` with an
    /// empty `attStmt` map — the simplest valid self-attestation statement
    /// format (spec §8.7, "none Attestation Statement Format": every
    /// conformant relying party must accept it). KeeBridge generates its
    /// own P-256 keys locally and holds no hardware-attestation chain to
    /// prove, so a real format (e.g. "packed") would only assert trust
    /// that doesn't exist. This is what `ASPasskeyRegistrationCredential`
    /// needs for its `rawAttestationObject` on a registration response.
    public static func attestationObject(authenticatorData: Data) -> Data {
        var cbor = Data([0xA3]) // map, 3 entries
        cbor.append(cborTextString("fmt"))
        cbor.append(cborTextString("none"))
        cbor.append(cborTextString("attStmt"))
        cbor.append(Data([0xA0])) // empty map — no attestation statement
        cbor.append(cborTextString("authData"))
        cbor.append(cborByteString(authenticatorData))
        return cbor
    }

    private static func privateKey(fromPEM pem: String) throws -> P256.Signing.PrivateKey {
        do {
            return try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw PasskeyCryptoError.invalidPrivateKeyPEM("\(error)")
        }
    }

    // MARK: - Minimal CBOR encoding (RFC 8949) — only what a COSE_Key and
    // an `attestationObject` envelope need.
    //
    // Deliberately not a general-purpose CBOR encoder: unsigned/small-
    // negative integers (major types 0/1), byte strings (major type 2),
    // text strings (major type 3), and fixed-size maps (major type 5,
    // written directly as a single head byte at each call site — never
    // more than a handful of fixed, known-at-compile-time entries here).
    // The integers used here (2, 3, 1, -1, -2, -3, -7) all fit in a single
    // immediate byte per RFC 8949 §3.1, so only that case is implemented
    // for integers. Byte/text strings share a general length-prefix
    // encoder (`cborHead`) supporting the 0–23 immediate, 1-byte, and
    // 2-byte length forms — `authenticatorData` can exceed 255 bytes for
    // a large credential ID, so the 1-byte-only form the COSE_Key encoder
    // used to hardcode isn't enough here. The 4-/8-byte-length forms RFC
    // 8949 also defines still aren't implemented — nothing this encodes
    // gets anywhere near 64KB.

    private static func cborUnsigned(_ value: UInt8) -> Data {
        precondition(value <= 23, "only single-byte-immediate unsigned ints are supported here")
        return Data([0x00 | value])
    }

    private static func cborNegative(_ value: Int) -> Data {
        precondition((-24...(-1)).contains(value), "only single-byte-immediate negative ints are supported here")
        return Data([0x20 | UInt8(-1 - value)])
    }

    /// Major-type head byte(s) + length, per RFC 8949 §3.1's length-prefix
    /// encoding (shared by byte strings, major type 2, and text strings,
    /// major type 3).
    private static func cborHead(major: UInt8, count: Int) -> Data {
        let topBits = major << 5
        if count <= 23 {
            return Data([topBits | UInt8(count)])
        } else if count <= 0xFF {
            return Data([topBits | 24, UInt8(count)])
        } else if count <= 0xFFFF {
            var head = Data([topBits | 25])
            withUnsafeBytes(of: UInt16(count).bigEndian) { head.append(contentsOf: $0) }
            return head
        }
        preconditionFailure("count \(count) too large for this minimal CBOR encoder (>65535 bytes)")
    }

    private static func cborByteString(_ bytes: Data) -> Data {
        cborHead(major: 2, count: bytes.count) + bytes
    }

    private static func cborTextString(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        return cborHead(major: 3, count: bytes.count) + bytes
    }
}
