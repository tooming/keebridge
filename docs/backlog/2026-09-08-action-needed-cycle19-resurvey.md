# [Action needed] Nineteenth-cycle re-survey — backlog still empty; one out-of-band merge noted

Nineteenth cycle this run. `ROADMAP.md`'s "Now / next" lane is fully checked; the
only remaining `[ ]` item is the "Needs maintainer/human action" one (`#77`,
`allowed_tools`/`RemoteTrigger` gating question), which STEP 3 correctly does not
pick up — it needs human input, not more code.

## Out-of-band merge noted

The prior cycle's PR (`#95`, the `project.pbxproj` full-read audit) was merged
directly by the maintainer (`tooming`) rather than through this run's own STEP 7
self-review-then-merge flow — no `[self-review]` comment or `self-reviewed` label
was ever posted on it before merge. Checked for any comment on `#95`, `#77`, or
`#89` that might carry an instruction for how to proceed: none exist on any of the
three. Also confirmed via `get_me` that this run's authenticated GitHub identity
*is* the maintainer's own account (`tooming`, id `6115129`) — not a distinct bot
identity — which is why every PR/commit this whole run shows as authored by
"tooming." Nothing to act on here beyond noting it; treating a human's own direct
merge of a docs-only PR as requiring a response would be manufacturing work where
none exists.

## Re-survey

Re-read areas not given a full pass recently rather than re-running the same
targeted greps as recent cycles:

- **Web extension JS** (`KeeBridgeCardExtension/Resources/{content,background,unlock}.js`,
  `manifest.json`) — full re-read, not just the cross-origin-iframe-block angle
  `#79`-era work already covered. `background.js`'s `unlock` action is correctly
  gated to `sender.url === browser.runtime.getURL("unlock.html")` (a compromised or
  malicious page's content script can't forge an unlock call); `listCards`/`fillCard`
  are only reachable from the extension's own `content.js` via `browser.runtime`
  messaging, which is not exposed to arbitrary page JS regardless of
  `host_permissions: ["<all_urls>"]`. One harmless dead field: `content.js`'s
  `nativeRequest()` always sends `origin: location.origin`, but
  `SafariWebExtensionHandler.handle(_:context:)` never reads `message["origin"]`
  anywhere — consistent with `content.js`'s own comment that card data has no
  per-entry origin to filter by, so this isn't a gap, just an unused field. Not
  worth its own cycle to strip.
- **`.github/workflows/ci.yml`** — re-read in full; `actions/checkout` still pinned
  by SHA with a matching version comment (re-confirming `#83`-era pin verification,
  no drift since).
- **`docs/WAYS-OF-WORKING.md`** — re-read in full; matches current self-merge
  authority and cost/kill-switch state, no drift from what recent cycles have
  assumed.

No new findings. Zero open PRs; same two open issues as every recent cycle
(`#77`, `#89`), both still awaiting a human.

Filing this rather than fabricating make-work, per STEP 6b.
