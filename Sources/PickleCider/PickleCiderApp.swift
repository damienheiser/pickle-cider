import SwiftUI
import CiderCore
import AppKit

@main
struct PickleCiderApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var noteCount: Int = 0
    @Published var versionCount: Int = 0
    @Published var syncedFileCount: Int = 0
    @Published var trackedNotes: [TrackedNote] = []
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var daemonRunning: Bool = false
    @Published var hasFullDiskAccess: Bool = true
    @Published var needsOnboarding: Bool = false
    @Published var inAppMonitoringActive: Bool = false
    @Published var lastMonitorCheck: Date?

    private var notesReader: NotesReader?
    private var versionDB: VersionDatabase?
    private var stateDB: StateDatabase?
    private var monitorTimer: Timer?
    private let monitorInterval: TimeInterval = 30

    init() {
        checkPermissionsAndRefresh()
        startInAppMonitoring()
    }

    deinit {
        stopInAppMonitoring()
    }

    /// Start in-app background monitoring (inherits app's FDA)
    func startInAppMonitoring() {
        guard monitorTimer == nil else { return }

        monitorTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in
            self?.performMonitorCheck()
        }

        // Initial check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.performMonitorCheck()
        }

        DispatchQueue.main.async {
            self.inAppMonitoringActive = true
        }
    }

    func stopInAppMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        inAppMonitoringActive = false
    }

    private func performMonitorCheck() {
        guard hasFullDiskAccess else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            do {
                let reader = try NotesReader()
                let versionDB = try VersionDatabase()
                let parser = ProtobufParser()

                let notes = try reader.getAllNotes()
                let knownStates = try versionDB.getAllMonitorStates()
                let knownMap = Dictionary(uniqueKeysWithValues: knownStates.map { ($0.noteUUID, $0) })

                var savedCount = 0

                for note in notes {
                    if note.isPasswordProtected { continue }

                    var plaintext = ""
                    if let rawData = note.rawData {
                        if let parsed = try? parser.parseNoteData(rawData) {
                            plaintext = parsed.plaintext
                        }
                    }

                    let currentHash = plaintext.sha256Hash
                    let modTime = note.modificationDate ?? Date()

                    let needsSave: Bool
                    if let known = knownMap[note.uuid] {
                        needsSave = currentHash != known.lastHash
                    } else {
                        needsSave = true
                    }

                    if needsSave {
                        let noteRecord = try versionDB.getOrCreateNote(
                            uuid: note.uuid,
                            title: note.displayTitle,
                            folderPath: note.folderName
                        )

                        if let noteID = noteRecord.id {
                            // Check if content actually changed
                            var shouldSave = true
                            if let lastVersion = try? versionDB.getLatestVersion(noteID: noteID),
                               let lastContent = try? versionDB.loadVersionContent(storagePath: lastVersion.storagePath) {
                                shouldSave = lastContent.content.plaintext != plaintext
                            }

                            if shouldSave {
                                let content = VersionContent(
                                    noteUUID: note.uuid,
                                    appleNoteID: nil,
                                    title: note.displayTitle,
                                    folderPath: note.folderName,
                                    capturedAt: Date(),
                                    appleModificationDate: note.modificationDate,
                                    plaintext: plaintext,
                                    html: nil,
                                    rawProtobuf: note.rawData
                                )
                                _ = try versionDB.saveVersion(noteID: noteID, content: content)
                                savedCount += 1
                            }
                        }

                        try versionDB.updateMonitorState(uuid: note.uuid, hash: currentHash, mtime: modTime)
                    }
                }

                DispatchQueue.main.async {
                    self.lastMonitorCheck = Date()
                    if savedCount > 0 {
                        self.refresh() // Refresh UI if versions were saved
                    }
                }
            } catch {
                // Silently fail - will retry next interval
            }
        }
    }

    /// Check if we have Full Disk Access by attempting to read a protected file
    func checkFullDiskAccess() -> Bool {
        let notesDBPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")

        // Try to open the file for reading
        if FileManager.default.isReadableFile(atPath: notesDBPath.path) {
            // File exists and is readable, but we need to actually try to open it
            // because isReadableFile doesn't check Full Disk Access
            do {
                let handle = try FileHandle(forReadingFrom: notesDBPath)
                handle.closeFile()
                return true
            } catch {
                return false
            }
        }

        // If file doesn't exist, user might not have Notes set up - that's okay
        return !FileManager.default.fileExists(atPath: notesDBPath.path)
    }

    func checkPermissionsAndRefresh() {
        let hasAccess = checkFullDiskAccess()

        DispatchQueue.main.async {
            self.hasFullDiskAccess = hasAccess
            self.needsOnboarding = !hasAccess
        }

        if hasAccess {
            refresh()
        } else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }

    func openSystemPreferences() {
        // Open System Settings > Privacy & Security > Full Disk Access
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                // Initialize readers
                let reader = try NotesReader()
                self?.notesReader = reader

                let noteCount = try reader.getNoteCount()

                // Version database
                let versionDB = try VersionDatabase()
                self?.versionDB = versionDB
                let stats = try versionDB.getStatistics()

                // State database
                let stateDB = try StateDatabase()
                self?.stateDB = stateDB
                let syncStats = try stateDB.getStatistics()

                // Get tracked notes
                let notes = try versionDB.getAllNotes()
                let trackedNotes: [TrackedNote] = try notes.compactMap { noteRecord in
                    let versions = try versionDB.getVersions(noteID: noteRecord.id ?? 0)
                    return TrackedNote(
                        id: noteRecord.uuid,
                        title: noteRecord.title ?? "Untitled",
                        versionCount: versions.count,
                        lastBackup: versions.first?.capturedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    )
                }

                // Check daemon status
                let daemonRunning = LaunchDaemonHelper.isRunning

                DispatchQueue.main.async {
                    self?.noteCount = noteCount
                    self?.versionCount = stats.totalVersions
                    self?.syncedFileCount = syncStats.syncedFiles
                    self?.trackedNotes = trackedNotes
                    self?.daemonRunning = daemonRunning
                    self?.isLoading = false
                    self?.lastError = nil
                    self?.hasFullDiskAccess = true
                    self?.needsOnboarding = false
                }
            } catch {
                let errorMessage = error.localizedDescription
                let isPermissionError = errorMessage.contains("authorization denied") ||
                                        errorMessage.contains("not permitted") ||
                                        errorMessage.contains("SQLite error 23")

                DispatchQueue.main.async {
                    if isPermissionError {
                        self?.hasFullDiskAccess = false
                        self?.needsOnboarding = true
                        self?.lastError = nil
                    } else {
                        self?.lastError = errorMessage
                    }
                    self?.isLoading = false
                }
            }
        }
    }

    func exportNote(_ note: TrackedNote, to url: URL) {
        guard let versionDB = versionDB else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let noteRecord = try versionDB.getNote(uuid: note.id),
                      let noteID = noteRecord.id else { return }

                let versions = try versionDB.getVersions(noteID: noteID)

                for version in versions {
                    let content = try versionDB.loadVersionContent(storagePath: version.storagePath)

                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
                    let filename = "v\(String(format: "%03d", version.versionNumber))_\(dateFormatter.string(from: content.capturedAt)).md"

                    let filePath = url.appendingPathComponent(filename)

                    var md = "---\ntitle: \"\(content.title)\"\nversion: \(version.versionNumber)\n---\n\n"
                    md += content.content.plaintext

                    try md.write(to: filePath, atomically: true, encoding: .utf8)
                }

                DispatchQueue.main.async {
                    self?.lastError = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Export all Apple Notes to markdown files with attachments
    func exportAllAppleNotes(to baseURL: URL) {
        guard let reader = notesReader else {
            lastError = "Notes reader not available"
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let notes = try reader.getAllNotes()
                let accountUUID = try reader.getAccountUUID()
                var exportedCount = 0
                var skippedCount = 0
                var attachmentCount = 0

                for note in notes {
                    // Skip password protected notes
                    if note.isPasswordProtected {
                        skippedCount += 1
                        continue
                    }

                    // Create folder path based on note's folder
                    let folderName = (note.folderName ?? "Notes").sanitizedForFilename
                    let folderPath = baseURL.appendingPathComponent(folderName)
                    try FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true)

                    // Create filename from title
                    let noteSafeFilename = note.safeFilename
                    let filename = noteSafeFilename + ".md"
                    let filePath = folderPath.appendingPathComponent(filename)

                    // Get attachments for this note
                    let attachments = try reader.getAttachments(noteID: note.id)
                    var attachmentMarkdown: [String: String] = [:] // uuid -> markdown

                    // Create attachments folder if needed
                    let attachmentsDir = folderPath.appendingPathComponent("_attachments").appendingPathComponent(noteSafeFilename)
                    if !attachments.isEmpty {
                        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
                    }

                    // Process attachments
                    for attachment in attachments {
                        switch attachment.attachmentType {
                        case .image, .video, .audio, .file:
                            // Copy media file
                            if let accountUUID = accountUUID,
                               let sourcePath = attachment.mediaFilePath(accountUUID: accountUUID, baseDir: NotesReader.notesBaseDir) {
                                let destFilename = attachment.filename ?? "\(attachment.uuid).\(sourcePath.pathExtension)"
                                let destPath = attachmentsDir.appendingPathComponent(destFilename)
                                try? FileManager.default.copyItem(at: sourcePath, to: destPath)

                                let relativePath = "_attachments/\(noteSafeFilename)/\(destFilename)"
                                if attachment.attachmentType == .image {
                                    attachmentMarkdown[attachment.uuid] = "![\(destFilename)](\(relativePath))"
                                } else {
                                    attachmentMarkdown[attachment.uuid] = "[\(destFilename)](\(relativePath))"
                                }
                                attachmentCount += 1
                            }

                        case .table:
                            // Get table content
                            if let tableContent = try? reader.getTableContent(attachmentID: attachment.id),
                               !tableContent.isEmpty {
                                // Convert table summary to markdown table format
                                let tableMarkdown = self?.formatTableAsMarkdown(tableContent) ?? tableContent
                                attachmentMarkdown[attachment.uuid] = "\n\n" + tableMarkdown + "\n\n"
                            }

                        case .drawing:
                            attachmentMarkdown[attachment.uuid] = "[Drawing]"

                        case .link:
                            attachmentMarkdown[attachment.uuid] = "[Link]"
                        }
                    }

                    // Get note content
                    var plaintext: String
                    if let text = note.plaintext, !text.isEmpty {
                        plaintext = text
                    } else if let data = note.rawData {
                        do {
                            let parser = ProtobufParser()
                            let content = try parser.parseNoteData(data)
                            plaintext = content.plaintext
                        } catch {
                            skippedCount += 1
                            continue
                        }
                    } else {
                        skippedCount += 1
                        continue
                    }

                    // Replace attachment placeholders (U+FFFC) with markdown
                    // The object replacement character marks where attachments go
                    var index = 0
                    var processedText = ""
                    for char in plaintext {
                        if char == "\u{FFFC}" && index < attachments.count {
                            let attachment = attachments[index]
                            if let md = attachmentMarkdown[attachment.uuid] {
                                processedText += md
                            } else {
                                processedText += "[attachment]"
                            }
                            index += 1
                        } else {
                            processedText.append(char)
                        }
                    }

                    var md = "---\n"
                    md += "title: \"\(note.displayTitle.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
                    if let folder = note.folderName {
                        md += "folder: \"\(folder)\"\n"
                    }
                    if let created = note.creationDate {
                        md += "created: \(ISO8601DateFormatter().string(from: created))\n"
                    }
                    if let modified = note.modificationDate {
                        md += "modified: \(ISO8601DateFormatter().string(from: modified))\n"
                    }
                    if !attachments.isEmpty {
                        md += "attachments: \(attachments.count)\n"
                    }
                    md += "---\n\n"
                    md += processedText

                    try md.write(to: filePath, atomically: true, encoding: .utf8)
                    exportedCount += 1
                }

                DispatchQueue.main.async {
                    self?.isLoading = false
                    var message = "Exported \(exportedCount) notes"
                    if attachmentCount > 0 {
                        message += ", \(attachmentCount) attachments"
                    }
                    if skippedCount > 0 {
                        message += ", skipped \(skippedCount) (locked/empty)"
                    }
                    self?.lastError = message
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.lastError = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Format table summary text as a markdown table
    private func formatTableAsMarkdown(_ summary: String) -> String {
        // Table summaries come as "Header:\nValue\nHeader:\nValue" format
        let lines = summary.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Try to detect if it's a key-value table
        var rows: [[String]] = []
        var currentRow: [String] = []
        var isKeyValue = false

        for line in lines {
            if line.hasSuffix(":") {
                // This looks like a header/key
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                    currentRow = []
                }
                currentRow.append(String(line.dropLast()))
                isKeyValue = true
            } else {
                currentRow.append(line)
                if isKeyValue && currentRow.count >= 2 {
                    rows.append(currentRow)
                    currentRow = []
                }
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        guard !rows.isEmpty else { return summary }

        // Determine column count
        let maxCols = rows.map { $0.count }.max() ?? 1

        // Build markdown table
        var md = "| " + (0..<maxCols).map { "Column \($0 + 1)" }.joined(separator: " | ") + " |\n"
        md += "| " + (0..<maxCols).map { _ in "---" }.joined(separator: " | ") + " |\n"

        for row in rows {
            let cells = (0..<maxCols).map { i in
                i < row.count ? row[i].replacingOccurrences(of: "|", with: "\\|") : ""
            }
            md += "| " + cells.joined(separator: " | ") + " |\n"
        }

        return md
    }
}

struct TrackedNote: Identifiable {
    let id: String
    let title: String
    let versionCount: Int
    let lastBackup: Date?
}

// MARK: - Launch Daemon Helper

struct LaunchDaemonHelper {
    static let plistLabel = "com.pickle.daemon"
    static let plistPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.pickle.daemon.plist")

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath.path)
    }

    static var isRunning: Bool {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", plistLabel]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    static var picklePath: String {
        // Prefer app bundle path for Full Disk Access inheritance
        let appBundlePath = "/Applications/Pickle Cider.app/Contents/MacOS/pickle"
        if FileManager.default.isExecutableFile(atPath: appBundlePath) {
            return appBundlePath
        }
        return "/usr/local/bin/pickle"
    }

    static func install() {
        // Use pickle CLI to install the daemon
        let task = Process()
        task.launchPath = picklePath
        task.arguments = ["install", "--force"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    static func start() {
        // Auto-install if not installed
        if !isInstalled {
            install()
        }

        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", plistPath.path]
        try? task.run()
        task.waitUntilExit()
    }

    static func stop() {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistPath.path]
        try? task.run()
        task.waitUntilExit()
    }
}
