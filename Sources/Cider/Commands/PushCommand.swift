import ArgumentParser
import Foundation
import CiderCore

struct PushCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "Upload markdown files to Apple Notes"
    )

    @Argument(help: "File or directory to upload")
    var path: String

    @OptionGroup var options: GlobalOptions

    @Flag(name: .shortAndLong, help: "Process directories recursively")
    var recursive: Bool = false

    @Flag(name: .long, help: "Update existing notes instead of creating new ones")
    var update: Bool = false

    @Option(name: .long, help: "File patterns to include (e.g., '*.md')")
    var include: [String] = ["*.md", "*.txt"]

    func run() throws {
        let inputURL = URL(fileURLWithPath: path).standardizedFileURL

        print("Cider - Uploading files to Apple Notes")
        print("Target folder: \(options.folder)")
        print("")

        do {
            let writer = NotesWriter()
            let converter = MarkdownConverter()
            let stateDB = try StateDatabase()

            var uploadedCount = 0
            var updatedCount = 0
            var skippedCount = 0
            var errorCount = 0

            // Ensure target folder exists
            if !options.dryRun {
                if !(try writer.folderExists(name: options.folder)) {
                    printInfo("Creating folder: \(options.folder)")
                    try writer.createFolder(name: options.folder)
                }
            }

            // Get files to process
            let files = try getFilesToProcess(at: inputURL)

            if files.isEmpty {
                printWarning("No matching files found")
                return
            }

            print("Found \(files.count) files to process\n")

            for fileURL in files {
                do {
                    let result = try uploadFile(
                        fileURL,
                        relativeTo: inputURL.deletingLastPathComponent(),
                        writer: writer,
                        converter: converter,
                        stateDB: stateDB
                    )

                    switch result {
                    case .uploaded: uploadedCount += 1
                    case .updated: updatedCount += 1
                    case .skipped: skippedCount += 1
                    case .error: errorCount += 1
                    }
                } catch {
                    printError("Failed to upload '\(fileURL.lastPathComponent)': \(error.localizedDescription)")
                    errorCount += 1
                }
            }

            print("")
            print("Upload complete:")
            if uploadedCount > 0 { printSuccess("\(uploadedCount) notes created") }
            if updatedCount > 0 { printSuccess("\(updatedCount) notes updated") }
            if skippedCount > 0 { printWarning("\(skippedCount) files skipped") }
            if errorCount > 0 { printError("\(errorCount) errors") }

        } catch {
            printError("Upload failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    enum UploadResult {
        case uploaded, updated, skipped, error
    }

    private func getFilesToProcess(at url: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ValidationError("Path does not exist: \(url.path)")
        }

        if isDirectory.boolValue {
            // Get files from directory
            var files: [URL] = []

            let options: FileManager.DirectoryEnumerationOptions = recursive ? [] : [.skipsSubdirectoryDescendants]
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: options
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                // Check if matches include patterns
                let filename = fileURL.lastPathComponent
                if matchesPatterns(filename: filename, patterns: include) {
                    files.append(fileURL)
                }
            }

            return files.sorted { $0.path < $1.path }
        } else {
            // Single file
            return [url]
        }
    }

    private func matchesPatterns(filename: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if matchesGlobPattern(filename: filename, pattern: pattern) {
                return true
            }
        }
        return false
    }

    private func matchesGlobPattern(filename: String, pattern: String) -> Bool {
        // Simple glob matching for *.ext patterns
        if pattern.hasPrefix("*") {
            let ext = String(pattern.dropFirst())
            return filename.hasSuffix(ext)
        }
        return filename == pattern
    }

    private func uploadFile(
        _ fileURL: URL,
        relativeTo baseURL: URL,
        writer: NotesWriter,
        converter: MarkdownConverter,
        stateDB: StateDatabase
    ) throws -> UploadResult {
        // Read file content
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Parse title and content
        let (title, body) = parseMarkdownFile(content: content, filename: fileURL.lastPathComponent)

        // Convert to HTML for Notes
        let htmlBody = converter.markdownToHTML(body)

        // Calculate relative path for folder structure
        let relativePath = fileURL.path.replacingOccurrences(of: baseURL.path + "/", with: "")
        let relativeDir = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path

        // Determine target folder
        let targetFolder: String
        if relativeDir.isEmpty || relativeDir == "." {
            targetFolder = options.folder
        } else {
            targetFolder = "\(options.folder)/\(relativeDir)"
        }

        // Check if note already exists
        if update {
            if try writer.noteExists(title: title, folder: targetFolder) {
                if options.dryRun {
                    print("Would update: \(title) in \(targetFolder)")
                } else {
                    try writer.updateNote(title: title, body: htmlBody, folder: targetFolder)
                    printVerbose("Updated: \(title)", verbose: options.verbose)

                    // Update sync state
                    try updateSyncState(
                        localPath: relativePath,
                        stateDB: stateDB,
                        content: content,
                        status: "synced"
                    )
                }
                return .updated
            }
        }

        // Create new note
        if options.dryRun {
            print("Would create: \(title) in \(targetFolder)")
        } else {
            // Ensure folder exists (create nested folders if needed)
            try ensureFolderExists(targetFolder, writer: writer)

            let noteID = try writer.createNote(title: title, body: htmlBody, folder: targetFolder)
            printVerbose("Created: \(title) (ID: \(noteID))", verbose: options.verbose)

            // Update sync state
            try updateSyncState(
                localPath: relativePath,
                stateDB: stateDB,
                content: content,
                noteID: noteID,
                status: "synced"
            )
        }

        return .uploaded
    }

    private func parseMarkdownFile(content: String, filename: String) -> (title: String, body: String) {
        var title = filename
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: ".txt", with: "")

        var body = content

        // Check for YAML frontmatter
        if content.hasPrefix("---") {
            let parts = content.components(separatedBy: "---")
            if parts.count >= 3 {
                let frontmatter = parts[1]
                body = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)

                // Extract title from frontmatter
                for line in frontmatter.components(separatedBy: "\n") {
                    if line.hasPrefix("title:") {
                        var extractedTitle = line.replacingOccurrences(of: "title:", with: "").trimmingCharacters(in: .whitespaces)
                        // Remove quotes
                        if extractedTitle.hasPrefix("\"") && extractedTitle.hasSuffix("\"") {
                            extractedTitle = String(extractedTitle.dropFirst().dropLast())
                        }
                        if !extractedTitle.isEmpty {
                            title = extractedTitle
                        }
                        break
                    }
                }
            }
        }

        // Check for H1 header
        if body.hasPrefix("# ") {
            let lines = body.components(separatedBy: "\n")
            if let firstLine = lines.first {
                title = firstLine.replacingOccurrences(of: "# ", with: "")
                body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return (title, body)
    }

    private func ensureFolderExists(_ folderPath: String, writer: NotesWriter) throws {
        let components = folderPath.components(separatedBy: "/")
        var currentPath = ""

        for component in components {
            if currentPath.isEmpty {
                currentPath = component
            } else {
                let parent = currentPath
                currentPath = "\(currentPath)/\(component)"

                // Note: Apple Notes doesn't support nested folders via AppleScript easily
                // We'll create as a flat folder for now
            }

            if !(try writer.folderExists(name: component)) {
                try writer.createFolder(name: component)
            }
        }
    }

    private func updateSyncState(
        localPath: String,
        stateDB: StateDatabase,
        content: String,
        noteID: String? = nil,
        status: String
    ) throws {
        let hash = content.data(using: .utf8)?.sha256 ?? ""
        let state = SyncStateRecord(
            localPath: localPath,
            noteID: noteID,
            folderPath: options.folder,
            localHash: hash,
            remoteHash: hash,
            localMtime: Int64(Date().timeIntervalSince1970),
            syncStatus: status,
            lastSync: Int64(Date().timeIntervalSince1970)
        )
        try stateDB.upsertSyncState(state)
    }
}
