# KeeBridge

A native macOS credential provider plus Safari Web Extension for KeePass-compatible (`.kdbx`) vaults — password, TOTP, passkey, and payment-card autofill backed by your own vault file instead of a cloud password manager.

Built as a personal replacement for a commercial password manager, with the explicit goal of avoiding vendor lock-in: the vault is a plain `.kdbx` file (the same format KeePass/KeePassXC/Strongbox use), synced however you like (this project uses Google Drive), and editable in [KeePassXC](https://keepassxc.org/) — KeeBridge only ever reads it for autofill, it never becomes the only thing that can open your data.

## What works today

- **Passwords** — system-wide AutoFill via Safari's native "Log in as…" picker, backed by any `.kdbx` v3.1/4.0/4.1 vault
- **TOTP / one-time codes** — RFC 6238, scans setup QR codes or parses the `otpauth://` URI KeePassXC/Proton Pass store in an entry's `otp` field
- **Vault write support** — create/edit/delete entries directly, from either the app's own UI or the headless `VaultProbe` CLI, not just via KeePassXC
- **A real secrets-management UI** in the app itself — browse/search entries, reveal fields, edit, delete
- **Passkeys (WebAuthn)** — sign in with an existing passkey, and register a brand-new one (both the interactive flow and, on macOS 15+, conditional/silent registration), backed by the vault's own KeePassXC-compatible passkey fields; visible read-only in both the app UI and `VaultProbe`. Still needs real-hardware verification (this project is built and validated headlessly, with no GUI or Touch ID hardware in CI) and carries a documented, unresolved Apple-side platform risk for third-party macOS passkey providers (AAGUID gets silently zeroed and the provider gets misreported as iCloud Keychain to the relying party) — see the issue tracker
- **Payment cards in Safari** — the bundled Web Extension detects standard card-number, cardholder, expiry, and CVV fields, shows its own picker only after you click the KeeBridge control, and fills the selected card. Card values are requested from native code only for field types present on that page and are never returned in the card-list response. The injected UI and Touch ID behavior still need real-Safari/hardware verification.
- **Independent Touch ID unlock** in the container app, credential provider, and card extension. Each process has its own biometric Keychain cache.

## What's planned

See [`ROADMAP.md`](ROADMAP.md) and the [issue tracker](../../issues) for the remaining backlog.

## Architecture

Three targets plus one shared Swift package in the Xcode project (`project.yml`, built via [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

- **`KeeBridge`** — the container app. Deliberately **not sandboxed**: it reads the real vault file directly (which may live on a cloud-synced, File Provider–backed path like Google Drive's `CloudStorage` mount — security-scoped bookmarking against that kind of path proved unreliable in practice, see commit history / issues for specifics), unlocks it, and mirrors separate copies into both extension containers.
- **`KeeBridgeProvider`** — the actual Credential Provider Extension. **Must** be sandboxed (macOS requires this for every app extension regardless of the host app's sandbox status). Reads the mirrored copy the app wrote into its own container — no shared entitlement needed for that, since sandboxing restricts what the *sandboxed* process can reach, not what another same-user process writes into its folder.
- **`KeeBridgeCardExtension`** — a sandboxed Safari Web Extension. Its content script recognizes card fields and owns the picker/fill UI; its native `SafariWebExtensionHandler` decrypts a dedicated read-only mirror. Unlike the provider mirror, this copy never participates in passkey merge-back.
- **`KeeBridgeCore`** — shared Swift package: KDBX parsing (via [KDBXKit](https://github.com/shadone/KDBXKit)), TOTP generation, payment-card aliases, and Keychain storage. Linked by the app, both extensions, and `VaultProbe`.

`VaultProbe` is a small standalone SPM diagnostic tool for validating a vault file opens correctly without going through the full app/extension flow — see its own usage notes.

### Notable non-obvious design decisions

- **No shared Keychain access group, no App Group** between the app and extensions, despite all needing to read the same vault. This Apple Developer team's automatic code-signing provisioning does not reliably grant either capability (confirmed by inspecting the actual embedded `.mobileprovision` entitlements — both were silently absent from the granted profile despite being requested). Each process keeps an independent Keychain item and unlocks separately. The first card fill therefore opens a private Safari extension page for the vault master password (never an element inside the untrusted payment page); later card sessions use the card extension's own Touch ID cache, independently of app/provider unlock state.
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

After installing/running the app, enable **KeeBridge Card AutoFill** in Safari → Settings → Extensions. Unlock or refresh KeeBridge once to create the card extension's mirror. Card entries are recognized by common custom-field aliases such as `Card Number`/`card_number`/Proton's `number`, `Expiration Date` or separate expiry month/year, `CVV`/`CVC`/`Verification Number`, and `Cardholder Name`/`Name on Card`. A number plus an unambiguous expiry or verification-code field is required; a generic `number` alone, `PIN`, login username, and password fields are deliberately not treated as a card.

## Debugging

The app and native extensions log through `os.Logger`, subsystem `com.martintooming.KeeBridge` (categories `app`, `extension`, and `card-extension`). Watch them live, interleaved by timestamp:

```bash
/usr/bin/log stream --predicate 'subsystem == "com.martintooming.KeeBridge"' --level debug --style compact
```

(Use the full path — `log` is shadowed by a builtin in some shells.)

## License

MIT — see [LICENSE](LICENSE).
