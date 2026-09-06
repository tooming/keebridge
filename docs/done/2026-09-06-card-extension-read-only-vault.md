# Thread the metadata-only read path into SafariWebExtensionHandler (part 2a of 3)

Part (2a) of the three-consumer split groomed after part (1)
(`docs/done/2026-09-06-vault-readable-content-refactor.md`) landed: thread
`VaultReadableContent`/the metadata-only read path into the session caches that hold a
`KDBXContent` across multiple requests, starting with the cleanest-boundary consumer.

## What changed

- Traced `SafariWebExtensionHandler`'s full call graph before touching anything: it only
  ever calls `vaultService.listPaymentCards(in:)` and `vaultService.revealPaymentCardFields
  (in:...)` — no `createEntry`/`updateEntry`/`deleteEntry`/`setPasskey` call anywhere in
  the file. Unlike `VaultController`/`CredentialProviderViewController` (both write, and
  re-cache after writing), this consumer is 100% read-only, so it carries none of the
  "re-open after a write" complexity the original grooming note flagged as needing
  careful per-file tracing — the safest of the three to migrate first.
- New public `VaultService.openReadOnlyVault(at url: URL, masterPassword: String)` /
  `openReadOnlyVault(at url: URL, rawKeyData: Data)`, mirroring the existing public
  `openVault(at:...)` pair's shape exactly. Discovered while implementing (not assumed in
  the prior grooming pass): `VaultService.openReadOnlyContent` — the function part (1)
  added — is package-internal, so it's invisible from `KeeBridgeCardExtension`, a
  separate Swift module that only sees `KeeBridgeCore`'s `public` API. These two new
  methods are thin wrappers around `openReadOnlyContent`, and are the reusable entry
  point the remaining two consumers (part 2b/2c, still open in `ROADMAP.md`) will call
  too.
- `SafariWebExtensionHandler`'s `cachedContent: KDBXContent?` → `(any
  VaultReadableContent)?`; `unlockedContent(at:password:) throws -> KDBXContent?` →
  `throws -> (any VaultReadableContent)?`; `cache(content: KDBXContent, ...)` →
  `cache(content: any VaultReadableContent, ...)`; both `vaultService.openVault(at:...)`
  call sites switched to `vaultService.openReadOnlyVault(at:...)`. The now-unused `import
  KDBXKit` removed (it was there only for the `KDBXContent` type annotation).
- No behavior change to the extension's own request handling, caching TTL, Keychain
  interaction, or biometric-unlock flow — only which underlying KDBXKit read API backs
  the cached content.

## Testing

New `openReadOnlyVaultReturnsLazyContentMatchingOpenReadOnlyContent` in
`VaultReadableContentTests.swift`: confirms both the `masterPassword` and `rawKeyData`
forms of `openReadOnlyVault` return a `LazyKDBXContent`, and that `listEntries(in:)` on
either agrees with the existing `at url:` convenience for the same vault. This exercises
the same "pass an `any VaultReadableContent` existential directly into a
`some VaultReadableContent`-generic function" self-conformance pattern part (1)'s
`openReadOnlyContent`-backed convenience methods already use — confirmed compiling and
passing there by part (1)'s green CI run, which is why this cycle had confidence
extending the same pattern to a second module (`KeeBridgeCardExtension`) was low-risk
despite no direct test coverage of `SafariWebExtensionHandler` itself (it has no test
target, same as every other app/extension-layer file in this ROADMAP — verified only by
`xcodebuild` compiling it, same as always).

**Environment note**: same as part (1) — this cycle's executor had no Swift toolchain or
macOS available locally. Validated by reading the diff adversarially and relying on this
repo's GitHub Actions CI (`macos-latest`) to actually compile/run `make ci` before
self-merge.

## PR

See the pull request this file's commit is part of.
