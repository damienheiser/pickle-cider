import Foundation
import Compression

/// Parses Apple Notes protobuf data format with full formatting support
public final class ProtobufParser: Sendable {

    public init() {}

    /// Parse gzipped protobuf data from Apple Notes
    /// Returns the content with formatting information
    public func parseNoteData(_ gzippedData: Data) throws -> ParsedNoteContent {
        guard gzippedData.count >= 2 else {
            throw ProtobufParserError.dataTooShort
        }

        let isGzipped = gzippedData[0] == 0x1F && gzippedData[1] == 0x8B

        let decompressed: Data
        if isGzipped {
            decompressed = try gunzip(gzippedData)
        } else {
            decompressed = gzippedData
        }

        return try parseProtobuf(decompressed)
    }

    // MARK: - Gzip Decompression

    private func gunzip(_ data: Data) throws -> Data {
        guard data.count > 10 else {
            throw ProtobufParserError.invalidGzipHeader
        }

        var headerLength = 10
        let flags = data[3]

        if flags & 0x04 != 0 {
            guard data.count > headerLength + 2 else {
                throw ProtobufParserError.invalidGzipHeader
            }
            let extraLength = Int(data[headerLength]) | (Int(data[headerLength + 1]) << 8)
            headerLength += 2 + extraLength
        }
        if flags & 0x08 != 0 {
            while headerLength < data.count && data[headerLength] != 0 {
                headerLength += 1
            }
            headerLength += 1
        }
        if flags & 0x10 != 0 {
            while headerLength < data.count && data[headerLength] != 0 {
                headerLength += 1
            }
            headerLength += 1
        }
        if flags & 0x02 != 0 {
            headerLength += 2
        }

        guard headerLength < data.count - 8 else {
            throw ProtobufParserError.invalidGzipHeader
        }

        let deflateData = data.subdata(in: headerLength..<(data.count - 8))
        return try decompressDeflate(deflateData)
    }

    private func decompressDeflate(_ data: Data) throws -> Data {
        let bufferSize = 262144  // 256KB for larger notes

        let result = data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Data? in
            guard let sourceBase = sourcePtr.baseAddress else { return nil }

            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { destinationBuffer.deallocate() }

            let decodedSize = compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                sourceBase.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )

