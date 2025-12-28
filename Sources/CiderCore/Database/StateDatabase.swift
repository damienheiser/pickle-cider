import Foundation
import GRDB

/// Database for tracking Cider sync state
public final class StateDatabase: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let lock = NSLock()

    /// Default database path
    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cider/state.db")
    }

    public init(path: URL = StateDatabase.defaultPath) throws {
        // Ensure directory exists
        let directory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var config = Configuration()
        config.label = "CiderCore.StateDatabase"

        self.dbQueue = try DatabaseQueue(path: path.path, configuration: config)

        try migrate()
    }

    // MARK: - Migration

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Sync state table
            try db.create(table: "sync_state") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("local_path", .text).notNull().unique()
                t.column("note_uuid", .text)
                t.column("note_id", .text)
                t.column("folder_path", .text).notNull()
                t.column("local_hash", .text)
                t.column("remote_hash", .text)
                t.column("local_mtime", .integer)
                t.column("remote_mtime", .integer)
                t.column("sync_status", .text).notNull().defaults(to: "new_local")
                t.column("last_sync", .integer)
                t.column("created_at", .integer).notNull().defaults(sql: "strftime('%s', 'now')")
                t.column("updated_at", .integer).notNull().defaults(sql: "strftime('%s', 'now')")
            }

            // Folder mapping table
            try db.create(table: "folder_mapping") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("local_path", .text).notNull().unique()
                t.column("note_folder_uuid", .text)
                t.column("note_folder_name", .text).notNull()
                t.column("created_at", .integer).notNull().defaults(sql: "strftime('%s', 'now')")
            }

            // Sync log for debugging
            try db.create(table: "sync_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("operation", .text).notNull()
                t.column("local_path", .text)
                t.column("note_uuid", .text)
                t.column("status", .text).notNull()
                t.column("error_message", .text)
                t.column("timestamp", .integer).notNull().defaults(sql: "strftime('%s', 'now')")
            }

            // Indexes
            try db.create(index: "idx_sync_state_uuid", on: "sync_state", columns: ["note_uuid"])
            try db.create(index: "idx_sync_state_status", on: "sync_state", columns: ["sync_status"])
            try db.create(index: "idx_sync_log_timestamp", on: "sync_log", columns: ["timestamp"])
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Sync State Operations

    /// Get sync state for a local file path
    public func getSyncState(localPath: String) throws -> SyncStateRecord? {
        try dbQueue.read { db in
            try SyncStateRecord.filter(Column("local_path") == localPath).fetchOne(db)
        }
    }

    /// Get sync state by note UUID
    public func getSyncState(noteUUID: String) throws -> SyncStateRecord? {
        try dbQueue.read { db in
            try SyncStateRecord.filter(Column("note_uuid") == noteUUID).fetchOne(db)
        }
    }

    /// Get all sync states
    public func getAllSyncStates() throws -> [SyncStateRecord] {
        try dbQueue.read { db in
            try SyncStateRecord.fetchAll(db)
        }
    }

    /// Get sync states by status
    public func getSyncStates(status: String) throws -> [SyncStateRecord] {
        try dbQueue.read { db in
            try SyncStateRecord.filter(Column("sync_status") == status).fetchAll(db)
        }
    }

    /// Create or update sync state
    public func upsertSyncState(_ state: SyncStateRecord) throws {
        lock.lock()
        defer { lock.unlock() }

        try dbQueue.write { db in
            var record = state
            record.updatedAt = Int64(Date().timeIntervalSince1970)
            try record.save(db)
        }
    }

    /// Delete sync state for a path
    public func deleteSyncState(localPath: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM sync_state WHERE local_path = ?", arguments: [localPath])
        }
    }

    /// Update sync status
    public func updateSyncStatus(localPath: String, status: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sync_state SET sync_status = ?, updated_at = strftime('%s', 'now') WHERE local_path = ?",
                arguments: [status, localPath]
            )
        }
    }

    // MARK: - Folder Mapping

    /// Get folder mapping
    public func getFolderMapping(localPath: String) throws -> FolderMappingRecord? {
        try dbQueue.read { db in
            try FolderMappingRecord.filter(Column("local_path") == localPath).fetchOne(db)
        }
    }

    /// Create or update folder mapping
    public func upsertFolderMapping(_ mapping: FolderMappingRecord) throws {
        lock.lock()
        defer { lock.unlock() }

        try dbQueue.write { db in
            try mapping.save(db)
        }
    }

    // MARK: - Sync Log

    /// Log a sync operation
    public func logOperation(operation: String, localPath: String?, noteUUID: String?, status: String, error: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }

        try dbQueue.write { db in
            let log = SyncLogRecord(
                operation: operation,
                localPath: localPath,
                noteUUID: noteUUID,
                status: status,
                errorMessage: error
            )
            try log.insert(db)
        }
    }

    /// Get recent log entries
    public func getRecentLogs(limit: Int = 50) throws -> [SyncLogRecord] {
        try dbQueue.read { db in
            try SyncLogRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Statistics

    /// Get sync statistics
    public func getStatistics() throws -> SyncStatistics {
        try dbQueue.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_state") ?? 0
            let synced = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_state WHERE sync_status = 'synced'") ?? 0
            let pending = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_state WHERE sync_status != 'synced'") ?? 0
            let conflicts = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_state WHERE sync_status = 'conflict'") ?? 0

            return SyncStatistics(
                totalFiles: total,
                syncedFiles: synced,
                pendingFiles: pending,
                conflicts: conflicts
            )
        }
    }
}

