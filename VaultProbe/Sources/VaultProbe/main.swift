// VaultProbe — milestone-1 validation tool.
//
// Proves KDBXKit can open the real vault.kdbx end-to-end before any UI or
// extension code is built around it. Prints ONLY entry titles, usernames,
// URLs, and custom-field *names* (never password/TOTP secret values) — the
// decrypted vault contents never touch disk, only transient in-memory
// Swift values for the life of this process.
//
// Usage:
//   swift run VaultProbe <path/to/vault.kdbx>
//   or set VAULT_PATH in the environment instead of passing an argument.

import Foundation
import KeeBridgeCore
#if canImport(Darwin)
import Darwin
#endif

guard let path = CommandLine.arguments.count >= 2
    ? CommandLine.arguments[1]
    : ProcessInfo.processInfo.environment["VAULT_PATH"]
else {
    print("Usage: VaultProbe <path/to/vault.kdbx>")
    print("   or: VAULT_PATH=/path/to/vault.kdbx swift run VaultProbe")
    exit(1)
}
let url = URL(fileURLWithPath: path)

guard FileManager.default.fileExists(atPath: url.path) else {
    print("Vault not found at \(url.path)")
    print("Usage: VaultProbe <path/to/vault.kdbx>")
    exit(1)
}

// getpass() reads from /dev/tty with echo disabled — the password never
// appears on screen or in shell history.
guard let passwordCString = getpass("Master password for \(url.lastPathComponent): ") else {
    print("Could not read password (no controlling TTY?).")
    exit(1)
}
let password = String(cString: passwordCString)

print("Opening \(url.path) ...")

let service = VaultService()
do {
    let entries = try service.listEntries(at: url, masterPassword: password)

    print("\nOK — decrypted successfully. \(entries.count) entries found.\n")

    var allCustomKeys = Set<String>()
    for entry in entries {
        let usernameDisplay = entry.username.isEmpty ? "(no username)" : entry.username
        let urlDisplay = entry.url.isEmpty ? "(no url)" : entry.url
        print("- \(entry.title)  |  \(usernameDisplay)  |  \(urlDisplay)")
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
} catch {
    print("\nFAILED to open vault: \(error)")
    print("(If this was a deliberate wrong-password test: good, this is the expected failure path.)")
    exit(1)
}
