import ArgumentParser
import Foundation
import CiderCore

struct PullCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Export Apple Notes to markdown files"
    )

    @Argument(help: "Output directory for exported files")
    var outputDir: String

    @OptionGroup var options: GlobalOptions

    @Flag(name: .shortAndLong, help: "Process all folders recursively")
    var recursive: Bool = false

    @Flag(name: .long, help: "Overwrite existing files without prompting")
    var force: Bool = false

    @Option(name: .long, help: "Only export notes from this specific folder")
    var sourceFolder: String?

    func run() throws {
        let outputURL = URL(fileURLWithPath: outputDir).standardizedFileURL

        // Ensure output directory exists
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        print("Cider - Exporting Apple Notes to \(outputURL.path)")
        print("")

        do {
            let reader = try NotesReader()
            let parser = ProtobufParser()
            let converter = MarkdownConverter()
            let stateDB = try StateDatabase()

            var exportedCount = 0
            var skippedCount = 0
            var errorCount = 0

            if let sourceFolder = sourceFolder {
                // Export from specific folder
                print("Exporting from folder: \(sourceFolder)")

                guard let folder = try reader.getFolder(name: sourceFolder) else {
                    printError("Folder not found: \(sourceFolder)")
                    throw ExitCode.failure
                }

                let notes = try reader.getNotes(inFolder: folder.id)
                print("Found \(notes.count) notes\n")

                for note in notes {
                    let result = try exportNote(
                        note,
                        to: outputURL,
                        folderPath: folder.safeName,
                        parser: parser,
                        converter: converter,
                        stateDB: stateDB
                    )

                    switch result {
                    case .exported: exportedCount += 1
                    case .skipped: skippedCount += 1
                    case .error: errorCount += 1
                    }
                }
            } else if recursive {
                // Export all folders recursively
                let folderTree = try reader.getFolderTree()
                print("Found \(folderTree.count) top-level folders\n")

                func exportTree(_ trees: [FolderTree], parentPath: String = "") {
                    for tree in trees {
                        // Skip special folders
                        if tree.folder.folderType.isSpecial {
                            printVerbose("Skipping special folder: \(tree.folder.name)", verbose: options.verbose)
                            continue
                        }

                        let folderPath = parentPath.isEmpty ? tree.folder.safeName : "\(parentPath)/\(tree.folder.safeName)"

                        // Create folder
                        let folderURL = outputURL.appendingPathComponent(folderPath)
                        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

                        printVerbose("Processing folder: \(folderPath)", verbose: options.verbose)

                        // Export notes in this folder
                        for note in tree.notes {
                            do {
                                let result = try exportNote(
                                    note,
                                    to: outputURL,
                                    folderPath: folderPath,
                                    parser: parser,
                                    converter: converter,
                                    stateDB: stateDB
                                )

                                switch result {
                                case .exported: exportedCount += 1
                                case .skipped: skippedCount += 1
                                case .error: errorCount += 1
                                }
                            } catch {
                                printError("Failed to export '\(note.displayTitle)': \(error.localizedDescription)")
                                errorCount += 1
                            }
                        }

                        // Recurse into children
                        exportTree(tree.children, parentPath: folderPath)
                    }
                }

                exportTree(folderTree)
            } else {
                // Export all notes flat
                let notes = try reader.getAllNotes()
                print("Found \(notes.count) notes\n")

                for note in notes {
                    do {
                        let result = try exportNote(
                            note,
                            to: outputURL,
                            folderPath: "",
                            parser: parser,
                            converter: converter,
                            stateDB: stateDB
                        )

                        switch result {
                        case .exported: exportedCount += 1
                        case .skipped: skippedCount += 1
                        case .error: errorCount += 1
                        }
                    } catch {
                        printError("Failed to export '\(note.displayTitle)': \(error.localizedDescription)")
                        errorCount += 1
                    }
                }
            }

            print("")
            print("Export complete:")
            printSuccess("\(exportedCount) notes exported")
            if skippedCount > 0 {
                printWarning("\(skippedCount) notes skipped")
            }
            if errorCount > 0 {
                printError("\(errorCount) errors")
            }

        } catch {
            printError("Export failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    enum ExportResult {
        case exported, skipped, error
    }

    private func exportNote(
        _ note: Note,
        to baseURL: URL,
        folderPath: String,
        parser: ProtobufParser,
        converter: MarkdownConverter,
        stateDB: StateDatabase
    ) throws -> ExportResult {
        // Skip password-protected notes
        if note.isPasswordProtected {
            printWarning("Skipping locked note: \(note.displayTitle)")
            return .skipped
        }

        // Parse note content
        var plaintext = ""
        if let rawData = note.rawData {
            do {
                let parsed = try parser.parseNoteData(rawData)
                plaintext = parsed.plaintext
            } catch {
                printVerbose("Could not parse protobuf for '\(note.displayTitle)': \(error.localizedDescription)", verbose: options.verbose)
                // Try using raw data as text
                plaintext = note.displayTitle
            }
        }

        // Convert to desired format
        let content: String
        switch options.format {
        case .md:
            // Create markdown with frontmatter
            var md = "---\n"
            md += "title: \"\(note.displayTitle.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
            if let created = note.creationDate {
                md += "created: \(ISO8601DateFormatter().string(from: created))\n"
            }
            if let modified = note.modificationDate {
                md += "modified: \(ISO8601DateFormatter().string(from: modified))\n"
            }
            md += "uuid: \(note.uuid)\n"
            md += "---\n\n"
            md += "# \(note.displayTitle)\n\n"
            md += plaintext
            content = md

        case .txt:
            content = "\(note.displayTitle)\n\n\(plaintext)"

        case .html:
            content = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <title>\(note.displayTitle)</title>
            </head>
            <body>
                <h1>\(note.displayTitle)</h1>
                <p>\(plaintext.replacingOccurrences(of: "\n", with: "</p><p>"))</p>
            </body>
            </html>
            """
        }

        // Determine output path
        let filename = "\(note.safeFilename).\(options.format.fileExtension)"
        let relativePath = folderPath.isEmpty ? filename : "\(folderPath)/\(filename)"
        let outputPath = baseURL.appendingPathComponent(relativePath)

        // Check if file exists
        if FileManager.default.fileExists(atPath: outputPath.path) && !force {
            if !options.dryRun {
                printWarning("File exists, skipping: \(relativePath)")
                return .skipped
            }
        }

        // Write file
        if options.dryRun {
            print("Would export: \(relativePath)")
        } else {
            // Ensure directory exists
            try FileManager.default.createDirectory(
                at: outputPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try content.write(to: outputPath, atomically: true, encoding: .utf8)
            printVerbose("Exported: \(relativePath)", verbose: options.verbose)

            // Update sync state
            let hash = content.data(using: .utf8)?.sha256 ?? ""
            let state = SyncStateRecord(
                localPath: relativePath,
                noteUUID: note.uuid,
                folderPath: folderPath,
                localHash: hash,
                remoteHash: hash,
                localMtime: Int64(Date().timeIntervalSince1970),
                remoteMtime: note.modificationDate.map { Int64($0.timeIntervalSince1970) },
                syncStatus: "synced",
                lastSync: Int64(Date().timeIntervalSince1970)
            )
            try stateDB.upsertSyncState(state)
        }

        return .exported
    }
}

// Extension for SHA256 on Data
extension Data {
    var sha256: String {
        var hash = [UInt8](repeating: 0, count: 32)
        self.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

import CommonCrypto
