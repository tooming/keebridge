// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import KDBXKit
@testable import KeeBridgeCore

@Test func paymentCardAliasesRecognizeCommonAndProtonNames() {
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "Card Number") == .number)
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "credit_card_number") == .number)
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "number") == .number)
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "Expiration Date") == .expiration)
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "expiration_month") == .expirationMonth)
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "Verification Number") == .verificationCode)
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "name-on-card") == .holder)
}

@Test func paymentCardAliasesRejectGenericLoginFields() {
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "Password") == nil)
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "UserName") == nil)
    #expect(PaymentCardField.recognizedField(forCustomFieldName: "PIN") == nil)
    #expect(!PaymentCardField.isRecognizedCard(customFieldNames: ["number", "PIN"]))
    #expect(PaymentCardField.isRecognizedCard(
        customFieldNames: ["number", "expirationDate", "verificationNumber"]
    ))
}

@Test func paymentCardExpirationParsingHandlesCommonFormats() {
    let slash = VaultService.paymentCardExpirationParts("04/29")
    #expect(slash?.month == "04")
    #expect(slash?.year == "29")

    let monthInput = VaultService.paymentCardExpirationParts("2029-04")
    #expect(monthInput?.month == "04")
    #expect(monthInput?.year == "2029")

    let compact = VaultService.paymentCardExpirationParts("042029")
    #expect(compact?.month == "04")
    #expect(compact?.year == "2029")
    #expect(VaultService.paymentCardExpirationParts("not a date") == nil)
}

@Test func paymentCardListingIsMetadataOnlyAndRevealIsRequestScoped() throws {
    var content = KDBXContent.makeEmpty(databaseName: "Card Test")
    let cardID = UUID()
    content.database.root.group.entries.append(KDBX.Entry(
        uuid: cardID,
        times: KDBX.Times(),
        strings: [
            KDBX.ProtectedString(key: "Title", value: .regular("Personal Visa")),
            KDBX.ProtectedString(key: "number", value: .regular("4111111111111111")),
            KDBX.ProtectedString(key: "expirationDate", value: .regular("04/29")),
            KDBX.ProtectedString(key: "verificationNumber", value: .regular("123")),
            KDBX.ProtectedString(key: "Password", value: .regular("must-not-leak")),
        ]
    ))
    content.database.root.group.entries.append(KDBX.Entry(
        uuid: UUID(),
        times: KDBX.Times(),
        strings: [
            KDBX.ProtectedString(key: "Title", value: .regular("Not a card")),
            KDBX.ProtectedString(key: "number", value: .regular("42")),
            KDBX.ProtectedString(key: "PIN", value: .regular("0000")),
        ]
    ))

    let service = VaultService()
    let cards = service.listPaymentCards(in: content)
    #expect(cards.count == 1)
    #expect(cards[0].uuid == "\(cardID)")
    #expect(cards[0].title == "Personal Visa")

    let fields = try #require(service.revealPaymentCardFields(
        in: content,
        entryUUID: "\(cardID)",
        fields: [.number, .expirationMonth]
    ))
    #expect(fields == [.number: "4111111111111111", .expirationMonth: "04"])
    #expect(fields[.verificationCode] == nil)
    #expect(fields.values.contains("must-not-leak") == false)
}

// MARK: - Read-only visibility (isPaymentCard flag + per-entry metadata)
//
// Mirrors the passkey-visibility tests: a card entry must be flagged in
// listEntries() and have per-entry metadata (title + available field
// *types*, never values) resolvable by UUID; a non-card entry must not.

@Test func listEntriesFlagsRecognizedPaymentCards() {
    var content = KDBXContent.makeEmpty(databaseName: "Card Visibility Test")
    let cardID = UUID()
    content.database.root.group.entries.append(KDBX.Entry(
        uuid: cardID,
        times: KDBX.Times(),
        strings: [
            KDBX.ProtectedString(key: "Title", value: .regular("Personal Visa")),
            KDBX.ProtectedString(key: "Card Number", value: .regular("4111111111111111")),
            KDBX.ProtectedString(key: "CVV", value: .regular("123")),
        ]
    ))
    let plainID = UUID()
    content.database.root.group.entries.append(KDBX.Entry(
        uuid: plainID,
        times: KDBX.Times(),
        strings: [
            KDBX.ProtectedString(key: "Title", value: .regular("Just a login")),
            KDBX.ProtectedString(key: "UserName", value: .regular("alice")),
            KDBX.ProtectedString(key: "Password", value: .regular("hunter2")),
        ]
    ))

    let entries = VaultService().listEntries(in: content)
    #expect(entries.first { $0.uuid == "\(cardID)" }?.isPaymentCard == true)
    #expect(entries.first { $0.uuid == "\(plainID)" }?.isPaymentCard == false)
}

