import ArgumentParser
import Foundation
import CiderCore

struct ExportToNotesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-to-notes",
        abstract: "Export version history to Apple Notes folders"
    )

    @Argument(help: "Note title or UUID to export (or 'all' for everything)")
    var noteIdentifier: String = "all"

    @Option(name: .long, help: "Parent folder name in Apple Notes")
    var folder: String = "Version History"

    @Option(name: .long, help: "Maximum versions to export per note")
    var limit: Int = 10

    @Flag(name: .long, help: "Preview without creating notes")
    var dryRun: Bool = false

    @OptionGroup var options: PickleGlobalOptions

    func run() throws {
        let versionDB = try VersionDatabase()
        let writer = NotesWriter()

        print("Export to Apple Notes")
        print("═════════════════════\n")
        print("Target folder: \(folder)")
        print("")

        // Ensure parent folder exists
        if !dryRun {
            if !(try writer.folderExists(name: folder)) {
                try writer.createFolder(name: folder)
                pickleSuccess("Created folder: \(folder)")
            }
        }

        // Get notes to export
        let notesToExport: [NoteRecord]

        if noteIdentifier.lowercased() == "all" {
            notesToExport = try versionDB.getAllNotes()
        } else {
            if let byUUID = try versionDB.getNote(uuid: noteIdentifier) {
                notesToExport = [byUUID]
            } else {
                let allNotes = try versionDB.getAllNotes()
                notesToExport = allNotes.filter {
                    $0.title?.localizedCaseInsensitiveContains(noteIdentifier) == true
                }

                if notesToExport.isEmpty {
                    throw PickleError.noteNotFound(noteIdentifier)
                }
            }
        }

        print("Exporting \(notesToExport.count) note(s)...\n")

        var totalVersions = 0
        var exportedVersions = 0

        for note in notesToExport {
            guard let noteID = note.id else { continue }

            let versions = try versionDB.getVersions(noteID: noteID)
            totalVersions += versions.count

            if versions.isEmpty {
                pickleVerbose("Skipping \(note.title ?? "Untitled"): no versions", verbose: options.verbose)
                continue
            }

            let safeName = sanitizeFolderName(note.title ?? note.uuid)

            print("• \(note.title ?? "Untitled") (\(min(versions.count, limit)) versions)")

            if dryRun {
                pickleVerbose("  Would create folder: \(folder)/\(safeName)", verbose: options.verbose)
            } else {
                // Create subfolder for this note
                let noteFolder = safeName
                if !(try writer.folderExists(name: noteFolder)) {
                    try writer.createFolder(name: noteFolder)
                }
            }

            // Export versions
            for version in versions.prefix(limit) {
                do {
                    let content = try versionDB.loadVersionContent(storagePath: version.storagePath)

                    let versionTitle = "v\(version.versionNumber) - \(formatDateShort(content.capturedAt))"

                    if dryRun {
                        pickleVerbose("  Would create: \(versionTitle)", verbose: options.verbose)
                    } else {
                        // Create note with version content
                        let htmlBody = formatVersionAsHTML(version: version, content: content)
                        try writer.createNote(title: versionTitle, body: htmlBody, folder: safeName)
                        pickleVerbose("  Created: \(versionTitle)", verbose: options.verbose)
                    }

                    exportedVersions += 1

                } catch {
                    pickleError("  Failed v\(version.versionNumber): \(error.localizedDescription)")
                }
            }
        }

        print("")
        if dryRun {
            pickleInfo("Dry run: would export \(exportedVersions) versions")
        } else {
            pickleSuccess("Exported \(exportedVersions) versions to Apple Notes")
        }

        if totalVersions > exportedVersions {
            pickleInfo("\(totalVersions - exportedVersions) versions not exported (--limit \(limit))")
        }
    }

    private func sanitizeFolderName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(50)
            .description
    }

    private func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    private func formatVersionAsHTML(version: VersionRecord, content: VersionContent) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .medium

        var html = "<html><head></head><body>"
        html += "<h1>\(content.title) - Version \(version.versionNumber)</h1>"
        html += "<p><strong>Captured:</strong> \(dateFormatter.string(from: content.capturedAt))</p>"
        html += "<p><strong>Characters:</strong> \(content.metadata.characterCount)</p>"
        html += "<p><strong>Words:</strong> \(content.metadata.wordCount)</p>"
        html += "<hr>"

        // Convert plaintext to HTML paragraphs
        let paragraphs = content.content.plaintext
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .components(separatedBy: "\n\n")
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined(separator: "\n")

        html += paragraphs
        html += "</body></html>"

        return html
    }
}
