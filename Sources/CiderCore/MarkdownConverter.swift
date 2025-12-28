import Foundation
import SwiftSoup

/// Converts between HTML and Markdown formats
public struct MarkdownConverter: Sendable {

    public init() {}

    // MARK: - HTML to Markdown

    /// Convert HTML to Markdown
    public func htmlToMarkdown(_ html: String) throws -> String {
        let doc = try SwiftSoup.parse(html)

        // Remove script and style tags
        try doc.select("script, style").remove()

        // Get the body content
        guard let body = doc.body() else {
            return try doc.text()
        }

        return try convertElementToMarkdown(body)
    }

    private func convertElementToMarkdown(_ element: Element) throws -> String {
        var result = ""

        for child in element.getChildNodes() {
            if let textNode = child as? TextNode {
                result += textNode.text()
            } else if let elem = child as? Element {
                let tag = elem.tagName().lowercased()
                let content = try convertElementToMarkdown(elem)

                switch tag {
                case "h1":
                    result += "# \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
                case "h2":
                    result += "## \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
                case "h3":
                    result += "### \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
                case "h4":
                    result += "#### \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
                case "h5":
                    result += "##### \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
                case "h6":
                    result += "###### \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"

                case "p", "div":
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        result += trimmed + "\n\n"
                    }

                case "br":
                    result += "\n"

                case "strong", "b":
                    result += "**\(content)**"

                case "em", "i":
                    result += "*\(content)*"

                case "u":
                    result += "_\(content)_"

                case "s", "strike", "del":
                    result += "~~\(content)~~"

                case "code":
                    if content.contains("\n") {
                        result += "```\n\(content)\n```\n"
                    } else {
                        result += "`\(content)`"
                    }

                case "pre":
                    result += "```\n\(content)\n```\n\n"

                case "blockquote":
                    let lines = content.components(separatedBy: "\n")
                    result += lines.map { "> \($0)" }.joined(separator: "\n") + "\n\n"

                case "ul":
                    result += content

                case "ol":
                    result += content

                case "li":
                    // Check for checkbox (Apple Notes style)
                    if let dataChecked = try? elem.attr("data-checked") {
                        let checked = dataChecked == "true" || dataChecked == "1"
                        result += "- [\(checked ? "x" : " ")] \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                    } else if elem.parent()?.tagName().lowercased() == "ol" {
                        result += "1. \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                    } else {
                        result += "- \(content.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                    }

                case "a":
                    let href = try elem.attr("href")
                    if !href.isEmpty {
                        result += "[\(content)](\(href))"
                    } else {
                        result += content
                    }

                case "img":
                    let src = try elem.attr("src")
                    let alt = try elem.attr("alt")
                    result += "![\(alt)](\(src))"

                case "hr":
                    result += "\n---\n\n"

                case "table":
                    result += try convertTableToMarkdown(elem) + "\n\n"

                case "span":
                    result += content

                default:
                    result += content
                }
            }
        }

        return result
    }

