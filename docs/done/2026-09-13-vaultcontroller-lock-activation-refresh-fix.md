# `VaultController.lock()`'s explicit Lock action could be silently undone by app activation alone

Found via a fresh, full re-read of `VaultController.swift` this cycle (the ROADMAP's
"Now / next" lane was otherwise fully checked off — this was a STEP 6b-style resurvey
that found a real, previously-unaddressed bug rather than coming up empty).

## The bug

`startWatching()` registers an `NSApplication.didBecomeActiveNotification` observer
whose handler calls `refreshIfStale()`. That observer is (re-)registered every time
`unlock()` succeeds, but `lock()` never tears it down — it stays live for the rest of
the app's process lifetime, including after the user explicitly locks.

`refreshIfStale()` itself had no `isUnlocked` check at all — only a 15-second throttle
against `lastRefreshDate`. So the sequence:

1. Unlock the vault normally (registers the activation observer).
2. Browse for a while (so `lastRefreshDate` is more than 15s in the past by the time
   you lock).
3. Tap "Lock" — `isUnlocked` becomes `false`, `cachedPreHash`/`cachedContent` are
   cleared, `entries` is emptied.
4. Switch to any other app, then switch back to KeeBridge (or just click on its
   window) — nothing more deliberate than that.

`didBecomeActiveNotification` fires, `refreshIfStale()` runs, the throttle window has
elapsed, and it calls `refreshFromCache()` unconditionally. Since `cachedPreHash` was
cleared by `lock()`, that hits the no-cached-key branch: a real Keychain read (which
prompts Touch ID if the item is `.biometryCurrentSet`-protected). On success, it sets
`isUnlocked = true`, repopulates `entries`, and re-registers the `ASCredentialIdentityStore`
identities — silently reverting the user's own Lock action, triggered by nothing more
than switching back to the app.

This is a different gap from the 2026-09-11 lock-race fix
(`docs/done/2026-09-11-vaultcontroller-lock-race-fix.md`), which added the `generation`
counter to discard a refresh/write completion that was *already in flight* at the moment
`lock()` ran. That counter can't catch this case: no second `lock()` call happens between
this brand-new, activation-triggered refresh starting and completing, so `generation`
never changes out from under it — the refresh's own `startGeneration` matches the
current `generation` throughout, and the result gets applied as if it were legitimate.

## The fix

One added guard at the top of `refreshIfStale()`:

```swift
guard isUnlocked else { return }
```

This stops the *automatic*, activation-triggered refresh path from running at all while
locked. The manual "Refresh from cached key" button in `LockedView` is unaffected — it
calls `controller.refreshFromCache()` directly, not through `refreshIfStale()`, and is
deliberately enabled "whenever a vault is picked, not gated on `isUnlocked`" (per that
view's own existing comment) precisely so a user can choose to unlock via the cached key
instead of retyping the master password. That explicit, user-initiated path keeps
working exactly as before; only the silent, activation-driven one is now gated.

No test target exists for `VaultController` (SwiftUI/AppKit + real Keychain/Argon2id, no
injectable seam) — compiled-only via `xcodebuild`, same as every other app-layer change
in this ROADMAP.

## Validation caveat (this cycle's own environment)

This cycle's executor session runs in a Linux sandbox with no Xcode/`xcodebuild`
available at all (confirmed: no `swift`/`xcodebuild` binary anywhere on the container,
and `xcodebuild` cannot exist on Linux regardless — it's macOS-only). The parts of
`make ci` that don't need a macOS toolchain (`make routines-check`,
`make routines-author-check`, `make routines-bats-test`, none of which this change
touches) were run locally and pass. The actual `make build` (`xcodebuild`) step for
this specific change could not be run locally — it relies on this PR's `ci.yml` run on
GitHub Actions' `macos-latest` runner as the real gate, confirmed green before merging
(see the `[self-review]` PR comment).

## PR

See the pull request opened for this change (linked from the PR history for
`auto/vaultcontroller-lock-activation-refresh` — self-reviewed and self-merged per
`docs/WAYS-OF-WORKING.md` §0.1).
