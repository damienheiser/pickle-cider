import ArgumentParser
import Foundation
import CiderCore

struct SyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Bidirectional sync between local files and Apple Notes"
    )

    @Argument(help: "Directory to sync with Apple Notes")
    var path: String

    @OptionGroup var options: GlobalOptions

    @Flag(name: .long, help: "Force overwrite conflicts (local wins)")
    var forceLocal: Bool = false

    @Flag(name: .long, help: "Force overwrite conflicts (remote wins)")
    var forceRemote: Bool = false

    func run() throws {
        let syncDir = URL(fileURLWithPath: path).standardizedFileURL

        // Ensure directory exists
        try FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)

        print("Cider - Bidirectional Sync")
        print("Local:  \(syncDir.path)")
        print("Remote: Apple Notes / \(options.folder)")
        print("")

        do {
            let reader = try NotesReader()
            let writer = NotesWriter()
            let parser = ProtobufParser()
            let converter = MarkdownConverter()
            let stateDB = try StateDatabase()

            // Ensure remote folder exists
            if !options.dryRun {
                let folderExists = try writer.folderExists(name: options.folder)
                if !folderExists {
                    printInfo("Creating remote folder: \(options.folder)")
                    try writer.createFolder(name: options.folder)
                }
            }

            // Get current state
            let localFiles = try getLocalFiles(in: syncDir)
            let remoteNotes = try getRemoteNotes(reader: reader, parser: parser)
            let syncStates = try stateDB.getAllSyncStates()

            print("Local files:  \(localFiles.count)")
            print("Remote notes: \(remoteNotes.count)")
            print("Tracked:      \(syncStates.count)")
            print("")

            // Build lookup maps
            var stateByPath: [String: SyncStateRecord] = [:]
            var stateByUUID: [String: SyncStateRecord] = [:]
            for state in syncStates {
                stateByPath[state.localPath] = state
                if let uuid = state.noteUUID {
                    stateByUUID[uuid] = state
                }
            }

            var actions: [SyncAction] = []

            // Analyze local files
            for (relativePath, fileInfo) in localFiles {
                if let state = stateByPath[relativePath] {
                    // Known file - check for changes
                    let localChanged = fileInfo.hash != state.localHash
                    let remoteNote = state.noteUUID.flatMap { remoteNotes[$0] }
                    let remoteChanged = remoteNote.map { $0.hash != state.remoteHash } ?? false

                    if localChanged && remoteChanged {
                        // Conflict
                        if forceLocal {
                            actions.append(.push(relativePath, fileInfo))
                        } else if forceRemote {
                            if let note = remoteNote {
                                actions.append(.pull(relativePath, note))
                            }
                        } else {
                            actions.append(.conflict(relativePath, fileInfo, remoteNote))
                        }
                    } else if localChanged {
                        actions.append(.push(relativePath, fileInfo))
                    } else if remoteChanged, let note = remoteNote {
                        actions.append(.pull(relativePath, note))
                    }
                    // else: no changes
                } else {
                    // New local file
                    actions.append(.createRemote(relativePath, fileInfo))
                }
            }

            // Analyze remote notes
            for (uuid, noteInfo) in remoteNotes {
                if stateByUUID[uuid] == nil {
                    // New remote note - check if we have it by title
                    let expectedPath = "\(noteInfo.title).\(options.format.fileExtension)"
                    if localFiles[expectedPath] == nil {
                        actions.append(.createLocal(expectedPath, noteInfo))
                    }
                }
            }

            // Check for deletions
            for state in syncStates {
                let localExists = localFiles[state.localPath] != nil
                let remoteExists = state.noteUUID.flatMap { remoteNotes[$0] } != nil

                if !localExists && remoteExists {
                    actions.append(.deletedLocally(state))
                } else if localExists && !remoteExists && state.noteUUID != nil {
                    actions.append(.deletedRemotely(state))
                }
            }

            // Report planned actions
            if actions.isEmpty {
                printSuccess("Everything is in sync!")
                return
            }

            print("Planned actions:")
            for action in actions {
                print("  \(action.description)")
            }
            print("")

            if options.dryRun {
                printInfo("Dry run - no changes made")
                return
            }

            // Execute actions
            var successCount = 0
            var errorCount = 0

            for action in actions {
                do {
                    try executeAction(
                        action,
                        syncDir: syncDir,
                        reader: reader,
                        writer: writer,
                        parser: parser,
                        converter: converter,
                        stateDB: stateDB
                    )
                    successCount += 1
                } catch {
                    printError("Failed: \(action.description) - \(error.localizedDescription)")
                    errorCount += 1
                }
            }

            print("")
            printSuccess("\(successCount) actions completed")
            if errorCount > 0 {
                printError("\(errorCount) errors")
            }

        } catch {
            printError("Sync failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    // MARK: - Helper Types

    struct LocalFileInfo {
        let url: URL
        let hash: String
        let mtime: Date
        let content: String
    }

    struct RemoteNoteInfo {
        let note: Note
        let hash: String
        let plaintext: String
        let title: String
    }

    enum SyncAction {
        case push(String, LocalFileInfo)
        case pull(String, RemoteNoteInfo)
        case createRemote(String, LocalFileInfo)
        case createLocal(String, RemoteNoteInfo)
        case conflict(String, LocalFileInfo, RemoteNoteInfo?)
        case deletedLocally(SyncStateRecord)
        case deletedRemotely(SyncStateRecord)

        var description: String {
            switch self {
            case .push(let path, _):
                return "→ Push: \(path)"
            case .pull(let path, _):
                return "← Pull: \(path)"
            case .createRemote(let path, _):
                return "→ Create remote: \(path)"
            case .createLocal(let path, _):
                return "← Create local: \(path)"
            case .conflict(let path, _, _):
                return "⚠ Conflict: \(path)"
            case .deletedLocally(let state):
                return "? Deleted locally: \(state.localPath)"
            case .deletedRemotely(let state):
                return "? Deleted remotely: \(state.localPath)"
            }
        }
    }

    // MARK: - Helpers

    private func getLocalFiles(in directory: URL) throws -> [String: LocalFileInfo] {
        var files: [String: LocalFileInfo] = [:]

        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == options.format.fileExtension else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: directory.path + "/", with: "")

            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let hash = content.data(using: .utf8)?.sha256 ?? ""
            let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

            files[relativePath] = LocalFileInfo(url: fileURL, hash: hash, mtime: mtime, content: content)
        }

        return files
    }

    private func getRemoteNotes(reader: NotesReader, parser: ProtobufParser) throws -> [String: RemoteNoteInfo] {
        var notes: [String: RemoteNoteInfo] = [:]

        // Get folder if it exists
        guard let folder = try reader.getFolder(name: options.folder) else {
            return notes
        }

        let remoteNotes = try reader.getNotes(inFolder: folder.id)

        for note in remoteNotes {
            guard !note.isPasswordProtected else { continue }

            var plaintext = ""
            if let rawData = note.rawData {
                if let parsed = try? parser.parseNoteData(rawData) {
                    plaintext = parsed.plaintext
                }
            }

            let hash = plaintext.data(using: .utf8)?.sha256 ?? ""

            notes[note.uuid] = RemoteNoteInfo(
                note: note,
                hash: hash,
                plaintext: plaintext,
                title: note.displayTitle
            )
        }

        return notes
    }

    private func executeAction(
        _ action: SyncAction,
        syncDir: URL,
        reader: NotesReader,
        writer: NotesWriter,
        parser: ProtobufParser,
        converter: MarkdownConverter,
        stateDB: StateDatabase
    ) throws {
        switch action {
        case .push(let path, let fileInfo):
            let (title, body) = parseFile(content: fileInfo.content)
            let html = converter.markdownToHTML(body)
            try writer.updateNote(title: title, body: html, folder: options.folder)

            let state = SyncStateRecord(
                localPath: path,
                folderPath: options.folder,
                localHash: fileInfo.hash,
                remoteHash: fileInfo.hash,
                syncStatus: "synced",
                lastSync: Int64(Date().timeIntervalSince1970)
            )
            try stateDB.upsertSyncState(state)
            printVerbose("Pushed: \(path)", verbose: options.verbose)

        case .pull(let path, let noteInfo):
            let outputPath = syncDir.appendingPathComponent(path)
            let content = formatAsMarkdown(note: noteInfo)
            try content.write(to: outputPath, atomically: true, encoding: .utf8)

            let state = SyncStateRecord(
                localPath: path,
                noteUUID: noteInfo.note.uuid,
                folderPath: options.folder,
                localHash: noteInfo.hash,
                remoteHash: noteInfo.hash,
                syncStatus: "synced",
                lastSync: Int64(Date().timeIntervalSince1970)
            )
            try stateDB.upsertSyncState(state)
            printVerbose("Pulled: \(path)", verbose: options.verbose)

        case .createRemote(let path, let fileInfo):
            let (title, body) = parseFile(content: fileInfo.content)
            let html = converter.markdownToHTML(body)
            let noteID = try writer.createNote(title: title, body: html, folder: options.folder)

            let state = SyncStateRecord(
                localPath: path,
                noteID: noteID,
                folderPath: options.folder,
                localHash: fileInfo.hash,
                remoteHash: fileInfo.hash,
                syncStatus: "synced",
                lastSync: Int64(Date().timeIntervalSince1970)
            )
            try stateDB.upsertSyncState(state)
            printVerbose("Created remote: \(path)", verbose: options.verbose)

        case .createLocal(let path, let noteInfo):
            let outputPath = syncDir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: outputPath.deletingLastPathComponent(), withIntermediateDirectories: true)

            let content = formatAsMarkdown(note: noteInfo)
            try content.write(to: outputPath, atomically: true, encoding: .utf8)

            let state = SyncStateRecord(
                localPath: path,
                noteUUID: noteInfo.note.uuid,
                folderPath: options.folder,
                localHash: noteInfo.hash,
                remoteHash: noteInfo.hash,
                syncStatus: "synced",
                lastSync: Int64(Date().timeIntervalSince1970)
            )
            try stateDB.upsertSyncState(state)
            printVerbose("Created local: \(path)", verbose: options.verbose)

        case .conflict(let path, _, _):
            printWarning("Conflict not resolved: \(path) - use --force-local or --force-remote")

        case .deletedLocally(let state):
            // Local file was deleted - remove from tracking (don't delete remote by default)
            try stateDB.deleteSyncState(localPath: state.localPath)
            printVerbose("Untracked: \(state.localPath)", verbose: options.verbose)

        case .deletedRemotely(let state):
            // Remote was deleted - remove local file
            let localPath = syncDir.appendingPathComponent(state.localPath)
            try? FileManager.default.removeItem(at: localPath)
            try stateDB.deleteSyncState(localPath: state.localPath)
            printVerbose("Deleted local: \(state.localPath)", verbose: options.verbose)
        }
    }

    private func parseFile(content: String) -> (title: String, body: String) {
        var title = "Untitled"
        var body = content

        if content.hasPrefix("---") {
            let parts = content.components(separatedBy: "---")
            if parts.count >= 3 {
                let frontmatter = parts[1]
                body = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)

                for line in frontmatter.components(separatedBy: "\n") {
                    if line.hasPrefix("title:") {
                        title = line.replacingOccurrences(of: "title:", with: "")
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        break
                    }
                }
            }
        }

        if body.hasPrefix("# ") {
            let lines = body.components(separatedBy: "\n")
            if let firstLine = lines.first {
                title = firstLine.replacingOccurrences(of: "# ", with: "")
                body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return (title, body)
    }

    private func formatAsMarkdown(note: RemoteNoteInfo) -> String {
        var md = "---\n"
        md += "title: \"\(note.title.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
        md += "uuid: \(note.note.uuid)\n"
        if let modified = note.note.modificationDate {
            md += "modified: \(ISO8601DateFormatter().string(from: modified))\n"
        }
        md += "---\n\n"
        md += "# \(note.title)\n\n"
        md += note.plaintext
        return md
    }
}
