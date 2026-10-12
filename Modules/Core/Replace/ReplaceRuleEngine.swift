import Foundation

/// Applies a list of `ReplaceRule` objects to a string.
///
/// Used after the book-source's per-source `##` replacement rules so
/// user-configured global rules run last.
///
/// Thread-safe: NSRegularExpression objects are reused via a simple cache.
enum ReplaceRuleEngine {

    // LRU-lite cache keyed by pattern string.
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    /// Apply all `rules` to `content` in order and return the result.
    static func apply(_ rules: [ReplaceRule], to content: String) -> String {
        var output = content
        for rule in rules {
            guard rule.enabled, !rule.pattern.isEmpty else { continue }
            output = apply(rule, to: output)
        }
        return output
    }

    /// Apply a single rule to `content`.
    static func apply(_ rule: ReplaceRule, to content: String) -> String {
        if rule.isRegex {
            return applyRegex(pattern: rule.pattern,
                              replacement: rule.replacement,
                              to: content)
        } else {
            return content.replacingOccurrences(of: rule.pattern, with: rule.replacement)
        }
    }

    // MARK: - Private

    private static func applyRegex(pattern: String, replacement: String, to content: String) -> String {
        guard !pattern.isEmpty else { return content }

        let regex: NSRegularExpression
        lock.lock()
        if let cached = regexCache[pattern] {
            regex = cached
            lock.unlock()
        } else {
            lock.unlock()
            guard let r = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                return content
            }
            lock.lock()
            if regexCache.count > 64 { regexCache.removeAll() } // simple eviction
            regexCache[pattern] = r
            lock.unlock()
            regex = r
        }

        // Reject expansion before allocating it. A zero-width or broad rule can
        // otherwise grow a chapter until Foundation aborts the entire process.
        // Keep the original chapter only when this externally supplied rule would
        // exceed the budget; remove this guard only when the pipeline streams output.
        let limit = max(content.utf16.count, 8 * 1024 * 1024)
        guard let output = boundedReplacement(regex, template: replacement, content: content, limit: limit) else {
            AppLogger.error("Replace rule output exceeds chapter budget", context: ["limit": "\(limit)"])
            return content
        }
        return output
    }

    private enum TemplatePart {
        case literal(String)
        case capture(Int)
    }

    /// Foundation already uses Legado's $0/$1 syntax. Backslashes escape the
    /// next character; converting $1 to \1 made it the literal character 1.
    private static func templateParts(_ template: String, captureCount: Int) -> [TemplatePart] {
        let units = Array(template.utf16)
        let maxDigits = String(captureCount).count
        var parts: [TemplatePart] = []
        var literal: [UInt16] = []
        var index = 0
        func flush() {
            if !literal.isEmpty {
                parts.append(.literal(String(decoding: literal, as: UTF16.self)))
                literal.removeAll(keepingCapacity: true)
            }
        }
        while index < units.count {
            let unit = units[index]
            index += 1
            if unit == 92, index < units.count {
                literal.append(units[index])
                index += 1
            } else if unit == 36, index < units.count, (48...57).contains(units[index]) {
                flush()
                var group = 0
                var digits = 0
                while index < units.count, digits < maxDigits, (48...57).contains(units[index]) {
                    group = group * 10 + Int(units[index] - 48)
                    index += 1
                    digits += 1
                }
                parts.append(.capture(group))
            } else if unit != 92 {
                literal.append(unit)
            }
        }
        flush()
        return parts
    }

    static func boundedReplacement(
        _ regex: NSRegularExpression, template: String, content: String, limit: Int
    ) -> String? {
        guard template.utf16.count <= limit else { return nil }
        let parts = templateParts(template, captureCount: regex.numberOfCaptureGroups)
        let source = content as NSString
        let output = NSMutableString()
        var cursor = 0
        var remaining = limit
        var exceeded = false
        func appendRange(_ range: NSRange) {
            guard range.location != NSNotFound else { return }
            guard range.length <= remaining else { exceeded = true; return }
            remaining -= range.length
            output.append(source.substring(with: range))
        }
        regex.enumerateMatches(in: content, range: NSRange(location: 0, length: source.length)) { match, _, stop in
            guard let match else { return }
            appendRange(NSRange(location: cursor, length: match.range.location - cursor))
            for part in parts where !exceeded {
                switch part {
                case .literal(let text):
                    guard text.utf16.count <= remaining else { exceeded = true; break }
                    remaining -= text.utf16.count
                    output.append(text)
                case .capture(let group):
                    if group < match.numberOfRanges { appendRange(match.range(at: group)) }
                }
            }
            cursor = NSMaxRange(match.range)
            if exceeded { stop.pointee = true }
        }
        guard !exceeded else { return nil }
        appendRange(NSRange(location: cursor, length: source.length - cursor))
        return exceeded ? nil : output as String
    }
}
