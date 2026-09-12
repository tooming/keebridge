# EntryDetailView showed the OLD password/notes after editing an entry

## The bug

`EntryDetailView` reveals an entry's password/notes once, in `reveal()`,
and caches them in `@State` (`revealedPassword`, `revealedNotes`). That
state only ever gets re-populated by two triggers: `.onAppear` (the view
first appearing) and the `onSave` callback passed into the "Edit…" sheet's
`EntryEditView`, which was wired to `reveal()` directly:

```swift
.sheet(isPresented: $showingEdit) {
    EntryEditView(controller: controller, mode: .edit(entry.uuid), onSave: reveal)
}
```

`EntryEditView.save()` calls this `onSave()` synchronously, immediately
after calling `controller.updateEntry(uuid:applying:)`:

```swift
case .edit(let uuid):
    controller.updateEntry(uuid: uuid, applying: draft)
onSave()
return true
```

But `VaultController.updateEntry` is fire-and-forget: it kicks off a
`Task.detached` that does the actual vault re-open/write/re-list/mirror
work, and only writes the result back to `cachedContent`/`entries` inside
a later `await MainActor.run { ... }` completion. `onSave()` — and
therefore `reveal()` — runs synchronously in the same call as
`updateEntry(...)`, guaranteed to happen well *before* that detached
task's completion has had any chance to run (real disk I/O + a fresh vault
open + mirroring, not a same-tick operation). So `reveal()` read
`cachedContent` while it still held the **pre-edit** state, populating
`revealedPassword`/`revealedNotes` with the OLD values right after Save.

Nothing then ever corrected this: `.onAppear` only fires when a SwiftUI
view is newly added to the hierarchy, not on a same-identity update (the
parent `VaultBrowserView` keeps this view alive via `.id(entry.uuid)`,
so a data update while it's open is just a normal body re-evaluation, not
a fresh appearance) — and no other trigger ever called `reveal()` again
for the same open entry. Once the real write eventually landed in
`cachedContent`/`entries` moments later, the detail view's `@State` was
already stuck at the stale snapshot, indefinitely, until the user
navigated away and back (forcing a fresh `.onAppear`).

This is real and reachable on **every single edit** that changes an
entry's password or notes — not a rare race, since the detached task can
never complete before the synchronous call that triggers it returns. A
user who edits a password, saves, and then views/copies "the new
password" from the still-open detail view would actually get the OLD one
— even though the vault file on disk was correctly updated with the new
value the whole time.

Found via a full, fresh read of `EntryDetailView.swift` this cycle,
cross-checked against `VaultController.updateEntry`'s actual
`Task.detached`/`MainActor.run` implementation (the same async shape
`docs/done/2026-09-11-vaultcontroller-lock-race-fix.md` already
documented for `lock()`'s own race) rather than assuming the "v3:
synchronous, no Argon2" doc comments on the *read* helpers
(`revealEntryForEditing`/`passkeyMetadata`/`paymentCardMetadata`) implied
anything about the *write* paths' timing.

## The fix

- `VaultController.lastRefreshDate` (previously `private`) is now
  internal (default access) — `createEntry`/`updateEntry`/`deleteEntry`
  already set it inside the same `MainActor.run` completion block that
  updates `cachedContent`/`entries`, so it's the correct "the real data
  actually refreshed" signal.
- `EntryDetailView` now reacts to it via
  `.onChange(of: controller.lastRefreshDate) { reveal() }`, so `reveal()`
  runs again once the new content is actually in place, instead of
  immediately on save-request.
- The sheet's `onSave: reveal` callback is now `onSave: {}` — matching
  `VaultBrowserView`'s own add-entry call site, which was already a
  no-op — since the reactive `.onChange` now correctly owns re-revealing
  after any mutation, not just the specific "close the edit sheet" moment.
  `EntryEditView.onSave` itself is untouched (still a real parameter,
  still called) in case a future caller needs it.

No new secret exposure: this only changes *when* the exact same
already-implemented reveal function runs, not what it reveals or how.

## Verification

Compiled-only (`xcodebuild`) — `KeeBridge`'s SwiftUI/AppKit views
(`VaultController`, `EntryDetailView`) have no test target, same
constraint every other app-layer fix in this ROADMAP carries. Reasoned
through the actual async completion ordering directly against
`VaultController.swift`'s `updateEntry`/`createEntry`/`deleteEntry`
implementations rather than assumed. Still needs a human eyeball on real
hardware to confirm the detail view visibly updates to the new
password/notes right after Save with no perceptible delay or flicker —
this executor has no GUI to click through the actual flow.
