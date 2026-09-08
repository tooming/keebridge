# Widen swift-crypto's dependency range to include 4.x

Eleventh cycle this run — STEP 3 picked up the topmost unchecked `ROADMAP.md` item, which
was this run's own tenth-cycle finding (`#86`): `swift-crypto` gained a `4.x` major
release that `KeeBridgeCore/Package.swift`'s `from: "3.0.0"` constraint (SwiftPM's
`>=3.0.0, <4.0.0` shorthand) would never pick up.

## What changed this cycle vs. last cycle

Last cycle stopped short of implementing because it hadn't yet read the actual `3.x→4.x`
API diff — the stated reason was "no Swift toolchain to validate," but that undersells
what was actually missing: CI *does* have a real toolchain and would have caught a
compile break, so the real gate was simply not having read what the diff even was yet.
This cycle read it, straight from upstream: `swift-crypto`'s own `README.md` states, in
its "Compatibility" section, that `4.0.0`'s *only* breaking change relative to
`1.x`/`2.x`/`3.x` is new cases added to the `CryptoError` enum — and the maintainers'
own recommended `Package.swift` snippet for that section widens straight across the
boundary (`"1.0.0" ..< "5.0.0"`), not something a downstream consumer needs to treat
cautiously.

## Why this was safe to actually bump

- **The one stated breaking change doesn't apply.** `grep -rn "CryptoError"` across every
  Swift target in this repo returns zero matches outside this codebase's own
  `PasskeyCryptoError` type (`PasskeyCrypto.swift`) — KeeBridge never pattern-matches
  exhaustively over Swift Crypto's `CryptoError`, so new cases being added to it cannot
  break anything here.
- **The Swift-version floor was already met.** `4.0.0` requires Swift 6.0+; `project.yml`
  already builds every target under `SWIFT_VERSION: "6.1"`.
- **No RSA usage**, confirmed last cycle, so the one security-hardening commit not yet
  backported to any `3.x` tag ("Enforce a 2048-bit minimum on RSA raw number
  initializers") is moot either way — neither a reason to rush the bump nor a reason to
  avoid it.
- **The actual API surface this codebase touches** (`P256`, `SHA256`/`SHA512`, `HMAC`,
  `Insecure` for RFC 6238 TOTP's required SHA-1) is exactly "the common API of Swift
  Crypto and CryptoKit" swift-crypto's own README describes as stable across the whole
  `1.x`-`4.x` line.

## What changed

`KeeBridgeCore/Package.swift`: `.package(url: ..., from: "3.0.0")` →
`.package(url: ..., "3.0.0"..<"5.0.0")` — same practical floor, now also covering `4.x`.
No call site changed; none needed to. `make ci`'s real `swift test`/`xcodebuild` run
against the newly-resolved `4.x` package is the actual proof this compiles and passes,
not just the README-reading above.

## PR

See the PR that accompanies this file.
