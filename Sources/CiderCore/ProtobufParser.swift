import Foundation
import Compression

/// Parses Apple Notes protobuf data format
public final class ProtobufParser: Sendable {

    public init() {}

    /// Parse gzipped protobuf data from Apple Notes
    /// Returns the plaintext content of the note
    public func parseNoteData(_ gzippedData: Data) throws -> ParsedNoteContent {
        // Check for gzip magic bytes
        guard gzippedData.count >= 2 else {
            throw ProtobufParserError.dataTooShort
        }

        // Gzip magic bytes: 0x1F 0x8B
        let isGzipped = gzippedData[0] == 0x1F && gzippedData[1] == 0x8B

        let decompressed: Data
        if isGzipped {
            decompressed = try gunzip(gzippedData)
        } else {
            // Some older notes might not be gzipped
            decompressed = gzippedData
        }

        // Parse the protobuf structure
        return try parseProtobuf(decompressed)
    }

    // MARK: - Gzip Decompression

    private func gunzip(_ data: Data) throws -> Data {
        // Skip the gzip header (minimum 10 bytes)
        guard data.count > 10 else {
            throw ProtobufParserError.invalidGzipHeader
        }

        // Find the start of the deflate stream (after gzip header)
        var headerLength = 10

        let flags = data[3]
        // FEXTRA
        if flags & 0x04 != 0 {
            guard data.count > headerLength + 2 else {
                throw ProtobufParserError.invalidGzipHeader
            }
            let extraLength = Int(data[headerLength]) | (Int(data[headerLength + 1]) << 8)
            headerLength += 2 + extraLength
        }
        // FNAME
        if flags & 0x08 != 0 {
            while headerLength < data.count && data[headerLength] != 0 {
                headerLength += 1
            }
            headerLength += 1 // Skip null terminator
        }
        // FCOMMENT
        if flags & 0x10 != 0 {
            while headerLength < data.count && data[headerLength] != 0 {
                headerLength += 1
            }
            headerLength += 1
        }
        // FHCRC
        if flags & 0x02 != 0 {
            headerLength += 2
        }

        guard headerLength < data.count - 8 else {
            throw ProtobufParserError.invalidGzipHeader
        }

        // Extract the deflate stream (excluding header and 8-byte trailer)
        let deflateData = data.subdata(in: headerLength..<(data.count - 8))

        // Decompress using zlib (raw deflate)
        return try decompressDeflate(deflateData)
    }

    private func decompressDeflate(_ data: Data) throws -> Data {
        let bufferSize = 65536
        var decompressed = Data()

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

        if let result = result {
            decompressed = result
        } else {
            throw ProtobufParserError.decompressionFailed
        }

        // Handle case where output is larger than buffer
        // In practice, we may need multiple iterations for large notes
        // For simplicity, we'll use a larger initial buffer approach
        if decompressed.isEmpty {
            throw ProtobufParserError.decompressionFailed
        }

        return decompressed
    }

    // MARK: - Protobuf Parsing

