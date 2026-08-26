# Passkey support: storage convention + platform-risk design spike

Answers two of the open design questions issue #4 itself listed before any passkey
code gets written: which storage convention to use for new passkeys (for KeePassXC
interop), and a closer look at the AAGUID-zeroing platform risk the issue flagged.
Deliberately does *not* attempt the actual WebAuthn/CBOR implementation — issue #4
calls this item "highest-risk, highest-effort... deliberately last," and this run's
remaining buildable work (see "why this item" below) is the research slice, not the
full feature.

## Why this item, this cycle

Every other "Now / next" item is currently blocked: the credit card autofill
implementation (the next item after last cycle's design spike) needs a brand-new
Xcode target (a Safari Web Extension + its `SafariWebExtensionHandler`), and this
environment has no `xcodegen` binary to regenerate `KeeBridge.xcodeproj` from
`project.yml` after adding one — confirmed by checking (`which xcodegen` → nothing).
The checked-in `project.pbxproj` still uses the classic explicit
`PBXFileReference`/`PBXBuildFile` format (no `PBXFileSystemSynchronizedRootGroup` —
grepped for it, zero matches), so hand-adding a whole new target's build phases,
product reference, and embed-phase entries by hand, with no way to validate the
result short of a real Xcode install, is a correctness risk this run isn't taking.
QR code scanning (#7) is explicitly gated on passkey support existing first.

Passkey support (#4), by contrast, has a research slice that's genuinely tractable
here: unlike card autofill, it needs no new Xcode target at all — all of it lands in
`KeeBridgeProvider` (already exists, already has `CredentialProviderViewController.swift`)
and `KeeBridgeCore`, both places this run has safely shipped changes to all day.

## What was confirmed

**KeePassXC's own passkey storage convention** (the interop question issue #4's scope
notes explicitly asked to check before inventing a KeeBridge-only scheme): as of
2.7.7+, KeePassXC stores a new passkey as a PEM-encoded private key **file attachment**
named `webauthn.pem` on the entry, with the WebAuthn-generated username stored in the
entry's **password** field. This is a real, checkable, already-shipping convention —
not speculation.

This matters for KeeBridge's own "never break the ability to open the same file in
KeePassXC" goal (`README.md`): **new** passkeys KeeBridge creates should use this same
attachment convention, not a third proprietary format. This is a different question
from the 9 **existing** Proton-Pass-carried passkeys already in the vault, which use
Proton's own proprietary double-nested MessagePack format (per issue #4's own research)
— those two data shapes don't need to converge; new passkeys can simply follow
KeePassXC's convention going forward while the Proton-carried ones stay a separate,
optional reconstruction decision.

**The AAGUID-zeroing platform risk** (issue #4 flagged this as Developer Forums thread
814547): confirmed real and current — a developer setting a custom AAGUID in the
attestation object during macOS passkey registration gets back an all-zero AAGUID and
"iCloud Keychain" reported as the provider to the relying party. One nuance worth
adding to issue #4's framing: this may be an intentional Apple privacy choice (iCloud
Keychain's *own* consumer passkeys also get a zeroed AAGUID, prioritizing user privacy
over hardware/provider attestation) rather than a straightforward bug specific to
third-party providers — it's ambiguous whether Apple ever intends third-party
credential providers to get a distinguishable AAGUID at all. Either way, the practical
risk issue #4 named stands: relying parties can't tell a KeeBridge-created passkey
from an iCloud Keychain one, which matters for anyone trying to distinguish/audit
their passkey providers.

## Recommendation

Storage: **follow KeePassXC's own convention** (PEM attachment + password-field
username) for any *new* passkey KeeBridge creates, rather than inventing a KeeBridge-
specific scheme — maximizes interop, matches this project's stated non-negotiable
(KeePassXC must always be able to open the file). Treat the 9 Proton-carried passkeys
as informational-only for now (matches issue #4's own suggested fallback) — reconstructing
them requires replicating Proton's proprietary MessagePack struct layout with no
independent verification of the byte format, a separate and riskier piece of work than
shipping new-passkey creation.

Platform risk: proceed anyway, but document the AAGUID limitation plainly in the
eventual PR/UI rather than treating it as a blocker — it's a real limitation of any
third-party macOS passkey provider, not something specific to getting KeeBridge's
implementation right.

## Still open (deliberately out of scope for this spike)

- The actual `ASPasskeyCredentialRequest`/`ASPasskeyRegistrationCredential`/
  `ASPasskeyAssertionCredential` implementation in `CredentialProviderViewController.swift`
  — real CBOR-encoded `attestationObject` construction and P-256/ES256 assertion
  signing. Substantial, headless-hard-to-verify (needs a real Safari passkey flow to
  confirm end-to-end), and correctly scoped as its own follow-up item(s), not attempted
  here.
- Declaring `ProvidesPasskeys: true` in `KeeBridgeProvider/Info.plist` (a plain content
  edit to an existing checked-in file, no new Xcode target or `xcodegen` needed) — a
  reasonable very-first slice of the implementation, left for a future cycle so this
  one stays purely research, matching the CLI and card-autofill spikes' precedent.
- Reconstructing the 9 Proton-carried passkeys, if ever decided worth doing.

## PR

#19