    private func convertTableToMarkdown(_ table: Element) throws -> String {
        var rows: [[String]] = []

        for row in try table.select("tr") {
            var cells: [String] = []
            for cell in try row.select("td, th") {
                cells.append(try cell.text().trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if !cells.isEmpty {
                rows.append(cells)
            }
        }

        guard !rows.isEmpty else { return "" }

        var result = ""

        // Calculate column widths
        let columnCount = rows.map { $0.count }.max() ?? 0
        var widths = Array(repeating: 3, count: columnCount)

        for row in rows {
            for (i, cell) in row.enumerated() where i < columnCount {
                widths[i] = max(widths[i], cell.count)
            }
        }

        // Header row
        if let header = rows.first {
            result += "| " + header.enumerated().map { i, cell in
                cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }.joined(separator: " | ") + " |\n"

            // Separator
            result += "|" + widths.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "|") + "|\n"
        }

        // Data rows
        for row in rows.dropFirst() {
            let paddedCells = (0..<columnCount).map { i -> String in
                let cell = i < row.count ? row[i] : ""
                return cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }
            result += "| " + paddedCells.joined(separator: " | ") + " |\n"
        }

        return result
    }

    // MARK: - Markdown to HTML

    /// Convert Markdown to HTML suitable for Apple Notes
    public func markdownToHTML(_ markdown: String) -> String {
        var html = ""
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBlockContent = ""
        var inList = false
        var listType = "ul"

        for line in lines {
            // Code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    html += "<pre><code>\(escapeHTML(codeBlockContent))</code></pre>\n"
                    codeBlockContent = ""
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeBlockContent += line + "\n"
                continue
            }

            // Close list if needed
            if inList && !line.hasPrefix("- ") && !line.hasPrefix("* ") && !line.hasPrefix("1. ") && !line.isEmpty {
                html += "</\(listType)>\n"
                inList = false
            }

            // Headers
            if line.hasPrefix("# ") {
                html += "<h1>\(escapeHTML(String(line.dropFirst(2))))</h1>\n"
            } else if line.hasPrefix("## ") {
                html += "<h2>\(escapeHTML(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("### ") {
                html += "<h3>\(escapeHTML(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("#### ") {
                html += "<h4>\(escapeHTML(String(line.dropFirst(5))))</h4>\n"
            } else if line.hasPrefix("##### ") {
                html += "<h5>\(escapeHTML(String(line.dropFirst(6))))</h5>\n"
            } else if line.hasPrefix("###### ") {
                html += "<h6>\(escapeHTML(String(line.dropFirst(7))))</h6>\n"
            }
            // Horizontal rule
            else if line == "---" || line == "***" || line == "___" {
                html += "<hr>\n"
            }
            // Blockquote
            else if line.hasPrefix("> ") {
                html += "<blockquote>\(escapeHTML(String(line.dropFirst(2))))</blockquote>\n"
            }
            // Checkbox list
            else if line.hasPrefix("- [ ] ") {
                if !inList { html += "<ul>\n"; inList = true; listType = "ul" }
                html += "<li data-checked=\"false\">\(convertInlineMarkdown(String(line.dropFirst(6))))</li>\n"
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                if !inList { html += "<ul>\n"; inList = true; listType = "ul" }
                html += "<li data-checked=\"true\">\(convertInlineMarkdown(String(line.dropFirst(6))))</li>\n"
            }
            // Unordered list
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { html += "<ul>\n"; inList = true; listType = "ul" }
                html += "<li>\(convertInlineMarkdown(String(line.dropFirst(2))))</li>\n"
            }
            // Ordered list
            else if let range = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                if !inList { html += "<ol>\n"; inList = true; listType = "ol" }
                html += "<li>\(convertInlineMarkdown(String(line[range.upperBound...])))</li>\n"
            }
            // Empty line
            else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if inList {
                    html += "</\(listType)>\n"
                    inList = false
                }
                html += "<br>\n"
            }
            // Paragraph
            else {
                html += "<p>\(convertInlineMarkdown(line))</p>\n"
            }
        }

        // Close any open list
        if inList {
            html += "</\(listType)>\n"
        }

        return "<html><head></head><body>\(html)</body></html>"
    }

    private func convertInlineMarkdown(_ text: String) -> String {
        var result = escapeHTML(text)

        // Bold: **text** or __text__
        result = result.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"__(.+?)__"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic: *text* or _text_
        result = result.replacingOccurrences(
            of: #"\*(.+?)\*"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"_(.+?)_"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Strikethrough: ~~text~~
        result = result.replacingOccurrences(
            of: #"~~(.+?)~~"#,
            with: "<del>$1</del>",
            options: .regularExpression
        )

        // Inline code: `text`
        result = result.replacingOccurrences(
            of: #"`(.+?)`"#,
            with: "<code>$1</code>",
            options: .regularExpression
        )

        // Links: [text](url)
        result = result.replacingOccurrences(
            of: #"\[(.+?)\]\((.+?)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        // Images: ![alt](src)
        result = result.replacingOccurrences(
            of: #"!\[(.+?)\]\((.+?)\)"#,
            with: "<img alt=\"$1\" src=\"$2\">",
            options: .regularExpression
        )

        return result
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