@Test func paymentCardMetadataReturnsAvailableFieldTypesOnlyByUUID() throws {
    var content = KDBXContent.makeEmpty(databaseName: "Card Metadata Test")
    let cardID = UUID()
    content.database.root.group.entries.append(KDBX.Entry(
        uuid: cardID,
        times: KDBX.Times(),
        strings: [
            KDBX.ProtectedString(key: "Title", value: .regular("Business Amex")),
            KDBX.ProtectedString(key: "Card Number", value: .regular("378282246310005")),
            KDBX.ProtectedString(key: "Expiration Date", value: .regular("11/28")),
        ]
    ))

    let service = VaultService()
    let metadata = try #require(service.paymentCardMetadata(in: content, entryUUID: "\(cardID)"))
    #expect(metadata.title == "Business Amex")
    #expect(Set(metadata.availableFields) == [.number, .expiration])
    #expect(service.paymentCardMetadata(in: content, entryUUID: "\(UUID())") == nil)
}

@Test func paymentCardFieldDisplayNamesAreHumanReadable() {
    #expect(PaymentCardField.number.displayName == "Card Number")
    #expect(PaymentCardField.verificationCode.displayName == "CVV / Security Code")
}

// MARK: - revealPaymentCardFields split-field <-> combined .expiration synthesis
//
// revealPaymentCardFields synthesizes in both directions when a requested field isn't
// stored directly: combined "Expiration Date" -> split .expirationMonth/.expirationYear
// (already covered above, via paymentCardListingIsMetadataOnlyAndRevealIsRequestScoped's
// .expirationMonth request against an "expirationDate" field) and, the opposite
// direction, split "Expiration Month"/"Expiration Year" -> combined .expiration. That
// second direction is live, secret-touching, extension-reachable code
// (KeeBridgeCardExtension's content.js requests "expiration" for any autocomplete="cc-exp"
// field) but had no test coverage at all before these two.

@Test func revealPaymentCardFieldsSynthesizesCombinedExpirationFromSplitFields() throws {
    var content = KDBXContent.makeEmpty(databaseName: "Split Expiration Test")
    let cardID = UUID()
    content.database.root.group.entries.append(KDBX.Entry(
        uuid: cardID,
        times: KDBX.Times(),
        strings: [
            KDBX.ProtectedString(key: "Title", value: .regular("Split Expiry Card")),
            KDBX.ProtectedString(key: "Card Number", value: .regular("4111111111111111")),
            KDBX.ProtectedString(key: "Expiration Month", value: .regular("04")),
            KDBX.ProtectedString(key: "Expiration Year", value: .regular("2029")),
        ]
    ))

    let service = VaultService()
    let fields = try #require(service.revealPaymentCardFields(
        in: content,
        entryUUID: "\(cardID)",
        fields: [.expiration]
    ))
    #expect(fields == [.expiration: "04/2029"])
}

@Test func revealPaymentCardFieldsOmitsCombinedExpirationWhenOnlyOneSplitFieldIsPresent() throws {
    var content = KDBXContent.makeEmpty(databaseName: "Partial Split Expiration Test")
    let cardID = UUID()
    content.database.root.group.entries.append(KDBX.Entry(
        uuid: cardID,
        times: KDBX.Times(),
        strings: [
            KDBX.ProtectedString(key: "Title", value: .regular("Month Only Card")),
            KDBX.ProtectedString(key: "Card Number", value: .regular("4111111111111111")),
            KDBX.ProtectedString(key: "Expiration Month", value: .regular("04")),
        ]
    ))

    let service = VaultService()
    // "number" + "Expiration Month" alone is enough to be recognized as a card (per
    // PaymentCardField.isRecognizedCard), but revealPaymentCardFields still can't
    // synthesize a combined .expiration without a year — it should omit the field
    // rather than emit a malformed "04/" value.
    let fields = try #require(service.revealPaymentCardFields(
        in: content,
        entryUUID: "\(cardID)",
        fields: [.expiration, .expirationMonth]
    ))
    #expect(fields[.expiration] == nil)
    #expect(fields[.expirationMonth] == "04")
}
