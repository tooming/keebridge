// VaultProbe — headless KDBX vault inspector, built on KeeBridgeCore.
//
// Originally a milestone-1 validation tool (prove KDBXKit can open the real
// vault.kdbx before any UI/extension code existed); now a small general CLI
// with seven subcommands: `list`, `reveal`, `totp`, `passkey` (read-only),
// and `create`, `update`, `delete` (write). Same secret-hygiene discipline
// throughout: only ever prints a field *value* when the command explicitly
// asked for that one field (`reveal`/`totp`/`passkey`) — `list` prints only
// titles/usernames/URLs/UUIDs, a passkey indicator, and custom-field
// *names*, never values; the write subcommands never print a field value
// back either (just the UUID + a confirmation). `passkey` itself never
// prints the private key — same read-only, metadata-only scope as the app's
// own passkey UI (`EntryDetailView`'s "Passkey" section).
//
// Usage:
//   swift run VaultProbe list <path/to/vault.kdbx>
//   swift run VaultProbe reveal <path/to/vault.kdbx> <entry-uuid> <field-key>
//   swift run VaultProbe totp <path/to/vault.kdbx> <entry-uuid>
//   swift run VaultProbe passkey <path/to/vault.kdbx> <entry-uuid>
//   swift run VaultProbe create <path/to/vault.kdbx> [--title ...] [--username ...] ...
//   swift run VaultProbe update <path/to/vault.kdbx> <entry-uuid> [--title ...] ...
//   swift run VaultProbe delete <path/to/vault.kdbx> <entry-uuid> --yes
//   swift run VaultProbe <path/to/vault.kdbx>            # `list` is the default subcommand
//
// Every subcommand also takes `--json`, for piping into `jq`/scripts instead
// of reading the human-readable text output.
//
// `update` reveals the entry's current fields first and only overwrites the
// ones an option was actually given for (reveal-then-merge) — `updateEntry`
// itself does a full field replace, not a patch, so blindly forwarding
// unset options straight through would silently blank out every field the
// caller didn't mention. `delete` refuses to run without `--yes` — there's
// no recycle bin (matches `VaultService.deleteEntry`'s own doc comment).
//
// The vault path can be omitted from any subcommand if $VAULT_PATH is set
// instead. Every subcommand reads the master password via `getpass()` (no
// echo, no shell history, no argv leak) — never pass it as a CLI argument.
// `create`/`update` take title/username/url/notes as ordinary flags (matching
// how `list` already treats those as non-secret, and how the KDBX format
// itself only inner-stream-cipher-protects the Password field) — but the
// entry's *password* is never a CLI argument. Pass `--set-password` instead
// and a second `getpass()` prompt asks for it, same no-echo/no-history/no-argv
// discipline as the vault's own master password.

import ArgumentParser
import Foundation
import KeeBridgeCore
#if canImport(Darwin)
import Darwin
#endif

/// Shared vault-path argument + resolution, reused by every subcommand via
/// `@OptionGroup`. Falls back to `$VAULT_PATH` when the argument is omitted,
/// matching the original single-file tool's behavior.
struct VaultPathArguments: ParsableArguments {
    @Argument(help: "Path to the .kdbx vault. Falls back to $VAULT_PATH if omitted.")
    var vaultPath: String?

    func resolved() throws -> URL {
        guard let path = vaultPath ?? ProcessInfo.processInfo.environment["VAULT_PATH"] else {
            throw ValidationError("Provide a vault path, or set $VAULT_PATH.")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("Vault not found at \(url.path)")
        }
        return url
    }
}

/// Shared `--json` flag, reused by every subcommand via `@OptionGroup`.
struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human-readable text.")
    var json: Bool = false
}

/// Reads the master password from `/dev/tty` with echo disabled — the
/// password never appears on screen, in shell history, or in `ps` output
/// (unlike a `--password` CLI flag).
func promptPassword(for url: URL) throws -> String {
    guard let passwordCString = getpass("Master password for \(url.lastPathComponent): ") else {
        throw ValidationError("Could not read password (no controlling TTY?).")
    }
    return String(cString: passwordCString)
}

/// Prompts for a new *entry's* password via `getpass()` — same no-echo/
/// no-history/no-argv discipline as `promptPassword(for:)`, but a distinct
/// prompt string so it's never confused with the vault's own master
/// password. Used by `create --set-password`/`update --set-password`.
func promptEntryPassword() throws -> String {
    guard let passwordCString = getpass("New entry password (leave blank for none): ") else {
        throw ValidationError("Could not read password (no controlling TTY?).")
    }
    return String(cString: passwordCString)
}

/// Encodes `value` as pretty-printed, key-sorted JSON and prints it to
/// stdout. Sorted keys keep `--json` output byte-stable across runs (no
/// dictionary-ordering nondeterminism) for anyone diffing or snapshotting it.
func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    print(String(decoding: data, as: UTF8.self))
}

