import ArgumentParser
import Foundation
import CiderCore

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show sync status and statistics"
    )

    @OptionGroup var options: GlobalOptions

    @Flag(name: .long, help: "Show detailed file-by-file status")
    var detailed: Bool = false

    func run() throws {
        print("Cider - Sync Status")
        print("═══════════════════\n")

        do {
            // Apple Notes stats
            let reader = try NotesReader()
            let noteCount = try reader.getNoteCount()
            let folderCount = try reader.getFolderCount()

            print("Apple Notes:")
            print("  Notes:   \(noteCount)")
            print("  Folders: \(folderCount)")
            print("")

            // Sync state stats
            let stateDB = try StateDatabase()
            let stats = try stateDB.getStatistics()

            print("Sync State:")
            print("  Tracked files: \(stats.totalFiles)")
            print("  Synced:        \(stats.syncedFiles)")
            print("  Pending:       \(stats.pendingFiles)")
            print("  Conflicts:     \(stats.conflicts)")
            print("")

            if detailed {
                let states = try stateDB.getAllSyncStates()

                if !states.isEmpty {
                    print("Tracked Files:")
                    print("─────────────────────────────────────────")

                    for state in states {
                        let statusIcon = statusIcon(for: state.syncStatus)
                        let lastSync = state.lastSync.map { formatDate(timestamp: $0) } ?? "never"
                        print("\(statusIcon) \(state.localPath)")
                        printVerbose("  Status: \(state.syncStatus), Last sync: \(lastSync)", verbose: options.verbose)
                    }
                    print("")
                }

                // Show pending items by status
                let pendingStates = states.filter { $0.syncStatus != "synced" }
                if !pendingStates.isEmpty {
                    print("Pending Changes:")
                    print("─────────────────────────────────────────")

                    let grouped = Dictionary(grouping: pendingStates) { $0.syncStatus }
                    for (status, items) in grouped.sorted(by: { $0.key < $1.key }) {
                        print("\n\(status.capitalized) (\(items.count)):")
                        for item in items.prefix(10) {
                            print("  • \(item.localPath)")
                        }
                        if items.count > 10 {
                            print("  ... and \(items.count - 10) more")
                        }
                    }
                    print("")
                }
            }

            // Recent activity
            let recentLogs = try stateDB.getRecentLogs(limit: 5)
            if !recentLogs.isEmpty && options.verbose {
                print("Recent Activity:")
                print("─────────────────────────────────────────")
                for log in recentLogs {
                    let timestamp = log.timestamp.map { formatDate(timestamp: $0) } ?? "?"
                    let path = log.localPath ?? log.noteUUID ?? "unknown"
                    let status = log.status == "success" ? "✓" : "✗"
                    print("\(status) [\(timestamp)] \(log.operation): \(path)")
                }
                print("")
            }

            // Quick tips
            if stats.pendingFiles > 0 {
                print("Tips:")
                print("  • Run 'cider sync <dir>' to synchronize pending changes")
                print("  • Run 'cider pull <dir>' to export all notes")
                print("  • Run 'cider push <file>' to upload a file")
            }

        } catch {
            printError("Failed to get status: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func statusIcon(for status: String) -> String {
        switch status {
        case "synced": return "✓"
        case "local_modified": return "M"
        case "remote_modified": return "↓"
        case "conflict": return "!"
        case "new_local": return "+"
        case "new_remote": return "↓"
        case "deleted_local": return "D"
        case "deleted_remote": return "×"
        default: return "?"
        }
    }

    private func formatDate(timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
