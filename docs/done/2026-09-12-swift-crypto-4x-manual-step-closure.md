# The swift-crypto 4.x manual-step issue asked for something no one can do

## The finding

`#89` ("[Manual step] Regenerate and commit Package.resolved for KeeBridgeCore and
VaultProbe (pin swift-crypto 4.x for real)") was filed after `#88` deleted both
`Package.resolved` lockfiles to force a genuine SwiftPM re-resolution, on the
assumption that a human running `swift package resolve` with a real Swift toolchain
would land a `4.x` pin where this executor's toolchain-less environment could not.

`#105` (2026-09-09) already ran exactly those commands and found the opposite:
both packages re-resolve to `swift-crypto 3.15.1`, not `4.x`, regardless of who runs
the command or what toolchain they have. Root cause, confirmed there and re-confirmed
fresh this cycle (fetching `KDBXKit`'s current `main` branch `Package.swift` directly
from GitHub rather than trusting the three-day-old finding to still hold): `KDBXKit`
— both at this repo's pinned revision and on its current upstream `main` — declares
its own `swift-crypto` dependency as

```swift
.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
```

SwiftPM's `from:` shorthand means "up to next major," i.e. `>=3.0.0, <4.0.0`. SwiftPM
resolves the *intersection* of every manifest's constraint across the whole dependency
graph — so no matter how wide `KeeBridgeCore/Package.swift` and `VaultProbe/Package.swift`
allow `swift-crypto` to go (`"3.0.0"..<"5.0.0"` in both, since the 2026-09-08 upgrade
cycle), `KDBXKit`'s own narrower constraint caps the whole resolved graph below `4.0.0`
regardless. `#105`'s commit message already stated this plainly ("This isn't fixable by
re-resolving locally — it needs KDBXKit itself to relax its constraint (or a fork/patch),
which is out of scope here"), but `#89` itself was never updated or closed to match —
it stayed open with a "done when" checklist item ("both pinning `swift-crypto` at a `4.x`
version") that `#105`'s own finding had already made permanently unsatisfiable by any
manual step available in this repo.

## Why this matters

`#89` carries the `manual-step` label and framing ("a human just needs to run this
command"), which is exactly the class of issue this ROADMAP's convention tells a human
maintainer to trust and act on directly. Leaving it open, unedited, pointed a maintainer
at a checklist that cannot be completed by running the commands it lists — the real
blocker is an upstream dependency's own manifest, not anything reachable from inside
this repo.

## The fix

- Closed `#89` as not planned, with a comment summarizing `#105`'s finding, this cycle's
  fresh re-confirmation, and why it's not actionable as a manual step.
- Added a second correction to `ROADMAP.md`'s swift-crypto bullet (the same bullet
  `#89`'s original correction was appended to) rather than a new near-duplicate entry,
  matching this ROADMAP's established pattern for multi-part corrections to one item.
- No production code changed — `KeeBridgeCore/Package.swift`, `VaultProbe/Package.swift`,
  and both `Package.resolved` files are untouched; `#105`'s reproducible `3.15.1` pin
  remains exactly correct and is not being revisited here.

## Verification

- `bash scripts/routines-check.sh` — pass
- `bash scripts/routines-author-check.sh` — pass
- `bats tests/drift-detectors.bats` — pass (15/15)

Doc/issue-hygiene only; no Swift/JS files touched, so `swift test`/`xcodebuild` are
unaffected (CI still runs them as usual for this PR, same as any other change).
