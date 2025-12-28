import XCTest
@testable import CiderCore

final class CiderCoreTests: XCTestCase {

    func testCocoaDateConversion() {
        // Test Cocoa timestamp conversion
        // Cocoa epoch: 2001-01-01 00:00:00 UTC
        let timestamp: Double = 0
        let date = Date.fromCocoaTimestamp(timestamp)

        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)

        XCTAssertEqual(components.year, 2001)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }

    func testNoteSafeFilename() {
        let note = Note(
            id: 1,
            uuid: "test-uuid",
            title: "My Note: With <Special> Characters?",
            folderID: nil,
            folderName: nil,
            modificationDate: nil,
            creationDate: nil,
            isPasswordProtected: false,
            plaintext: nil,
            html: nil,
            rawData: nil
        )

        let safeName = note.safeFilename
        XCTAssertFalse(safeName.contains(":"))
        XCTAssertFalse(safeName.contains("<"))
        XCTAssertFalse(safeName.contains(">"))
        XCTAssertFalse(safeName.contains("?"))
    }

    func testMarkdownToHTML() {
        let converter = MarkdownConverter()

        let markdown = """
        # Hello World

        This is a **bold** and *italic* text.

        - Item 1
        - Item 2
        """

        let html = converter.markdownToHTML(markdown)

        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
        XCTAssertTrue(html.contains("<li>"))
    }

    func testHTMLToMarkdown() throws {
        let converter = MarkdownConverter()

        let html = """
        <html><body>
        <h1>Test Title</h1>
        <p>This is a <strong>test</strong> paragraph.</p>
        </body></html>
        """

        let markdown = try converter.htmlToMarkdown(html)

        XCTAssertTrue(markdown.contains("# Test Title"))
        XCTAssertTrue(markdown.contains("**test**"))
    }

    func testSyncStateRecord() {
        let state = SyncStateRecord(
            localPath: "test/path.md",
            noteUUID: "uuid-123",
            folderPath: "TestFolder",
            localHash: "abc123",
            remoteHash: "abc123",
            syncStatus: "synced"
        )

        XCTAssertEqual(state.localPath, "test/path.md")
        XCTAssertEqual(state.syncStatus, "synced")
    }

    func testVersionContent() {
        let content = VersionContent(
            noteUUID: "test-uuid",
            appleNoteID: nil,
            title: "Test Note",
            folderPath: nil,
            capturedAt: Date(),
            appleModificationDate: nil,
            plaintext: "Hello World",
            html: nil,
            rawProtobuf: nil
        )

        XCTAssertEqual(content.title, "Test Note")
        XCTAssertEqual(content.content.plaintext, "Hello World")
        XCTAssertEqual(content.metadata.characterCount, 11)
    }
}
