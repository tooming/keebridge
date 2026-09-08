# [Action needed] Twenty-second cycle — full read of CredentialProviderViewController.swift; clean

Twenty-second cycle this run. `ROADMAP.md`'s "Now / next" lane remains fully checked
(only `#77` unchecked, correctly skipped by STEP 3). Zero open PRs.

## What was checked

Read `KeeBridgeProvider/CredentialProviderViewController.swift` (959 lines, the
largest source file in the repo and the one with the most security-relevant
responsibility — Touch ID/Keychain gating, the passkey assertion/registration
crypto flows, the "always respond exactly once" watchdog contract) start to finish
in one linear pass, same technique as `#95`'s full `project.pbxproj` read — rather
than the piecemeal targeted reads every prior cycle touching this file used (each
of the ~10 passkey-related `docs/done` entries only read the specific method it was
changing).

Specifically traced:

- The `isWorking`/`hasResponded`/watchdog reentrancy contract across every entry
  point (`prepareCredentialList`, `prepareInterfaceToProvideCredential`,
  `prepareInterface(forPasskeyRegistration:)`,
  `performWithoutUserInteractionIfPossible(passkeyRegistration:)`) — each
  `respondComplete`/`respondCancel` overload correctly guards `!hasResponded`
  before firing, so no path can double-complete the extension context.
- The `cachedPreHash`/`cachedContent` invariant: every code path that sets
  `Self.cachedContent` (`openContentThenProceed`, `handleUnlock`) also sets
  `Self.cachedPreHash` first, so the silent conditional-passkey-registration path's
  `guard let preHash = Self.cachedPreHash` (in `completePasskeyRegistration`) can
  never fail while `Self.validCachedContent()` — the precondition
  `performWithoutUserInteractionIfPossible` itself checks — is what let it in.
- The conditional (silent, no-UI) passkey registration policy's three conditions
  (already-unlocked-in-memory only, exactly one URL-host match, no pre-existing
  passkey on that entry) are enforced together in one guard, matching the header
  comment's stated policy exactly — no gap between the documented intent and the
  code.
- `isWorking`/instance state is per-`CredentialProviderViewController`-instance,
  not shared across the concurrent-fresh-instance-per-field model the file's own
  comments describe, so there's no cross-request race through those flags; the
  genuinely shared state (`cachedPreHash`/`cachedContent`, both `static`) is only
  ever read/written on `workQueue`'s callbacks hopped back to main or directly on
  main, never off it.

No bug found. Clean.

## No new findings

Same two open issues as recent cycles (`#77`, `#89`). Filing this rather than
fabricating make-work, per STEP 6b.
