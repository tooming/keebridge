# [Action needed] Card-extension web surface (JS/HTML/manifest) audited fresh — still nothing new

Fourth consecutive empty-backlog cycle. The three cycles on 2026-09-07 (#73, #74, #75)
gave every Swift source file in the repo (`KeeBridgeCore`, `VaultProbe`, `KeeBridge`,
`KeeBridgeProvider`, `KeeBridgeCardExtension`'s Swift file) a fresh adversarial read and
confirmed the pinned `KDBXKit` dependency matches upstream `develop` HEAD. Before falling
straight back to "nothing changed, re-file the same notice," this cycle read the one part
of the codebase none of those Swift-focused passes actually covered: the card
extension's non-Swift web surface — `KeeBridgeCardExtension/Resources/` — which is real
attack surface (a content script that runs on every frame of every page the user visits,
including third-party/untrusted pages) and hadn't had a fresh line-by-line read since its
last functional change (#64, 2026-09-05).

## What was read fresh this cycle

- `content.js` (325 lines) — the cross-origin-iframe guard (`isTopLevelOrSameOriginFrame`:
  confirmed `window.top` is always readable by reference, only its properties are
  same-origin-restricted, so the try/catch-to-`false` pattern is sound), the field-type
  heuristics (`fieldType`), the shadow-DOM picker panel (`createPanel` uses a `closed`
  shadow root so the host page's CSS/JS can't reach into or restyle the picker),
  `fillCard`'s clear-after-use of revealed values (`values[type] = ""`, consistent with
  this repo's existing secret-hygiene discipline), and the expiration-format synthesis
  logic already covered for its Swift-side twin in #74 (this is the client-side mirror
  of the same placeholder-token-order reasoning, re-checked independently here since it's
  a different language and different bug class — DOM-write correctness, not Swift memory
  safety).
- `background.js` (21 lines) — the native-action allowlist (`listCards`/`unlock`/
  `fillCard` only) and the `unlock` action's sender-origin gate
  (`sender.url !== browser.runtime.getURL("unlock.html")`), which is what stops an
  arbitrary web page from ever sending a raw vault password through
  `sendNativeMessage` — only this extension's own bundled unlock page can.
- `unlock.js` / `unlock.html` (29 + 29 lines) — confirmed the password field is cleared
  immediately after read (`passwordInput.value = ""`, before the async native-message
  round-trip) and never logged.
- `manifest.json` — `all_frames: true` + `<all_urls>` matches, cross-checked against
  `content.js`'s own same-origin-frame guard (the manifest's permissiveness is exactly
  why that guard exists client-side, not a gap by itself).

One observation, not a bug: `content.js`'s `nativeRequest()` adds `origin: location.origin`
to every native-messaging request, but `SafariWebExtensionHandler.swift`'s `handle(_:
context:)` never reads `message["origin"]` — it's sent and silently dropped. Not a
security gap (nothing depends on it for authorization, and per this repo's own documented
design a card genuinely has no per-origin restriction to enforce — see `README.md`'s
"Notable non-obvious design decisions" and the guard's own comment in `content.js`), just
a vestigial field. Too thin to justify its own PR (no behavior change, nothing to fix, no
test to add) — recorded here rather than silently dropped, in case a future cycle finds a
real use for threading it through (e.g. richer logging) or decides to remove it as dead
weight.

Also re-confirmed this cycle: zero open GitHub issues, zero open PRs, zero `TODO`/`FIXME`
markers repo-wide, `git log` shows no commits since #75 merged (nothing changed under the
codebase between yesterday's audit and today's).

## Current state

Between 2026-09-07's three cycles and this one, every source file in the repo — Swift
and the card extension's JS/HTML/manifest alike — has had a fresh adversarial read within
the last two days, and none of it surfaced a new, confirmed, actionable bug. `ROADMAP.md`'s
"Now / next" lane and "Needs maintainer/human action" section remain empty. The next
genuinely new finding needs new input (a maintainer-filed issue, a code change, an
upstream dependency update) rather than another re-read of what's now been read multiple
times this week — filing this rather than fabricating make-work, per STEP 6b.
