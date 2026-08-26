// VaultProbe — headless KDBX vault inspector, built on KeeBridgeCore.
//
// Originally a milestone-1 validation tool (prove KDBXKit can open the real
// vault.kdbx before any UI/extension code existed); now a small general CLI
// with three subcommands: `list`, `reveal`, `totp`. Same secret-hygiene
// discipline throughout: only ever prints a field *value* when the command
// explicitly asked for that one field (`reveal`/`totp`) — `list` prints only
// titles/usernames/URLs/UUIDs and custom-field *names*, never values.
//
// Usage:
//   swift run VaultProbe list <path/to/vault.kdbx>
//   swift run VaultProbe reveal <path/to/vault.kdbx> <entry-uuid> <field-key>
//   swift run VaultProbe totp <path/to/vault.kdbx> <entry-uuid>
//   swift run VaultProbe <path/to/vault.kdbx>            # `list` is the default subcommand
//
// Every subcommand also takes `--json`, for piping into `jq`/scripts instead
// of reading the human-readable text output.
//
// The vault path can be omitted from any subcommand if $VAULT_PATH is set
// instead. Every subcommand reads the master password via `getpass()` (no
// echo, no shell history, no argv leak) — never pass it as a CLI argument.

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
        subcommands: [ListCommand.self, RevealCommand.self, TOTPCommand.self],
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
                    JSONEntry(uuid: $0.uuid, title: $0.title, username: $0.username, url: $0.url, customFieldKeys: $0.customFieldKeys)
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
            print("- \(entry.title)  |  \(usernameDisplay)  |  \(urlDisplay)  |  uuid=\(entry.uuid)")
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
