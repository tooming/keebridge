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

/// Reads the master password from `/dev/tty` with echo disabled — the
/// password never appears on screen, in shell history, or in `ps` output
/// (unlike a `--password` CLI flag).
func promptPassword(for url: URL) throws -> String {
    guard let passwordCString = getpass("Master password for \(url.lastPathComponent): ") else {
        throw ValidationError("Could not read password (no controlling TTY?).")
    }
    return String(cString: passwordCString)
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

    @OptionGroup var vault: VaultPathArguments

    mutating func run() throws {
        let url = try vault.resolved()
        let password = try promptPassword(for: url)

        print("Opening \(url.path) ...")
        let entries = try VaultService().listEntries(at: url, masterPassword: password)
        print("\nOK — decrypted successfully. \(entries.count) entries found.\n")

        var allCustomKeys = Set<String>()
        for entry in entries {
            let usernameDisplay = entry.username.isEmpty ? "(no username)" : entry.username
            let urlDisplay = entry.url.isEmpty ? "(no url)" : entry.url
            print("- \(entry.title)  |  \(usernameDisplay)  |  \(urlDisplay)  |  uuid=\(entry.uuid)")
            allCustomKeys.formUnion(entry.customFieldKeys)
        }

        print("\n=== distinct custom field keys across all entries (names only, no values) ===")
        if allCustomKeys.isEmpty {
            print("(none)")
        } else {
            for key in allCustomKeys.sorted() {
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

    @OptionGroup var vault: VaultPathArguments
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
        print(value)
    }
}

struct TOTPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "totp",
        abstract: "Print the current TOTP code for one entry, by UUID (from `list`'s output)."
    )

    @OptionGroup var vault: VaultPathArguments
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
        print(code)
    }
}