            guard decodedSize > 0 else { return nil }
            return Data(bytes: destinationBuffer, count: decodedSize)
        }

        guard let decompressed = result, !decompressed.isEmpty else {
            throw ProtobufParserError.decompressionFailed
        }

        return decompressed
    }

    // MARK: - Protobuf Parsing

    /// Parse the decompressed protobuf data
    private func parseProtobuf(_ data: Data) throws -> ParsedNoteContent {
        var plaintext = ""
        var attributeRuns: [AttributeRun] = []
        var position = 0

        // Parse top-level message
        while position < data.count {
            guard let (fieldNumber, wireType, bytesRead) = try? readTag(from: data, at: position) else {
                break
            }
            position += bytesRead

            switch wireType {
            case 0: // Varint
                if let (_, varIntBytes) = try? readVarint(from: data, at: position) {
                    position += varIntBytes
                } else {
                    position = data.count
                }

            case 1: // 64-bit
                position += 8

            case 2: // Length-delimited
                guard let (length, lengthBytes) = try? readVarint(from: data, at: position) else {
                    position = data.count
                    continue
                }
                position += lengthBytes

                if position + Int(length) <= data.count {
                    let fieldData = data.subdata(in: position..<(position + Int(length)))

                    if fieldNumber == 2 {
                        // Document/Note container - parse recursively
                        let (text, runs) = parseNoteContent(from: fieldData)
                        if !text.isEmpty {
                            plaintext = text
                            attributeRuns = runs
                        }
                    }

                    position += Int(length)
                } else {
                    position = data.count
                }

            case 5: // 32-bit
                position += 4

            default:
                position = data.count
            }
        }

        // Fallback
        if plaintext.isEmpty {
            plaintext = extractReadableText(from: data)
        }

        // Apply formatting to create markdown
        let markdown = applyFormatting(plaintext, runs: attributeRuns)
        let hasAttachments = plaintext.contains("\u{FFFC}")

        return ParsedNoteContent(
            plaintext: plaintext,
            markdown: markdown,
            html: convertToHTML(plaintext, runs: attributeRuns),
            hasAttachments: hasAttachments,
            attributeRuns: attributeRuns
        )
    }

    /// Parse note content and extract text + attribute runs
    private func parseNoteContent(from data: Data) -> (String, [AttributeRun]) {
        var text = ""
        var runs: [AttributeRun] = []
        var position = 0

        while position < data.count {
            guard let (fieldNumber, wireType, bytesRead) = try? readTag(from: data, at: position) else {
                break
            }
            position += bytesRead

            switch wireType {
            case 0:
                if let (_, varIntBytes) = try? readVarint(from: data, at: position) {
                    position += varIntBytes
                } else {
                    return (text, runs)
                }

            case 2:
                guard let (length, lengthBytes) = try? readVarint(from: data, at: position) else {
                    return (text, runs)
                }
                position += lengthBytes

                if position + Int(length) <= data.count {
                    let fieldData = data.subdata(in: position..<(position + Int(length)))

                    switch fieldNumber {
                    case 2:
                        // This might be text or nested message
                        if let textContent = String(data: fieldData, encoding: .utf8),
                           isValidText(textContent) {
                            text = textContent
                        } else {
                            // Recurse into nested message
                            let (nestedText, nestedRuns) = parseNoteContent(from: fieldData)
                            if !nestedText.isEmpty {
                                text = nestedText
                                runs = nestedRuns
                            }
                        }

                    case 3:
                        // Field 3 at note level contains attribute runs array
                        let parsedRuns = parseAttributeRuns(from: fieldData)
                        if !parsedRuns.isEmpty {
                            runs = parsedRuns
                        }

                    default:
                        // Try recursing for other fields
                        let (nestedText, nestedRuns) = parseNoteContent(from: fieldData)
                        if text.isEmpty && !nestedText.isEmpty {
                            text = nestedText
                            runs = nestedRuns
                        }
                    }

                    position += Int(length)
                } else {
                    return (text, runs)
                }

            default:
                position += 4
            }
        }

        return (text, runs)
    }

    /// Parse attribute runs from field 3 data
    private func parseAttributeRuns(from data: Data) -> [AttributeRun] {
        var runs: [AttributeRun] = []
        var position = 0

        while position < data.count {
            guard let (fieldNumber, wireType, bytesRead) = try? readTag(from: data, at: position) else {
                break
            }
            position += bytesRead

            if wireType == 2 {
                guard let (length, lengthBytes) = try? readVarint(from: data, at: position) else {
                    break
                }
                position += lengthBytes

                if position + Int(length) <= data.count {
                    let runData = data.subdata(in: position..<(position + Int(length)))

                    // Parse individual AttributeRun
                    if let run = parseAttributeRun(from: runData) {
                        runs.append(run)
                    }

                    position += Int(length)
                } else {
                    break
                }
            } else if wireType == 0 {
                if let (_, varIntBytes) = try? readVarint(from: data, at: position) {
                    position += varIntBytes
                } else {
                    break
                }
            } else {
                position += 4
            }
        }

        return runs
    }

    /// Parse a single AttributeRun message
    private func parseAttributeRun(from data: Data) -> AttributeRun? {
        var length: Int = 0
        var fontWeight: FontWeight = .default
        var paragraphStyle: ParagraphStyle = .default
        var position = 0

        while position < data.count {
            guard let (fieldNumber, wireType, bytesRead) = try? readTag(from: data, at: position) else {
                break
            }
            position += bytesRead

            switch wireType {
            case 0: // Varint
                guard let (value, varIntBytes) = try? readVarint(from: data, at: position) else {
                    break
                }
                position += varIntBytes

                switch fieldNumber {
                case 1:
                    // Length field
                    length = Int(value)
                case 5:
                    // Font weight: 0=default, 1=bold, 2=italic, 3=both
                    fontWeight = FontWeight(rawValue: Int(value)) ?? .default
                default:
                    break
                }

            case 2: // Length-delimited (nested message like ParagraphStyle)
                guard let (msgLength, lengthBytes) = try? readVarint(from: data, at: position) else {
                    break
                }
                position += lengthBytes

                if position + Int(msgLength) <= data.count {
                    let nestedData = data.subdata(in: position..<(position + Int(msgLength)))

                    if fieldNumber == 2 {
                        // ParagraphStyle
                        paragraphStyle = parseParagraphStyle(from: nestedData)
                    }

                    position += Int(msgLength)
                } else {
                    break
                }

            default:
                position += 4
            }
        }

        guard length > 0 else { return nil }

        return AttributeRun(
            length: length,
            fontWeight: fontWeight,
            paragraphStyle: paragraphStyle
        )
    }

    /// Parse ParagraphStyle from nested message
    private func parseParagraphStyle(from data: Data) -> ParagraphStyle {
        var position = 0

        while position < data.count {
            guard let (fieldNumber, wireType, bytesRead) = try? readTag(from: data, at: position) else {
                break
            }
            position += bytesRead

            if wireType == 0 {
                guard let (value, varIntBytes) = try? readVarint(from: data, at: position) else {
                    break
                }
                position += varIntBytes

                // Field 1 in ParagraphStyle is the style type
                if fieldNumber == 1 {
                    return ParagraphStyle(rawValue: Int(value)) ?? .default
                }
            } else if wireType == 2 {
                guard let (length, lengthBytes) = try? readVarint(from: data, at: position) else {
                    break
                }
                position += lengthBytes + Int(length)
            } else {
                position += 4
            }
        }

        return .default
    }

    // MARK: - Formatting Application

    /// Apply formatting to create markdown
    private func applyFormatting(_ text: String, runs: [AttributeRun]) -> String {
        guard !runs.isEmpty else { return text }

        var result = ""
        var charIndex = 0
        let chars = Array(text)

        for run in runs {
            let endIndex = min(charIndex + run.length, chars.count)
            guard charIndex < chars.count else { break }

            var segment = String(chars[charIndex..<endIndex])

            // Apply paragraph style
            switch run.paragraphStyle {
            case .title:
                segment = "# " + segment.trimmingCharacters(in: .newlines)
                if !segment.hasSuffix("\n") { segment += "\n" }
            case .heading:
                segment = "## " + segment.trimmingCharacters(in: .newlines)
                if !segment.hasSuffix("\n") { segment += "\n" }
            case .subheading:
                segment = "### " + segment.trimmingCharacters(in: .newlines)
                if !segment.hasSuffix("\n") { segment += "\n" }
            case .monospaced:
                segment = "`" + segment + "`"
            case .dottedList:
                segment = "• " + segment
            case .dashedList:
                segment = "- " + segment
            case .numberedList:
                segment = "1. " + segment
            case .checkbox:
                segment = "- [ ] " + segment
            case .checkedBox:
                segment = "- [x] " + segment
            default:
                break
            }

            // Apply font weight (bold/italic)
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && run.fontWeight != .default {
                switch run.fontWeight {
                case .bold:
                    segment = segment.replacingOccurrences(of: trimmed, with: "**\(trimmed)**")
                case .italic:
                    segment = segment.replacingOccurrences(of: trimmed, with: "*\(trimmed)*")
                case .boldItalic:
                    segment = segment.replacingOccurrences(of: trimmed, with: "***\(trimmed)***")
                default:
                    break
                }
            }

            result += segment
            charIndex = endIndex
        }

        // Append any remaining text
        if charIndex < chars.count {
            result += String(chars[charIndex...])
        }

        return result
    }

    /// Convert to HTML with formatting
    private func convertToHTML(_ text: String, runs: [AttributeRun]) -> String {
        guard !runs.isEmpty else {
            return "<html><body>\(escapeHTML(text))</body></html>"
        }

        var result = ""
        var charIndex = 0
        let chars = Array(text)

        for run in runs {
            let endIndex = min(charIndex + run.length, chars.count)
            guard charIndex < chars.count else { break }

            var segment = escapeHTML(String(chars[charIndex..<endIndex]))

            // Apply formatting
            switch run.fontWeight {
            case .bold:
                segment = "<strong>\(segment)</strong>"
            case .italic:
                segment = "<em>\(segment)</em>"
            case .boldItalic:
                segment = "<strong><em>\(segment)</em></strong>"
            default:
                break
            }

            switch run.paragraphStyle {
            case .title:
                segment = "<h1>\(segment)</h1>"
            case .heading:
                segment = "<h2>\(segment)</h2>"
            case .subheading:
                segment = "<h3>\(segment)</h3>"
            case .monospaced:
                segment = "<code>\(segment)</code>"
            default:
                break
            }

            result += segment
            charIndex = endIndex
        }

        if charIndex < chars.count {
            result += escapeHTML(String(chars[charIndex...]))
        }

        return "<html><body>\(result.replacingOccurrences(of: "\n", with: "<br>"))</body></html>"
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Helper Methods

    private func isValidText(_ text: String) -> Bool {
        // Check if this looks like actual text content
        let validChars = text.filter {
            $0.isLetter || $0.isNumber || $0.isWhitespace ||
            $0.isPunctuation || $0.isSymbol || $0 == "\u{FFFC}"
        }
        return validChars.count > text.count / 2 && text.count > 1
    }

    private func readVarint(from data: Data, at position: Int) throws -> (value: UInt64, bytesRead: Int) {
        var value: UInt64 = 0
        var bytesRead = 0
        var shift = 0

        while position + bytesRead < data.count {
            let byte = data[position + bytesRead]
            value |= UInt64(byte & 0x7F) << shift
            bytesRead += 1

            if byte & 0x80 == 0 {
                return (value, bytesRead)
            }

            shift += 7
            if shift > 63 {
                throw ProtobufParserError.invalidVarint
            }
        }

        throw ProtobufParserError.unexpectedEndOfData
    }

    private func readTag(from data: Data, at position: Int) throws -> (fieldNumber: Int, wireType: Int, bytesRead: Int) {
        let (value, bytesRead) = try readVarint(from: data, at: position)
        let fieldNumber = Int(value >> 3)
        let wireType = Int(value & 0x7)
        return (fieldNumber, wireType, bytesRead)
    }

    private func extractReadableText(from data: Data) -> String {
        var text = ""
        var currentWord = ""

        for byte in data {
            if byte >= 0x20 && byte < 0x7F {
                currentWord.append(Character(UnicodeScalar(byte)))
            } else if byte == 0x0A || byte == 0x0D {
                if currentWord.count >= 3 {
                    text += currentWord + "\n"
                }
                currentWord = ""
            } else {
                if currentWord.count >= 3 {
                    text += currentWord + " "
                }
                currentWord = ""
            }
        }

        if currentWord.count >= 3 {
            text += currentWord
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Types

public struct ParsedNoteContent: Sendable {
    public let plaintext: String
    public let markdown: String
    public let html: String
    public let hasAttachments: Bool
    public let attributeRuns: [AttributeRun]

    public init(plaintext: String, markdown: String, html: String, hasAttachments: Bool, attributeRuns: [AttributeRun] = []) {
        self.plaintext = plaintext
        self.markdown = markdown
        self.html = html
        self.hasAttachments = hasAttachments
        self.attributeRuns = attributeRuns
    }
}

public struct AttributeRun: Sendable {
    public let length: Int
    public let fontWeight: FontWeight
    public let paragraphStyle: ParagraphStyle

    public init(length: Int, fontWeight: FontWeight = .default, paragraphStyle: ParagraphStyle = .default) {
        self.length = length
        self.fontWeight = fontWeight
        self.paragraphStyle = paragraphStyle
    }
}

public enum FontWeight: Int, Sendable {
    case `default` = 0
    case bold = 1
    case italic = 2
    case boldItalic = 3
}

public enum ParagraphStyle: Int, Sendable {
    case `default` = -1
    case title = 0
    case heading = 1
    case subheading = 2
    case monospaced = 4
    case dottedList = 100
    case dashedList = 101
    case numberedList = 102
    case checkbox = 103
    case checkedBox = 104  // Checked checkbox
}

// MARK: - Errors

public enum ProtobufParserError: Error, LocalizedError {
    case dataTooShort
    case invalidGzipHeader
    case decompressionFailed
    case invalidVarint
    case unexpectedEndOfData
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .dataTooShort:
            return "Note data is too short to parse"
        case .invalidGzipHeader:
            return "Invalid gzip header in note data"
        case .decompressionFailed:
            return "Failed to decompress note data"
        case .invalidVarint:
            return "Invalid varint in protobuf data"
        case .unexpectedEndOfData:
            return "Unexpected end of protobuf data"
        case .parseError(let message):
            return "Protobuf parse error: \(message)"
        }
    }
}