@main
struct VaultProbe: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Headless KDBX vault inspector, built on KeeBridgeCore — no GUI, no Touch ID.",
        subcommands: [
            ListCommand.self, RevealCommand.self, TOTPCommand.self, PasskeyCommand.self,
            CreateCommand.self, UpdateCommand.self, DeleteCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List entry titles/usernames/URLs/UUIDs and distinct custom-field names (never values)."
    )

    struct JSONEntry: Encodable {
        let uuid: String
        let title: String
        let username: String
        let url: String
        let customFieldKeys: [String]
        let isPasskey: Bool
    }

    struct JSONOutput: Encodable {
        let entries: [JSONEntry]
        let customFieldKeys: [String]
    }

    @OptionGroup var vault: VaultPathArguments
    @OptionGroup var output: OutputOptions

    mutating func run() throws {
        let url = try vault.resolved()
        let password = try promptPassword(for: url)
        let entries = try VaultService().listEntries(at: url, masterPassword: password)
        var allCustomKeys = Set<String>()
        for entry in entries { allCustomKeys.formUnion(entry.customFieldKeys) }
        let sortedCustomKeys = allCustomKeys.sorted()

        if output.json {
            try printJSON(JSONOutput(
                entries: entries.map {
                    JSONEntry(
                        uuid: $0.uuid, title: $0.title, username: $0.username, url: $0.url,
                        customFieldKeys: $0.customFieldKeys, isPasskey: $0.isPasskey
                    )
                },
                customFieldKeys: sortedCustomKeys
            ))
            return
        }

        print("Opening \(url.path) ...")
        print("\nOK — decrypted successfully. \(entries.count) entries found.\n")
        for entry in entries {
            let usernameDisplay = entry.username.isEmpty ? "(no username)" : entry.username
            let urlDisplay = entry.url.isEmpty ? "(no url)" : entry.url
            let passkeyMarker = entry.isPasskey ? "  [passkey]" : ""
            print("- \(entry.title)  |  \(usernameDisplay)  |  \(urlDisplay)  |  uuid=\(entry.uuid)\(passkeyMarker)")
        }
        print("\n=== distinct custom field keys across all entries (names only, no values) ===")
        if sortedCustomKeys.isEmpty {
            print("(none)")
        } else {
            for key in sortedCustomKeys {
                print("- \(key)")
            }
        }
    }
}

struct RevealCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reveal",
        abstract: "Reveal one field's value for one entry, by UUID and field key (from `list`'s output)."
    )

    struct JSONOutput: Encodable {
        let uuid: String
        let fieldKey: String
        let value: String
    }

    @OptionGroup var vault: VaultPathArguments
    @OptionGroup var output: OutputOptions
    @Argument(help: "Entry UUID, as printed by `list`.")
    var entryUUID: String
    @Argument(help: "Field key to reveal — e.g. Password, UserName, URL, Notes, or a custom field name.")
    var fieldKey: String

    mutating func run() throws {
        let url = try vault.resolved()
        let password = try promptPassword(for: url)

        guard let value = try VaultService().revealField(
            at: url, masterPassword: password, entryUUID: entryUUID, fieldKey: fieldKey
        ) else {
            throw ValidationError("No entry with UUID \(entryUUID), or it has no \"\(fieldKey)\" field.")
        }

        if output.json {
            try printJSON(JSONOutput(uuid: entryUUID, fieldKey: fieldKey, value: value))
        } else {
            print(value)
        }
    }
}

struct TOTPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "totp",
        abstract: "Print the current TOTP code for one entry, by UUID (from `list`'s output)."
    )

    struct JSONOutput: Encodable {
        let uuid: String
        let code: String
    }

    @OptionGroup var vault: VaultPathArguments
    @OptionGroup var output: OutputOptions
    @Argument(help: "Entry UUID, as printed by `list`.")
    var entryUUID: String

    mutating func run() throws {
        let url = try vault.resolved()
        let password = try promptPassword(for: url)

        guard let code = try VaultService().currentTOTPCode(
            at: url, masterPassword: password, entryUUID: entryUUID
        ) else {
            throw ValidationError("No entry with UUID \(entryUUID), or it has no otp field.")
        }

        if output.json {
            try printJSON(JSONOutput(uuid: entryUUID, code: code))
        } else {
            print(code)
        }
    }
}

struct PasskeyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "passkey",
        abstract: "Print one entry's passkey metadata (relying party, username, credential ID) — never the private key."
    )

    struct JSONOutput: Encodable {
        let uuid: String
        let relyingParty: String?
        let username: String?
        let credentialID: String?
    }

    @OptionGroup var vault: VaultPathArguments
    @OptionGroup var output: OutputOptions
    @Argument(help: "Entry UUID, as printed by `list`.")
    var entryUUID: String

    mutating func run() throws {
        let url = try vault.resolved()
        let password = try promptPassword(for: url)

        // Same read-only, metadata-only scope as EntryDetailView's own
        // "Passkey" section: relying party, username, credential ID — the
        // private key deliberately has no CLI exposure (VaultService's own
        // revealPasskeyPrivateKeyPEM exists only for actual WebAuthn
        // signing inside the credential provider extension, not general
        // inspection).
        guard let metadata = try VaultService().passkeyMetadata(
            at: url, masterPassword: password, entryUUID: entryUUID
        ) else {
            throw ValidationError("No entry with UUID \(entryUUID), or it has no passkey.")
        }

        if output.json {
            try printJSON(JSONOutput(
                uuid: entryUUID,
                relyingParty: metadata.relyingParty,
                username: metadata.username,
                credentialID: metadata.credentialID?.base64EncodedString()
            ))
        } else {
            print("Relying party: \(metadata.relyingParty ?? "(none)")")
            print("Username:      \(metadata.username ?? "(none)")")
            print("Credential ID: \(metadata.credentialID?.base64EncodedString() ?? "(none)")")
        }
    }
}

