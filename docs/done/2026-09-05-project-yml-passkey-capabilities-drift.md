# `project.yml` was missing two passkey capability flags a real `xcodegen generate` would silently regress

`project.yml` is this project's declarative source of truth for the Xcode project
(`README.md`'s own Setup section: `xcodegen generate` is the first command anyone — a new
contributor, a fresh machine, CI if it ever adopts this step — runs). Its
`KeeBridgeProvider` target's `info.properties` block only declared two of the four
`ASCredentialProviderExtensionCapabilities` flags:

```yaml
NSExtensionAttributes:
  ASCredentialProviderExtensionCapabilities:
    ProvidesPasswords: true
    ProvidesOneTimeCodes: true
```

but the actual, checked-in `KeeBridgeProvider/Info.plist` — the file Xcode's build
(`INFOPLIST_FILE = KeeBridgeProvider/Info.plist`, confirmed in `project.pbxproj`) actually
reads — has all four:

```xml
<key>ProvidesOneTimeCodes</key><true/>
<key>ProvidesPasswords</key><true/>
<key>ProvidesPasskeys</key><true/>
<key>SupportsConditionalPasskeyRegistration</key><true/>
```

Confirmed via git history this is real drift, not an intentional difference: `project.yml`'s
capabilities block was added once and never touched again, while `#32` ("Wire passkey
registration") and `#38` ("Add conditional passkey registration support") each added
`ProvidesPasskeys`/`SupportsConditionalPasskeyRegistration` directly to the physical
`Info.plist` file without updating `project.yml` to match.

This doesn't affect *today's* build — Xcode reads the physical `Info.plist` file directly,
which is currently correct — but it's a live regression trap: XcodeGen regenerates
`info.path` from `info.properties` on every `xcodegen generate` run, so the next time anyone
follows `README.md`'s own documented setup step (or any future workflow that regenerates the
Xcode project — e.g. `xcodegen` becoming a CI step, which a prior `docs/backlog/*.md` entry
already noted this project doesn't currently have set up), the real `Info.plist` would be
silently overwritten with the two-flag version, which would **silently disable passkey
assertion routing (`ASCredentialIdentityStore` can't route a request without the capability
declared) and both the interactive and conditional passkey registration flows** — several
ROADMAP cycles worth of shipped work, with no error or test failure anywhere to catch it,
since neither `make ci` nor this repo's `ci` GitHub Actions workflow runs `xcodegen
generate` at all today.

## Fix

Added the two missing flags to `project.yml`'s `KeeBridgeProvider` target so it matches the
physical `Info.plist` exactly — a future `xcodegen generate` now reproduces the same file
instead of regressing it. No behavior change today (the physical file was already correct);
this is a drift/regression-prevention fix, not a functional one.

Found via a fresh, adversarial read of `project.yml` cross-checked against the physical
`Info.plist`/`project.pbxproj` files — the fourth finding this run's STEP 8 loop (after
#60, #61, #62), and the first in this run's survey to look at build configuration rather
than application logic.

**Verification**: config-only YAML change, no Swift compiled. Confirmed by direct text
comparison against `KeeBridgeProvider/Info.plist`'s existing (correct) content — the two
files' `ASCredentialProviderExtensionCapabilities` blocks now match exactly. This executor's
environment has no `xcodegen` binary to actually regenerate the project and diff the output
(see `docs/backlog/2026-09-03-action-needed-backlog-blocked.md` for the toolchain gap this
extends to), so this is validated by the pushed branch's `ci` GitHub Actions run
(`make build`/`xcodebuild`, which reads the physical `Info.plist` unaffected by this change)
plus the direct textual comparison above, not by actually running `xcodegen generate`
end-to-end. **Still needs a human eyeball**: running `xcodegen generate` locally once to
confirm it now reproduces `Info.plist` byte-for-byte (or at least capability-for-capability)
rather than regressing it, since this executor cannot run that tool at all.

## PR

See the PR that accompanies this file.
