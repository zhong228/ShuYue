import Foundation

/// Block boundaries remain stable while streaming; inline Markdown is rendered by SwiftUI.
enum AIAnswerMarkdown {
    enum Kind: Equatable { case paragraph, heading, quote, list, code, table }
    struct Block: Equatable { let kind: Kind; let text: String }
    /// One `.list` block split into what is drawn: nesting depth, marker and item text.
    struct ListItem: Equatable { let depth: Int; let marker: String; let text: String }

    /// Unordered markers (`-`, `*`, `+`) become a bullet; ordered markers keep their number.
    /// Two spaces or one tab of indentation is one nesting level.
    static func listItem(_ line: String) -> ListItem {
        let body = line.drop { $0 == " " || $0 == "\t" }
        let indentWidth = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
        guard let range = body.range(of: #"^(?:[-*+]|\d+[.)])\s+"#, options: .regularExpression) else {
            return ListItem(depth: indentWidth / 2, marker: "•", text: String(body))
        }
        let rawMarker = body[range].trimmingCharacters(in: .whitespaces)
        return ListItem(depth: indentWidth / 2,
                        marker: rawMarker.first?.isNumber == true ? rawMarker : "•",
                        text: String(body[range.upperBound...]))
    }

    static func blocks(_ text: String) -> [Block] {
        var result: [Block] = []
        var buffer: [String] = []
        var kind: Kind = .paragraph
        var fence: String?
        func flush() {
            if !buffer.isEmpty { result.append(.init(kind: kind, text: buffer.joined(separator: "\n"))); buffer = [] }
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let current = fence {
                if trimmed.hasPrefix(current) { flush(); fence = nil; kind = .paragraph }
                else { buffer.append(line) }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush(); fence = String(trimmed.prefix(3)); kind = .code
                continue
            }
            if trimmed.isEmpty { flush(); kind = .paragraph; continue }
            if trimmed.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil {
                flush(); result.append(.init(kind: .heading, text: String(trimmed.drop(while: { $0 == "#" || $0 == " " }))))
                continue
            }
            let next: Kind
            if trimmed.hasPrefix("> ") { next = .quote }
            else if trimmed.range(of: #"^(?:[-*+] |\d+[.)] )"#, options: .regularExpression) != nil { next = .list }
            else if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") { next = .table }
            else { next = .paragraph }
            if kind != next || next == .list { flush(); kind = next }
            buffer.append(next == .quote ? String(trimmed.dropFirst(2)) : line)
        }
        flush()
        return result
    }
}
