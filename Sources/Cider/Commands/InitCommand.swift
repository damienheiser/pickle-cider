import ArgumentParser
import Foundation
import CiderCore

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize Cider sync state database"
    )

    @Flag(name: .long, help: "Reset existing state database")
    var reset: Bool = false

    func run() throws {
        let stateDBPath = StateDatabase.defaultPath

        print("Cider - Initialize")
        print("")

        if reset {
            // Remove existing database
            if FileManager.default.fileExists(atPath: stateDBPath.path) {
                try FileManager.default.removeItem(at: stateDBPath)
                printInfo("Removed existing state database")
            }
        }

        // Check if already initialized
        if FileManager.default.fileExists(atPath: stateDBPath.path) && !reset {
            printWarning("State database already exists at: \(stateDBPath.path)")
            printInfo("Use --reset to reinitialize")
            return
        }

        // Create new database
        do {
            let _ = try StateDatabase()
            printSuccess("Initialized state database at: \(stateDBPath.path)")

            print("")
            print("Next steps:")
            print("  1. Run 'cider pull <output-dir>' to export your Apple Notes")
            print("  2. Run 'cider push <file-or-dir>' to upload files to Apple Notes")
            print("  3. Run 'cider sync <dir>' for bidirectional sync")
            print("")
            print("Use 'cider --help' for more options")

        } catch {
            printError("Failed to initialize: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
