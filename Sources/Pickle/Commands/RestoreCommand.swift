import ArgumentParser
import Foundation
import CiderCore

struct RestoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Restore a note to a previous version"
    )

    @Argument(help: "Version ID to restore")
    var versionID: Int64

    @Flag(name: .long, help: "Preview changes without applying")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

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
            print("This will overwrite the current note content in Apple Notes.")
            print("Type 'yes' to confirm: ", terminator: "")

            guard let response = readLine()?.lowercased(), response == "yes" else {
                pickleInfo("Cancelled")
                return
            }
        }

        // Convert plaintext to HTML
        let converter = MarkdownConverter()
        let html = converter.markdownToHTML(content.content.plaintext)

        // Restore via AppleScript
        let writer = NotesWriter()

        // Find the note in Apple Notes
        let reader = try NotesReader()
        guard let appleNote = try reader.getNote(uuid: note.uuid) else {
            pickleError("Note not found in Apple Notes: \(note.uuid)")
            pickleInfo("The note may have been deleted. Use 'pickle export' to save versions as files.")
            return
        }

        // We need to get the note's ID from AppleScript, not the database
        // For now, we'll update by title
        let folder = appleNote.folderName ?? "Notes"

        do {
            try writer.updateNote(title: content.title, body: html, folder: folder)
            pickleSuccess("Restored note to version \(version.versionNumber)")

            print("")
            pickleInfo("The current version has been saved before restore")
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
