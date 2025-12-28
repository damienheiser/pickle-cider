import Foundation

/// Writes notes to Apple Notes using AppleScript
public final class NotesWriter: @unchecked Sendable {

    public init() {}

    // MARK: - Folder Operations

    /// Create a new folder in Apple Notes
    /// - Parameters:
    ///   - name: The folder name
    ///   - parent: Optional parent folder name for nesting
    /// - Returns: The created folder's ID
    @discardableResult
    public func createFolder(name: String, parent: String? = nil) throws -> String {
        let script: String
        if let parent = parent {
            script = """
            tell application "Notes"
                tell folder "\(parent.escapedForAppleScript)"
                    set newFolder to make new folder with properties {name:"\(name.escapedForAppleScript)"}
                    return id of newFolder
                end tell
            end tell
            """
        } else {
            script = """
            tell application "Notes"
                set newFolder to make new folder with properties {name:"\(name.escapedForAppleScript)"}
                return id of newFolder
            end tell
            """
        }

        return try executeAppleScript(script)
    }

    /// Check if a folder exists
    public func folderExists(name: String) throws -> Bool {
        let script = """
        tell application "Notes"
            try
                get folder "\(name.escapedForAppleScript)"
                return "true"
            on error
                return "false"
            end try
        end tell
        """

        let result = try executeAppleScript(script)
        return result.lowercased() == "true"
    }

    /// Get all folder names
    public func listFolders() throws -> [String] {
        let script = """
        tell application "Notes"
            set folderNames to {}
            repeat with f in folders
                set end of folderNames to name of f
            end repeat
            return folderNames
        end tell
        """

        let result = try executeAppleScript(script)
        // Parse AppleScript list format: "folder1, folder2, folder3"
        return result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ", ")
            .filter { !$0.isEmpty }
    }

    // MARK: - Note Operations

    /// Create a new note in Apple Notes
    /// - Parameters:
    ///   - title: The note title
    ///   - body: The note body (HTML format)
    ///   - folder: The folder to create the note in
    /// - Returns: The created note's ID
    @discardableResult
    public func createNote(title: String, body: String, folder: String) throws -> String {
        // Ensure folder exists
        if !(try folderExists(name: folder)) {
            try createFolder(name: folder)
        }

        let script = """
        tell application "Notes"
            tell folder "\(folder.escapedForAppleScript)"
                set newNote to make new note with properties {name:"\(title.escapedForAppleScript)", body:"\(body.escapedForAppleScript)"}
                return id of newNote
            end tell
        end tell
        """

        return try executeAppleScript(script)
    }

    /// Update an existing note's body
    public func updateNote(id: String, body: String) throws {
        let script = """
        tell application "Notes"
            set theNote to note id "\(id.escapedForAppleScript)"
            set body of theNote to "\(body.escapedForAppleScript)"
        end tell
        """

        _ = try executeAppleScript(script)
    }

    /// Update a note by title (first match in folder)
    public func updateNote(title: String, body: String, folder: String) throws {
        let script = """
        tell application "Notes"
            tell folder "\(folder.escapedForAppleScript)"
                set theNote to first note whose name is "\(title.escapedForAppleScript)"
                set body of theNote to "\(body.escapedForAppleScript)"
            end tell
        end tell
        """

        _ = try executeAppleScript(script)
    }

    /// Delete a note by ID
    public func deleteNote(id: String) throws {
        let script = """
        tell application "Notes"
            delete note id "\(id.escapedForAppleScript)"
        end tell
        """

        _ = try executeAppleScript(script)
    }

    /// Check if a note exists in a folder
    public func noteExists(title: String, folder: String) throws -> Bool {
        let script = """
        tell application "Notes"
            tell folder "\(folder.escapedForAppleScript)"
                try
                    get first note whose name is "\(title.escapedForAppleScript)"
                    return "true"
                on error
                    return "false"
                end try
            end tell
        end tell
        """

        let result = try executeAppleScript(script)
        return result.lowercased() == "true"
    }

    /// Get note content by title
    public func getNoteContent(title: String, folder: String) throws -> (body: String, plaintext: String) {
        let script = """
        tell application "Notes"
            tell folder "\(folder.escapedForAppleScript)"
                set theNote to first note whose name is "\(title.escapedForAppleScript)"
                set noteBody to body of theNote
                set notePlaintext to plaintext of theNote
                return noteBody & "|||SEPARATOR|||" & notePlaintext
            end tell
        end tell
        """

        let result = try executeAppleScript(script)
        let parts = result.components(separatedBy: "|||SEPARATOR|||")
        let body = parts.first ?? ""
        let plaintext = parts.count > 1 ? parts[1] : ""

        return (body, plaintext)
    }

    /// List all notes in a folder
    public func listNotes(folder: String) throws -> [(title: String, id: String)] {
        let script = """
        tell application "Notes"
            tell folder "\(folder.escapedForAppleScript)"
                set noteList to {}
                repeat with n in notes
                    set end of noteList to (name of n) & "|||" & (id of n)
                end repeat
                return noteList
            end tell
        end tell
        """

        let result = try executeAppleScript(script)
        // Parse the list
        return result
            .components(separatedBy: ", ")
            .compactMap { item -> (String, String)? in
                let parts = item.components(separatedBy: "|||")
                guard parts.count == 2 else { return nil }
                return (parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                        parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }

    // MARK: - Private

    private func executeAppleScript(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw NotesWriterError.scriptCreationFailed
        }

        let result = script.executeAndReturnError(&error)

        if let error = error {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? -1
            throw NotesWriterError.scriptExecutionFailed(
                message: errorMessage,
                errorNumber: errorNumber
            )
        }

        return result.stringValue ?? ""
    }
}

// MARK: - String Extensions

extension String {
    /// Escape string for use in AppleScript
    var escapedForAppleScript: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Errors

public enum NotesWriterError: Error, LocalizedError {
    case scriptCreationFailed
    case scriptExecutionFailed(message: String, errorNumber: Int)
    case folderNotFound(String)
    case noteNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            return "Failed to create AppleScript"
        case .scriptExecutionFailed(let message, let errorNumber):
            return "AppleScript execution failed (\(errorNumber)): \(message)"
        case .folderNotFound(let name):
            return "Folder not found: \(name)"
        case .noteNotFound(let title):
            return "Note not found: \(title)"
        }
    }
}
