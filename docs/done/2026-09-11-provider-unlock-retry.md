# `CredentialProviderViewController`'s unlock prompt dead-ended after a wrong master password

Found via a fresh, full adversarial read of `CredentialProviderViewController.swift`
(952 lines) this cycle — this run's earlier cycles had fixed bugs in `EntryEditView.swift`
(a UI dead-end after an invalid QR scan) and `TOTPGenerator.swift` (a silent-fallback
validation gap); this cycle applied the same "trace every control-flow path, especially
error paths" lens to the one large file that hadn't had it yet this run.

## The bug

`handleUnlock(password:)` has two failure paths, both of which called
`showMessage(_:)`:

```swift
} catch {
    self.isWorking = false
    self.log.error("handleUnlock: Keychain store failed: \(String(describing: error))")
    self.showMessage("Couldn't cache unlock: \(error)")
}
// ...
} catch {
    self.log.error("handleUnlock: Argon2id verify failed (wrong password?): \(String(describing: error))")
    DispatchQueue.main.async {
        self.isWorking = false
        self.showMessage("Couldn't unlock: \(error)")
    }
}
```

`showMessage` embeds a plain, non-interactive `Text` view (`embed(Text(text)...)`)  —
no password field, no button, nothing to click. The only way out was pressing Escape
(`onExitCommand`, wired into every embedded view via `embed(_:)`), which cancels the
**entire** autofill request — the user then has to go back to Safari and re-trigger
the credential picker from scratch to get a fresh
`CredentialProviderViewController` instance and try again.

This is a real, reachable gap, not a rare edge case: mistyping a master password is
the single most common failure mode of exactly this screen (the first-use unlock
prompt, before a Keychain item exists to skip it). Unlike the "no vault mirror found"
case (`showMessage`'s other caller, `showUnlockOrProceed`/`openContentThenProceed`) —
which genuinely can't be retried in-place since it needs the separate app opened
first — a wrong password is trivially retriable in the same popover, and every
comparable credential manager (1Password, Bitwarden, KeePassXC's own unlock dialog)
lets you just try again immediately.

## The fix

- `showUnlockPrompt()` gained an `errorMessage: String? = nil` parameter.
- `UnlockView` gained a matching `errorMessage: String? = nil` property, rendered as
  red `Text` above the (always empty — never pre-filled with the rejected attempt)
  `SecureField`.
- Both `handleUnlock` failure paths now call `showUnlockPrompt(errorMessage:)` instead
  of `showMessage(...)`.

A mistyped password is now a one-click retry: the same popover re-appears with the
error shown and a fresh field ready for another attempt, instead of a dead end.

## No new secret exposure

The error text shown is the exact same `error` value `showMessage` already displayed
to the user before this fix — this change only moves WHERE it's shown (inline with a
retry field) and doesn't add, remove, or alter what's shown. The underlying error
(`VaultServiceError.openFailed`, wrapping KDBXReader's own error) never carries the
plaintext password in its description — confirmed by reading `VaultService.swift`'s
error-wrapping code (this run's earlier full read of that file) — so this stays
consistent with the file's existing secret-hygiene discipline (the password field
itself is always cleared/never logged, same as before).

## Verification

Compiled-only (`xcodebuild`) — `CredentialProviderViewController.swift` has no test
target for its `NSViewController`/SwiftUI layer, same as every other change to this
file in this ROADMAP. Genuinely unverifiable end-to-end without a real Safari autofill
popover and a real wrong-password attempt in front of it — this executor has no GUI or
hardware — flagged as a "still needs a human eyeball" caveat in the PR.

## PR

See the PR this cycle opened (self-merged per `docs/WAYS-OF-WORKING.md` §0.1).
