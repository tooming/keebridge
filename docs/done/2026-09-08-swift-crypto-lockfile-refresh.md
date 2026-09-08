# Fix: swift-crypto 4.x widen didn't actually change what builds (Package.resolved was still pinning 3.15.1)

Twelfth cycle this run — a self-caught correction to the eleventh cycle's own work
(`#87`), found by checking something that cycle's self-review should have checked but
didn't: what `Package.resolved` actually pins, not just what `Package.swift` allows.

## What went wrong

`#87` widened `KeeBridgeCore/Package.swift`'s `swift-crypto` constraint from
`from: "3.0.0"` to `"3.0.0"..<"5.0.0"` and claimed, in both `ROADMAP.md` and its own
`[self-review]` PR comment, that CI's green run was "actual proof this compiles and
passes against `4.x`'s API." That claim was wrong. Both `KeeBridgeCore/Package.resolved`
and `VaultProbe/Package.resolved` were already committed to the repo, pinning
`swift-crypto` at `3.15.1` (revision `95ba0316a9b733e92bb6b071255ff46263bbe7dc`).
SwiftPM's dependency resolution only replaces an existing pin when it stops satisfying
the manifest's constraint — and `3.15.1` still satisfies `"3.0.0"..<"5.0.0"` just as it
satisfied the old `from: "3.0.0"`. So widening the *allowed range* changed nothing about
what actually got resolved and built: CI's green run on `#87` validated that the widened
constraint is internally consistent and compiles, which it does, but the actual compiled
binary still linked against `3.15.1`, not any `4.x` release. The whole point of the
ROADMAP item — actually moving onto `4.x` — was not accomplished.

Found this cycle by checking the one thing `#87`'s self-review should have but didn't:
`cat KeeBridgeCore/Package.resolved` after the merge, to see what version is *actually*
pinned post-merge, rather than trusting that a widened `Package.swift` constraint implies
a new resolution happened.

## The fix

Deleted both `KeeBridgeCore/Package.resolved` and `VaultProbe/Package.resolved` (the
latter transitively depends on `KeeBridgeCore` via a local path, so it carries the same
stale pin) — the standard, SwiftPM-documented way to force a completely fresh dependency
resolution, safer than hand-editing a lockfile's JSON (including its `originHash`
content-hash field) without a local Swift toolchain to verify the result is internally
consistent. This PR's own CI run (`swift test` + the unsigned `xcodebuild` build) performs
that fresh resolution for real and is the actual, first genuine proof this codebase
compiles and its tests pass against a real `4.x` release — not the widened-constraint
compile `#87`'s CI run actually tested.

## What's still needed (filed as a manual-step issue)

Deleting the lockfiles restores fresh-resolve-every-build behavior for `KeeBridgeCore`
and `VaultProbe`, but it does *not* restore this repo's previous property of a committed,
reproducible pin — every future `swift build`/`xcodebuild` (CI's included) will now
silently pick up whatever the newest version satisfying each manifest's range happens to
be at build time, for every dependency in both packages, not just `swift-crypto`. That's
a real, if modest, regression in supply-chain reproducibility this executor cannot safely
fix itself: reconstructing a fully correct `Package.resolved` (with the right transitive
versions for `swift-crypto`, `swift-asn1`, and anything else `4.x` requires) needs a real
Swift toolchain to run `swift package resolve`/`swift package update` and verify the
result, which this executor's environment doesn't have locally. Filed as a `manual-step`
issue for a human to run that and commit the regenerated lockfiles.

## PR

See the PR that accompanies this file.
