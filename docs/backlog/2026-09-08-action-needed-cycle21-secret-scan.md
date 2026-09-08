# [Action needed] Twenty-first cycle — targeted secret scan of credential-adjacent files; backlog still empty

Twenty-first cycle this run. `ROADMAP.md`'s "Now / next" lane remains fully checked
(only `#77` unchecked, correctly skipped by STEP 3). Zero open PRs.

## What was checked

Tried the dedicated secret-scanning tool available to this session
(`run_secret_scanning`) against the repo's most credential-adjacent files —
`routines/routines.yaml`, `.routines-applied`, all three `.entitlements` files, both
extension `Info.plist`s, both `Package.swift`s, all three `routines/` shell scripts,
`scripts/lib/colors.sh`, `.github/workflows/ci.yml`, and `project.yml` — rather than
re-running prior cycles' manual `grep`-for-patterns sweeps (`#82`'s
silent-error-swallowing sweep and `#83`'s `.gitignore` check already covered adjacent
ground, but neither used an actual secret-detection engine).

The tool itself errored (`"Repository does not have GitHub Advanced Security
enabled"`) rather than returning a scan result — this repo is public, and GHAS is
typically a private-repo/org feature, so this is plausibly just this tool requiring a
capability this repo doesn't carry, not evidence the repo itself lacks GitHub's
free-for-public-repos baseline secret scanning. Not confident enough either way to
assert a real gap here — flagging the ambiguity rather than guessing, since asserting
a security gap that turns out to be a tool artifact would be worse than saying nothing.

Manually re-read the same fileset directly instead: `routines.yaml`/`.routines-applied`
contain a trigger ID and a sha256 digest, not secrets; the `.entitlements`/`Info.plist`
files are plain capability declarations; `Package.swift`s pin public GitHub URLs and a
public commit revision; `project.yml`'s `DEVELOPMENT_TEAM: M2KQ698ZS5` is an Apple Team
ID (public-ish, visible in any signed binary from this account, not a credential); the
`routines/` scripts and `colors.sh` contain no embedded tokens. No secret material found.

## No new findings

Same two open issues as recent cycles (`#77`, `#89`). Filing this rather than
fabricating make-work, per STEP 6b.
