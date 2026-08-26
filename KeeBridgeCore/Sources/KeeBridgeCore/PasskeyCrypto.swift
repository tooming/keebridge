// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// P-256 key generation and ECDSA signing for passkey support, built
// entirely on swift-crypto (already a KeeBridgeCore dependency) — no
// hand-rolled crypto. Produces/consumes PKCS#8 PEM private keys: the
// exact format `KDBX.Entry.setPasskeyPrivateKeyPEM` expects (confirmed —
// `P256.Signing.PrivateKey.pemRepresentation` serializes via
// `ASN1.PKCS8PrivateKey`, matching KeePassXC's own `KPEX_PASSKEY_PRIVATE_KEY_PEM`
// convention exactly, not the SEC1/"EC PRIVATE KEY" format some other
// libraries default to).
//
// Deliberately does NOT build a WebAuthn `attestationObject` or any
// CBOR/COSE encoding — this is only the key-generation and raw-signing
// primitives real registration/assertion code will need to call. See
// `docs/done/2026-08-26-passkey-write-support.md` and the ROADMAP entry
// for #4 for what's still open.

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

    private static func privateKey(fromPEM pem: String) throws -> P256.Signing.PrivateKey {
        do {
            return try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw PasskeyCryptoError.invalidPrivateKeyPEM("\(error)")
        }
    }
}
