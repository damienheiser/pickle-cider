import SwiftUI
import CiderCore

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

    private var notesReader: NotesReader?
    private var versionDB: VersionDatabase?
    private var stateDB: StateDatabase?

    init() {
        refresh()
    }

    func refresh() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                // Initialize readers
                let reader = try NotesReader()
                self?.notesReader = reader

                let noteCount = try reader.getNoteCount()
                let folderCount = try reader.getFolderCount()

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
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
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

    static func start() {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["start", plistLabel]
        try? task.run()
        task.waitUntilExit()
    }

    static func stop() {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["stop", plistLabel]
        try? task.run()
        task.waitUntilExit()
    }
}
