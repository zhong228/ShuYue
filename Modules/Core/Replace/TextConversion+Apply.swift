import Foundation

// MARK: - 繁簡轉換

extension TextConversion {
    /// Display name for the reading-settings picker; the raw values double as keys.
    var localizedTitle: String { localized(rawValue) }

    private var transform: StringTransform? {
        switch self {
        case .original: return nil
        case .toTraditional: return StringTransform(rawValue: "Hans-Hant")
        case .toSimplified: return StringTransform(rawValue: "Hant-Hans")
        }
    }

    /// Converts `text` without changing the UTF-16 width of any character.
    ///
    /// Reading positions, 劃線 and bookmarks are UTF-16 offsets into this text, so switching
    /// modes must not move them. ICU runs over the whole string because it picks characters
    /// by context (复制 → 複製; one character at a time gives 復制). Any character whose
    /// result has a different width then keeps its original: under Hant → Hans, 168 rare
    /// characters (勣 → 𪟝 …) land on a supplementary plane.
    func apply(to text: String) -> String {
        guard let transform, !text.isEmpty,
              let converted = text.applyingTransform(transform, reverse: false),
              converted != text
        else { return text }

        let originals = Array(text)
        let candidates = Array(converted)
        guard originals.count == candidates.count else {
            // ICU's Han transforms substitute character for character: 27,584 ideographs and
            // both of the app's string tables converted without a count change. Guards a future
            // ICU that merges or splits characters, which could not be aligned; the text stays
            // as authored instead of shifting every offset after the change. Once diagnostics
            // exports have never shown this line, it can become an assertion.
            AppLogger.render("繁簡轉換：轉換後字數改變，保留原文", context: [
                "mode": rawValue,
                "characters": "\(originals.count)→\(candidates.count)",
                "sample": String(text.prefix(40)),
            ])
            return text
        }

        var result = String()
        result.reserveCapacity(converted.utf8.count)
        for (original, candidate) in zip(originals, candidates) {
            result.append(original.utf16.count == candidate.utf16.count ? candidate : original)
        }
        return result
    }

    /// The same conversion in place. The converted text has the same UTF-16 layout, so each
    /// attribute run is copied onto exactly the characters it covered.
    func apply(to attributed: NSMutableAttributedString) {
        guard transform != nil, attributed.length > 0 else { return }
        let original = attributed.string
        let converted = apply(to: original)
        guard converted != original else { return }

        let rebuilt = NSMutableAttributedString(string: converted)
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length)
        ) { attributes, range, _ in
            rebuilt.setAttributes(attributes, range: range)
        }
        attributed.setAttributedString(rebuilt)
    }
}

extension String {
    func converted(to mode: TextConversion) -> String {
        mode.apply(to: self)
    }
}
