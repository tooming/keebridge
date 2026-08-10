# KeeBridge

A native macOS [Credential Provider Extension](https://developer.apple.com/documentation/authenticationservices/ascredentialproviderviewcontroller) for KeePass-compatible (`.kdbx`) vaults — system-wide password, TOTP, and (soon) card/passkey autofill in Safari and other apps, backed by your own vault file instead of a cloud password manager.

Built as a personal replacement for a commercial password manager, with the explicit goal of avoiding vendor lock-in: the vault is a plain `.kdbx` file (the same format KeePass/KeePassXC/Strongbox use), synced however you like (this project uses Google Drive), and editable in [KeePassXC](https://keepassxc.org/) — KeeBridge only ever reads it for autofill, it never becomes the only thing that can open your data.

## What works today

- **Passwords** — system-wide AutoFill via Safari's native "Log in as…" picker, backed by any `.kdbx` v3.1/4.0/4.1 vault
- **TOTP / one-time codes** — RFC 6238, parses the `otpauth://` URI KeePassXC/Proton Pass store in an entry's `otp` field
- **Independent Touch ID unlock** in both the container app and the extension, each with their own local cache so you're not re-authenticating for every field on a page

## What's planned

See the [issue tracker](../../issues) for the actual backlog. Roughly, in priority order:

1. **Vault write support** — currently strictly read-only; needed for everything below
2. **A real secrets-management UI** in the app itself (browse/add/edit/delete entries) — right now KeeBridge only unlocks and registers identities, KeePassXC is the only editor
3. **Credit card autofill** — Apple has no system extension point for cards (confirmed: no `AuthenticationServices` credential type, no Info.plist capability key exists for it), so this means a Safari Web Extension with a content script, the same mechanism 1Password/Bitwarden/Dashlane/Proton Pass all actually use for cards
4. **Passkeys** — real WebAuthn (P-256 signing, CBOR), plus vault write support; flagged as highest-risk: there's a documented, unresolved Apple-side bug around third-party macOS passkey providers as of this writing (AAGUID gets silently zeroed and the provider gets misreported as iCloud Keychain to the relying party)

## Architecture

Three targets in one Xcode project (`project.yml`, built via [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

- **`KeeBridge`** — the container app. Deliberately **not sandboxed**: it reads the real vault file directly (which may live on a cloud-synced, File Provider–backed path like Google Drive's `CloudStorage` mount — security-scoped bookmarking against that kind of path proved unreliable in practice, see commit history / issues for specifics), unlocks it, and mirrors a copy into the extension's own sandbox container.
- **`KeeBridgeProvider`** — the actual Credential Provider Extension. **Must** be sandboxed (macOS requires this for every app extension regardless of the host app's sandbox status). Reads the mirrored copy the app wrote into its own container — no shared entitlement needed for that, since sandboxing restricts what the *sandboxed* process can reach, not what another same-user process writes into its folder.
- **`KeeBridgeCore`** — shared Swift package: KDBX parsing (via [KDBXKit](https://github.com/shadone/KDBXKit)), TOTP generation, Keychain storage. Linked by both the app, the extension, and `VaultProbe`.

`VaultProbe` is a small standalone SPM diagnostic tool for validating a vault file opens correctly without going through the full app/extension flow — see its own usage notes.

### Notable non-obvious design decisions

- **No shared Keychain access group, no App Group** between the app and extension, despite both needing to read the same unlocked vault. This Apple Developer team's automatic code-signing provisioning does not reliably grant either capability (confirmed by inspecting the actual embedded `.mobileprovision` entitlements — both were silently absent from the granted profile despite being requested). Each process keeps its own independent, unshared Keychain item and unlocks separately instead of fighting that.
- **`kSecUseDataProtectionKeychain`** is required for `SecAccessControl`-protected (biometry-gated) Keychain items on macOS — omitting it throws `errSecMissingEntitlement` (-34018). Not needed on iOS, where the Data Protection Keychain is the only one, so it's an easy miss coming from iOS-first Keychain code.
- **Touch ID prompts must happen on the main thread** in this extension's window session — moving that call to a background queue causes the sheet to appear but never resolve. Argon2id key-derivation work is the opposite: deliberately slow, no UI dependency, and *must* move off main or it blocks Safari's synchronous wait for a response.
- **`preferredContentSize`** has to be set explicitly in `viewDidLoad` — extension hosts (Safari's credential picker) size the popover from it, and without it the popover can end up zero-sized: the embedded SwiftUI content is technically in the view hierarchy and "loaded," just never visible.
- The system creates a **fresh `CredentialProviderViewController` instance per field** (username, password, and OTP on the same page each got their own instance in testing), even though the host process is reused across them. Any in-memory cache (like the unlocked pre-hash) needs to be a `static`, not an instance property, or it resets on every field and Touch ID fires repeatedly for what's conceptually one login.

## Setup

Requires Xcode 26+, a paid Apple Developer Program membership (the `autofill-credential-provider` entitlement requires one even for purely local, non-distributed use — confirmed by Apple DTS on the developer forums), and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild build -project KeeBridge.xcodeproj -scheme KeeBridge -configuration Debug \
  -destination 'platform=macOS' -allowProvisioningUpdates -allowProvisioningDeviceRegistration
```

Update `DEVELOPMENT_TEAM` and the bundle ID prefix in `project.yml` for your own team before building.

## Debugging

Both the app and extension log through `os.Logger`, subsystem `com.martintooming.KeeBridge` (categories `app` / `extension`). Watch both processes live, interleaved by timestamp:

```bash
/usr/bin/log stream --predicate 'subsystem == "com.martintooming.KeeBridge"' --level debug --style compact
```

(Use the full path — `log` is shadowed by a builtin in some shells.)

## License

MIT — see [LICENSE](LICENSE).
