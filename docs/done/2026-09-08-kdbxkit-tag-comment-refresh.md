# KDBXKit dependency comment: tags now exist, but the pin is still current

Eighth cycle this run — after cycle seven (#83) noted that further code-only re-audits
were hitting diminishing returns, this cycle tried a genuinely different activity per its
own suggestion: re-checking upstream `KDBXKit` freshness, the exact periodic check
`docs/backlog/2026-09-07-action-needed-remaining-files-and-dependency.md` explicitly
flagged as "worth a future cycle repeating... upstream `develop` moves; this snapshot is
only good as of today."

## What changed upstream

`git ls-remote https://github.com/shadone/KDBXKit.git develop` still resolves to the
exact pinned revision (`e9b8839f1226b82665e1e4b7f12f13635d189deb`) — no drift, same
result as 2026-09-07's check. But `git ls-remote --tags` turned up something genuinely new
since that last check: **four tagged releases now exist** (`v1.0.0` through `v1.3.0`),
where `KeeBridgeCore/Package.swift`'s own comment still said "KDBXKit has no tagged
release yet (checked 2026-08-07: zero tags...)".

Cloned the repo to verify the relationship rather than guessing: `v1.3.0`'s tagged commit
(`930fb977...`, 2026-06-11) is an ancestor of the pinned revision (`e9b8839f...`,
2026-06-12) — the pin is **41 commits ahead** of the latest tag, not behind it. So this is
not a "the pin is stale, upgrade to the tag" finding (that would actually be a 41-commit
*downgrade*, exactly what the original comment's own reasoning — "so this doesn't
silently float to a future commit" — was written to avoid). It's a "the comment's factual
premise is now wrong" finding: it still needs correcting even though the actual pinned
revision needs no change.

## What changed

`KeeBridgeCore/Package.swift`'s dependency comment only — updated to record that tags now
exist, confirm the pin is still `develop`'s current HEAD and ahead of the newest tag, and
note a future cycle could reconsider tracking the newest tag once `develop` and tags
converge (they're 41 commits apart right now, so not yet). The pinned `revision:` value
itself is unchanged — this is not a dependency version bump, just a comment correction
verified against the actual upstream repository state (cloned to run `git merge-base
--is-ancestor` and compare commit dates, not just eyeballing SHAs).

## PR

See the PR that accompanies this file.
