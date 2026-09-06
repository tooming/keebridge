# Read-only vault opens: metadata-only path (part 1 of 2)

Part (1) of the two-part split the ROADMAP's KDBX attachment memory-footprint spike
recommended: a narrow `VaultService`-internal refactor introducing a shared read-only
surface both KDBXKit's eager `KDBXContent` and its metadata-only `LazyKDBXContent` can
satisfy, with the one-off `at url:` read convenience methods switched from the eager
`KDBXReader.parse` to `KDBXReader.openMetadataOnly` — while every write path keeps the
eager path unchanged.

## What changed

- New `VaultReadableContent` protocol (`KeeBridgeCore/Sources/KeeBridgeCore/
  VaultReadableContent.swift`): `var database: KDBX { get }`. `KDBXContent` and
  `LazyKDBXContent` both conform via an empty extension — both types already expose
  `.database` publicly, so no changes needed to the pinned KDBXKit dependency itself.
- Every `VaultService`/`PaymentCard.swift` read-only `in content:` function
  (`listEntries`, `revealField`, `currentTOTPCode`, `passkeyMetadata`,
  `revealPasskeyPrivateKeyPEM`, `revealEntry`, `listPaymentCards`,
  `revealPaymentCardFields`, `paymentCardMetadata`) is now generic over
  `some VaultReadableContent` instead of pinned to `KDBXContent`. Confirmed by reading
  every one of their bodies first: none touch `.header`/`.innerHeader`/`.parserWarnings`
  or a binary attachment's bytes, only `.database` — so this is a source-compatible
  widening, not a behavior change, for every existing caller that already passes a
  `KDBXContent`.
- New `VaultService.openReadOnlyContent(at:unlock:) -> any VaultReadableContent`
  (package-internal, not `private`, so tests can call it directly): opens via
  `KDBXReader.openMetadataOnly` first. `LazyKDBXContent`'s own doc comment: "the binary
  payload bytes that would have lived on `innerHeader.binaryContent[i].data` are
  intentionally not retained." Falls back to the eager `KDBXReader.parse` only for
  `KDBXReader.Error.unsupportedFormatVersion(major: 3, ...)` — KDBX 3.x has no separable
  binary pool `openMetadataOnly` can re-slice later, matching that API's own documented
  guidance to callers. Any other error (wrong password, corrupted file, an unsupported
  format `parse` itself would also reject) is NOT treated as a fallback trigger; it
  propagates as `VaultServiceError.openFailed`, same as the existing eager path.
- Every one-off `at url:` read convenience routed through the new path: `listEntries(at:
  masterPassword/rawKeyData:)`, `revealField(at:...)`, `currentTOTPCode(at:...)`,
  `passkeyMetadata(at:...)`, `paymentCardMetadata(at:masterPassword:)`,
  `revealEntry(uuid:at:...)`. `VaultProbe`'s six read subcommands call these exclusively,
  so they get the memory-footprint fix with no changes of their own.
- `openVault(at:masterPassword/rawKeyData:)` (returning the concrete `KDBXContent`) is
  UNCHANGED, on purpose — the app (`VaultController`), `KeeBridgeProvider`
  (`CredentialProviderViewController`), and `KeeBridgeCardExtension`
  (`SafariWebExtensionHandler`) all cache its result across a session, and every WRITE
  path (`createEntry`/`updateEntry`/`deleteEntry`/`mergeExtensionOriginatedPasskeys`)
  still needs the eager type — `KDBXWriter.write(_:unlockData:)` only accepts
  `KDBXContent`. Threading the lighter path through those three session caches is the
  deliberately-deferred part (2) — see the new ROADMAP.md follow-up bullet.

## Testing

New `VaultReadableContentTests.swift` in `KeeBridgeCoreTests`:

- `openReadOnlyContentReturnsLazyContentForAnOrdinaryVault` — confirms the metadata-only
  path is actually taken for a normal KDBX 4.1 vault (not silently falling back to eager
  every time).
- `openReadOnlyContentCapturesAttachmentMetadataWithoutRetainingBytes` — builds a vault
  with a real binary attachment (via KDBXKit's own `InnerHeader.BinaryContent`/
  `KDBX.ProtectedBinary`, the same low-level construction pattern `PasskeyTests.swift`
  already uses for KDBXKit-only fields — no binary fixture file needed), confirms the
  returned `LazyKDBXContent` captures size/hash metadata for it while having no `.data`
  field to retain the decrypted bytes on at all — a structural guarantee, not just a
  runtime check.
- `readOnlyFunctionsAgreeBetweenEagerAndMetadataOnlyOpens` — the actual regression net:
  for a vault carrying a real attachment, every read function (`listEntries`,
  `revealField`, `currentTOTPCode`, `revealEntry`) produces identical results whether
  backed by the eager or the metadata-only open.
- `openReadOnlyContentFallsBackToEagerParseForUnsupportedFormatVersionOnly` — a garbage
  (non-KDBX) file still throws normally rather than being silently swallowed by the 3.x
  fallback, proving that fallback is scoped to exactly the one documented error case.
- `openReadOnlyContentThrowsFileNotFoundForMissingVault` — existing error-path parity.

Existing tests continue to exercise the new path with no changes of their own:
`VaultServiceTests.swift`'s `openVaultPlusInMemoryReadsMatchTheAtURLConvenience` already
asserted the `at url:` convenience and `openVault`-plus-`in content:` produce identical
results — that assertion now specifically covers "metadata-only open vs. eager open agree",
which it didn't before this change. Every `PasskeyTests.swift`/`PaymentCardTests.swift`
test that calls an `at url:` convenience (most of them) now exercises the metadata-only
path end-to-end too.

**Environment note**: this PR could not be validated with a local `swift test`/`xcodebuild`
run — the executor's environment for this cycle had no Swift toolchain or macOS available
at all (not even the usual "headless, no GUI/Touch ID hardware" limitation this ROADMAP
already documents elsewhere — literally no `swift` binary, no Docker daemon to fall back
to). Every code change here was validated by careful reading of the pinned KDBXKit
dependency's own source (cloned read-only to check exact signatures: `KDBXReader
+Lazy.swift`, `LazyKDBXContent.swift`, `KDBXContent.swift`, `ProtectedBinary.swift`,
`InnerHeader.swift`, `BinaryMetadata.swift`) rather than compiler feedback. This PR relies
on the repo's own GitHub Actions CI (`macos-latest`) to actually run `make ci` before
self-merge, per `docs/WAYS-OF-WORKING.md`'s "CI green is necessary" gate and this file's
own PR-babysitting instructions — flagged here prominently since it's a first for this
ROADMAP's done-log, not the usual "still needs a human eyeball on real hardware" caveat.

## PR

See the pull request this file's commit is part of.
