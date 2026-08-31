# Passkey registration write-path spike: the mirror is read-only, one-way

## What this is

A design spike, not a code change — found while scoping the "passkey registration"
ROADMAP item (#4), before writing any `prepareInterface(forPasskeyRegistration:)` code.
No implementation shipped this cycle; see the two ROADMAP bullets this splits the
registration item into.

## The finding

`KeeBridgeProvider` (the credential-provider extension) has never written to the vault —
README.md's own architecture section calls it out: "v1 scope: passwords + TOTP. Read-only
against the vault — never writes" (the file header comment in
`CredentialProviderViewController.swift`, unchanged since the project's start). The
mirroring that gets a vault copy INTO the extension's sandbox container is strictly
one-way:

- `KeeBridgeConfig.vaultMirrorURLForApp()` / `vaultMirrorURLForExtension()` compute the
  SAME path two different ways (real user home vs. sandbox-redirected home) — confirmed
  by reading `KeeBridgeConfig.swift` directly.
- `VaultController.mirrorVaultToExtension(from:)` is called from the (unsandboxed) app
  after every app-side `createVault`/`createEntry`/`updateEntry`/`deleteEntry` (5 call
  sites, confirmed via `grep`), copying the app's own just-written vault into that path.
- Nothing anywhere reads a change back the other way. The extension only ever calls
  `VaultService.openVault`/`revealField`/`currentTOTPCode`/`passkeyMetadata` — all reads —
  against the mirror.

**Why this matters for registration specifically**: `VaultService.setPasskey` already
exists (shipped for the app's own use), so it would be technically trivial for
`CredentialProviderViewController` to call it directly against `vaultURL` (the mirror) to
store a freshly-registered passkey's credential ID + private key. But doing that naively
would be a real data-integrity bug, not just an incomplete feature:

1. The write lands ONLY in the extension's sandbox-container mirror copy — never in the
   real, Google-Drive-synced vault file the app (and KeePassXC) actually read. The new
   passkey doesn't durably exist anywhere else.
2. The next time the app performs ANY of its own writes (`mirrorVaultToExtension` runs
   after every one), it overwrites the mirror from the real vault — which still doesn't
   have the passkey — silently erasing the extension's local write.
3. From the relying party's perspective, a passkey was successfully registered (KeeBridge
   returned a valid `ASPasskeyRegistrationCredential`, they stored its public key).
   KeeBridge would then be unable to produce a matching assertion once the mirror gets
   clobbered — an unrecoverable, silent failure the user has no way to anticipate or
   diagnose from outside.

This is worse than not implementing registration at all: a passkey that appears to
register successfully and then silently stops working is a confusing, hard-to-debug user
experience, and — for a password/credential manager specifically — a trust-eroding failure
mode. It's the kind of thing this repo's SECRET HYGIENE / CRYPTO-ENTITLEMENTS hard rules
exist to catch even though it isn't strictly a secret-hygiene or crypto issue itself: a
silent, hard-to-notice correctness failure in exactly the code path meant to be trustworthy.

## Why this wasn't caught by the earlier design spikes

The original passkey design spike (`docs/done/2026-08-26-passkey-design-spike.md`)
focused on storage CONVENTION (which KDBX custom fields to use) and the AAGUID
platform-risk finding — both about representing a passkey once it exists in the vault, not
about how a NEWLY-created one gets there from the extension's sandboxed, read-only-so-far
vantage point. Every subsequent passkey PR (read metadata, write metadata, crypto
primitives, `authenticatorData`, `attestationObject`, assertion wiring) either operated on
an ALREADY-mirrored vault (read paths) or was primitive/pure-function work with no I/O at
all (`PasskeyCrypto`) — none of them exercised the extension's write path, so this gap
stayed invisible until registration, the first feature that actually needs the extension to
persist something.

## Likely shape of a fix (not yet designed in detail — this is a spike, not a plan)

Since `vaultMirrorURLForApp()` is a normal, computable filesystem path reachable from the
UNSANDBOXED app side (the same directory the app already writes INTO — no new entitlement
needed, same reasoning that already lets the app write there in the first place), the most
promising direction is: the app detects, on next launch or activation, that the mirror
changed independently of its own last write (e.g. an mtime or content-hash comparison
against what it last wrote), and if so, merges that change back into the real vault BEFORE
re-mirroring forward again. Open questions this spike does NOT resolve:

- Atomicity: what if the app's own edit and an extension-originated registration race?
- Conflict handling: what if the real vault changed (e.g. edited in KeePassXC on another
  device, synced via Google Drive) in the same window the extension wrote to its mirror?
- Whether the app needs to actively poll the mirror, or only check on specific triggers
  (app launch, becoming active, a periodic timer).

## What ships instead this cycle

Nothing code-wise. The registration ROADMAP item is now explicitly marked blocked on a new
prerequisite item (extension→app write-back path) that must be designed and solved first.
`PasskeyCrypto`/`VaultService` primitives from prior cycles are all still correct and
reusable once the write-path question is resolved — this finding doesn't invalidate any of
them, it just means the registration override itself can't safely be written yet.

## PR

See the PR this file was committed alongside.
