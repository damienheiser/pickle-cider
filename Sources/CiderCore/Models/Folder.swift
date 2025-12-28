import Foundation
import GRDB

/// Represents an Apple Notes folder
public struct Folder: Codable, FetchableRecord, Identifiable, Sendable {
    public let id: Int64
    public let uuid: String
    public let name: String
    public let parentID: Int64?
    public let folderType: FolderType
    public let noteCount: Int

    public enum FolderType: Int, Codable, Sendable {
        case normal = 0
        case trash = 1
        case locked = 2
        case smart = 3

        public var isSpecial: Bool {
            self != .normal
        }
    }

    public init(
        id: Int64,
        uuid: String,
        name: String,
        parentID: Int64?,
        folderType: FolderType,
        noteCount: Int
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.parentID = parentID
        self.folderType = folderType
        self.noteCount = noteCount
    }

    /// Initialize from a database row
    public init(row: Row) throws {
        id = row["id"]
        uuid = row["uuid"]
        name = row["name"] ?? "Untitled Folder"
        parentID = row["parentID"]

        let typeRaw: Int = row["folderType"] ?? 0
        folderType = FolderType(rawValue: typeRaw) ?? .normal

        noteCount = row["noteCount"] ?? 0
    }

    /// Sanitized folder name for filesystem
    public var safeName: String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Represents a folder tree structure
public struct FolderTree: Sendable {
    public let folder: Folder
    public var children: [FolderTree]
    public var notes: [Note]

    public init(folder: Folder, children: [FolderTree] = [], notes: [Note] = []) {
        self.folder = folder
        self.children = children
        self.notes = notes
    }

    /// Get the full path from root to this folder
    public func path(parents: [String] = []) -> String {
        let components = parents + [folder.safeName]
        return components.joined(separator: "/")
    }
}
