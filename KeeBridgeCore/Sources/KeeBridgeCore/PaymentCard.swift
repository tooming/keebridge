// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT

import Foundation
import KDBXKit

public enum PaymentCardField: String, CaseIterable, Sendable {
    case number
    case holder
    case expiration
    case expirationMonth
    case expirationYear
    case verificationCode

    private static let aliases: [PaymentCardField: [String]] = [
        .number: [
            "card number", "card_number", "card-number", "cardnumber",
            "credit card number", "credit_card_number", "creditcardnumber",
            "cc number", "cc_number", "cc-number", "ccnumber", "ccnum",
            "primary account number", "primaryaccountnumber", "pan", "number",
        ],
        .holder: [
            "cardholder name", "cardholder_name", "cardholder-name", "cardholdername",
            "card holder", "card_holder", "cardholder", "name on card",
            "name_on_card", "nameoncard",
        ],
        .expiration: [
            "expiration date", "expiration_date", "expiration-date", "expirationdate",
            "expiry date", "expiry_date", "expiry-date", "expirydate",
            "card expiration", "card_expiration", "cardexpiry", "expires",
            "valid thru", "valid_thru", "validthru", "valid through", "validthrough",
            "cc exp", "cc_exp", "cc-exp", "ccexp",
        ],
        .expirationMonth: [
            "expiration month", "expiration_month", "expiration-month", "expirationmonth",
            "expiry month", "expiry_month", "expiry-month", "expirymonth",
            "exp month", "exp_month", "expmonth", "cc exp month", "cc-exp-month",
        ],
        .expirationYear: [
            "expiration year", "expiration_year", "expiration-year", "expirationyear",
            "expiry year", "expiry_year", "expiry-year", "expiryyear",
            "exp year", "exp_year", "expyear", "cc exp year", "cc-exp-year",
        ],
        .verificationCode: [
            "cvv", "cvv2", "cvc", "cvc2", "cid", "card security code",
            "card_security_code", "cardsecuritycode", "security code", "security_code",
            "securitycode", "verification number", "verification_number",
            "verificationnumber", "verification code", "verification_code",
            "verificationcode", "card verification value", "cardverificationvalue",
            "card verification code", "cardverificationcode",
        ],
    ]

    private static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    public static func recognizedField(forCustomFieldName name: String) -> PaymentCardField? {
        let candidate = normalized(name)
        return aliases.first { _, names in
            names.contains { normalized($0) == candidate }
        }?.key
    }

    /// A generic `number` field is accepted for Proton-style exports only
    /// when another unambiguous card field is present on the same entry.
    public static func isRecognizedCard(customFieldNames: [String]) -> Bool {
        let fields = Set(customFieldNames.compactMap(recognizedField(forCustomFieldName:)))
        return fields.contains(.number)
            && (!fields.isDisjoint(with: [.expiration, .expirationMonth, .expirationYear, .verificationCode]))
    }

    /// Human-readable label for this field, for read-only UI/CLI display
    /// (`EntryDetailView`'s "Payment Card" section, `VaultProbe card`) —
    /// never paired with the field's actual value in those surfaces, same
    /// "which fields exist, not what they contain" scope as passkey
    /// metadata display.
    public var displayName: String {
        switch self {
        case .number: return "Card Number"
        case .holder: return "Cardholder Name"
        case .expiration: return "Expiration Date"
        case .expirationMonth: return "Expiration Month"
        case .expirationYear: return "Expiration Year"
        case .verificationCode: return "CVV / Security Code"
        }
    }

