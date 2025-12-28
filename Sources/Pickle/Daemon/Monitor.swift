import Foundation
import CiderCore

/// The Pickle monitoring daemon that watches for Apple Notes changes
public final class PickleMonitor {
    private let reader: NotesReader
    private let parser: ProtobufParser
    private let versionDB: VersionDatabase
    private let interval: TimeInterval
    private let verbose: Bool

    private var isRunning = false
    private var lastCheck: Date?

    public init(interval: TimeInterval, verbose: Bool = false) throws {
        self.reader = try NotesReader()
        self.parser = ProtobufParser()
        self.versionDB = try VersionDatabase()
        self.interval = interval
        self.verbose = verbose
    }

    /// Start the monitoring loop
    public func start() {
        isRunning = true

        log("Pickle daemon started")
        log("  Interval: \(Int(interval)) seconds")
        log("  Database: ~/.pickle/versions.db")

        // Initial scan
        do {
            try performCheck()
        } catch {
            log("Initial scan failed: \(error.localizedDescription)")
        }

        // Main loop
        while isRunning {
            Thread.sleep(forTimeInterval: interval)

            do {
                try performCheck()
            } catch {
                log("Check failed: \(error.localizedDescription)")
            }
        }

        log("Pickle daemon stopped")
    }

    /// Stop the monitoring loop
    public func stop() {
        isRunning = false
    }

    /// Perform a single check for changes
    private func performCheck() throws {
        let startTime = Date()

        // Get all notes from Apple Notes
        let currentNotes = try reader.getAllNotes()
        let currentMap = Dictionary(uniqueKeysWithValues: currentNotes.compactMap { note -> (String, Note)? in
            return (note.uuid, note)
        })

        // Get known monitor states
        let knownStates = try versionDB.getAllMonitorStates()
        let knownMap = Dictionary(uniqueKeysWithValues: knownStates.map { ($0.noteUUID, $0) })

        var changesDetected = 0
        var newNotes = 0
        var deletedNotes = 0

        // Check for new and modified notes
        for (uuid, note) in currentMap {
            // Skip password-protected notes
            if note.isPasswordProtected {
                continue
            }

            // Parse note content
            var plaintext = ""
            if let rawData = note.rawData {
                if let parsed = try? parser.parseNoteData(rawData) {
                    plaintext = parsed.plaintext
                }
            }

            let currentHash = computeHash(plaintext)
            let modTime = note.modificationDate ?? Date()

            if let known = knownMap[uuid] {
                // Check if changed
                if currentHash != known.lastHash {
                    // Note was modified - save version
                    try saveVersion(note: note, plaintext: plaintext)
                    try versionDB.updateMonitorState(uuid: uuid, hash: currentHash, mtime: modTime)
                    changesDetected += 1
                    logVerbose("Changed: \(note.displayTitle)")
                }
            } else {
                // New note - save initial version
                try saveVersion(note: note, plaintext: plaintext)
                try versionDB.updateMonitorState(uuid: uuid, hash: currentHash, mtime: modTime)
                newNotes += 1
                logVerbose("New: \(note.displayTitle)")
            }
        }

        // Check for deleted notes
        for (uuid, _) in knownMap {
            if currentMap[uuid] == nil {
                try versionDB.markNoteDeleted(uuid: uuid)
                deletedNotes += 1
                logVerbose("Deleted: \(uuid)")
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        lastCheck = Date()

        if changesDetected > 0 || newNotes > 0 || deletedNotes > 0 || verbose {
            log("Check complete: \(currentNotes.count) notes, \(changesDetected) changed, \(newNotes) new, \(deletedNotes) deleted (\(String(format: "%.2f", elapsed))s)")
        }
    }

    /// Save a version of a note
    private func saveVersion(note: Note, plaintext: String) throws {
        // Get or create note record
        let noteRecord = try versionDB.getOrCreateNote(
            uuid: note.uuid,
            title: note.displayTitle,
            folderPath: note.folderName
        )

        guard let noteID = noteRecord.id else { return }

        // Check if content actually changed from last version
        if let lastVersion = try versionDB.getLatestVersion(noteID: noteID) {
            let lastContent = try? versionDB.loadVersionContent(storagePath: lastVersion.storagePath)
            if lastContent?.content.plaintext == plaintext {
                // No actual change
                return
            }
        }

        // Create version content
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

        // Save version
        let version = try versionDB.saveVersion(noteID: noteID, content: content)

        log("Saved version \(version.versionNumber) of '\(note.displayTitle)'")
    }

    /// Compute SHA-256 hash of content
    private func computeHash(_ text: String) -> String {
        text.sha256Hash
    }

    /// Log a message
    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }

    /// Log a verbose message
    private func logVerbose(_ message: String) {
        if verbose {
            log("  \(message)")
        }
    }
}