struct CreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new entry. The entry's password is prompted separately via --set-password, never a CLI argument."
    )

    struct JSONOutput: Encodable {
        let uuid: String
    }

    @OptionGroup var vault: VaultPathArguments
    @OptionGroup var output: OutputOptions
    @Option(name: .long, help: "Entry title.") var title: String = ""
    @Option(name: .long, help: "Entry username.") var username: String = ""
    @Option(name: .long, help: "Entry URL.") var url: String = ""
    @Option(name: .long, help: "Entry notes.") var notes: String = ""
    @Flag(name: .long, help: "Prompt (via getpass) for the entry's password. Omit to create it with no password.")
    var setPassword: Bool = false

    mutating func run() throws {
        let vaultURL = try vault.resolved()
        let vaultPassword = try promptPassword(for: vaultURL)
        let entryPassword = setPassword ? try promptEntryPassword() : ""

        let draft = VaultService.EntryDraft(title: title, username: username, password: entryPassword, url: url, notes: notes)
        let newUUID = try VaultService().createEntry(draft, at: vaultURL, masterPassword: vaultPassword)

        if output.json {
            try printJSON(JSONOutput(uuid: newUUID))
        } else {
            print("Created entry \(newUUID)")
        }
    }
}

struct UpdateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: """
        Update an existing entry, by UUID. Reveals its current fields first and only \
        overwrites the ones you pass a flag for — an omitted flag keeps its existing \
        value (updateEntry itself replaces all fields, so this reveal-then-merge step \
        is what stops an omitted flag from silently blanking that field). The password \
        is only touched if you pass --set-password (prompted separately, never a CLI \
        argument).
        """
    )

    struct JSONOutput: Encodable {
        let uuid: String
    }

    @OptionGroup var vault: VaultPathArguments
    @OptionGroup var output: OutputOptions
    @Argument(help: "Entry UUID, as printed by `list`.")
    var entryUUID: String
    @Option(name: .long, help: "New title. Omit to keep the existing title.") var title: String?
    @Option(name: .long, help: "New username. Omit to keep the existing username.") var username: String?
    @Option(name: .long, help: "New URL. Omit to keep the existing URL.") var url: String?
    @Option(name: .long, help: "New notes. Omit to keep the existing notes.") var notes: String?
    @Flag(name: .long, help: "Prompt (via getpass) for a new password. Omit to keep the existing password.")
    var setPassword: Bool = false

    mutating func run() throws {
        let vaultURL = try vault.resolved()
        let vaultPassword = try promptPassword(for: vaultURL)
        let service = VaultService()

        let current = try service.revealEntry(uuid: entryUUID, at: vaultURL, masterPassword: vaultPassword)
        let newPassword = setPassword ? try promptEntryPassword() : current.password

        let merged = VaultService.EntryDraft(
            title: title ?? current.title,
            username: username ?? current.username,
            password: newPassword,
            url: url ?? current.url,
            notes: notes ?? current.notes
        )
        try service.updateEntry(uuid: entryUUID, applying: merged, at: vaultURL, masterPassword: vaultPassword)

        if output.json {
            try printJSON(JSONOutput(uuid: entryUUID))
        } else {
            print("Updated entry \(entryUUID)")
        }
    }
}

struct DeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an entry, by UUID. Irreversible (no recycle bin) — requires --yes."
    )

    struct JSONOutput: Encodable {
        let uuid: String
        let deleted: Bool
    }

    @OptionGroup var vault: VaultPathArguments
    @OptionGroup var output: OutputOptions
    @Argument(help: "Entry UUID, as printed by `list`.")
    var entryUUID: String
    @Flag(name: .long, help: "Confirm the deletion. Required — delete refuses to run without it.")
    var yes: Bool = false

    mutating func run() throws {
        guard yes else {
            throw ValidationError("Refusing to delete without --yes (irreversible — there's no recycle bin).")
        }
        let vaultURL = try vault.resolved()
        let vaultPassword = try promptPassword(for: vaultURL)
        try VaultService().deleteEntry(uuid: entryUUID, at: vaultURL, masterPassword: vaultPassword)

        if output.json {
            try printJSON(JSONOutput(uuid: entryUUID, deleted: true))
        } else {
            print("Deleted entry \(entryUUID)")
        }
    }
}
