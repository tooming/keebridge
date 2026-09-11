# `CredentialProviderViewController`'s "no vault mirror found" message dead-ended

## The bug

`CredentialProviderViewController.showMessage(_:)` embeds a plain,
non-interactive SwiftUI `Text` view — no button, no field, no way to trigger
any further action from inside it. `docs/done/2026-09-11-provider-unlock-retry.md`
(#116) already fixed the two `handleUnlock` failure paths that used it, but
two more call sites still went straight to `showMessage(...)` when `vaultURL`
was `nil` — i.e. no vault mirror exists yet at
`KeeBridgeConfig.vaultMirrorURLForExtension()`:

- `showUnlockOrProceed()`, the very first thing every request-handling
  override (`prepareCredentialList`, `prepareInterfaceToProvideCredential`,
  `prepareInterface(forPasskeyRegistration:)`) calls.
- `openContentThenProceed(preHash:)`, reached when a pre-hash is already
  cached but the vault URL vanished between calls (e.g. the mirror was
  deleted after an earlier successful unlock this process's lifetime).

This is a real, reachable, first-use path: anyone who enables the KeeBridge
AutoFill provider in System Settings before ever opening the main KeeBridge
app and picking a `vault.kdbx` hits it immediately on the very first autofill
attempt. Before this fix, the credential provider sheet showed:

> Open KeeBridge on this Mac and pick your vault.kdbx first.

with no button. The only way out was Escape, cancelling the entire autofill
request — even for a user who, having read that message, switched to the main
app, picked their vault, unlocked it (mirroring it into this extension's
container), and switched back to Safari with this exact sheet still open.
There was no way to tell the still-open sheet to look again.

## The fix

`vaultURL` is a computed property (`KeeBridgeConfig.vaultMirrorURLForExtension()`
+ a live `FileManager.fileExists` check) — re-evaluating it always reflects
the current filesystem state, not a stale snapshot from when the sheet first
appeared. Both call sites now call a new `showNoVaultMirrorMessage()`, which
embeds a `NoVaultMirrorView` (same shape as the existing `UnlockView`): the
same message text, plus a "Try Again" button that calls
`showUnlockOrProceed()` again. If the mirror now exists, the retry proceeds
normally (Touch ID / cached key / unlock prompt, whichever applies); if it
still doesn't, the same retry-capable message reappears — no dead end either
way.

`showUnlockOrProceed()`'s existing re-entrancy guard (`guard !isWorking else
{ ...; respondCancel(.failed); return }`) is safe to re-enter here:
`isWorking` is still `false` at the point this dead end is reached (it's only
set `true` after the `vaultURL != nil` check succeeds), so the retry isn't
rejected as a concurrent invocation. The 30-second request watchdog armed by
`beginRequest()` still bounds the whole flow, same as it already does for
#116's unlock-prompt retry — clicking "Try Again" doesn't reset or extend it.

`showMessage(_:)` itself is untouched and still used for the one case where
it's correct: `handleUnlock`'s "Unlocking…" progress text, which isn't a
dead end (a terminal response — success, or one of the two retry-capable
error paths — always follows shortly after).

## Verification

Compiled-only (`xcodebuild build`, unsigned, via CI's `macos-latest` runner —
this executor has no local Swift toolchain or macOS GUI). This extension's
`NSViewController`/SwiftUI layer has no test target, same as every other
`CredentialProviderViewController.swift` change in this ROADMAP (#116
included) — `KeeBridgeCore`'s own `swift test` suite is unaffected since this
file lives in `KeeBridgeProvider`, not `KeeBridgeCore`.

Still needs a human eyeball: confirming the retry flow actually feels right
in a real Safari autofill popover, and that switching to the main app,
picking a vault, and switching back really does leave this sheet's "Try
Again" button working as described — this executor has no GUI to click
through the flow itself.
