# Conditional (silent/background) passkey registration

Discovered via a STEP 6b re-survey (`ROADMAP.md`'s "Now / next" lane had no other
buildable code item this cycle: credit card autofill stays blocked on missing `xcodegen`,
the automatic-password-save item (#33) is blocked on an Apple macOS API gap, and Proton
Pass decommission is a human-only action). A fresh read of
`KeeBridgeProvider/CredentialProviderViewController.swift`'s own header comment turned up
something the interactive passkey-registration PR had explicitly flagged but deliberately
deferred, not ruled out:

> Deliberately NOT implementing `performWithoutUserInteractionIfPossible(passkeyRegistration:)`
> — that override is only required when opting into `SupportsConditionalPasskeyRegistration`
> (silent/background registration, macOS 15+), a separate, still-unclaimed capability from
> `ProvidesPasskeys` itself.

"Still-unclaimed" (not "not implementable") — worth a fresh look now that the interactive
flow (and all its underlying `PasskeyCrypto`/`VaultService` primitives) has landed and been
running for several cycles.

## Research

- Apple's DocC JSON API (`.../performwithoutuserinteractionifpossible(passkeyregistration:).json`)
  confirms: `func performWithoutUserInteractionIfPossible(passkeyRegistration registrationRequest: ASPasskeyCredentialRequest)`,
  available macOS 15.0+/iOS 18.0+/visionOS 2.0+ — `project.yml`'s
  `MACOSX_DEPLOYMENT_TARGET` is already `"15.0"`, so no deployment-target bump needed.
  Requires declaring `SupportsConditionalPasskeyRegistration: true` under
  `ASCredentialProviderExtensionCapabilities` in `Info.plist`, alongside the existing
  `ProvidesPasskeys`.
- Cross-checked the exact Swift override signature against a real, shipped
  implementation: Dashlane's own open-source `apple-apps` repository
  (`TachyonAutofillExtension/CredentialProviderViewController.swift`) has the identical
  `override func performWithoutUserInteractionIfPossible(passkeyRegistration registrationRequest: ASPasskeyCredentialRequest)`
  — confirms the parameter is the concrete `ASPasskeyCredentialRequest` type, not the
  more general `any ASCredentialRequest` the *interactive*
  `prepareInterface(forPasskeyRegistration:)` override takes.
- Apple's docs are explicit about the contract: no UI is permitted in this path at all
  ("This request cannot show UI; `ASExtensionErrorCodeUserInteractionRequired` is treated
  like any other error"), and the implementation should be non-destructive (never remove
  an existing saved credential) — cancelling with that specific error code is the
  documented way to fall back to the normal interactive flow instead of failing the page
  outright.

## What changed

- `KeeBridgeProvider/Info.plist`: added `SupportsConditionalPasskeyRegistration: true`
  next to the existing `ProvidesPasskeys`.
- `CredentialProviderViewController.performWithoutUserInteractionIfPossible(passkeyRegistration:)`
  (new): deliberately more conservative than the interactive flow, since this WRITES a new
  WebAuthn credential with no human in the loop at all. Registers only when ALL of:
  1. The vault is **already** unlocked in memory (`Self.validCachedContent()` non-nil) —
     never attempts a Keychain read, Touch ID, or the master-password prompt, since none
     of those can show UI either. This only ever fires within an existing
     `contentCacheTTL` window following some earlier, human-triggered unlock.
  2. Exactly **one** existing vault entry's URL host matches the relying party ID (the
     same host/subdomain rule the interactive flow already used — extracted into a new
     shared `matchingEntries(forRelyingPartyID:in:)` helper so both flows use one
     implementation instead of two copies that could drift).
  3. That matched entry does **not** already have a passkey (checked via the existing
     `VaultService.passkeyMetadata`) — never silently replace or duplicate one.

  Any other case cancels with `ASExtensionError.Code.userInteractionRequired`, letting the
  system fall back to the interactive path (where a human is present and the existing
  auto-attach-or-picker policy applies as before). When all three conditions hold, this
  calls the exact same `completePasskeyRegistration` write path the interactive flow uses
  — no new crypto or vault-write logic, only a new, stricter gate in front of the existing
  one.

## Why this scope, not more

No new write primitive, no change to what gets written — only a new, narrower *entry
point* into the same registration write path, gated by conditions deliberately stricter
than the interactive flow's (which can fall back to a picker; this path has no UI to fall
back to, so ambiguity means "don't register," not "ask"). Explicitly does NOT attempt to
track "was this account recently filled with a password" (one of Apple's example
conditions in their docs) — that would need new state this codebase doesn't have anywhere
yet (no existing "last filled" timestamp), and the three conditions already implemented
are a defensible, self-contained bar on their own without inventing that.

## Verification

Headless only, and more so than the interactive registration item before it: `swift test`
covers none of `CredentialProviderViewController` (no test target exists for it, same as
before this change — it depends on live `AuthenticationServices`/`AppKit` extension
plumbing). Correctness rests on: (1) CI's `xcodebuild` build catching any compile error —
notably, since `override` requires an exact signature match against the real SDK method,
a wrong signature fails the build loudly rather than silently no-op-ing; (2) the
Dashlane cross-check above for that signature; (3) `completePasskeyRegistration`, the
write path this reuses unchanged, already being exercised by the existing interactive
registration flow.

**Still needs a human eyeball, more than most items in this ROADMAP**: this override can
only ever be exercised by a real site's conditional-mediation WebAuthn call
(`navigator.credentials.get({ mediation: 'conditional', publicKey: ... })` with a passkey
upgrade offered), which needs a real Safari session, a real relying party willing to make
that call, and real hardware — there is no way to simulate the system invoking this path
at all in this executor's headless environment, unlike the interactive flow which at
least compiles and links against a real Xcode build. Treat this as implemented-and-reasoned-
about, not implemented-and-observed-working.

## PR

See the PR this file was committed alongside.
