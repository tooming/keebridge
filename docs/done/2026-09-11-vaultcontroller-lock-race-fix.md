# Lock() could be silently undone by an in-flight background refresh/write

## The bug

`VaultController.lock()` is the app's own "Lock" button action. Its doc
comment says exactly what it's supposed to do: "Clears in-memory unlock
state... purely a UI-state reset so the browser closes and the locked
screen shows again." It has no guard against work already in flight when
it's called.

`unlock()`, `refresh()` (reached via the manual "Refresh from cached key"
button and the throttled auto-refresh on every `NSApplication.
didBecomeActiveNotification`), `createEntry()`, `updateEntry()`, and
`deleteEntry()` each dispatch a `Task.detached` for the real Argon2id/I/O
work, then hop back to `MainActor.run` on completion and unconditionally
write `self.isUnlocked = true` (unlock/refresh) and/or repopulate
`self.cachedContent`/`self.entries` (all five) — with no check for
anything having changed about the controller's state in the meantime.

Concretely reachable sequence:

1. Vault is unlocked; the user switches away to Safari and back (or just
   waits — `didBecomeActiveNotification` fires on internal focus changes
   too, per this file's own `refreshIfStale()` comment), triggering a
   throttled `refreshFromCache()` in the background.
2. Before that refresh's detached task completes, the user taps "Lock".
   `lock()` runs immediately: `isUnlocked = false`, `entries = []`,
   `cachedPreHash = nil`, `cachedContent = nil`. `ContentView` switches to
   `LockedView` right away, exactly as expected.
3. The refresh's completion then runs anyway: `self.isUnlocked = true`,
   `self.cachedContent = content`, `self.entries = entries`. `ContentView`
   switches straight back to the unlocked vault browser, showing every
   entry — with no new authentication of any kind. The "Lock" action the
   user just took is silently reverted behind their back.

`createEntry`/`updateEntry`/`deleteEntry` share the same shape but don't
touch `isUnlocked` — their late completions instead quietly restore
`cachedContent`/`entries` in memory (the actual decrypted vault content
`lock()` was specifically supposed to purge) while the UI still shows
`LockedView`, invisible but just as real a residual-plaintext-after-lock
problem for as long as the process stays running. The on-disk write itself
in these three is unaffected either way and shouldn't be — this is only
about what gets reflected back into this object's own `@Published` state.

Found by reading `VaultController.swift` in full (not yet read this run)
as this cycle's resurvey — a fresh angle on top of the "dead-end UI" and
"stale documentation" lenses already applied almost everywhere else in the
codebase this run: tracing what happens to a `Task.detached`'s captured
state when the object it reports back to changes shape while the task is
still running.

## The fix

Added a `generation` counter, bumped by `lock()`. Each of the five
call sites captures `generation` into a local `startGeneration` on the
main actor, right before starting its background work; each completion
still unconditionally clears `isWorking` (so a `lock()` mid-flight can't
leave the controller stuck refusing all future unlock/refresh/write calls)
but now guards everything else — `isUnlocked`, `cachedContent`, `entries`,
`lastRefreshDate`, `populateIdentityStore` — behind `self.generation ==
startGeneration`. A `lock()` that happened after the background work
started, but before it finished, makes the stale completion a no-op for
all of that state, instead of quietly reviving it.

## Verification

Swift-only change (`KeeBridge/VaultController.swift`), no test target
exists for the app-layer `KeeBridge` target at all (confirmed: no
`KeeBridgeTests` directory, and `VaultController` needs `@MainActor` +
`AppKit` + `AuthenticationServices`, not headlessly testable the way
`KeeBridgeCore`'s library targets are) — compiled-only via CI's
`xcodebuild`/`make build`, same constraint every prior app/extension-layer
UI fix this run has had (e.g. the QR-scanner and CredentialProvider
dead-end fixes).

- `bash scripts/routines-check.sh` — ✅
- `bash scripts/routines-author-check.sh` — ✅
- `bats tests/drift-detectors.bats` — ✅ (15/15)

No entitlements, secrets, or KDBX crypto touched. Still needs a human
eyeball on real hardware to reproduce the original race under Instruments
or manual timing (lock a switch-triggered auto-refresh mid-flight) — this
executor has no GUI or macOS hardware to do that itself.
