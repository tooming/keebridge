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
