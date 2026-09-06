# Thread the metadata-only read path into VaultController (part 2b of 3)

Part (2b) of the three-consumer split groomed after part (2a)
(`docs/done/2026-09-06-card-extension-read-only-vault.md`) landed: thread
`VaultReadableContent`/`VaultService.openReadOnlyVault` into the app's own session
cache.

## What changed

- Traced `VaultController`'s full call graph before touching anything, per the same
  discipline part (2a) used. Finding: all 5 `vaultService.openVault(at:...)` call sites
  in this file (`unlock`, `refresh`, and the post-write re-list inside each of
  `createEntry`/`updateEntry`/`deleteEntry`) are themselves READ-ONLY re-opens — every
  actual WRITE goes through `vaultService.createEntry`/`updateEntry`/`deleteEntry`
  directly, which are unaffected and unchanged (still the eager path internally, per
  part (1)'s scope). `cachedContent` is only ever assigned from the return value of one
  of those 5 read re-opens, never from a write call's own return value (those return a
  UUID string or `Void`). The file's own header comment ("Never writes to the *source*
  vault — read-only against it") turned out to be stale/inaccurate about writes existing
  at all (this file's `createEntry`/`updateEntry`/`deleteEntry` methods clearly do write,
  via `VaultService`), but the *cache* itself really was read-only-only, which is the
  part that mattered for this change — so this consumer had NONE of the write-path
  complexity the original grooming note worried about.
- `VaultController.cachedContent: KDBXContent?` → `(any VaultReadableContent)?`. All 5
  `openVault(at:...)` call sites switched to `openReadOnlyVault(at:...)`.
  `populateIdentityStore(entries:content:)` — the one place taking `content` as an
  explicit parameter, used only via the already-generic
  `VaultService.passkeyMetadata(in:entryUUID:)` — had its parameter type switched from
  `KDBXContent` to `any VaultReadableContent` to match. The now-unused `import KDBXKit`
  removed (it was there only for the `KDBXContent` type annotations). Comments
  referencing `openVault`/`KDBXContent` updated to match the new reality where they
  explained caching rationale.
- No behavior change to unlock/refresh timing, Keychain/Touch-ID interaction, mirror
  writes, or `ASCredentialIdentityStore` population — only which underlying KDBXKit read
  API backs `cachedContent`.

## Testing

`VaultController` has no test target (SwiftUI/AppKit app layer, same as every other
app-layer file in this ROADMAP) — verified by `xcodebuild` compiling it, same as always.
The underlying `openReadOnlyVault`/`VaultReadableContent` machinery this change routes
through is already covered by `KeeBridgeCoreTests` (`VaultReadableContentTests.swift`,
landed in parts (1) and (2a)), and by part (2a)'s own PR having proven the same
self-conformance pattern (`any VaultReadableContent` passed into a
`some VaultReadableContent`-generic function) compiles cleanly across a module boundary.

**Environment note**: same as parts (1)/(2a) — this cycle's executor had no Swift
toolchain or macOS available locally. Validated by reading the diff adversarially and
relying on this repo's GitHub Actions CI (`macos-latest`) to actually compile `make ci`
before self-merge.

## PR

See the pull request this file's commit is part of.
