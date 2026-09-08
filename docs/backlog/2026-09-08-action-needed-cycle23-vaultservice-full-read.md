# [Action needed] Twenty-third cycle — full read of VaultService.swift; clean

Twenty-third cycle this run. `ROADMAP.md`'s "Now / next" lane remains fully checked
(only `#77` unchecked, correctly skipped by STEP 3). Zero open PRs.

## What was checked

Read `KeeBridgeCore/Sources/KeeBridgeCore/VaultService.swift` (864 lines, the
second-largest source file and the one every other target — the app, both
extensions, `VaultProbe` — actually calls to touch the vault) start to finish in
one linear pass, same technique as `#95`/`#99`'s full reads of `project.pbxproj`
and `CredentialProviderViewController.swift`.

Specifically traced:

- `updateEntry`'s custom-field-preservation logic (the exact code path `#57`'s
  data-loss bug lived in): the `preservedCustomFields` filter's `otp`-specific
  clause correctly implements all three documented cases from the method's own
  doc comment — `otpURI: nil` preserves an existing `otp` field untouched,
  `otpURI: ""` drops it, and a non-empty `otpURI` replaces it without ever
  producing a duplicate `otp` key (the filter excludes the old one exactly when
  `draftStrings` is about to add a new one).
- `mergeExtensionOriginatedPasskeys`: the `sourceAlreadyMatches` short-circuit
  (skip when the source entry's credential ID already matches the mirror's — no
  spurious re-merge/re-timestamp) and the "entry in mirror but absent from
  source" case (defensively skipped via `mutateEntry`'s return value, never
  throws or creates) both match the doc comment's stated contract exactly.
- `openReadOnlyContent`'s KDBX-3.x fallback: catches only
  `.unsupportedFormatVersion(major: 3, _)` and falls back to the eager parse for
  that one case; every other error (wrong password, corruption, an unsupported
  *newer* format version) propagates as `.openFailed` without a fallback attempt
  — matches `KDBXReader.openMetadataOnly`'s own documented guidance, no
  overly-broad catch that could mask a real error as a soft failure.
- `trimHistory`'s off-by-one: `removeFirst(entry.history.count - Int(max))` after
  the new snapshot has already been appended — correctly leaves exactly `max`
  entries (including a `max == 0` "keep no history" configuration).
- The three tree-walk helpers (`findEntry`/`mutateEntry`/`removeEntry`) all
  recurse into subgroups consistently and stop at the first UUID match, matching
  `listEntries`'s own recursive walk.

No bug found. Clean.

## No new findings

Same two open issues as recent cycles (`#77`, `#89`). Filing this rather than
fabricating make-work, per STEP 6b.
