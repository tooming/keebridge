# Fix: real Swift 6 Sendable-concurrency compiler warnings, found via CI log content

Third re-survey angle this run, after `scripts/lib/colors.sh`'s fabricated cross-repo
comment history (PR #107, merged) and a second pass that found nothing further
(PR #108). This time the new signal was the CI build's own raw log content, not source
code: `make ci`'s pass/fail conclusion — the only thing any prior cycle had ever
consulted — never surfaces non-fatal compiler warnings, so a real, standing hygiene gap
had gone unnoticed across ~20+ prior audit cycles simply because nobody had fetched and
grepped the actual GitHub Actions job log for `warning:`.

## What was found

Fetching this repo's most recent successful CI run's job log and grepping for
`warning:` turned up exactly 4 real Swift compiler warnings (plus 3 unrelated
Xcode-tooling `appintentsmetadataprocessor` notices, not from this codebase):

- `KeeBridge/VaultController.swift:625` — capture of `store`
  (`ASCredentialIdentityStore`) in the `@Sendable` completion-handler closure passed to
  `store.replaceCredentialIdentities(_:completionHandler:)`. The compiler's own note
  suggested the fix directly: add `@preconcurrency` to the `AuthenticationServices`
  import.
- `KeeBridgeCardExtension/SafariWebExtensionHandler.swift:67` (three warnings on one
  line) — capture of `self`, `message: [String: Any]`, and `context:
  NSExtensionContext` in the `Self.workQueue.async { [self] in handle(message,
  context: context) }` closure inside `beginRequest`.

All are legitimate Swift 6 strict-concurrency diagnostics (non-`Sendable` types
crossing into a `@Sendable` closure boundary), not fatal — `make ci` was already green
— but real, standing hygiene gaps worth fixing where a clean fix exists, and worth
documenting honestly where it doesn't.

## What was fixed (confirmed via this PR's own rebuilt CI log, not assumed)

1. **`VaultController.swift`**: `@preconcurrency import AuthenticationServices` — the
   exact remediation the compiler's own diagnostic note suggested. Standard,
   zero-runtime-effect: it tells the type checker that this pre-Sendable-era Apple
   framework hasn't been Sendable-audited, without touching this codebase's own types.
   Confirmed gone from the rebuilt log after pushing.
2. **`SafariWebExtensionHandler.swift`**: marked the class `@unchecked Sendable`,
   confirmed safe by inspection *before* applying it, not assumed: every stored
   instance property is an immutable `let` of an already-`Sendable` type
   (`VaultService`/`KeychainStore` are `Sendable` structs — confirmed via their own
   declarations in `KeeBridgeCore`; `Logger` is `Sendable`), and the only actual
   mutable state is the `static` cache fields, which already carry their own
   `nonisolated(unsafe)` + `workQueue`-serialization justification from an earlier
   cycle's own three-source-confirmed audit. This silences the `self`-capture warning
   specifically. Confirmed gone from the rebuilt log after pushing.

## What was deliberately left, and why (2 of the original 4 remain)

- **`message: [String: Any]`** — `Any` can never be proven `Sendable` by the type
  system; this is a language-level limitation, not a "module needs an escape hatch"
  case. The payload's shape comes directly from `SFExtensionMessageKey` (Safari's own
  JS-bridged message dictionary), not something this codebase controls. Fixing this
  cleanly would mean redesigning how messages are typed end-to-end — real work, but
  well outside this item's scope.
- **`context: NSExtensionContext`** — first "fixed" the same way as the
  `AuthenticationServices` case, with `@preconcurrency import Foundation`. **Caught
  during this cycle's own verification, not left unchecked**: re-fetching and
  re-grepping this PR's rebuilt CI log after pushing showed the warning was still
  present. Root-caused: the `@Sendable` requirement here comes from `DispatchQueue.
  async`'s own closure-parameter type (declared in the `Dispatch` module, not
  `Foundation`), so `@preconcurrency import Foundation` had nothing to suppress —
  `NSExtensionContext` merely happens to be *defined* in Foundation, but the
  Sendable-crossing boundary isn't a Foundation API. Reverted the ineffective import
  rather than leave a "fix" in place that does nothing but widens what future
  Foundation-Sendable diagnostics get silently suppressed in this file. A real fix
  would require retroactively declaring Apple's own `NSExtensionContext`
  `@unchecked Sendable` in an extension — plausible in practice (extension contexts are
  commonly used from background queues in real-world extensions), but this cycle
  couldn't gather strong enough evidence of its actual thread-safety contract to make
  that call with the same confidence bar this ROADMAP holds itself to elsewhere
  (e.g. the three-independent-source confirmation for the static-cache fix). Left as a
  genuine, documented gap for a future cycle with either stronger evidence or a
  maintainer decision, not a guessed-at conformance.

## Net result

4 real compiler warnings → 2, confirmed via the actual rebuilt CI log content (not the
diff alone). No behavior change in either direction — every change here is a
compile-time-only diagnostic annotation. `make ci` was green before, during, and after
every push on this PR.

## PR

See the PR that accompanies this file.
