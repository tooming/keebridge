# Add test coverage for KeeBridgeConfig's mirror-path functions

Fourteenth cycle this run. Checked a genuinely new angle: which `KeeBridgeCore` source
files have zero corresponding test coverage (`find` both `Sources/` and `Tests/`,
diff the names). Two came up with no dedicated test file and zero references anywhere
in the test suite: `KeeBridgeConfig.swift` and `KeychainStore.swift`.

## Why only `KeeBridgeConfig`, not `KeychainStore`

`KeychainStore.swift` calls the real macOS Security framework directly (`SecItemAdd`,
`SecItemCopyMatching`, biometry-gated `SecAccessControl`) with no injectable
abstraction — testing it meaningfully needs either real Keychain access (uncertain in
CI's headless macOS runner) or Touch ID hardware (which this repo's own README already
documents as unavailable everywhere this codebase is built and validated). Not a gap
this cycle can responsibly close without either adding a mockable protocol seam
(a larger refactor, its own item if pursued) or writing a test that might not even run
correctly in CI — left alone.

`KeeBridgeConfig.swift` is different: every function in it is a pure computation over
`NSHomeDirectory()` and string constants — no I/O, no Security framework, no
Touch ID — and it's the single source of truth for every mirror-file path
`VaultController`, `CredentialProviderViewController`, and `SafariWebExtensionHandler`
read from or write to. A wrong path here (a typo'd bundle ID, a swapped
provider/card-extension container, a wrong marker filename) would silently break mirror
sync in a way none of those callers' own tests would catch — they'd all agree with each
other and just point at the wrong place, since none of them re-derive the expected path
independently. Zero prior coverage of that risk.

## What changed

New `KeeBridgeCore/Tests/KeeBridgeCoreTests/KeeBridgeConfigTests.swift`, six tests:

- `vaultMirrorURLForApp()`/`cardVaultMirrorURLForApp()` land in the correct, *different*
  containers (a copy-paste bug swapping the provider/card-extension bundle IDs would
  make both return the same URL — asserted explicitly, not just each in isolation).
- `vaultMirrorURLForExtension()`/`cardVaultMirrorURLForExtension()` are home-directory-
  plus-filename only (no `Library/Containers/...` subpath — that shape is only correct
  from the app's side, since the sandboxed extension's `NSHomeDirectory()` is already
  redirected to its container root).
- `vaultMirrorLastWriteMarkerURLForApp()` sits in the exact same directory as the mirror
  file it tracks the write time of.

Tests check the *relative* structure appended onto `NSHomeDirectory()`, not the root
itself, matching how every real caller consumes these functions and how CI's home
directory (unlikely to be a real user's `/Users/<name>`) doesn't matter to the assertions.

## PR

See the PR that accompanies this file.
