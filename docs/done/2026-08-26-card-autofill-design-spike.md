# Credit card autofill: native-messaging vs. local-decrypt design spike

> **Implemented September 2026.** `KeeBridgeCardExtension` now follows this
> recommendation with a separate full-vault, read-only mirror, native local
> decrypt, independent biometric Keychain item, and requested-field-only
> responses. Conservative aliases cover common KeePass/Proton-style card
> fields without treating a generic `number` alone, `PIN`, or login fields as cards.

Answers the scoping question issue #3 and `ROADMAP.md` both flagged as blocking any
implementation: how does the Safari Web Extension (new JS/TS code, a different tech
stack than everything else in this repo) actually get card data out of the vault,
given this app's already-established "no shared Keychain access group, no App Group"
constraint (see `README.md`'s "Notable non-obvious design decisions")?

## Why this needed research before code

Issue #3 already ruled out the system credential-provider mechanism (no
`ASCreditCardCredential` type, no `ProvidesCreditCards` capability key exists) and named
the open question directly: "Needs some way to talk to the native app/extension to get
card data. Needs design." Picking this up cold and writing extension code against a
guessed-at IPC mechanism risked the same mistake #3's own body already warns about for
card field names: shipping code against an unconfirmed assumption.

## What the Safari Web Extension platform actually offers

Confirmed via Apple's own documentation (titles/URLs below — the actual page bodies
didn't render in this headless environment's fetch, so treat the API *names* and
*direction* as confirmed, the finer method signatures as "check the linked page before
implementing"):

- **[Messaging a Web Extension's Native App](https://developer.apple.com/documentation/safariservices/messaging-a-web-extension-s-native-app)**
  — the extension's background/content script calls `browser.runtime.connectNative(...)`
  to open a port to a native handler; that handler is `SafariWebExtensionHandler`, itself
  a small native macOS **app extension target** (same category of thing
  `KeeBridgeProvider` already is — sandboxed, bundled inside the app). Its
  `beginRequest()` receives the JS message and replies via the `NSExtensionContext`
  completion handler passed into it.
- **[Messaging between the app and JavaScript in a Safari web extension](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)**
  — the *containing app* can push a message to the extension's background page via
  `SFSafariApplication.dispatchMessage(...)` (noted in a live Apple Developer Forums
  thread, 763879, as having changed/regressed in recent Xcode versions — worth
  re-confirming against whatever Xcode version is current when this is implemented).
  Cross-component sharing (containing app ↔ extension's native handler) is normally done
  via an **App Group** — `NSUserDefaults(suiteName:)` or an XPC connection into a shared
  container.

## The App Group problem — and the way around it

This repo already hit exactly this wall once: `README.md` documents that this Apple
Developer team's automatic provisioning does **not** reliably grant an App Group
capability to `KeeBridge`/`KeeBridgeProvider`, confirmed by inspecting the actual
embedded `.mobileprovision` entitlements. A Safari Web Extension's native handler is
signed under the same team, so there's no reason to expect an App Group would provision
any more reliably for a third target.

The good news: this repo already has a working pattern for exactly this situation,
already shipping in production for `KeeBridgeProvider` — **no App Group needed at all**.
`KeeBridge` (the container app) is deliberately *not* sandboxed, so it can write directly
into a sandboxed extension's own container path; sandboxing restricts what the
*sandboxed* process can reach, not what another same-user process writes into its
folder. `mirrorVaultToExtension` already does this for the credential-provider
extension's copy of the vault. The same trick applies unchanged to a second sandboxed
extension target (the Web Extension's native handler): the app mirrors whatever
card-entry data the extension needs into *that* extension's container the same way, and
`SafariWebExtensionHandler.beginRequest` reads it from there — no native-messaging round
trip to the app needed for the data itself, only (optionally) `dispatchMessage`/
`connectNative` for liveness/lock-state signaling.

## Recommendation

**Local-decrypt via the existing mirror pattern, not a native-messaging round trip for
the card data itself.** Concretely, once someone picks this up for implementation:

1. Extend the existing app→extension mirroring (`mirrorVaultToExtension`'s sibling) to
   also write a card-entries-only mirror into the new Safari Web Extension native
   handler target's container — same "app writes, sandboxed extension reads" shape
   already proven, no App Group, no new provisioning risk.
2. Scaffold the actual Safari Web Extension target (JS/TS content script + background
   script + the `SafariWebExtensionHandler` native handler) — this is the genuinely new
   tech stack for this project; budget it as its own implementation item, not bundled
   with this design spike.
3. Content script: card-number/expiry/CVV field detection heuristics (comparable to
   what KeePassXC-Browser/Bitwarden do — issue #3 already named this as the shape to
   follow) and a fill UI.
4. `connectNative`/`dispatchMessage` stay available for lock-state / "vault is locked,
   please unlock in the app" signaling — a much smaller, lower-stakes use of the
   native-messaging channel than shuttling card data itself through it.

This still leaves real open work (the card field-name convention issue #3 also flagged —
no conversion script or existing card-handling code confirms what the 9 real card
entries' field names actually are; that's a separate, still-open unknown this spike
doesn't resolve) — but the *transport* question is now answered with a concrete,
low-risk, already-proven mechanism instead of an open "needs design" note.

## Open at the time of this spike (resolution)

- Field-name uncertainty is handled with normalized, conservative aliases for common
  KeePass/Proton-style names; real-vault and browser UI verification remains manual.
- The Safari Web Extension target, native handler, background script, and content
  script now exist.
- `SFSafariApplication.dispatchMessage` was unnecessary. JavaScript uses native
  messaging on demand; the app supplies data through the dedicated file mirror.

## PR

#18
