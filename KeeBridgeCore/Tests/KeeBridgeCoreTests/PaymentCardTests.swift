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
