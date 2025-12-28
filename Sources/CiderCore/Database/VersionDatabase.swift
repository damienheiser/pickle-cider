import Foundation
import GRDB
import Compression

/// Database for tracking Pickle version history
public final class VersionDatabase: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let lock = NSLock()

    /// Default database path
    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pickle/versions.db")
    }

    /// Default version storage directory
    public static var defaultStoragePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pickle/versions")
    }

    public let storagePath: URL

    public init(path: URL = VersionDatabase.defaultPath, storagePath: URL = VersionDatabase.defaultStoragePath) throws {
        self.storagePath = storagePath

        // Ensure directories exist
        let dbDirectory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storagePath, withIntermediateDirectories: true)

        var config = Configuration()
        config.label = "CiderCore.VersionDatabase"

        self.dbQueue = try DatabaseQueue(path: path.path, configuration: config)

        try migrate()
    }

    // MARK: - Migration

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Notes tracking table
            try db.create(table: "notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("title", .text)
                t.column("folder_path", .text)
                t.column("is_deleted", .boolean).notNull().defaults(to: false)
                t.column("created_at", .integer).notNull().defaults(sql: "strftime('%s', 'now')")
                t.column("updated_at", .integer).notNull().defaults(sql: "strftime('%s', 'now')")
            }

            // Versions table
            try db.create(table: "versions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("note_id", .integer).notNull().references("notes", onDelete: .cascade)
                t.column("version_number", .integer).notNull()
                t.column("content_hash", .text).notNull()
                t.column("storage_path", .text).notNull()
                t.column("plaintext_preview", .text)
                t.column("character_count", .integer).notNull().defaults(to: 0)
                t.column("word_count", .integer).notNull().defaults(to: 0)
                t.column("change_summary", .text)
                t.column("apple_mtime", .integer)
                t.column("captured_at", .integer).notNull().defaults(sql: "strftime('%s', 'now')")

                t.uniqueKey(["note_id", "version_number"])
            }

            // Monitor state for change detection
            try db.create(table: "monitor_state") { t in
                t.column("note_uuid", .text).primaryKey()
                t.column("last_hash", .text).notNull()
                t.column("last_mtime", .integer).notNull()
                t.column("last_checked", .integer).notNull()
            }

            // Indexes
            try db.create(index: "idx_versions_note", on: "versions", columns: ["note_id"])
            try db.create(index: "idx_versions_captured", on: "versions", columns: ["captured_at"])
            try db.create(index: "idx_notes_uuid", on: "notes", columns: ["uuid"])
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Notes Operations

    /// Get or create a note record
    public func getOrCreateNote(uuid: String, title: String?, folderPath: String?) throws -> NoteRecord {
        lock.lock()
        defer { lock.unlock() }

        return try dbQueue.write { db in
            if let existing = try NoteRecord.filter(Column("uuid") == uuid).fetchOne(db) {
                // Update title/folder if changed
                var updated = existing
                updated.title = title
                updated.folderPath = folderPath
                updated.updatedAt = Int64(Date().timeIntervalSince1970)
                try updated.update(db)
                return updated
            } else {
                var record = NoteRecord(uuid: uuid, title: title, folderPath: folderPath)
                try record.insert(db)
                return record
            }
        }
    }

    /// Get note by UUID
    public func getNote(uuid: String) throws -> NoteRecord? {
        try dbQueue.read { db in
            try NoteRecord.filter(Column("uuid") == uuid).fetchOne(db)
        }
    }

    /// Get note by ID
    public func getNote(id: Int64) throws -> NoteRecord? {
        try dbQueue.read { db in
            try NoteRecord.filter(key: id).fetchOne(db)
        }
    }

    /// Get all tracked notes
    public func getAllNotes(includeDeleted: Bool = false) throws -> [NoteRecord] {
        try dbQueue.read { db in
            if includeDeleted {
                return try NoteRecord.fetchAll(db)
            } else {
                return try NoteRecord.filter(Column("is_deleted") == false).fetchAll(db)
            }
        }
    }

    /// Mark note as deleted
    public func markNoteDeleted(uuid: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE notes SET is_deleted = 1, updated_at = strftime('%s', 'now') WHERE uuid = ?",
                arguments: [uuid]
            )
        }
    }

    // MARK: - Version Operations

    /// Save a new version
    public func saveVersion(noteID: Int64, content: VersionContent) throws -> VersionRecord {
        lock.lock()
        defer { lock.unlock() }

        return try dbQueue.write { db in
            // Get next version number
            let maxVersion = try Int.fetchOne(
                db,
                sql: "SELECT MAX(version_number) FROM versions WHERE note_id = ?",
                arguments: [noteID]
            ) ?? 0
            let versionNumber = maxVersion + 1

            // Calculate content hash
            let contentHash = content.content.plaintext.sha256Hash

            // Generate storage path
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy/MM/dd"
            let datePath = dateFormatter.string(from: content.capturedAt)
            let filename = "\(content.noteUUID)-v\(String(format: "%03d", versionNumber)).json.gz"
            let relativePath = "\(datePath)/\(filename)"
            let fullPath = storagePath.appendingPathComponent(relativePath)

            // Save content to file
            try saveVersionContent(content, to: fullPath)

            // Create record
            var record = VersionRecord(
                noteID: noteID,
                versionNumber: versionNumber,
                contentHash: contentHash,
                storagePath: relativePath,
                plaintextPreview: String(content.content.plaintext.prefix(500)),
                characterCount: content.metadata.characterCount,
                wordCount: content.metadata.wordCount,
                changeSummary: nil,
                appleMtime: content.appleModificationDate.map { Int64($0.timeIntervalSince1970) }
            )

            try record.insert(db)
            return record
        }
    }

    private func saveVersionContent(_ content: VersionContent, to path: URL) throws {
        // Ensure directory exists
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(content)

        // Compress with gzip
        let compressedData = try gzip(jsonData)

        // Write to file
        try compressedData.write(to: path)
    }

    private func gzip(_ data: Data) throws -> Data {
        let bufferSize = max(data.count * 2, 64)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                bufferSize,
                sourcePtr.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else {
            throw VersionDatabaseError.compressionFailed
        }

        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    /// Get all versions for a note
    public func getVersions(noteID: Int64) throws -> [VersionRecord] {
        try dbQueue.read { db in
            try VersionRecord
                .filter(Column("note_id") == noteID)
                .order(Column("version_number").desc)
                .fetchAll(db)
        }
    }

    /// Get a specific version
    public func getVersion(id: Int64) throws -> VersionRecord? {
        try dbQueue.read { db in
            try VersionRecord.filter(key: id).fetchOne(db)
        }
    }

    /// Get latest version for a note
    public func getLatestVersion(noteID: Int64) throws -> VersionRecord? {
        try dbQueue.read { db in
            try VersionRecord
                .filter(Column("note_id") == noteID)
                .order(Column("version_number").desc)
                .fetchOne(db)
        }
    }

    /// Load version content from file
    public func loadVersionContent(storagePath: String) throws -> VersionContent {
        let fullPath = self.storagePath.appendingPathComponent(storagePath)
        let compressedData = try Data(contentsOf: fullPath)

        // Decompress
        let decompressedData = try gunzip(compressedData)

        // Decode JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VersionContent.self, from: decompressedData)
    }

    private func gunzip(_ data: Data) throws -> Data {
        let bufferSize = data.count * 10 // Estimate decompressed size
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Int in
            guard let sourcePtr = sourceBuffer.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                sourcePtr.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw VersionDatabaseError.decompressionFailed
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }

    /// Delete old versions (keep most recent N)
    public func pruneVersions(noteID: Int64, keepCount: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        try dbQueue.write { db in
            // Get versions to delete
            let versionsToDelete = try VersionRecord
                .filter(Column("note_id") == noteID)
                .order(Column("version_number").desc)
                .limit(1000, offset: keepCount)
                .fetchAll(db)

            for version in versionsToDelete {
                // Delete file
                let filePath = storagePath.appendingPathComponent(version.storagePath)
                try? FileManager.default.removeItem(at: filePath)

                // Delete record
                try version.delete(db)
            }
        }
    }

    // MARK: - Monitor State

    /// Get monitor state for a note
    public func getMonitorState(uuid: String) throws -> MonitorStateRecord? {
        try dbQueue.read { db in
            try MonitorStateRecord.filter(key: uuid).fetchOne(db)
        }
    }

    /// Update monitor state
    public func updateMonitorState(uuid: String, hash: String, mtime: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        try dbQueue.write { db in
            let record = MonitorStateRecord(
                noteUUID: uuid,
                lastHash: hash,
                lastMtime: Int64(mtime.timeIntervalSince1970),
                lastChecked: Int64(Date().timeIntervalSince1970)
            )
            try record.save(db)
        }
    }

    /// Get all monitor states
    public func getAllMonitorStates() throws -> [MonitorStateRecord] {
        try dbQueue.read { db in
            try MonitorStateRecord.fetchAll(db)
        }
    }

    // MARK: - Statistics

    /// Get version statistics
    public func getStatistics() throws -> VersionStatistics {
        try dbQueue.read { db in
            let noteCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE is_deleted = 0") ?? 0
            let versionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM versions") ?? 0
            let oldestCapture = try Int64.fetchOne(db, sql: "SELECT MIN(captured_at) FROM versions")
            let newestCapture = try Int64.fetchOne(db, sql: "SELECT MAX(captured_at) FROM versions")

            return VersionStatistics(
                trackedNotes: noteCount,
                totalVersions: versionCount,
                oldestVersion: oldestCapture.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                newestVersion: newestCapture.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
    }
}

// MARK: - Database Records

public struct NoteRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "notes"

    public var id: Int64?
    public var uuid: String
    public var title: String?
    public var folderPath: String?
    public var isDeleted: Bool
    public var createdAt: Int64?
    public var updatedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case title
        case folderPath = "folder_path"
        case isDeleted = "is_deleted"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(uuid: String, title: String?, folderPath: String?) {
        self.uuid = uuid
        self.title = title
        self.folderPath = folderPath
        self.isDeleted = false
    }
}

public struct VersionRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "versions"

    public var id: Int64?
    public var noteID: Int64
    public var versionNumber: Int
    public var contentHash: String
    public var storagePath: String
    public var plaintextPreview: String?
    public var characterCount: Int
    public var wordCount: Int
    public var changeSummary: String?
    public var appleMtime: Int64?
    public var capturedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case noteID = "note_id"
        case versionNumber = "version_number"
        case contentHash = "content_hash"
        case storagePath = "storage_path"
        case plaintextPreview = "plaintext_preview"
        case characterCount = "character_count"
        case wordCount = "word_count"
        case changeSummary = "change_summary"
        case appleMtime = "apple_mtime"
        case capturedAt = "captured_at"
    }

    public init(
        noteID: Int64,
        versionNumber: Int,
        contentHash: String,
        storagePath: String,
        plaintextPreview: String?,
        characterCount: Int,
        wordCount: Int,
        changeSummary: String?,
        appleMtime: Int64?
    ) {
        self.noteID = noteID
        self.versionNumber = versionNumber
        self.contentHash = contentHash
        self.storagePath = storagePath
        self.plaintextPreview = plaintextPreview
        self.characterCount = characterCount
        self.wordCount = wordCount
        self.changeSummary = changeSummary
        self.appleMtime = appleMtime
    }
}

public struct MonitorStateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "monitor_state"

    public var noteUUID: String
    public var lastHash: String
    public var lastMtime: Int64
    public var lastChecked: Int64

    enum CodingKeys: String, CodingKey {
        case noteUUID = "note_uuid"
        case lastHash = "last_hash"
        case lastMtime = "last_mtime"
        case lastChecked = "last_checked"
    }
}

public struct VersionStatistics: Sendable {
    public let trackedNotes: Int
    public let totalVersions: Int
    public let oldestVersion: Date?
    public let newestVersion: Date?
}

// MARK: - Errors

public enum VersionDatabaseError: Error, LocalizedError {
    case compressionFailed
    case decompressionFailed
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress version data"
        case .decompressionFailed:
            return "Failed to decompress version data"
        case .fileNotFound(let path):
            return "Version file not found: \(path)"
        }
    }
}

// MARK: - String Extensions

extension String {
    public var sha256Hash: String {
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: 32)

        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// CommonCrypto import for SHA256
import CommonCrypto
