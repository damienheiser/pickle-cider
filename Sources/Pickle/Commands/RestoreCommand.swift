import ArgumentParser
import Foundation
import CiderCore

struct RestoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Restore a note to a previous version (creates a new note for comparison)"
    )

    @Argument(help: "Version ID to restore")
    var versionID: Int64

    @Flag(name: .long, help: "Preview changes without applying")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

    @Flag(name: .long, help: "Overwrite the original note instead of creating a new one")
    var overwrite: Bool = false

    @OptionGroup var options: PickleGlobalOptions

    func run() throws {
        let versionDB = try VersionDatabase()

        // Load version
        guard let version = try versionDB.getVersion(id: versionID) else {
            throw PickleError.versionNotFound(versionID)
        }

        // Get note info
        guard let note = try versionDB.getNote(id: version.noteID) else {
            throw PickleError.noteNotFound("ID: \(version.noteID)")
        }

        // Load version content
        let content = try versionDB.loadVersionContent(storagePath: version.storagePath)

        print("Restore Version")
        print("═══════════════\n")
        print("Note:    \(content.title)")
        print("Version: \(version.versionNumber) (ID: \(versionID))")
        print("Date:    \(formatDate(content.capturedAt))")
        print("Size:    \(content.metadata.characterCount) characters")
        print("Mode:    \(overwrite ? "Overwrite original" : "Create new note")")
        print("")

        if options.verbose {
            print("Preview:")
            print("─────────────────────────────────────────────────────")
            let preview = String(content.content.plaintext.prefix(500))
            print(preview)
            if content.content.plaintext.count > 500 {
                print("\n... (truncated)")
            }
            print("─────────────────────────────────────────────────────")
            print("")
        }

        if dryRun {
            pickleInfo("Dry run - no changes will be made")
            return
        }

        // Confirmation
        if !force {
            if overwrite {
                print("This will OVERWRITE the current note content in Apple Notes.")
            } else {
                print("This will create a NEW note with the restored content.")
                print("The original note remains unchanged for comparison.")
            }
            print("Type 'yes' to confirm: ", terminator: "")

            guard let response = readLine()?.lowercased(), response == "yes" else {
                pickleInfo("Cancelled")
                return
            }
        }

        // Restore via AppleScript
        let writer = NotesWriter()

        // Find the note in Apple Notes for folder info
        let reader = try NotesReader()
        guard let appleNote = try reader.getNote(uuid: note.uuid) else {
            pickleError("Note not found in Apple Notes: \(note.uuid)")
            pickleInfo("The note may have been deleted. Use 'pickle export' to save versions as files.")
            return
        }

        let folder = appleNote.folderName ?? "Notes"

        do {
            if overwrite {
                // Convert plaintext to HTML and overwrite original
                let converter = MarkdownConverter()
                let html = converter.markdownToHTML(content.content.plaintext)
                try writer.updateNote(title: content.title, body: html, folder: folder)
                pickleSuccess("Restored note to version \(version.versionNumber)")
                print("")
                pickleInfo("The current version has been saved before restore")
            } else {
                // Create a NEW note with restored content
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
                let timestamp = dateFormatter.string(from: Date())
                let restoredTitle = "\(content.title) (Restored v\(version.versionNumber) - \(timestamp))"

                // Build HTML with header referencing original
                var htmlLines: [String] = []
                htmlLines.append("<div><b>🔄 Restored from Version \(version.versionNumber)</b></div>")
                htmlLines.append("<div><i>Original note: \(content.title.escapedForHTML)</i></div>")
                htmlLines.append("<div><i>Restored on: \(timestamp)</i></div>")
                htmlLines.append("<div><br></div>")
                htmlLines.append("<div>─────────────────────────</div>")
                htmlLines.append("<div><br></div>")

                let contentLines = content.content.plaintext
                    .components(separatedBy: "\n")
                    .map { "<div>\($0.isEmpty ? "<br>" : $0.escapedForHTML)</div>" }
                htmlLines.append(contentsOf: contentLines)

                let html = htmlLines.joined()
                try writer.createNote(title: restoredTitle, body: html, folder: folder)

                pickleSuccess("Created restored note: \(restoredTitle)")
                print("")
                pickleInfo("Original note '\(content.title)' remains unchanged")
                pickleInfo("Compare them side-by-side in Apple Notes")
            }

            pickleInfo("Use 'pickle history \"\(content.title)\"' to see all versions")

        } catch {
            pickleError("Failed to restore: \(error.localizedDescription)")
            print("")
            pickleInfo("Alternative: Use 'pickle export' to save the version as a file")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - String Extensions

extension String {
    var escapedForHTML: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
