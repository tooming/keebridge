// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT

import Foundation
import SafariServices
import KeeBridgeCore
import KDBXKit
import os

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let vaultService = VaultService()
    private let keychain = KeychainStore(service: KeeBridgeConfig.cardExtensionKeychainService)
    private let log = Logger(subsystem: "com.martintooming.KeeBridge", category: "card-extension")
    private static let workQueue = DispatchQueue(
        label: "com.martintooming.KeeBridge.CardExtension.work",
        qos: .userInitiated
    )
    private var cachedPreHash: Data?
    private var cachedContent: KDBXContent?
    private var cachedContentDate: Date?
    private var cachedMirrorDate: Date?
    private static let cacheTTL: TimeInterval = 5 * 60

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any]
        else {
            complete(context, response: ["ok": false, "status": "invalidRequest"])
            return
        }

        Self.workQueue.async { [self] in
            handle(message, context: context)
        }
    }

    private func handle(_ message: [String: Any], context: NSExtensionContext) {
        guard let action = message["action"] as? String else {
            complete(context, response: ["ok": false, "status": "invalidRequest"])
            return
        }
        guard let vaultURL = mirroredVaultURL else {
            complete(context, response: ["ok": false, "status": "missingMirror"])
            return
        }

        do {
            let suppliedPassword = message["password"] as? String
            guard let content = try unlockedContent(at: vaultURL, password: suppliedPassword) else {
                complete(context, response: ["ok": false, "status": "locked"])
                return
            }

            switch action {
            case "listCards", "unlock":
                let cards = vaultService.listPaymentCards(in: content).map { card in
                    [
                        "id": card.uuid,
                        "title": card.title,
                        "availableFields": card.availableFields.map(\.rawValue),
                    ] as [String: Any]
                }
                complete(context, response: ["ok": true, "status": "ok", "cards": cards])

            case "fillCard":
                guard let cardID = message["cardID"] as? String,
                      let names = message["fields"] as? [String]
                else {
                    complete(context, response: ["ok": false, "status": "invalidRequest"])
                    return
                }
                let requested = Set(names.compactMap(PaymentCardField.init(rawValue:)))
                guard !requested.isEmpty, requested.count == names.count,
                      let revealed = vaultService.revealPaymentCardFields(
                        in: content, entryUUID: cardID, fields: requested
                      )
                else {
                    complete(context, response: ["ok": false, "status": "cardNotFound"])
                    return
                }
                let values = Dictionary(uniqueKeysWithValues: revealed.map { ($0.key.rawValue, $0.value) })
                complete(context, response: ["ok": true, "status": "ok", "values": values])

            default:
                complete(context, response: ["ok": false, "status": "invalidRequest"])
            }
        } catch {
            log.error("native card request failed: \(String(describing: error), privacy: .public)")
            complete(context, response: ["ok": false, "status": "error"])
        }
    }

    private var mirroredVaultURL: URL? {
        let url = KeeBridgeConfig.cardVaultMirrorURLForExtension()
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func unlockedContent(at url: URL, password: String?) throws -> KDBXContent? {
        let mirrorDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let content = cachedContent,
           let cachedAt = cachedContentDate,
           Date().timeIntervalSince(cachedAt) < Self.cacheTTL,
           mirrorDate == cachedMirrorDate {
            return content
        }

        let preHash: Data
        if let password, !password.isEmpty {
            do {
                let content = try vaultService.openVault(at: url, masterPassword: password)
                preHash = vaultService.preHashKeyData(forPassword: password)
                try keychainOnMain { try keychain.store(
                    preHash, account: KeeBridgeConfig.cardExtensionKeychainAccount
                ) }
                cache(content: content, preHash: preHash, mirrorDate: mirrorDate)
                return content
            } catch {
                throw error
            }
        } else if let cached = cachedPreHash {
            preHash = cached
        } else {
            do {
                guard let stored = try keychainOnMain({
                    try keychain.read(
                        account: KeeBridgeConfig.cardExtensionKeychainAccount,
                        reason: "Unlock KeeBridge cards in Safari"
                    )
                }) else { return nil }
                preHash = stored
            } catch {
                // Biometric cancellation/failure leaves the request locked so
                // the user can choose the secure password page instead.
                return nil
            }
        }

        do {
            let content = try vaultService.openVault(at: url, rawKeyData: preHash)
            cache(content: content, preHash: preHash, mirrorDate: mirrorDate)
            return content
        } catch {
            cachedPreHash = nil
            keychainOnMain {
                keychain.delete(account: KeeBridgeConfig.cardExtensionKeychainAccount)
            }
            return nil
        }
    }

    private func cache(content: KDBXContent, preHash: Data, mirrorDate: Date?) {
        cachedContent = content
        cachedContentDate = Date()
        cachedMirrorDate = mirrorDate
        cachedPreHash = preHash
    }

    private func keychainOnMain<T>(_ operation: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try operation() }
        return try DispatchQueue.main.sync(execute: operation)
    }

    private func complete(_ context: NSExtensionContext, response: [String: Any]) {
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
