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

    private var notesReader: NotesReader?
    private var versionDB: VersionDatabase?
    private var stateDB: StateDatabase?

    init() {
        checkPermissionsAndRefresh()
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

    /// Export all Apple Notes to markdown files
    func exportAllAppleNotes(to baseURL: URL) {
        guard let reader = notesReader else {
            lastError = "Notes reader not available"
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let notes = try reader.getAllNotes()
                var exportedCount = 0
                var skippedCount = 0

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
                    let filename = note.safeFilename + ".md"
                    let filePath = folderPath.appendingPathComponent(filename)

                    // Get note content - need to parse it from rawData
                    let plaintext: String
                    if let text = note.plaintext, !text.isEmpty {
                        plaintext = text
                    } else if let data = note.rawData {
                        // Parse protobuf content
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
                    md += "---\n\n"
                    md += plaintext

                    try md.write(to: filePath, atomically: true, encoding: .utf8)
                    exportedCount += 1
                }

                DispatchQueue.main.async {
                    self?.isLoading = false
                    if skippedCount > 0 {
                        self?.lastError = "Exported \(exportedCount) notes, skipped \(skippedCount) (locked/empty)"
                    } else {
                        self?.lastError = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.lastError = "Export failed: \(error.localizedDescription)"
                }
            }
        }
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

    static func install() {
        // Use pickle CLI to install the daemon
        let task = Process()
        task.launchPath = "/usr/local/bin/pickle"
        task.arguments = ["install"]
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