// MARK: - Database Records

public struct SyncStateRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "sync_state"

    public var id: Int64?
    public var localPath: String
    public var noteUUID: String?
    public var noteID: String?
    public var folderPath: String
    public var localHash: String?
    public var remoteHash: String?
    public var localMtime: Int64?
    public var remoteMtime: Int64?
    public var syncStatus: String
    public var lastSync: Int64?
    public var createdAt: Int64?
    public var updatedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case localPath = "local_path"
        case noteUUID = "note_uuid"
        case noteID = "note_id"
        case folderPath = "folder_path"
        case localHash = "local_hash"
        case remoteHash = "remote_hash"
        case localMtime = "local_mtime"
        case remoteMtime = "remote_mtime"
        case syncStatus = "sync_status"
        case lastSync = "last_sync"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: Int64? = nil,
        localPath: String,
        noteUUID: String? = nil,
        noteID: String? = nil,
        folderPath: String,
        localHash: String? = nil,
        remoteHash: String? = nil,
        localMtime: Int64? = nil,
        remoteMtime: Int64? = nil,
        syncStatus: String = "new_local",
        lastSync: Int64? = nil
    ) {
        self.id = id
        self.localPath = localPath
        self.noteUUID = noteUUID
        self.noteID = noteID
        self.folderPath = folderPath
        self.localHash = localHash
        self.remoteHash = remoteHash
        self.localMtime = localMtime
        self.remoteMtime = remoteMtime
        self.syncStatus = syncStatus
        self.lastSync = lastSync
    }
}

public struct FolderMappingRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "folder_mapping"

    public var id: Int64?
    public var localPath: String
    public var noteFolderUUID: String?
    public var noteFolderName: String
    public var createdAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case localPath = "local_path"
        case noteFolderUUID = "note_folder_uuid"
        case noteFolderName = "note_folder_name"
        case createdAt = "created_at"
    }

    public init(localPath: String, noteFolderUUID: String?, noteFolderName: String) {
        self.localPath = localPath
        self.noteFolderUUID = noteFolderUUID
        self.noteFolderName = noteFolderName
    }
}

public struct SyncLogRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "sync_log"

    public var id: Int64?
    public var operation: String
    public var localPath: String?
    public var noteUUID: String?
    public var status: String
    public var errorMessage: String?
    public var timestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case operation
        case localPath = "local_path"
        case noteUUID = "note_uuid"
        case status
        case errorMessage = "error_message"
        case timestamp
    }

    public init(operation: String, localPath: String?, noteUUID: String?, status: String, errorMessage: String? = nil) {
        self.operation = operation
        self.localPath = localPath
        self.noteUUID = noteUUID
        self.status = status
        self.errorMessage = errorMessage
    }
}

public struct SyncStatistics: Sendable {
    public let totalFiles: Int
    public let syncedFiles: Int
    public let pendingFiles: Int
    public let conflicts: Int
}
