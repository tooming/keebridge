# Vault mirror files were replaced non-atomically, racing both extensions' reads

`VaultController`'s mirroring functions (`mirrorVaultToExtension`/`mirrorVaultToExtensions`)
replaced the provider and card-extension mirror files with a `removeItem` + `copyItem`
sequence:

```swift
if fm.fileExists(atPath: mirrorURL.path) {
    try fm.removeItem(at: mirrorURL)
}
try fm.copyItem(at: source, to: mirrorURL)
```

`KeeBridgeProvider/CredentialProviderViewController.swift` and
`KeeBridgeCardExtension/SafariWebExtensionHandler.swift` are separate OS processes that read
this exact file path independently and asynchronously — each just checks
`FileManager.fileExists` then hands the path straight to `VaultService.openVault`. This
non-atomic replace left a real window where the mirror path was either momentarily missing
entirely, or present but only partially written by `copyItem`'s underlying `copyfile()`
call. A reader landing in that window sees a spurious "no vault mirror found"/`missingMirror`
response or a corrupt-KDBX open failure — through no fault of its own, and with no
retry-without-user-action path (the credential provider's `provideCredentialWithoutUserInteraction`
always cancels with `.userInteractionRequired` anyway, but the interactive/manual-list paths
would surface this as a plain failure).

This window isn't a remote edge case: `VaultController.refreshIfStale()` re-mirrors on every
`NSApplication.didBecomeActiveNotification` (throttled to once per 15s) — switching from
Safari back to KeeBridge and back again, which is exactly the normal autofill workflow, can
land a mirror refresh at the same moment either extension is independently reading that file.

The codebase already has, and follows, the correct standard for this exact class of problem
on the *source* vault: `VaultService.write(_:unlock:to:)` writes via
`AtomicFileWriter.write(data, to: url, backup: true)`, a pattern explicitly borrowed from
KDBXKit's own CLI specifically to avoid non-atomic writes. The mirror-copy path in
`VaultController` never adopted that same discipline — this fix brings it in line.

## Fix

New `VaultController.atomicallyReplaceMirror(at:withContentsOf:)`: copies `source` into a
temp file in the *same* directory as the destination mirror, then swaps it into place with
`FileManager.replaceItemAt` (backed by `rename()`, atomic on one volume) when a mirror
already exists, or `moveItem` (same underlying guarantee) for the very first mirror write. A
concurrent reader now always sees either the complete old file or the complete new one,
never a missing or partial one. Both `mirrorVaultToExtension` (the provider mirror) and
`mirrorVaultToExtensions` (the card mirror) now go through this one helper instead of their
own copies of the old remove+copy sequence.

Found via a fresh, adversarial read of `VaultController.swift`, cross-checked against
`VaultService`'s own existing atomic-write precedent for the source vault — a distinct
hazard from the passkey merge-back race already tracked in
`docs/done/2026-08-31-passkey-registration-write-path-spike.md` (that one is about *content*
correctness during a merge; this one is about a reader ever observing a *structurally
incomplete* file at all).

**Verification**: `VaultController` has no test target (same as every other app-layer fix in
this ROADMAP). Verified by reasoning about `FileManager.replaceItemAt`/`moveItem`'s
same-volume atomic-rename guarantees and by this repo's own `make build`/CI
(`xcodebuild`, macOS). This executor's environment has no local Swift/Xcode toolchain (see
`docs/backlog/2026-09-03-action-needed-backlog-blocked.md`), so this is validated via the
PR's own CI run rather than locally. No "still needs a human eyeball" caveat beyond the
general headless-only limitation — this is a plain filesystem-atomicity fix with no Touch
ID/UI dependency to reason about.

## PR

See the PR that accompanies this file.
