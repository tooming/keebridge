// Copyright (c) 2026 Martin Tooming
// SPDX-License-Identifier: MIT
//
// Shared read-only surface over KDBXKit's two "vault is open" result
// types. Introduced for the first half of the KDBX attachment
// memory-footprint fix (see ROADMAP.md's "Read-only vault opens
// materialize every binary attachment" entry) — this file has no
// behavior of its own, just the seam the second half needs.

import KDBXKit

/// Anything that carries a decrypted vault's data tree.
///
/// `VaultService`'s read-only functions (`listEntries`, `revealField`,
/// `currentTOTPCode`, `passkeyMetadata`, `revealPasskeyPrivateKeyPEM`,
/// `revealEntry`, and `PaymentCard.swift`'s `listPaymentCards`/
/// `revealPaymentCardFields`/`paymentCardMetadata`) only ever walk
/// `.database` — never `.header`, `.innerHeader`, `.parserWarnings`, or a
/// binary attachment's decrypted bytes (confirmed by reading every one of
/// their bodies: `VaultLoginEntry`/`EntryDraft`/`VaultPasskeyMetadata`/
/// `VaultPaymentCard` only ever carry title/username/URL/password/notes/
/// custom-string field values). So they're generic over this protocol
/// instead of pinned to KDBXKit's eager `KDBXContent`, letting a caller
/// open a vault via either `KDBXReader.parse` (eager — every attachment's
/// bytes resident on `innerHeader.binaryContent[i].data` for the lifetime
/// of the open vault) or `KDBXReader.openMetadataOnly` (attachment bytes
/// never materialized — see `LazyKDBXContent`'s own doc comment) and reuse
/// every one of these read functions unchanged, with no duplicated logic
/// between the two paths.
///
/// Every WRITE path (`createEntry`/`updateEntry`/`deleteEntry`/
/// `mergeExtensionOriginatedPasskeys`) still requires the eager
/// `KDBXContent` specifically — `KDBXWriter.write(_:unlockData:)` only
/// accepts that concrete type — so this protocol is deliberately a
/// read-only surface, not a replacement for `KDBXContent` everywhere.
///
/// No `Self` or associated-type requirements, so `any VaultReadableContent`
/// self-conforms to this protocol (a plain Swift language feature, not
/// something special this file opts into) — `VaultService`'s internal
/// `openReadOnlyContent` returns the existential directly rather than
/// forcing every caller to be generic itself.
public protocol VaultReadableContent: Sendable {
    var database: KDBX { get }
}

extension KDBXContent: VaultReadableContent {}
extension LazyKDBXContent: VaultReadableContent {}
