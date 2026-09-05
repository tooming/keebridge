# Manual credential picker never responded for an entry with no Password field

`CredentialProviderViewController`'s manual list flow (`prepareCredentialList(for:)` →
`showList` → `completeSelection`) lists **every** entry in the vault, not just ones that
have a `Password` field — a passkey-only entry (no traditional login at all), or any other
entry someone picks from Safari's "Passwords…" picker, can legitimately have none.

`completeSelection` handled that case by silently returning:

```swift
private func completeSelection(entry: VaultLoginEntry, content: KDBXContent) {
    guard let password = vaultService.revealField(in: content, entryUUID: entry.uuid, fieldKey: "Password") else { return }
    respondComplete(with: ASPasswordCredential(user: entry.username, password: password))
}
```

No `respond*()` call ever fired on that path, so the popover just sat there, unresponsive,
until this file's own 30-second watchdog eventually forced a generic `.failed` cancel. This
directly contradicts the guarantee this file's own header comment describes — "every entry
point goes through `respond(...)`, which guarantees `completeRequest`/`cancelRequest` fires
at most once AND within a bounded time... no matter what happens internally" — the intent
was clearly an *immediate* bounded response, not a 30-second stall as the normal outcome for
a reachable, non-error case.

The sibling code path handling the exact same "no Password field" condition —
`completePasswordCredential`, used by the *interactive* auto-fill request rather than the
manual list — already does this correctly:

```swift
guard let password else {
    respondCancel(.credentialIdentityNotFound)
    return
}
```

`completeSelection` was simply missing the equivalent explicit cancel. Found via a fresh,
adversarial read of `CredentialProviderViewController.swift` (938 lines, previously read in
full by earlier cycles per `ROADMAP.md`'s history, but not with this specific "does every
exit path actually respond" lens) — this repo's passkey support means a real vault can
easily contain login-less, passkey-only entries today, so this isn't a hypothetical.

## Fix

`completeSelection` now calls `respondCancel(.credentialIdentityNotFound)` in the missing-
password case, mirroring `completePasswordCredential` exactly. ~10 changed lines, no other
behavior touched.

**Verification**: `KeeBridgeProvider` has no test target (same as every other app/extension-
layer fix in this ROADMAP) — verified by reading the change against
`ASCredentialProviderViewController`'s documented `respond*()` contract and by
compiling via the repo's `ci` GitHub Actions workflow (`macos-latest`, `make build`), the
same "no local Swift/Xcode toolchain in this executor's environment" workaround noted in
`docs/backlog/2026-09-03-action-needed-backlog-blocked.md` — this executor pushed the branch
and polled the check run rather than running `xcodebuild` locally. No headless-hardware
caveat beyond that: this fix is a plain, deterministic code path (no Touch ID, no real
Safari interaction needed to reason about it), so it does not need the usual "still needs a
human eyeball" flag the passkey/card items carry.

## PR

See the PR that accompanies this file.
