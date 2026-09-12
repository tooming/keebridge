# swift-crypto 4.x, for real this time: fork KDBXKit instead of waiting on it

## The finding

`#89`'s own trail (see `docs/done/2026-09-12-swift-crypto-4x-manual-step-closure.md`)
established that no command run inside this repo can land a `4.x` swift-crypto pin:
`KDBXKit` — this repo's own dependency — declares its `swift-crypto` constraint as
`from: "3.0.0"` (SwiftPM: `>=3.0.0, <4.0.0`), and SwiftPM resolves the *intersection* of
every manifest's constraint across the whole graph. No matter how wide this repo's own
two manifests go, `KDBXKit`'s own narrower cap held the entire build below `4.0.0`
regardless.

The maintainer decided not to wait on upstream: `shadone/KDBXKit#5` (issue) and `#6`
(PR — the exact one-line diff, `from: "3.0.0"` → `"3.0.0"..<"5.0.0"`, already carrying a
full compatibility writeup and a green local build/test run against `swift-crypto`
4.5.2) were filed upstream on 2026-09-09. Both were closed today, 2026-09-12, in favor of
a downstream workaround instead of waiting indefinitely for a maintainer response.

## Why this matters

`#6`'s branch already existed, unmerged, on the maintainer's own `tooming/KDBXKit` fork
(created when the PR was opened) — `widen-swift-crypto-constraint`, exactly one commit
ahead of the fork's `develop`. That `develop` HEAD is, in turn, exactly this repo's
existing KDBXKit pin (`e9b8839f...`). So the fork's branch tip is precisely "this repo's
current pin, plus only the one dependency-constraint line" — not a downgrade, not a
drift from whatever else upstream `develop` has done since, and not a new fork-wide
maintenance burden: one line of diff, already reviewed once as a standalone PR.

## The fix

- `KeeBridgeCore/Package.swift`: repointed the `KDBXKit` dependency from
  `https://github.com/shadone/KDBXKit.git` (revision `e9b8839f...`) to
  `https://github.com/tooming/KDBXKit.git` (revision `b010359337fef293a4a5138faba1fdf37839976f`,
  the `widen-swift-crypto-constraint` branch HEAD). Comments on both the `KDBXKit` and
  `swift-crypto` dependency lines updated to explain the fork, link the closed upstream
  issue/PR, and note reverting to upstream if/when it ever merges the equivalent change.
- Deleted and regenerated `KeeBridgeCore/Package.resolved` and `VaultProbe/Package.resolved`
  (`swift package resolve`, then `swift package update swift-crypto` — plain `resolve`
  keeps whatever pin already satisfies the manifest, same non-upgrading behavior
  `docs/done/2026-09-08-swift-crypto-lockfile-refresh.md` already documented; `update`
  is what actually moves the pin). Both now resolve `swift-crypto` at **4.5.2**, not
  `3.15.1` — this is the first time either lockfile has actually pinned `4.x`.
- `#89`'s literal "done when" checklist (both `Package.resolved` committed, pinning
  `swift-crypto` at a `4.x` version; `make ci` green) is now satisfiable and satisfied —
  reopened and closed for real by this PR rather than left "not planned."
- Added a third correction to `ROADMAP.md`'s swift-crypto bullet, same multi-part-
  correction convention the previous two corrections on this bullet already used.

## Verification

- `cd KeeBridgeCore && swift test` — 100/100 tests pass, against `swift-crypto` 4.5.2.
- `make ci` (`swift test` + unsigned `xcodebuild` + `VaultProbe` build + routines drift
  checks) — all green, including the app target actually linking against the 4.x
  resolution.
- Confirmed by inspection: `KeeBridgeCore/Package.resolved` and `VaultProbe/Package.resolved`
  both list `swift-crypto` at `4.5.2` and `KDBXKit` at revision `b010359337fef293a4a5138faba1fdf37839976f`
  from `https://github.com/tooming/KDBXKit.git`.
