// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// RFC 6238 Appendix B official test vectors (SHA1 secret, T0=0, X=30s,
// 8 digits) — verifies the HOTP/TOTP math independent of the otpauth://
// URI parsing or anything SDK-specific.

import Foundation
import Testing
@testable import KeeBridgeCore

private let rfc6238SHA1Secret = Data("12345678901234567890".utf8)

@Test func rfc6238VectorAt59Seconds() {
    let params = TOTPParameters(secret: rfc6238SHA1Secret, algorithm: .sha1, digits: 8, period: 30)
    let code = TOTPGenerator.currentCode(for: params, at: Date(timeIntervalSince1970: 59))
    #expect(code == "94287082")
}

@Test func rfc6238VectorAt1111111109() {
    let params = TOTPParameters(secret: rfc6238SHA1Secret, algorithm: .sha1, digits: 8, period: 30)
    let code = TOTPGenerator.currentCode(for: params, at: Date(timeIntervalSince1970: 1_111_111_109))
    #expect(code == "07081804")
}

@Test func rfc6238VectorAt1234567890() {
    let params = TOTPParameters(secret: rfc6238SHA1Secret, algorithm: .sha1, digits: 8, period: 30)
    let code = TOTPGenerator.currentCode(for: params, at: Date(timeIntervalSince1970: 1_234_567_890))
    #expect(code == "89005924")
}

@Test func rfc6238VectorAt2000000000() {
    let params = TOTPParameters(secret: rfc6238SHA1Secret, algorithm: .sha1, digits: 8, period: 30)
    let code = TOTPGenerator.currentCode(for: params, at: Date(timeIntervalSince1970: 2_000_000_000))
    #expect(code == "69279037")
}

@Test func parsesStandardOtpauthURI() throws {
    // A base32 encoding of "12345678901234567890" (RFC 6238's SHA1 test
    // secret) — cross-checks the URI parser + base32 decoder against the
    // same known-good vector above, this time going through parse().
    let uri = "otpauth://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example&digits=8"
    let params = try TOTPGenerator.parse(otpauthURI: uri)
    #expect(params.digits == 8)
    #expect(params.algorithm == .sha1)
    #expect(params.period == 30)
    let code = TOTPGenerator.currentCode(for: params, at: Date(timeIntervalSince1970: 59))
    #expect(code == "94287082")
}

@Test func defaultsWhenParametersOmitted() throws {
    let uri = "otpauth://totp/Example:bob?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    let params = try TOTPGenerator.parse(otpauthURI: uri)
    #expect(params.digits == 6)
    #expect(params.algorithm == .sha1)
    #expect(params.period == 30)
}

@Test func rejectsNonTotpURI() {
    #expect(throws: TOTPError.self) {
        try TOTPGenerator.parse(otpauthURI: "otpauth://hotp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    }
}

@Test func rejectsMissingSecret() {
    #expect(throws: TOTPError.self) {
        try TOTPGenerator.parse(otpauthURI: "otpauth://totp/Example:alice")
    }
}

@Test func rejectsNonOtpauthScheme() {
    // Distinct from rejectsNonTotpURI above: that one has scheme "otpauth" but an
    // unsupported host ("hotp"), hitting the *second* guard (.unsupportedType). This
    // exercises the *first* guard — a URI whose scheme isn't "otpauth" at all — which
    // had no coverage of its own before this test.
    #expect(throws: TOTPError.self) {
        try TOTPGenerator.parse(otpauthURI: "https://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    }
}

@Test func rejectsInvalidBase32Secret() {
    // "1" is not in this type's Base32 alphabet (RFC 4648's is A-Z and 2-7; the
    // digits 0/1/8/9 are deliberately excluded to avoid visual confusion with O/I/B/S/Z
    // in real authenticator apps) — base32Decode returns nil, so parse() must throw
    // rather than silently produce a garbage/empty secret.
    #expect(throws: TOTPError.self) {
        try TOTPGenerator.parse(otpauthURI: "otpauth://totp/Example:alice?secret=11118")
    }
}

// MARK: - digits/period validation
//
// Regression coverage for a real crash: digits/period used to be parsed with a
// silent numeric fallback and no range check, so an out-of-range value (a
// malformed or adversarial QR code/otpauth URI) sailed through parse() only to
// trap — an uncatchable Swift runtime crash, not a throwable error — the next
// time currentCode(for:at:)/code(for:counter:) actually used it (UInt64
// conversion of a non-finite Double for period<=0, or integer overflow/
// division-by-zero in the digits-to-modulus math for out-of-range digits).
// These cases must be rejected at parse() time, before that can happen.

@Test func acceptsDigitsAtTheSupportedBoundary() throws {
    // 9 is the largest digit count whose 10^digits modulus still fits UInt32
    // (10^10 overflows UInt32.max) — see parse()'s own comment.
    let uri = "otpauth://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=9"
    let params = try TOTPGenerator.parse(otpauthURI: uri)
    #expect(params.digits == 9)
}

@Test func rejectsDigitsTooLarge() {
    let uri = "otpauth://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=10"
    #expect(throws: TOTPError.self) {
        try TOTPGenerator.parse(otpauthURI: uri)
    }
}

@Test func rejectsZeroOrNegativeDigits() {
    for digits in ["0", "-1"] {
        let uri = "otpauth://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=\(digits)"
        #expect(throws: TOTPError.self) {
            try TOTPGenerator.parse(otpauthURI: uri)
        }
    }
}

@Test func rejectsZeroOrNegativePeriod() {
    for period in ["0", "-30"] {
        let uri = "otpauth://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&period=\(period)"
        #expect(throws: TOTPError.self) {
            try TOTPGenerator.parse(otpauthURI: uri)
        }
    }
}

@Test func rejectsNonFinitePeriod() {
    // Foundation's TimeInterval(String) initializer parses the literal strings
    // "inf"/"nan" successfully (to non-finite Doubles), so these would otherwise
    // slip past a naive "TimeInterval(...) ?? 30" fallback undetected.
    for period in ["inf", "-inf", "nan"] {
        let uri = "otpauth://totp/Example:alice?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&period=\(period)"
        #expect(throws: TOTPError.self) {
            try TOTPGenerator.parse(otpauthURI: uri)
        }
    }
}
