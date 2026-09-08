# [Action needed] Entitlements/project.yml drift check + full git-history secret sweep — clean

Third cycle this run. First cycle (#76) audited the card extension's JS/HTML/manifest web
surface; second cycle (#78) re-surveyed `routines/` and found a real tool-grant/governance
discrepancy worth a human's attention (see #77, `ROADMAP.md`'s "Needs maintainer/human
action"). This cycle covers two angles genuinely not exercised by any prior cycle,
including yesterday's three exhaustive Swift-file passes:

## Entitlements / `project.yml` / `project.pbxproj` cross-check

Read all five entitlements/Info.plist files fresh
(`KeeBridge/KeeBridge.entitlements`, `KeeBridgeProvider/KeeBridgeProvider.entitlements`,
`KeeBridgeProvider/Info.plist`, `KeeBridgeCardExtension/KeeBridgeCardExtension.entitlements`,
`KeeBridgeCardExtension/Info.plist`) against `project.yml`'s declared
`entitlements`/`info` blocks, then cross-checked both against the actual
`KeeBridge.xcodeproj/project.pbxproj` build settings that `xcodebuild` uses directly (the
`.xcodeproj` is committed and built as-is — CI has no `xcodegen generate` step, so
`project.yml` alone isn't what actually builds; drift between the two would mean
`project.yml` documents intent that isn't what's really shipped, the same class of gap
`#63` already found and fixed once for the passkey capability flags).

**Result: no drift.** `ENABLE_APP_SANDBOX`, `CODE_SIGN_ENTITLEMENTS` paths,
`PRODUCT_BUNDLE_IDENTIFIER`, `SWIFT_VERSION`, and `MACOSX_DEPLOYMENT_TARGET` all match
between `project.yml` and `project.pbxproj` for all three targets (`KeeBridge`:
unsandboxed, no extra entitlements beyond the credential-provider flag, matching the
README's documented "deliberately not sandboxed" design; `KeeBridgeProvider`: sandboxed +
credential-provider entitlement; `KeeBridgeCardExtension`: sandboxed only, correctly
*without* the credential-provider entitlement since it's a Safari extension, not a
credential provider). `ASCredentialProviderExtensionCapabilities`
(`ProvidesPasswords`/`ProvidesOneTimeCodes`/`ProvidesPasskeys`/
`SupportsConditionalPasskeyRegistration`) live directly in the static `Info.plist` file
that `INFOPLIST_FILE` points to (not embedded in `project.pbxproj`'s build settings,
which is expected given `GENERATE_INFOPLIST_FILE: YES` merges the on-disk plist with
generated keys) — matches `project.yml`'s declared `info.properties` exactly, still in
sync with `#63`'s fix.

## Full git-history secret sweep

Prior cycles' secret-hygiene checks (this run's #76, and #73-#75 before it) grepped the
*current working tree* for `TODO`/`FIXME` and reviewed code paths handling secrets. None
explicitly swept full git history for a secret that was committed and later removed —
which current-tree scans can't catch, since a since-deleted blob still lives in history
unless it was purged. Ran three checks against `git log --all -p` (every commit on every
ref, not just `main`):

- Any file ever added matching `*.kdbx` (a real vault) — **none**.
- Any file ever added matching `*.p8`/`*.p12`/`*.pem`/`*.mobileprovision`/`*.cer`/`*.key`
  (signing/provisioning material) — **none**.
- Every historical diff line matching common secret-marker patterns (PEM private-key
  headers, AWS access-key IDs, Slack tokens, OpenAI-style API keys, Google API keys,
  generic `password = "..."` / `*_key = "..."` assignments) — the only hits are the
  existing synthetic `"-----BEGIN PRIVATE KEY-----\nMOCK-NOT-A-REAL-KEY\n-----END PRIVATE
  KEY-----"` PEM fixture already used throughout `PasskeyTests.swift`/`PasskeyCrypto`
  (explicitly marked as mock, consistent with this repo's existing secret-hygiene
  discipline) and prose in doc/commit-message text discussing that same fixture. No real
  credential, no `hunter2`-adjacent password used outside the documented synthetic
  test-password convention, no real API/service key anywhere in history.

**Result: clean.** No secret was ever committed and later scrubbed; the repo's
secret-hygiene discipline holds across its full history, not just its current tree.

## Current state

Between this run's three cycles (#76, #78, this one) and yesterday's three (#73-#75),
every source file, the card extension's non-Swift web surface, `routines/`'s governance
tooling, the entitlements/project-config surface, and now the full git history have each
had a fresh, targeted check this week. `ROADMAP.md`'s "Now / next" lane remains empty; its
"Needs maintainer/human action" section carries the one open item from this run (#77).
Zero open GitHub issues besides #77, zero other open PRs, zero `TODO`/`FIXME` markers.
Filing this rather than fabricating make-work, per STEP 6b.
