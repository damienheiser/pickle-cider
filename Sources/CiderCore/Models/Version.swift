import Foundation

/// Represents a saved version of a note (for Pickle)
public struct NoteVersion: Codable, Identifiable, Sendable {
    public let id: Int64
    public let noteID: Int64
    public let noteUUID: String
    public let versionNumber: Int
    public let contentHash: String
    public let storagePath: String
    public let plaintextPreview: String?
    public let characterCount: Int
    public let wordCount: Int
    public let changeSummary: String?
    public let appleModificationTime: Date?
    public let capturedAt: Date

    public init(
        id: Int64,
        noteID: Int64,
        noteUUID: String,
        versionNumber: Int,
        contentHash: String,
        storagePath: String,
        plaintextPreview: String?,
        characterCount: Int,
        wordCount: Int,
        changeSummary: String?,
        appleModificationTime: Date?,
        capturedAt: Date
    ) {
        self.id = id
        self.noteID = noteID
        self.noteUUID = noteUUID
        self.versionNumber = versionNumber
        self.contentHash = contentHash
        self.storagePath = storagePath
        self.plaintextPreview = plaintextPreview
        self.characterCount = characterCount
        self.wordCount = wordCount
        self.changeSummary = changeSummary
        self.appleModificationTime = appleModificationTime
        self.capturedAt = capturedAt
    }

    /// Generate a short display description
    public var displayDescription: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let dateStr = dateFormatter.string(from: capturedAt)
        let summary = changeSummary ?? "\(characterCount) chars"

        return "v\(versionNumber) - \(dateStr) (\(summary))"
    }
}

/// Content stored in a version file
public struct VersionContent: Codable, Sendable {
    public let version: Int
    public let noteUUID: String
    public let appleNoteID: String?
    public let title: String
    public let folderPath: String?
    public let capturedAt: Date
    public let appleModificationDate: Date?
    public let content: VersionContentData
    public let metadata: VersionMetadata

    public init(
        noteUUID: String,
        appleNoteID: String?,
        title: String,
        folderPath: String?,
        capturedAt: Date,
        appleModificationDate: Date?,
        plaintext: String,
        html: String?,
        rawProtobuf: Data?
    ) {
        self.version = 1
        self.noteUUID = noteUUID
        self.appleNoteID = appleNoteID
        self.title = title
        self.folderPath = folderPath
        self.capturedAt = capturedAt
        self.appleModificationDate = appleModificationDate
        self.content = VersionContentData(
            plaintext: plaintext,
            html: html,
            protobufBase64: rawProtobuf?.base64EncodedString()
        )
        self.metadata = VersionMetadata(
            characterCount: plaintext.count,
            wordCount: plaintext.split(separator: " ").count,
            hasAttachments: false,
            isPasswordProtected: false
        )
    }
}

public struct VersionContentData: Codable, Sendable {
    public let plaintext: String
    public let html: String?
    public let protobufBase64: String?
}

public struct VersionMetadata: Codable, Sendable {
    public let characterCount: Int
    public let wordCount: Int
    public let hasAttachments: Bool
    public let isPasswordProtected: Bool
}

/// Sync state for a note (for Cider)
public struct SyncState: Codable, Sendable {
    public let localPath: String
    public let noteUUID: String?
    public let noteID: String?
    public let localHash: String?
    public let remoteHash: String?
    public let syncStatus: SyncStatus
    public let lastSync: Date?

    public enum SyncStatus: String, Codable, Sendable {
        case synced
        case localModified = "local_modified"
        case remoteModified = "remote_modified"
        case conflict
        case newLocal = "new_local"
        case newRemote = "new_remote"
        case deletedLocal = "deleted_local"
        case deletedRemote = "deleted_remote"
    }
}

/// Monitor state for change detection (for Pickle)
public struct MonitorState: Codable, Sendable {
    public let noteUUID: String
    public let lastKnownHash: String
    public let lastModificationDate: Date
    public let lastChecked: Date

    public init(noteUUID: String, lastKnownHash: String, lastModificationDate: Date) {
        self.noteUUID = noteUUID
        self.lastKnownHash = lastKnownHash
        self.lastModificationDate = lastModificationDate
        self.lastChecked = Date()
    }
}
