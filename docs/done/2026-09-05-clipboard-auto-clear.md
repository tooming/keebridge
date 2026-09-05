# Copied passwords stayed on the system pasteboard indefinitely

`EntryDetailView`'s password field has a "copy" button (`doc.on.doc`) that put the
plaintext password on the system pasteboard via `copyToPasteboard`:

```swift
private func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}
```

Nothing ever cleared it again. The system pasteboard is readable by any other app on the
Mac until it's overwritten or explicitly cleared — every other password manager in
KeeBridge's own stated competitive set (1Password, Bitwarden, and KeePassXC itself, the
format KeeBridge is a "replacement for a commercial password manager" that deliberately
stays interoperable with) auto-clears the clipboard after a short delay for exactly this
reason. Leaving a just-revealed vault password sitting in shared, cross-app pasteboard
state indefinitely is a real, silent exposure window for a credential manager, not a
hypothetical one — this had never been addressed by any prior ROADMAP cycle (confirmed via
`grep -rn "clipboard\|Pasteboard"` across the repo, which only turned up this one call
site).

## Fix

`copyToPasteboard` gained an optional `autoClearAfter:` delay. When passed, it captures
`NSPasteboard.changeCount` immediately after writing, then after the delay only clears the
pasteboard if `changeCount` still matches — `changeCount` increments on every pasteboard
write from any app, so this is the standard, AppKit-documented way to detect "did someone
else already overwrite this" and avoid wiping out something the user copied from elsewhere
in the meantime. Only the password's own copy button passes this (30 seconds, matching the
common default other password managers use); the username/URL/passkey-metadata copy buttons
(`fieldRow`'s `copyable: true`) are non-secret and deliberately keep the old
no-auto-clear behavior — same secret vs. non-secret distinction KeeBridge already draws
everywhere else (`revealField`, `passkeyMetadata`, payment-card metadata).

Found via a fresh, adversarial re-read of `EntryDetailView.swift` this run, after two
earlier findings in this same cycle (#60, #61) — the third pass this run, following the
same "read every exit/side-effect path adversarially" lens.

**Verification**: `KeeBridge`'s SwiftUI views have no test target (same as every other
app-layer fix in this ROADMAP's history) — verified by reading the change against
`NSPasteboard.changeCount`'s documented semantics, and by this repo's own `make build`/CI
(macOS `xcodebuild`). This executor's environment has no local Swift/Xcode toolchain (see
`docs/backlog/2026-09-03-action-needed-backlog-blocked.md`), so this is validated via the
PR's own CI run rather than locally. **Still needs a human eyeball**: confirming the
pasteboard actually clears after 30s, and that a subsequent manual copy from elsewhere
correctly prevents the stale auto-clear from firing, both need a real macOS session to
observe — this executor has no GUI or ability to interact with the system pasteboard.

## PR

See the PR that accompanies this file.
