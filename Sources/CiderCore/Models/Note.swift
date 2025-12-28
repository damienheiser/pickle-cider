import Foundation
import GRDB

/// Represents an Apple Note with all its metadata and content
public struct Note: Codable, FetchableRecord, Identifiable, Sendable {
    public let id: Int64
    public let uuid: String
    public let title: String?
    public let folderID: Int64?
    public let folderName: String?
    public let modificationDate: Date?
    public let creationDate: Date?
    public let isPasswordProtected: Bool
    public let plaintext: String?
    public let html: String?
    public let rawData: Data?

    public init(
        id: Int64,
        uuid: String,
        title: String?,
        folderID: Int64?,
        folderName: String?,
        modificationDate: Date?,
        creationDate: Date?,
        isPasswordProtected: Bool,
        plaintext: String?,
        html: String?,
        rawData: Data?
    ) {
        self.id = id
        self.uuid = uuid
        self.title = title
        self.folderID = folderID
        self.folderName = folderName
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.isPasswordProtected = isPasswordProtected
        self.plaintext = plaintext
        self.html = html
        self.rawData = rawData
    }

    /// Initialize from a database row
    public init(row: Row) throws {
        id = row["id"]
        uuid = row["uuid"]
        title = row["title"]
        folderID = row["folderID"]
        folderName = row["folderName"]

        // Convert Cocoa timestamps (seconds since 2001-01-01) to Date
        if let modTimestamp: Double = row["modificationDate"] {
            modificationDate = Date.fromCocoaTimestamp(modTimestamp)
        } else {
            modificationDate = nil
        }

        if let createTimestamp: Double = row["creationDate"] {
            creationDate = Date.fromCocoaTimestamp(createTimestamp)
        } else {
            creationDate = nil
        }

        isPasswordProtected = (row["isLocked"] as Int64?) == 1
        plaintext = nil
        html = nil
        rawData = row["data"]
    }

    /// Display title, using "Untitled" as fallback
    public var displayTitle: String {
        title?.isEmpty == false ? title! : "Untitled"
    }

    /// Sanitized filename for export
    public var safeFilename: String {
        let name = displayTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "<", with: "(")
            .replacingOccurrences(of: ">", with: ")")
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Limit length
        if name.count > 200 {
            return String(name.prefix(200))
        }
        return name.isEmpty ? "Untitled" : name
    }
}

// MARK: - Cocoa Date Conversion

extension Date {
    /// Cocoa epoch: January 1, 2001, 00:00:00 UTC
    private static let cocoaEpoch = Date(timeIntervalSince1970: 978307200)

    /// Create a Date from a Cocoa Core Data timestamp
    public static func fromCocoaTimestamp(_ timestamp: Double) -> Date {
        return cocoaEpoch.addingTimeInterval(timestamp)
    }

    /// Convert to Cocoa Core Data timestamp
    public func toCocoaTimestamp() -> Double {
        return self.timeIntervalSince(Date.cocoaEpoch)
    }
}
