# `SafariWebExtensionHandler`'s Keychain/content cache was instance-scoped, not `static`

Found via the same 2026-09-04 second/adversarial STEP 6b re-survey pass as
`docs/done/2026-09-04-totp-parse-digits-period-validation.md` and
`docs/done/2026-09-04-card-picker-cross-origin-iframe-block.md` — the third and last
finding from that pass. Originally flagged **PLAUSIBLE, not confirmed headlessly**,
explicitly pending the kind of verification this record documents before a fix was
applied.

## The bug

`SafariWebExtensionHandler` (the `NSExtensionRequestHandling`-conforming native message
handler for `KeeBridgeCardExtension`) declared its Touch-ID/decrypt cache as plain
instance properties:

```swift
private var cachedPreHash: Data?
private var cachedContent: KDBXContent?
private var cachedContentDate: Date?
private var cachedMirrorDate: Date?
```

Compare `KeeBridgeProvider/CredentialProviderViewController.swift`, which stores the
identical kind of cache — decrypted vault content plus a decrypt-key pre-hash, TTL'd to
avoid re-prompting Touch ID on every field — as `static`, with an explicit comment
explaining why: "confirmed via logging that the system creates a fresh
`CredentialProviderViewController` instance per field... An instance property would
reset every time, defeating the whole point." This codebase has already found and fixed
this exact failure mode once, for a sibling extension type.

## Confirming the diagnosis before fixing it

The original ROADMAP entry was explicit that this needed verification before a fix,
"same as `CredentialProviderViewController`'s own diagnosis originally was" — not applied
"on pattern-matching alone without confirming this extension type's actual instantiation
behavior." This executor's environment is headless with no real Safari to log instance
identity against, so confirmation came from external research instead — three independent
sources converging on the same conclusion:

1. **Apple's own App Extension Programming Guide** describes a non-UI app extension's
   general lifecycle: the system instantiates the extension to handle one request from
   the host app, and the extension is usually terminated soon after it completes that
   request.
2. **Safari Web Extension native messaging semantics**: `background.js` calls
   `browser.runtime.sendNativeMessage(nativeApplication, message)` — the one-shot form of
   native messaging (as opposed to `connectNative`, which opens a persistent port for
   multiple messages over one connection; this extension never uses it). The standard,
   documented behavior for `sendNativeMessage` across WebExtension implementations is a
   fresh native application instance launched per call, terminated after the reply.
3. **A developer report specifically about this class**: Apple Developer Forums thread
   696134, titled "SafariWebExtensionHandler creates new object for every request" —
   an independent, specific empirical observation of the exact class this codebase uses,
   not just the general non-UI-extension pattern.

Same standard this ROADMAP already applies to other platform-behavior questions it has
no way to test on real hardware in this environment (e.g. the passkey conditional
registration API surface, confirmed via Apple's DocC JSON API rather than guessed).

## The fix

All four cache fields are now `static var`, following
`CredentialProviderViewController`'s exact established pattern — including its
`Self.`-qualified read/write convention at every call site (`unlockedContent`'s
cache-hit check, its fallback-to-cached-preHash branch, its cache-miss cleanup, and
`cache(content:preHash:mirrorDate:)`'s writes) for consistency with the sibling file.

**Thread safety**: no new surface introduced. Every cache read/write already happens
inside `handle(_:context:)`, which is always dispatched via the handler's existing
`private static let workQueue` (a serial `DispatchQueue`) from `beginRequest(with:)`.
Access to the cache was already funneled through one serial queue before this change;
making the cache itself `static` doesn't add concurrent access, it just makes the cache
actually shared the way the serialization already assumed.

**Caught by CI, fixed on this branch before merging**: the first push of this fix failed
`make ci`'s `build` step — Swift 6's strict concurrency checking (`SWIFT_VERSION: "6.1"`
per `project.yml`) flags a plain `static var` as "not concurrency-safe... nonisolated
global shared mutable state" unless the enclosing type is actor-isolated.
`CredentialProviderViewController`'s identical pattern never hits this: it's a UI view
controller, implicitly `@MainActor`-isolated by the SDK, so the compiler already knows
every access is single-threaded. `SafariWebExtensionHandler` is a plain `NSObject` with
no actor isolation, so its static cache needed an explicit `nonisolated(unsafe)` on each
of the four fields — the correct annotation for exactly this situation (manual
serial-queue synchronization the compiler can't see through, not an actual data race
being suppressed), not a workaround. Re-pushed and re-validated green.

## Verification

Compiled-only (`xcodebuild`, via this repo's `ci` GitHub Actions workflow on
`macos-latest` — this executor's own environment has no local Swift/Xcode toolchain).
`KeeBridgeCardExtension` has no test target (same as `KeeBridgeProvider`/
`CredentialProviderViewController`, which has none either — both are native extension
entry points, not directly unit-testable). **Still needs a human eyeball**: confirming in
a real Safari session that the cache genuinely now survives across multiple
`listCards`/`fillCard` calls without re-prompting Touch ID each time — this executor's
environment is headless with no camera or Safari to observe the actual prompt behavior,
same limitation every Touch ID-adjacent item in this ROADMAP carries.

## PR

See the PR this file was committed alongside.
