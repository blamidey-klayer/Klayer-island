import Foundation

// MARK: - Markdown block types

enum MDBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(lang: String, code: String)
    /// prefix: "•" for unordered, "1." / "2." etc for ordered; indent: nesting level (0-based)
    case listItem(prefix: String, text: String, indent: Int)
    case quote(text: String)
    case rule
}

// MARK: - Parser (Foundation only)

enum ChatMarkdown {

    static func parse(_ input: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = input.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(lang: lang, code: code.joined(separator: "\n")))
                i += 1
                continue
            }

            // ATX heading — MUST have space after the #s
            if line.hasPrefix("#") {
                var level = 0
                var rest = line
                while rest.hasPrefix("#") { level += 1; rest = String(rest.dropFirst()) }
                // Require a space (or end of line) after the hashes
                if rest.hasPrefix(" ") || rest.isEmpty {
                    let text = rest.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty { blocks.append(.heading(level: min(level, 6), text: text)) }
                    i += 1
                    continue
                }
                // else fall through to paragraph
            }

            // Horizontal rule
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped == "---" || stripped == "***" || stripped == "___" {
                blocks.append(.rule)
                i += 1
                continue
            }

            // Blockquote
            if stripped.hasPrefix("> ") || stripped == ">" {
                let text = stripped.hasPrefix("> ") ? String(stripped.dropFirst(2)) : ""
                blocks.append(.quote(text: text))
                i += 1
                continue
            }

            // List item — detect indent level by leading spaces, then match marker
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let indent = leadingSpaces / 2
            if stripped.hasPrefix("- ") || stripped.hasPrefix("* ") || stripped.hasPrefix("+ ") {
                let text = String(stripped.dropFirst(2))
                blocks.append(.listItem(prefix: "•", text: text, indent: indent))
                i += 1
                continue
            }
            // Ordered list item
            if let range = stripped.range(of: "^(\\d+)\\.\\s+", options: .regularExpression) {
                let number = String(stripped[..<range.upperBound])
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: ".").first ?? "1"
                let text = String(stripped[range.upperBound...])
                blocks.append(.listItem(prefix: "\(number).", text: text, indent: indent))
                i += 1
                continue
            }

            // Blank line — skip
            if stripped.isEmpty {
                i += 1
                continue
            }

            // Paragraph: accumulate consecutive non-special lines
            var paragraphLines: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                let nextStripped = next.trimmingCharacters(in: .whitespaces)
                if nextStripped.isEmpty { break }
                if next.hasPrefix("#") { break }
                if next.hasPrefix("```") { break }
                if nextStripped.hasPrefix("> ") || nextStripped == ">" { break }
                if nextStripped.hasPrefix("- ") || nextStripped.hasPrefix("* ") || nextStripped.hasPrefix("+ ") { break }
                if nextStripped == "---" || nextStripped == "***" || nextStripped == "___" { break }
                // Break before ordered list items too
                if nextStripped.range(of: "^\\d+\\.\\s+", options: .regularExpression) != nil { break }
                paragraphLines.append(next)
                i += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: "\n")))
        }
        return blocks
    }

    // MARK: - One line of plain text

    /// Converts a possibly multi-line, markdown-formatted string to a single line of plain text:
    /// the last message of a finished session, for its row and the finished view.
    /// Uses only the first non-empty paragraph (stops at blank line, horizontal rule, or table row).
    /// Strips `**`, `__`, backticks, leading `#`, and leading bullet markers.
    static func toOneLine(_ text: String, maxChars: Int = 200) -> String {
        let lines = text.components(separatedBy: "\n")

        // Split into paragraphs. Separators: blank line, HR (3+ repeated -/*/_ chars), table row (starts with |).
        var paragraphs: [[String]] = []
        var current: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isHR = trimmed.count >= 3 && (trimmed.allSatisfy { $0 == "-" } ||
                                               trimmed.allSatisfy { $0 == "*" } ||
                                               trimmed.allSatisfy { $0 == "_" })
            let isSep = trimmed.isEmpty || isHR || trimmed.hasPrefix("|")
            if isSep {
                if !current.isEmpty { paragraphs.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { paragraphs.append(current) }

        // Find first paragraph that yields non-empty text after cleaning.
        for paraLines in paragraphs {
            var s = paraLines.joined(separator: "\n")
            s = s.replacingOccurrences(of: "**", with: "")
            s = s.replacingOccurrences(of: "__", with: "")
            s = s.replacingOccurrences(of: "`", with: "")
            let processed: [String] = s.components(separatedBy: "\n").compactMap { line in
                var l = line
                while l.hasPrefix("#") { l = String(l.dropFirst()) }
                l = l.trimmingCharacters(in: .whitespaces)
                // Strip leading bullet markers: -, *, •, or N. (ordered list)
                if l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("• ") {
                    l = String(l.dropFirst(2))
                } else if let m = l.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    l = String(l[m.upperBound...])
                }
                let trimmed = l.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : trimmed
            }
            let joined = processed.joined(separator: " ")
            let collapsed = joined.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !collapsed.isEmpty { return String(collapsed.prefix(maxChars)) }
        }
        return ""
    }
}
