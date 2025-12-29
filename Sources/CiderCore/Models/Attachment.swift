import Foundation
import GRDB

/// Represents an attachment in Apple Notes (image, table, drawing, etc.)
public struct NoteAttachment: Codable, FetchableRecord, Identifiable, Sendable {
    public let id: Int64
    public let uuid: String
    public let noteID: Int64
    public let typeUTI: String
    public let mediaUUID: String?
    public let filename: String?
    public let fileSize: Int64?
    public let summary: String?  // For tables, contains the text content

    /// The type of attachment
    public var attachmentType: AttachmentType {
        switch typeUTI {
        case "com.apple.notes.table":
            return .table
        case "com.apple.paper", "com.apple.paper.doc.pdf":
            return .drawing
        case "public.url":
            return .link
        case _ where typeUTI.hasPrefix("public.image") || typeUTI == "public.png" || typeUTI == "public.jpeg":
            return .image
        case _ where typeUTI.contains("audio"):
            return .audio
        case _ where typeUTI.contains("video") || typeUTI.contains("movie"):
            return .video
        default:
            return .file
        }
    }

    public init(row: Row) throws {
        id = row["id"]
        uuid = row["uuid"]
        noteID = row["noteID"]
        typeUTI = row["typeUTI"] ?? "unknown"
        mediaUUID = row["mediaUUID"]
        filename = row["filename"]
        fileSize = row["fileSize"]
        summary = row["summary"]
    }

    /// Get the file path for media attachments
    public func mediaFilePath(accountUUID: String, baseDir: URL) -> URL? {
        guard let mediaUUID = mediaUUID else { return nil }

        // Media is stored in: Accounts/{account}/Media/{mediaUUID}/1_*/{filename}
        let mediaDir = baseDir
            .appendingPathComponent("Accounts")
            .appendingPathComponent(accountUUID)
            .appendingPathComponent("Media")
            .appendingPathComponent(mediaUUID)

        // Find the subdirectory (usually starts with "1_")
        if let contents = try? FileManager.default.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil),
           let subdir = contents.first(where: { $0.lastPathComponent.hasPrefix("1_") }) {
            // Find the actual file in the subdirectory
            if let files = try? FileManager.default.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil),
               let file = files.first {
                return file
            }
        }

        return nil
    }
}

public enum AttachmentType: String, Codable, Sendable {
    case image
    case table
    case drawing
    case link
    case audio
    case video
    case file
}
