// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// RFC 6238 TOTP, parsed from the `otpauth://totp/...` URI KeePassXC/pykeepass
// store in an entry's `otp` custom field (confirmed field name via
// VaultProbe against the real vault — see milestone 1 in the project plan).

import Foundation
import Crypto

public struct TOTPParameters: Sendable, Equatable {
    public let secret: Data
    public let algorithm: HMACAlgorithm
    public let digits: Int
    public let period: TimeInterval

    public enum HMACAlgorithm: String, Sendable, Equatable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }
}

public enum TOTPError: Error, CustomStringConvertible {
    case invalidURI
    case unsupportedType(String)
    case missingSecret
    case invalidBase32Secret

    public var description: String {
        switch self {
        case .invalidURI: return "Not a valid otpauth:// URI"
        case .unsupportedType(let type): return "Unsupported otpauth type: \(type) (only \"totp\" is supported)"
        case .missingSecret: return "otpauth URI has no secret parameter"
        case .invalidBase32Secret: return "Could not Base32-decode the secret"
        }
    }
}

public enum TOTPGenerator {
    /// Parses an `otpauth://totp/...?secret=BASE32&algorithm=SHA1&digits=6&period=30`
    /// URI. Unspecified parameters default per RFC 6238 / Google
    /// Authenticator convention: SHA1, 6 digits, 30-second period.
    public static func parse(otpauthURI: String) throws -> TOTPParameters {
        guard let components = URLComponents(string: otpauthURI),
              components.scheme == "otpauth"
        else {
            throw TOTPError.invalidURI
        }
        // host is "totp" or "hotp" for otpauth://totp/... — URLComponents
        // parses the part right after "otpauth://" as host.
        guard components.host?.lowercased() == "totp" else {
            throw TOTPError.unsupportedType(components.host ?? "(none)")
        }

        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") })

        guard let secretBase32 = query["secret"], !secretBase32.isEmpty else {
            throw TOTPError.missingSecret
        }
        guard let secret = base32Decode(secretBase32) else {
            throw TOTPError.invalidBase32Secret
        }

        let algorithm = TOTPParameters.HMACAlgorithm(rawValue: (query["algorithm"] ?? "SHA1").uppercased()) ?? .sha1
        let digits = Int(query["digits"] ?? "") ?? 6
        let period = TimeInterval(query["period"] ?? "") ?? 30

        return TOTPParameters(secret: secret, algorithm: algorithm, digits: digits, period: period)
    }

    /// The current TOTP code for `parameters` at `date` (defaults to now).
    public static func currentCode(for parameters: TOTPParameters, at date: Date = Date()) -> String {
        let counter = UInt64(date.timeIntervalSince1970 / parameters.period)
        return code(for: parameters, counter: counter)
    }

    /// Seconds remaining in the current period at `date` — useful for a
    /// "code expires in Ns" UI, not required for autofill itself.
    public static func secondsRemaining(for parameters: TOTPParameters, at date: Date = Date()) -> Int {
        let elapsed = date.timeIntervalSince1970.truncatingRemainder(dividingBy: parameters.period)
        return Int(parameters.period - elapsed)
    }

    // MARK: - RFC 4226 HOTP (TOTP is HOTP with counter = time / period)

    private static func code(for parameters: TOTPParameters, counter: UInt64) -> String {
        var counterBytes = counter.bigEndian
        let counterData = Data(bytes: &counterBytes, count: 8)

        let hmac: Data
        let key = SymmetricKey(data: parameters.secret)
        switch parameters.algorithm {
        case .sha1:
            hmac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key))
        case .sha256:
            hmac = Data(HMAC<SHA256>.authenticationCode(for: counterData, using: key))
        case .sha512:
            hmac = Data(HMAC<SHA512>.authenticationCode(for: counterData, using: key))
        }

        // Dynamic truncation, RFC 4226 §5.4.
        let offset = Int(hmac[hmac.count - 1] & 0x0f)
        let truncated = (UInt32(hmac[offset] & 0x7f) << 24)
            | (UInt32(hmac[offset + 1]) << 16)
            | (UInt32(hmac[offset + 2]) << 8)
            | UInt32(hmac[offset + 3])

        let modulus = UInt32(pow(10.0, Double(parameters.digits)))
        let code = truncated % modulus
        return String(format: "%0\(parameters.digits)d", code)
    }

    // MARK: - Base32 (RFC 4648, no padding required)

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    private static func base32Decode(_ string: String) -> Data? {
        let cleaned = string.uppercased().filter { $0 != "=" && !$0.isWhitespace }
        guard !cleaned.isEmpty else { return nil }

        var bits = 0
        var value = 0
        var output = [UInt8]()
        output.reserveCapacity(cleaned.count * 5 / 8)

        for char in cleaned {
            guard let index = base32Alphabet.firstIndex(of: char) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((value >> bits) & 0xff))
            }
        }
        return Data(output)
    }
}
