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
// Deliberately does NOT build a full WebAuthn `attestationObject` (the
// `authData` envelope, `fmt`, `attStmt`) — only the COSE_Key encoding of
// the credential public key that goes *inside* one. See
// `docs/done/2026-08-26-passkey-crypto.md` and the ROADMAP entry for #4
// for what's still open.

import Crypto
import Foundation
import KDBXKit

public enum PasskeyCrypto {
    public enum PasskeyCryptoError: Error, CustomStringConvertible {
        case invalidPrivateKeyPEM(String)

        public var description: String {
            switch self {
            case .invalidPrivateKeyPEM(let reason):
                return "Invalid P-256 private key PEM: \(reason)"
            }
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

    private static func privateKey(fromPEM pem: String) throws -> P256.Signing.PrivateKey {
        do {
            return try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw PasskeyCryptoError.invalidPrivateKeyPEM("\(error)")
        }
    }

    // MARK: - Minimal CBOR encoding (RFC 8949) — only what a COSE_Key needs
    //
    // Deliberately not a general-purpose CBOR encoder: just unsigned/small-
    // negative integers (major types 0/1) and byte strings (major type 2),
    // the only pieces a COSE_Key for an EC2 P-256 key ever needs. The
    // integers used here (2, 3, 1, -1, -2, -3, -7) all fit in a single
    // immediate byte per RFC 8949 §3.1, so only that case is implemented
    // for integers. Byte strings need the 1-byte-length-prefix form too
    // (a 32-byte coordinate doesn't fit the 0-23 immediate range) — the
    // 2-/4-/8-byte-length forms RFC 8949 also defines aren't implemented,
    // since nothing this fixed, five-field map ever encodes needs them.

    private static func cborUnsigned(_ value: UInt8) -> Data {
        precondition(value <= 23, "only single-byte-immediate unsigned ints are supported here")
        return Data([0x00 | value])
    }

    private static func cborNegative(_ value: Int) -> Data {
        precondition((-24...(-1)).contains(value), "only single-byte-immediate negative ints are supported here")
        return Data([0x20 | UInt8(-1 - value)])
    }

    private static func cborByteString(_ bytes: Data) -> Data {
        precondition(bytes.count <= 255, "only byte strings up to 255 bytes (1-byte length prefix) are supported here")
        if bytes.count <= 23 {
            return Data([0x40 | UInt8(bytes.count)]) + bytes
        }
        return Data([0x58, UInt8(bytes.count)]) + bytes
    }
}