    fileprivate static func value(in entry: KDBX.Entry, for field: PaymentCardField) -> String? {
        guard let names = aliases[field] else { return nil }
        for alias in names {
            let normalizedAlias = normalized(alias)
            if let value = entry.strings.first(where: { normalized($0.key) == normalizedAlias })?.value.revealedString,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

public struct VaultPaymentCard: Sendable {
    public let uuid: String
    public let title: String
    public let availableFields: [PaymentCardField]

    public init(uuid: String, title: String, availableFields: [PaymentCardField]) {
        self.uuid = uuid
        self.title = title
        self.availableFields = availableFields
    }
}

extension VaultService {
    /// Returns card-selection metadata only. No card field value crosses this
    /// boundary; values are revealed solely by `revealPaymentCardFields`.
    public func listPaymentCards(in content: KDBXContent) -> [VaultPaymentCard] {
        var cards: [VaultPaymentCard] = []

        func walk(_ group: KDBX.Group) {
            for entry in group.entries {
                let available = Set(entry.strings.compactMap {
                    PaymentCardField.recognizedField(forCustomFieldName: $0.key)
                })
                guard PaymentCardField.isRecognizedCard(
                    customFieldNames: entry.strings.map(\.key)
                ) else { continue }
                let title = entry.strings.first(where: { $0.key == "Title" })?.value.revealedString ?? ""
                cards.append(VaultPaymentCard(
                    uuid: "\(entry.uuid)",
                    title: title.isEmpty ? "(untitled card)" : title,
                    availableFields: PaymentCardField.allCases.filter(available.contains)
                ))
            }
            group.groups.forEach(walk)
        }

        walk(content.database.root.group)
        return cards
    }

    /// Reveals only the explicitly requested card fields and only from an
    /// entry recognized as a card (a known card-number custom field is
    /// required). Missing requested fields are omitted from the result.
    public func revealPaymentCardFields(
        in content: KDBXContent,
        entryUUID: String,
        fields: Set<PaymentCardField>
    ) -> [PaymentCardField: String]? {
        guard let entry = paymentCardEntry(in: content.database.root.group, uuid: entryUUID),
              PaymentCardField.isRecognizedCard(customFieldNames: entry.strings.map(\.key))
        else { return nil }

        var result: [PaymentCardField: String] = [:]
        for field in fields {
            if let direct = PaymentCardField.value(in: entry, for: field) {
                result[field] = direct
                continue
            }

            switch field {
            case .expiration:
                if let month = PaymentCardField.value(in: entry, for: .expirationMonth),
                   let year = PaymentCardField.value(in: entry, for: .expirationYear) {
                    result[field] = "\(month)/\(year)"
                }
            case .expirationMonth, .expirationYear:
                guard let expiration = PaymentCardField.value(in: entry, for: .expiration),
                      let parts = Self.paymentCardExpirationParts(expiration)
                else { continue }
                result[field] = field == .expirationMonth ? parts.month : parts.year
            default:
                break
            }
        }
        return result
    }

    /// Card-selection metadata (title + available field *types*, never
    /// values) for one entry, by UUID — the per-entry counterpart to
    /// `listPaymentCards(in:)`, used for read-only display (`EntryDetailView`'s
    /// "Payment Card" section, `VaultProbe card`). Returns `nil` if the UUID
    /// doesn't match any recognized card entry.
    public func paymentCardMetadata(in content: KDBXContent, entryUUID: String) -> VaultPaymentCard? {
        listPaymentCards(in: content).first { $0.uuid == entryUUID }
    }

    /// Same as `paymentCardMetadata(in:entryUUID:)`, opening the vault fresh
    /// from disk first — convenience for one-off reads (`VaultProbe`).
    public func paymentCardMetadata(at url: URL, masterPassword: String, entryUUID: String) throws -> VaultPaymentCard? {
        paymentCardMetadata(in: try openVault(at: url, masterPassword: masterPassword), entryUUID: entryUUID)
    }

    static func paymentCardExpirationParts(_ value: String) -> (month: String, year: String)? {
        let groups = value.split(whereSeparator: { !$0.isNumber }).map(String.init)
        if groups.count >= 2 {
            if groups[0].count == 4 {
                return (groups[1], groups[0])
            }
            return (groups[0], groups[1])
        }

        let digits = value.filter(\.isNumber)
        switch digits.count {
        case 4:
            return (String(digits.prefix(2)), String(digits.suffix(2)))
        case 6:
            return (String(digits.prefix(2)), String(digits.suffix(4)))
        default:
            return nil
        }
    }

    private func paymentCardEntry(in group: KDBX.Group, uuid: String) -> KDBX.Entry? {
        for entry in group.entries where "\(entry.uuid)" == uuid { return entry }
        for child in group.groups {
            if let entry = paymentCardEntry(in: child, uuid: uuid) { return entry }
        }
        return nil
    }
}
