# [Action needed] Ninth cycle this run — reverse-direction pbxproj↔disk file check, clean

Ninth cycle this run. Prior cycles landed three real fixes (#113, #114, #116), four
honest re-surveys (#112, #115, #117, #118), and one `plan/*` refill flagging stale
git branches as a maintainer action item (#119).

## What this ninth cycle checked

A prior run's `pbxproj-audit` cycle (`docs/backlog/2026-09-08-action-needed-pbxproj-audit.md`)
read `project.pbxproj` in full and confirmed "every `PBXFileReference` matches a real
file already read this run" — the forward direction (pbxproj → disk). This cycle
checked the REVERSE direction, which that audit didn't: does every real source/resource
file on disk actually have a `PBXFileReference` in `project.pbxproj`? A `.swift` file
present in `KeeBridge/`/`KeeBridgeProvider/`/`KeeBridgeCardExtension/` but missing from
the project file would silently never compile — the repo would look complete on
GitHub, `git status` would show nothing wrong, but the built app simply wouldn't
contain that code. The same class of gap the earlier `docs/done/`↔`ROADMAP.md`
backward-consistency check (#110) closed, applied to a different pair of artifacts.

- **Every `.swift` file** in the three targets' source directories (9 files:
  `ContentView`, `EntryDetailView`, `EntryEditView`, `KeeBridgeApp`, `LockedView`,
  `VaultBrowserView`, `VaultController`, `SafariWebExtensionHandler`,
  `CredentialProviderViewController`) has a matching reference in `project.pbxproj`
  — confirmed by diffing `find ... -name "*.swift"` against a grep of the `.pbxproj`
  file, not assumed.
- **Every resource file** in `KeeBridgeCardExtension/Resources/` (`background.js`,
  `content.js`, `manifest.json`, `unlock.html`, `unlock.js`) — same result, all
  present.

No orphaned file (on disk, silently excluded from the build) found. This is a useful
negative result, not wasted effort: it rules out the one class of drift that neither
`make ci` (which builds successfully either way — a missing file just means less code
ran, not a build failure) nor any prior cycle's pbxproj read had specifically checked
for.

## Current state

`ROADMAP.md`'s "Now / next" lane remains fully checked off after this run's three real
fixes; "Needs maintainer/human action" now has two items (`#77`, and this run's own
stale-branch-cleanup flag), both correctly needing a human. Filing this rather than
fabricating a tenth "finding" from nothing, per `routines/executor.prompt.md` STEP 6b.
