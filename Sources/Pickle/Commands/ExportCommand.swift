import ArgumentParser
import Foundation
import CiderCore

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export all versions of a note to files"
    )

    @Argument(help: "Note title or UUID to export")
    var noteIdentifier: String

    @Argument(help: "Output directory")
    var outputDir: String

    @Option(name: .long, help: "Output format (md, txt, json)")
    var format: ExportFormat = .md

    @OptionGroup var options: PickleGlobalOptions

    func run() throws {
        let versionDB = try VersionDatabase()
        let outputURL = URL(fileURLWithPath: outputDir).standardizedFileURL

        // Find the note
        let note: NoteRecord

        if let byUUID = try versionDB.getNote(uuid: noteIdentifier) {
            note = byUUID
        } else {
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
                pickleInfo("Please specify the exact UUID")
                return
            }

            note = matches[0]
        }

        guard let noteID = note.id else {
            throw PickleError.noteNotFound(noteIdentifier)
        }

        // Create output directory
        let noteDir = outputURL.appendingPathComponent(note.title ?? note.uuid)
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)

        print("Exporting versions of: \(note.title ?? "Untitled")")
        print("Output: \(noteDir.path)")
        print("")

        let versions = try versionDB.getVersions(noteID: noteID)

        if versions.isEmpty {
            pickleWarning("No versions found")
            return
        }

        var exportedCount = 0

        for version in versions {
            do {
                let content = try versionDB.loadVersionContent(storagePath: version.storagePath)

                let filename: String
                let fileContent: String

                switch format {
                case .md:
                    filename = "v\(String(format: "%03d", version.versionNumber))_\(formatDateForFilename(content.capturedAt)).md"
                    fileContent = formatAsMarkdown(version: version, content: content)
                case .txt:
                    filename = "v\(String(format: "%03d", version.versionNumber))_\(formatDateForFilename(content.capturedAt)).txt"
                    fileContent = content.content.plaintext
                case .json:
                    filename = "v\(String(format: "%03d", version.versionNumber))_\(formatDateForFilename(content.capturedAt)).json"
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    let jsonData = try encoder.encode(content)
                    fileContent = String(data: jsonData, encoding: .utf8) ?? "{}"
                }

                let filePath = noteDir.appendingPathComponent(filename)
                try fileContent.write(to: filePath, atomically: true, encoding: .utf8)

                pickleVerbose("Exported: \(filename)", verbose: options.verbose)
                exportedCount += 1

            } catch {
                pickleError("Failed to export version \(version.versionNumber): \(error.localizedDescription)")
            }
        }

        print("")
        pickleSuccess("Exported \(exportedCount) versions to \(noteDir.path)")
    }

    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }

    private func formatAsMarkdown(version: VersionRecord, content: VersionContent) -> String {
        var md = "---\n"
        md += "title: \"\(content.title.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
        md += "version: \(version.versionNumber)\n"
        md += "captured: \(ISO8601DateFormatter().string(from: content.capturedAt))\n"
        md += "uuid: \(content.noteUUID)\n"
        md += "characters: \(content.metadata.characterCount)\n"
        md += "words: \(content.metadata.wordCount)\n"
        md += "---\n\n"
        md += content.content.plaintext
        return md
    }
}

enum ExportFormat: String, ExpressibleByArgument, CaseIterable {
    case md, txt, json
}