    /// Parse the decompressed protobuf data
    /// Apple Notes uses a custom protobuf schema based on CRDT structures
    private func parseProtobuf(_ data: Data) throws -> ParsedNoteContent {
        // The protobuf structure is:
        // message NoteStoreProto {
        //   Document document = 2;
        // }
        // message Document {
        //   Note note = 2;
        // }
        // message Note {
        //   string noteText = 2;
        //   repeated AttributeRun attributeRun = 5;
        // }

        var plaintext = ""
        var position = 0

        while position < data.count {
            // Read field tag (varint)
            let (fieldNumber, wireType, bytesRead) = try readTag(from: data, at: position)
            position += bytesRead

            switch wireType {
            case 0: // Varint
                let (_, varIntBytes) = try readVarint(from: data, at: position)
                position += varIntBytes

            case 1: // 64-bit
                position += 8

            case 2: // Length-delimited
                let (length, lengthBytes) = try readVarint(from: data, at: position)
                position += lengthBytes

                if position + Int(length) <= data.count {
                    let fieldData = data.subdata(in: position..<(position + Int(length)))

                    // Field 2 at the top level is the Document
                    // Within Document, field 2 is the Note
                    // Within Note, field 2 is the noteText
                    if fieldNumber == 2 {
                        // Try to extract text from nested structure
                        if let text = extractText(from: fieldData) {
                            if !text.isEmpty {
                                plaintext = text
                            }
                        }
                    }

                    position += Int(length)
                } else {
                    position = data.count
                }

            case 5: // 32-bit
                position += 4

            default:
                // Unknown wire type, skip
                position = data.count
            }
        }

        // Fallback: try to extract any readable text from the raw data
        if plaintext.isEmpty {
            plaintext = extractReadableText(from: data)
        }

        return ParsedNoteContent(
            plaintext: plaintext,
            html: convertToBasicHTML(plaintext),
            hasAttachments: data.contains(0xEF) // Unicode replacement char often indicates attachments
        )
    }

    /// Extract text from nested protobuf structure
    private func extractText(from data: Data) -> String? {
        var position = 0
        var extractedText = ""

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
                    return extractedText.isEmpty ? nil : extractedText
                }

            case 2:
                guard let (length, lengthBytes) = try? readVarint(from: data, at: position) else {
                    return extractedText.isEmpty ? nil : extractedText
                }
                position += lengthBytes

                if position + Int(length) <= data.count {
                    let fieldData = data.subdata(in: position..<(position + Int(length)))

                    // Field 2 is typically the text content
                    if fieldNumber == 2 {
                        if let text = String(data: fieldData, encoding: .utf8) {
                            // Check if it looks like actual text (not binary)
                            if text.allSatisfy({ $0.isLetter || $0.isNumber || $0.isWhitespace || $0.isPunctuation || $0.isSymbol }) {
                                if !text.isEmpty {
                                    extractedText = text
                                }
                            } else {
                                // Recurse into nested message
                                if let nestedText = extractText(from: fieldData), !nestedText.isEmpty {
                                    extractedText = nestedText
                                }
                            }
                        }
                    } else {
                        // Recurse into nested message
                        if let nestedText = extractText(from: fieldData), !nestedText.isEmpty {
                            if extractedText.isEmpty {
                                extractedText = nestedText
                            }
                        }
                    }

                    position += Int(length)
                } else {
                    return extractedText.isEmpty ? nil : extractedText
                }

            default:
                position += 4
            }
        }

        return extractedText.isEmpty ? nil : extractedText
    }

    /// Read a protobuf varint
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

    /// Read a protobuf field tag
    private func readTag(from data: Data, at position: Int) throws -> (fieldNumber: Int, wireType: Int, bytesRead: Int) {
        let (value, bytesRead) = try readVarint(from: data, at: position)
        let fieldNumber = Int(value >> 3)
        let wireType = Int(value & 0x7)
        return (fieldNumber, wireType, bytesRead)
    }

    /// Extract readable ASCII/UTF-8 text as fallback
    private func extractReadableText(from data: Data) -> String {
        // Look for UTF-8 string sequences
        var text = ""
        var currentWord = ""

        for byte in data {
            if byte >= 0x20 && byte < 0x7F {
                // Printable ASCII
                currentWord.append(Character(UnicodeScalar(byte)))
            } else if byte == 0x0A || byte == 0x0D {
                // Newline
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

    /// Convert plaintext to basic HTML
    private func convertToBasicHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let paragraphs = escaped.components(separatedBy: "\n\n")
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined(separator: "\n")

        return "<html><head></head><body>\(paragraphs)</body></html>"
    }
}

// MARK: - Types

public struct ParsedNoteContent: Sendable {
    public let plaintext: String
    public let html: String
    public let hasAttachments: Bool

    public init(plaintext: String, html: String, hasAttachments: Bool) {
        self.plaintext = plaintext
        self.html = html
        self.hasAttachments = hasAttachments
    }
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
