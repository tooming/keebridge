# Fix: `refreshIfStale()`'s throttle timestamp could absorb a legitimate refresh

Twenty-fourth cycle this run. Found via a continued full-linear-file-read audit
(same technique as `#95`/`#99`/`#100`) — this time `KeeBridge/VaultController.swift`
(697 lines, the app's own AutoFill-flow coordinator, not yet given a complete
top-to-bottom read by any prior cycle).

## The bug

`refreshIfStale()` (fired on every `NSApplication.didBecomeActiveNotification`,
throttled to once per 15s) stamped `lastRefreshDate = Date()` *before* calling
`refreshFromCache()` — including on a call that `refreshFromCache()`'s own
`guard let vaultURL, !isWorking else { return }` immediately no-ops on (e.g. a
`createEntry`/`updateEntry`/`deleteEntry`/another `refresh` already in flight).
That silently marked a sync as having just happened even though nothing was
actually read or re-registered with `ASCredentialIdentityStore` — the next
legitimate window-activation refresh (meant to pick up an edit made in KeePassXC
while KeeBridge was in the background) could then be throttled away for up to the
full 15s interval on top of however long the original in-flight operation still
had left, delaying how soon an external edit shows up in the app's UI and Safari's
suggestions. Not a security or data-loss bug — `isWorking`/the write paths' own
completions already guarantee correctness of what's on disk — but a real,
previously-undocumented UX-staleness gap in exactly the kind of subtle
async-timing class of bug this file's own comments show multiple prior fixes for
(the removed 45s polling Timer, the didBecomeActive-fires-on-sheet-interaction
throttle itself).

## The fix

Removed the premature stamp from `refreshIfStale()`. Every path that actually
performs a sync (`unlock`, `refresh(vaultURL:preHash:)`, `createEntry`,
`updateEntry`, `deleteEntry` — confirmed via `grep -n "lastRefreshDate = Date()"`,
all five still present) already stamps `lastRefreshDate` in its own
`MainActor.run` completion once the work genuinely lands, so nothing else needed
to change. Re-verified the remaining reentrancy behavior: two `didBecomeActive`
firings arriving back-to-back, before the first refresh's async work completes,
now both pass the throttle check (since `lastRefreshDate` hasn't moved yet) but
the second harmlessly no-ops against `refreshFromCache()`'s `isWorking` guard
instead of launching duplicate work — same outcome as before for that case, just
without the false-positive throttle side effect for the actually-skipped case.

## Verification

No local Swift toolchain in this run's environment (confirmed again this cycle:
`swift: not found`), so this couldn't be compiled locally — same limitation every
other app-target Swift edit this run has had (e.g. `#91`'s `KeeBridgeConfigTests`,
verified only by CI's `make build`/`make test`, not locally). Traced the change by
hand instead: it's a one-line removal with no new symbols, no changed signatures,
and no altered control flow outside `refreshIfStale()` itself — CI's unsigned
`xcodebuild` build is what actually confirms it type-checks; will confirm green
before merging, per STEP 7.

## PR

See the PR that accompanies this file.
