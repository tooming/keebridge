# Thread the metadata-only read path into CredentialProviderViewController (part 2c of 3)

Part (2c) of the three-consumer split groomed after part (2b)
(`docs/done/2026-09-06-app-read-only-vault.md`) landed — the last of the three original
session-cache consumers (`SafariWebExtensionHandler`, `VaultController`,
`CredentialProviderViewController`). This closes out the full 3-part follow-up to the
original attachment memory-footprint fix
(`docs/done/2026-09-06-vault-readable-content-refactor.md`).

## What changed

- Traced `CredentialProviderViewController`'s full call graph before touching anything,
  same discipline parts (2a)/(2b) used — NOT assumed to be as clean a migration as part
  (2b) turned out to be, given this file is meaningfully larger (952 lines vs.
  `VaultController`'s ~685) and handles more flows: password/OTP autofill, passkey
  assertion, interactive AND conditional (silent) passkey registration, and the manual
  credential picker.
- Finding: it turned out just as clean as part (2b). Both `openVault` call sites
  (`openContentThenProceed`, the pre-hash unlock path; `handleUnlock`, the
  master-password unlock path) are themselves read-only opens whose result only ever
  gets cached and read from. Every one of the 8 functions taking `content` as an
  explicit parameter — `proceed(withContent:)`, `completeCredential(for:content:)`,
  `completePasskeyAssertion(for:content:)`, `beginPasskeyRegistration(for:content:)`,
  `completePasswordCredential(content:recordIdentifier:username:)`,
  `completeOTPCredential(content:recordIdentifier:)`, `showList(content:)`,
  `completeSelection(entry:content:)` — only ever reads through it, via functions already
  generic over `VaultReadableContent` (`listEntries`, `revealField`, `currentTOTPCode`,
  `revealPasskeyPrivateKeyPEM`, `passkeyMetadata`).
- This file's one WRITE (`completePasskeyRegistration`'s `vaultService.setPasskey`)
  doesn't take `content` as a parameter at all — it opens its own fresh copy internally
  via `vaultURL`/`Self.cachedPreHash`, independent of whatever's cached in
  `Self.cachedContent`. The pre-existing code already explicitly invalidates (sets to
  `nil`, doesn't re-cache) `Self.cachedContent`/`Self.cachedContentDate` right after that
  write completes — exactly the "never write through this cache, and don't even trust it
  stale after a write" pattern parts (2a)/(2b) both had, just with an extra explicit
  invalidation step this file already had before this change (unrelated to it).
- `Self.cachedContent: KDBXContent?` → `(any VaultReadableContent)?`;
  `validCachedContent() -> KDBXContent?` → `-> (any VaultReadableContent)?`. Both
  `vaultService.openVault(at:...)` call sites switched to
  `vaultService.openReadOnlyVault(at:...)`. All 8 `content: KDBXContent` parameter types
  switched to `content: any VaultReadableContent`. The now-unused `import KDBXKit`
  removed. Comments referencing `openVault`/`KDBXContent` updated where they explained
  caching/threading rationale — including labeling this "v7" in the file's own header
  comment, following its existing v1–v6 versioning convention for prior feature waves
  (v1 passwords/TOTP, v3 session cache, v4 passkey assertion, v5 passkey registration, v6
  conditional registration).
- No behavior change to unlock flow, Touch ID/Keychain interaction, the manual picker,
  or any passkey flow — only which underlying KDBXKit read API backs `cachedContent`.

## Testing

`CredentialProviderViewController` has no test target (extension UI layer, same as
`VaultController` and every other app/extension-layer file in this ROADMAP) — verified
by `xcodebuild` compiling it. The underlying `openReadOnlyVault`/`VaultReadableContent`
machinery is already covered by `KeeBridgeCoreTests`, and parts (2a)/(2b) already proved
the same self-conformance pattern (`any VaultReadableContent` passed into a
`some VaultReadableContent`-generic function) compiles cleanly, including across a
module boundary (2a) and inside `Task`/`DispatchQueue`-crossing closures under Swift 6
strict concurrency (2b) — this file's `workQueue.async`/`DispatchQueue.main.async`
closures capturing `content` are the same shape.

**Environment note**: same as parts (1)/(2a)/(2b) — this cycle's executor had no Swift
toolchain or macOS available locally. Validated by reading the diff adversarially and
relying on this repo's GitHub Actions CI (`macos-latest`) to actually compile `make ci`
before self-merge.

## PR

See the pull request this file's commit is part of.
