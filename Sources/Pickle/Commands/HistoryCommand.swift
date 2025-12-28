import ArgumentParser
import Foundation
import CiderCore

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show version history for a note"
    )

    @Argument(help: "Note title or UUID to show history for")
    var noteIdentifier: String

    @Option(name: .shortAndLong, help: "Maximum number of versions to show")
    var limit: Int = 20

    @OptionGroup var options: PickleGlobalOptions

    func run() throws {
        let versionDB = try VersionDatabase()

        // Find the note
        let note: NoteRecord

        // Try UUID first, then title search
        if let byUUID = try versionDB.getNote(uuid: noteIdentifier) {
            note = byUUID
        } else {
            // Search by title
            let allNotes = try versionDB.getAllNotes()
            let matches = allNotes.filter {
                $0.title?.localizedCaseInsensitiveContains(noteIdentifier) == true
            }

            if matches.isEmpty {
                throw PickleError.noteNotFound(noteIdentifier)
            } else if matches.count > 1 {
                print("Multiple notes match '\(noteIdentifier)':")
                for match in matches {
                    print("  • \(match.title ?? "Untitled") (UUID: \(match.uuid))")
                }
                print("")
                pickleInfo("Please specify the exact UUID")
                return
            }

            note = matches[0]
        }

        guard let noteID = note.id else {
            throw PickleError.noteNotFound(noteIdentifier)
        }

        print("Version History: \(note.title ?? "Untitled")")
        print("UUID: \(note.uuid)")
        print("═══════════════════════════════════════════════════\n")

        let versions = try versionDB.getVersions(noteID: noteID)

        if versions.isEmpty {
            pickleWarning("No versions recorded yet")
            return
        }

        print("Found \(versions.count) version(s)\n")

        for version in versions.prefix(limit) {
            let capturedAt = version.capturedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
            let dateStr = formatDate(capturedAt)

            print("┌─ Version \(version.versionNumber) ─────────────────────────")
            print("│ ID:        \(version.id ?? 0)")
            print("│ Captured:  \(dateStr)")
            print("│ Size:      \(version.characterCount) chars, \(version.wordCount) words")
            if let summary = version.changeSummary {
                print("│ Changes:   \(summary)")
            }
            print("│ Hash:      \(String(version.contentHash.prefix(16)))...")

            if options.verbose, let preview = version.plaintextPreview {
                print("│")
                print("│ Preview:")
                let lines = preview.components(separatedBy: "\n").prefix(3)
                for line in lines {
                    print("│   \(String(line.prefix(60)))")
                }
            }

            print("└──────────────────────────────────────────────────")
            print("")
        }

        if versions.count > limit {
            print("... and \(versions.count - limit) more versions")
            pickleInfo("Use --limit to show more")
        }

        print("")
        print("Commands:")
        print("  pickle diff \(versions.first?.id ?? 0) \(versions.dropFirst().first?.id ?? 0)  - Compare versions")
        print("  pickle restore \(versions.first?.id ?? 0)                 - Restore to version")
        print("  pickle export '\(note.title ?? note.uuid)' <dir>  - Export all versions")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
