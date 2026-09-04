# Security: card autofill's picker was reachable from any cross-origin iframe

Found via a second, adversarial STEP 6b re-survey pass (2026-09-04) — see
`docs/done/2026-09-04-totp-parse-digits-period-validation.md` for the first finding from
that same pass. This is the second; a third (a plausible-but-unconfirmed
instance-vs-`static` cache-scope question in `SafariWebExtensionHandler`) stays queued in
`ROADMAP.md` for a future cycle.

## The vulnerability

`KeeBridgeCardExtension`'s `manifest.json` injects `content.js` into every frame on every
page (`"matches": ["<all_urls>"]`, `"all_frames": true`) — including third-party iframes
(ads, trackers, or a deliberately hostile embed) that have nothing to do with the page the
user actually trusts. `content.js` detects card-shaped input fields in whichever frame
it's running in and shows its own fill trigger/picker with no check on which frame that
is. Since `manifest.json` declares no `externally_connectable`, the only way to reach
`background.js`'s `listCards`/`fillCard` handlers (and from there,
`SafariWebExtensionHandler`'s native code, and the actual card data) is through this
extension's own injected `content.js` instance — so a cross-origin iframe running that
same injected script could present KeeBridge's own trigger, and a user who clicked it
believing it belonged to the page they were looking at would have their card list shown,
and any selected card's number/CVV/expiration/holder filled into the iframe's own fields
— not the page's.

## Why the originally-sketched fix was wrong, not just bigger

This item's own text, as first written, proposed the same fix shape this ROADMAP already
uses for logins and passkeys: give `VaultPaymentCard` a per-entry URL, thread the
requesting `origin` (already sent by `content.js`'s `nativeRequest`, already ignored by
`background.js` and `SafariWebExtensionHandler`) through the stack, and only list/fill
cards whose entry URL host matches.

That doesn't actually fit payment cards. A login credential or passkey has exactly one
site it belongs to — host-matching is the right model, and `CredentialProviderViewController`
already does it (`matchingEntries`, `showList`). A payment card doesn't: the same Visa is
legitimately used at many unrelated merchants, and in practice most stored cards would
have no URL field set at all, since nothing about "adding a card" naturally suggests
tagging it to one site. Two consequences of implementing origin-filtering anyway:

- **Strict filtering, no fallback**: every untagged card (almost all of them, in
  practice) would simply stop being offered anywhere — a large usability regression for
  no security benefit, since most legitimate uses would be blocked right alongside the
  attack this was meant to stop.
- **Filtering with a "show everything" fallback on zero matches** (the pattern
  `showList` already uses, safely, for `ASCredentialServiceIdentifier`-sourced
  data — which is OS-provided and not something a webpage can spoof): would not close
  the gap at all. An attacker's iframe origin would simply never match any card's URL,
  hit the empty-match fallback, and see the exact same full card list as before. Origin
  data from `content.js` is a different trust tier than `ASCredentialServiceIdentifier` —
  it originates from code running inside the (potentially hostile) page/iframe itself, not
  from Safari's own trusted picker plumbing — so mirroring the fallback semantics that are
  safe for the trusted case would have been unsafe here.

## The actual fix

The real question was never "which cards match this origin" — it's "should this frame be
allowed to run the picker flow at all." `content.js` now gates its entire activation on
frame trust, checked once at load and bailing out before attaching any listeners if it
fails:

```js
const isTopLevelOrSameOriginFrame = (() => {
  if (window.self === window.top) return true;
  try {
    return window.top.location.origin === window.location.origin;
  } catch {
    return false;
  }
})();
if (!isTopLevelOrSameOriginFrame) return;
```

- The top-level page is always trusted (unaffected — this is the overwhelmingly common
  case).
- A same-origin iframe (e.g. a checkout widget hosted on the same site as the page
  embedding it) is trusted the same as the top-level page.
- A cross-origin iframe is not: `content.js` returns immediately, before attaching any
  `focusin`/`focusout` listeners or creating a trigger button — so it can never show a
  picker or call `listCards`/`fillCard` at all from within that frame.

This is a **complete** fix, not defense-in-depth on top of a partial one:
`manifest.json` declares no `externally_connectable`, so no webpage's own script — cross-
origin iframe included — can call `browser.runtime.sendMessage` against this extension
directly; the only code that can ever reach `background.js`'s message handler is this
extension's own injected `content.js`. Gating that one entry point by frame trust closes
every path in.

`window.self === window.top` is always safe to read, even cross-origin — only a cross-
origin window's *properties* (like `.location`) are Same-Origin-Policy-restricted, not
the reference itself. Reading `window.top.location.origin` throws precisely when `top` is
a different origin, which the `catch` block treats as untrusted — exactly the signal
needed, with no false negatives (a thrown access always means "not same-origin," never a
same-origin frame silently misreported as untrusted by a transient error, since a
same-origin `.location.origin` read cannot throw).

## What this deliberately doesn't change

No native/Swift code changed — `PaymentCard.swift`, `SafariWebExtensionHandler.swift`,
and `background.js` are untouched. `VaultPaymentCard` still carries no per-entry URL,
deliberately: nothing about the payment-card domain model calls for one, and adding one
now would just be unused plumbing left over from the wrong-shaped fix this item first
proposed.

## Verification

CI has no JS lint/test step at all — only the Swift targets (`swift test`,
`xcodebuild`) are built/tested by `make ci`/`ci.yml`. This was verified by careful reading
of the actual WebExtension/Same-Origin-Policy semantics involved (confirmed which
`window`/`window.top` properties are SOP-restricted vs. always-readable, confirmed
`manifest.json` grants no `externally_connectable`, confirmed `background.js`'s listener
is the only reachable entry point), not by running anything. **Still needs a human
eyeball**: confirming in a real Safari session that (1) the trigger/picker still appears
correctly on ordinary pages and same-origin-embedded card forms, and (2) it genuinely
does not appear inside a deliberately-constructed cross-origin test iframe — this
executor's environment is headless with no real Safari to load the extension in.

## PR

See the PR this file was committed alongside.
