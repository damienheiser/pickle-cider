import Foundation
import GRDB

/// Reads notes directly from the Apple Notes SQLite database
public final class NotesReader: Sendable {
    /// Path to the Apple Notes database
    public static let databasePath: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
    }()

    private let dbQueue: DatabaseQueue

    /// Initialize with the default Apple Notes database
    public init() throws {
        var config = Configuration()
        config.readonly = true
        config.label = "CiderCore.NotesReader"

        guard FileManager.default.fileExists(atPath: Self.databasePath.path) else {
            throw NotesReaderError.databaseNotFound(Self.databasePath.path)
        }

        self.dbQueue = try DatabaseQueue(path: Self.databasePath.path, configuration: config)
    }

    /// Initialize with a custom database path (for testing)
    public init(databasePath: URL) throws {
        var config = Configuration()
        config.readonly = true
        config.label = "CiderCore.NotesReader"

        self.dbQueue = try DatabaseQueue(path: databasePath.path, configuration: config)
    }

    // MARK: - Read Notes

    /// Fetch all notes from the database
    public func getAllNotes() throws -> [Note] {
        try dbQueue.read { db in
            try fetchNotes(db: db, whereClause: "1=1")
        }
    }

    /// Fetch notes from a specific folder
    public func getNotes(inFolder folderID: Int64) throws -> [Note] {
        try dbQueue.read { db in
            try fetchNotes(db: db, whereClause: "z.ZFOLDER = \(folderID)")
        }
    }

    /// Fetch a single note by UUID
    public func getNote(uuid: String) throws -> Note? {
        try dbQueue.read { db in
            let notes = try fetchNotes(db: db, whereClause: "z.ZIDENTIFIER = '\(uuid.escapedForSQL)'")
            return notes.first
        }
    }

    /// Fetch a single note by title (first match)
    public func getNote(title: String) throws -> Note? {
        try dbQueue.read { db in
            let notes = try fetchNotes(db: db, whereClause: "z.ZTITLE1 = '\(title.escapedForSQL)'")
            return notes.first
        }
    }

    private func fetchNotes(db: Database, whereClause: String) throws -> [Note] {
        let sql = """
            SELECT
                z.Z_PK as id,
                z.ZIDENTIFIER as uuid,
                z.ZTITLE1 as title,
                z.ZFOLDER as folderID,
                f.ZTITLE2 as folderName,
                z.ZMODIFICATIONDATE1 as modificationDate,
                z.ZCREATIONDATE3 as creationDate,
                z.ZISPASSWORDPROTECTED as isLocked,
                d.ZDATA as data
            FROM ZICCLOUDSYNCINGOBJECT z
            LEFT JOIN ZICNOTEDATA d ON d.ZNOTE = z.Z_PK
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON f.Z_PK = z.ZFOLDER AND f.Z_ENT = 15
            WHERE z.Z_ENT = 12
              AND (z.ZMARKEDFORDELETION IS NULL OR z.ZMARKEDFORDELETION = 0)
              AND \(whereClause)
            ORDER BY z.ZMODIFICATIONDATE1 DESC
        """

        let rows = try Row.fetchAll(db, sql: sql)
        return try rows.map { try Note(row: $0) }
    }

    // MARK: - Read Folders

    /// Fetch all folders from the database
    public func getAllFolders() throws -> [Folder] {
        try dbQueue.read { db in
            let sql = """
                SELECT
                    z.Z_PK as id,
                    z.ZIDENTIFIER as uuid,
                    z.ZTITLE2 as name,
                    z.ZPARENT as parentID,
                    z.ZFOLDERTYPE as folderType,
                    (SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT n
                     WHERE n.ZFOLDER = z.Z_PK AND n.Z_ENT = 12
                     AND (n.ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION = 0)) as noteCount
                FROM ZICCLOUDSYNCINGOBJECT z
                WHERE z.Z_ENT = 15
                  AND (z.ZMARKEDFORDELETION IS NULL OR z.ZMARKEDFORDELETION = 0)
                ORDER BY z.ZTITLE2
            """

            let rows = try Row.fetchAll(db, sql: sql)
            return try rows.map { try Folder(row: $0) }
        }
    }

    /// Fetch a folder by name
    public func getFolder(name: String) throws -> Folder? {
        try dbQueue.read { db in
            let sql = """
                SELECT
                    z.Z_PK as id,
                    z.ZIDENTIFIER as uuid,
                    z.ZTITLE2 as name,
                    z.ZPARENT as parentID,
                    z.ZFOLDERTYPE as folderType,
                    0 as noteCount
                FROM ZICCLOUDSYNCINGOBJECT z
                WHERE z.Z_ENT = 15
                  AND z.ZTITLE2 = '\(name.escapedForSQL)'
                  AND (z.ZMARKEDFORDELETION IS NULL OR z.ZMARKEDFORDELETION = 0)
                LIMIT 1
            """

            let rows = try Row.fetchAll(db, sql: sql)
            return rows.first.map { try? Folder(row: $0) } ?? nil
        }
    }

    /// Build a folder tree structure
    public func getFolderTree() throws -> [FolderTree] {
        let folders = try getAllFolders()
        let notes = try getAllNotes()

        // Group notes by folder
        var notesByFolder: [Int64: [Note]] = [:]
        for note in notes {
            if let folderID = note.folderID {
                notesByFolder[folderID, default: []].append(note)
            }
        }

        // Build tree recursively
        func buildTree(parentID: Int64?) -> [FolderTree] {
            folders
                .filter { $0.parentID == parentID }
                .map { folder in
                    FolderTree(
                        folder: folder,
                        children: buildTree(parentID: folder.id),
                        notes: notesByFolder[folder.id] ?? []
                    )
                }
        }

        return buildTree(parentID: nil)
    }

    // MARK: - Statistics

    /// Get total note count
    public func getNoteCount() throws -> Int {
        try dbQueue.read { db in
            let sql = """
                SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT
                WHERE Z_ENT = 12
                  AND (ZMARKEDFORDELETION IS NULL OR ZMARKEDFORDELETION = 0)
            """
            return try Int.fetchOne(db, sql: sql) ?? 0
        }
    }

    /// Get total folder count
    public func getFolderCount() throws -> Int {
        try dbQueue.read { db in
            let sql = """
                SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT
                WHERE Z_ENT = 15
                  AND (ZMARKEDFORDELETION IS NULL OR ZMARKEDFORDELETION = 0)
            """
            return try Int.fetchOne(db, sql: sql) ?? 0
        }
    }
}

// MARK: - Errors

public enum NotesReaderError: Error, LocalizedError {
    case databaseNotFound(String)
    case queryFailed(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .databaseNotFound(let path):
            return "Apple Notes database not found at: \(path). Make sure you have Full Disk Access enabled."
        case .queryFailed(let message):
            return "Database query failed: \(message)"
        case .parseError(let message):
            return "Failed to parse note data: \(message)"
        }
    }
}

// MARK: - String Extensions

extension String {
    /// Escape single quotes for SQL
    var escapedForSQL: String {
        self.replacingOccurrences(of: "'", with: "''")
    }
}
