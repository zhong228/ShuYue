import CryptoKit
import Foundation
import UIKit

/// How the reader shows 整章翻譯. Part of `ReaderRenderSettings`, so switching it re-runs layout.
struct ReaderTranslationPresentation: Equatable, Codable, Sendable {
    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case off, bilingual, translationOnly
        var id: String { rawValue }
    }

    var mode: Mode = .off
    var language: AIAnswerLanguage = .current

    static let off = ReaderTranslationPresentation(mode: .off)
    var isActive: Bool { mode != .off }
}

/// The paragraphs of a chapter as translation sees them.
///
/// The translator and the layout both cut the chapter with this, so a translation is always
/// found again by the text it was made from — not by an offset that a font change, a
/// replace rule or 繁簡轉換 would move.
enum ReaderTranslationText {
    struct Paragraph: Equatable, Sendable {
        /// The paragraph's text, without its line break.
        let range: NSRange
        /// The line break that ends it; nil for the last paragraph of the chapter.
        let terminator: NSRange?
        /// The text a translation is stored under: trimmed of indentation and attachments.
        let key: String
    }

    private static let terminators: Set<unichar> = [0x0A, 0x2028, 0x2029]
    /// Indentation, attachments (images, tables) and zero-width marks are not text to translate.
    private static let trimmed = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{3000}\u{FFFC}\u{200B}\u{FEFF}"))

    /// Whether a UTF-16 unit is indentation, an attachment or a zero-width mark rather than text.
    static func isPadding(_ unit: unichar) -> Bool {
        Unicode.Scalar(unit).map(trimmed.contains) ?? false
    }

    static func paragraphs(in text: String) -> [Paragraph] {
        let string = text as NSString
        let length = string.length
        var result: [Paragraph] = []
        var start = 0
        while start < length {
            var end = start
            while end < length, !terminators.contains(string.character(at: end)) { end += 1 }
            let range = NSRange(location: start, length: end - start)
            let key = string.substring(with: range).trimmingCharacters(in: trimmed)
            if key.unicodeScalars.contains(where: CharacterSet.letters.contains) {
                result.append(Paragraph(range: range, terminator: end < length ? NSRange(location: end, length: 1) : nil, key: key))
            }
            start = end + 1
        }
        return result
    }

    /// Where a translation is stored: a digest of the paragraph's text, so the store holds no
    /// book text of its own.
    static func storageKey(_ paragraphKey: String) -> String {
        SHA256.hash(data: Data(paragraphKey.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// A chapter laid out with its translation, and the map between what the engine lays out
/// (display text) and the chapter's own text (source text).
///
/// Everything outside the layout engines works in source coordinates — reading positions,
/// bookmarks, highlights, TTS, AI citations — so turning translation on or off moves none of
/// them. A place inside a translation has no source character of its own: it is written as
/// the source offset the translation hangs off (`anchor`) plus `translationOffset` into it.
/// That is what lets a page that starts halfway through a translation be found again, which
/// page turning depends on: the page after a position must never be the page it is on.
struct ReaderTranslationLayout: Equatable, Sendable {
    typealias Mode = ReaderTranslationPresentation.Mode

    struct Block: Equatable, Sendable {
        /// The translated paragraph's source text, without its line break.
        let source: NSRange
        /// The source offset positions inside the translation are written against: the
        /// paragraph's line break (or last character) when the original stays on screen, its
        /// first character when the translation takes its place.
        let anchor: Int
        /// Everything the block adds to the display text.
        let inserted: NSRange
        /// The translation itself, inside `inserted`.
        let translation: NSRange
    }

    let mode: Mode
    let sourceText: String
    let sourceLength: Int
    let displayLength: Int
    let blocks: [Block]
    /// Display text copied unchanged from the source, in order; the gaps are blocks.
    private let copies: [Copy]

    private struct Copy: Equatable, Sendable {
        let source: Int
        let display: Int
        let length: Int
    }

    /// The attribute marking translated text in the display string.
    static let attribute = NSAttributedString.Key("YDReaderTranslation")

    /// Splices the translations `translation(key)` returns into `source`. Nil when no
    /// paragraph has one, so an untranslated chapter keeps its document untouched.
    static func splice(_ source: NSAttributedString, mode: Mode,
                       translation: (String) -> String?) -> (display: NSAttributedString, layout: ReaderTranslationLayout)? {
        guard mode != .off else { return nil }
        let text = source.string
        let display = NSMutableAttributedString()
        var blocks: [Block] = []
        var copies: [Copy] = []
        var cursor = 0

        func copy(upTo end: Int) {
            guard end > cursor else { return }
            copies.append(Copy(source: cursor, display: display.length, length: end - cursor))
            display.append(source.attributedSubstring(from: NSRange(location: cursor, length: end - cursor)))
            cursor = end
        }

        for paragraph in ReaderTranslationText.paragraphs(in: text) {
            guard let raw = translation(paragraph.key) else { continue }
            let translated = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty, let look = look(of: paragraph.range, in: source) else { continue }
            let attributes = look.attributes
            let block: Block
            switch mode {
            case .off:
                return nil
            case .bilingual:
                if let terminator = paragraph.terminator {
                    copy(upTo: NSMaxRange(terminator))
                    let start = display.length
                    let separator = (text as NSString).substring(with: terminator)
                    display.append(NSAttributedString(string: translated, attributes: attributes))
                    display.append(NSAttributedString(string: separator, attributes: attributes))
                    block = Block(source: paragraph.range, anchor: terminator.location,
                                  inserted: NSRange(location: start, length: display.length - start),
                                  translation: NSRange(location: start, length: (translated as NSString).length))
                } else {
                    // The chapter's last paragraph: the translation needs a line break of its own.
                    copy(upTo: NSMaxRange(paragraph.range))
                    let start = display.length
                    display.append(NSAttributedString(string: "\n", attributes: attributes))
                    display.append(NSAttributedString(string: translated, attributes: attributes))
                    block = Block(source: paragraph.range, anchor: NSMaxRange(paragraph.range) - 1,
                                  inserted: NSRange(location: start, length: display.length - start),
                                  translation: NSRange(location: start + 1, length: (translated as NSString).length))
                }
            case .translationOnly:
                copy(upTo: paragraph.range.location)
                let start = display.length
                display.append(NSAttributedString(string: translated, attributes: attributes))
                block = Block(source: paragraph.range, anchor: paragraph.range.location,
                              inserted: NSRange(location: start, length: display.length - start),
                              translation: NSRange(location: start, length: display.length - start))
                cursor = NSMaxRange(paragraph.range)
            }
            if let bubble = look.bubble {
                ReaderDialogueBubbleMarker.markAdded(block.translation, like: bubble, in: display)
            }
            blocks.append(block)
        }
        guard !blocks.isEmpty else { return nil }
        copy(upTo: source.length)
        let layout = ReaderTranslationLayout(mode: mode, sourceText: text, sourceLength: source.length,
                                             displayLength: display.length, blocks: blocks, copies: copies)
        return (display, layout)
    }

    // MARK: - Look

    private struct Look {
        let attributes: [NSAttributedString.Key: Any]
        /// The 對話氣泡 the paragraph is drawn in; its translation gets a bubble of its own.
        let bubble: ReaderDialogueBubbleMark?
    }

    /// What a paragraph's translation looks like: the paragraph's main text — the style
    /// covering most of its visible characters, not its first character, which may be a bold
    /// lead-in (`<b>周明瑞：</b>…`) or a quote mark 對話氣泡 has hidden — as the book set it:
    /// a regex highlight is the reader's own decoration, laid over the laid-out text again on
    /// every appearance change.
    ///
    /// The translation also takes every box that text's colour was chosen against. 诡秘之主's
    /// `<span class="look">` headings are white on an orange inline box; a translation with
    /// the white and without the box was invisible on the page. So it keeps the inline box,
    /// joins the paragraph's block and container boxes, and gets a bubble of its own.
    ///
    /// Nil when none of the paragraph is visible text of its own — a designed chapter title is
    /// drawn from its render plan over clear placeholder characters — so nothing on the page
    /// could carry a translation.
    private static func look(of paragraph: NSRange, in source: NSAttributedString) -> Look? {
        let text = NSMutableAttributedString(attributedString: source.attributedSubstring(from: paragraph))
        do {
            // Restores what the highlight overwrote; a disabled configuration evaluates nothing.
            try RegexHighlightEngine.apply(configuration: .disabled, appearance: .light, to: text)
        } catch {
            AppLogger.render("regex highlight restore failed while styling a translation",
                             context: ["error": String(describing: error)])
        }
        let string = text.string as NSString
        var weights: [Signature: Int] = [:]
        var main: (signature: Signature, attributes: [NSAttributedString.Key: Any])?
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length), options: []) { attributes, range, _ in
            guard isVisible(attributes) else { return }
            var visible = 0
            for index in range.location..<NSMaxRange(range) where !ReaderTranslationText.isPadding(string.character(at: index)) {
                visible += 1
            }
            guard visible > 0 else { return }
            let signature = Signature(attributes)
            weights[signature, default: 0] += visible
            // Ties go to the earlier style.
            if let current = main, current.signature == signature || weights[current.signature, default: 0] >= weights[signature, default: 0] {
                return
            }
            main = (signature, attributes)
        }
        guard let main else { return nil }
        var attributes: [NSAttributedString.Key: Any] = [attribute: true]
        for key in lookKeys + boxKeys { if let value = main.attributes[key] { attributes[key] = value } }
        return Look(attributes: attributes, bubble: main.attributes[ReaderDialogueBubbleMarker.attributeKey] as? ReaderDialogueBubbleMark)
    }

    /// Runs styled alike, for finding the paragraph's main text.
    private struct Signature: Hashable {
        let font: UIFont?
        let color: UIColor?
        let boxed: Bool

        init(_ attributes: [NSAttributedString.Key: Any]) {
            font = attributes[.font] as? UIFont
            color = attributes[.foregroundColor] as? UIColor
            boxed = attributes[HTMLAttributedStringBuilder.inlineBorderBoxAttribute] != nil
        }
    }

    /// Whether text with these attributes shows on the page as itself. Clear text does not:
    /// the quote marks 對話氣泡 hides in place, a designed title's placeholder characters —
    /// unless it is outlined, drawn by its stroke alone.
    private static func isVisible(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard attributes[ChapterTitleAttributedBuilder.designRenderPlanAttribute] == nil else { return false }
        if ((attributes[.foregroundColor] as? UIColor)?.cgColor.alpha ?? 1) > 0.01 { return true }
        guard let width = attributes[.strokeWidth] as? NSNumber, width.doubleValue != 0 else { return false }
        return ((attributes[.strokeColor] as? UIColor)?.cgColor.alpha ?? 0) > 0.01
    }

    /// The text's look: font (a synthesized italic lives in its matrix, a synthesized bold in
    /// the stroke), paragraph style, colour, and the marks that keep an authored colour
    /// through a theme change. Not the language attribute: it would tell CoreText to break an
    /// English translation like the Chinese it came from. Not kern either: letter spacing set
    /// for Chinese pulls English words apart (seen in 诡秘之主's spaced verse lines). Never a
    /// link, anchor or attachment, which would turn the translation into something it is not.
    private static let lookKeys: [NSAttributedString.Key] = [
        .font, .paragraphStyle, .foregroundColor, .ligature, .strokeWidth, .strokeColor,
        NSAttributedString.Key(kCTVerticalFormsAttributeName as String),
        HTMLAttributedStringBuilder.cssSpecifiedForegroundColorAttribute,
        HTMLAttributedStringBuilder.cssSpecifiedDarkForegroundColorAttribute,
    ]

    /// The boxes the text's colour was chosen against. Block boxes are drawn around every
    /// line carrying their id, so the translation is drawn inside its paragraph's box.
    private static let boxKeys: [NSAttributedString.Key] = [
        HTMLAttributedStringBuilder.inlineBorderBoxAttribute,
        HTMLAttributedStringBuilder.blockBackgroundColorAttribute,
        HTMLAttributedStringBuilder.blockDarkBackgroundColorAttribute,
        HTMLAttributedStringBuilder.blockRenderStyleAttribute,
        HTMLAttributedStringBuilder.blockRenderIDAttribute,
        HTMLAttributedStringBuilder.containerBlockRenderStyleAttribute,
        HTMLAttributedStringBuilder.containerBlockRenderIDAttribute,
        HTMLAttributedStringBuilder.outerContainerBlockRenderStyleAttribute,
        HTMLAttributedStringBuilder.outerContainerBlockRenderIDAttribute,
    ]

    // MARK: - Positions

    /// The display offset of a source position. `translationOffset` places it inside the
    /// translation hanging off `charOffset`; without one, or once that translation is gone,
    /// it is the source character's own place.
    func displayOffset(charOffset: Int, translationOffset: Int?) -> Int {
        if charOffset >= sourceLength { return displayLength }
        let offset = max(0, charOffset)
        if let translationOffset, let block = block(anchoredAt: offset) {
            return block.inserted.location + min(max(0, translationOffset), max(0, block.inserted.length - 1))
        }
        if let copy = copy(containingSource: offset) {
            return copy.display + (offset - copy.source)
        }
        // Inside a paragraph the translation replaced: the same share of the way through it.
        if let block = blocks.first(where: { NSLocationInRange(offset, $0.source) }) {
            let share = Double(offset - block.source.location) / Double(max(1, block.source.length))
            return block.inserted.location + min(block.inserted.length - 1, Int(share * Double(block.inserted.length)))
        }
        return displayLength
    }

    /// The source position of a display offset: a source character, or the translation's
    /// anchor and how far into the translation it is.
    func sourcePosition(displayOffset: Int) -> (charOffset: Int, translationOffset: Int?) {
        if displayOffset >= displayLength { return (sourceLength, nil) }
        let offset = max(0, displayOffset)
        if let copy = copy(containingDisplay: offset) {
            return (copy.source + (offset - copy.display), nil)
        }
        guard let block = blocks.first(where: { NSLocationInRange(offset, $0.inserted) }) else { return (sourceLength, nil) }
        let into = offset - block.inserted.location
        switch mode {
        case .translationOnly:
            // The approximate source character, so a reader who turns translation off lands in
            // the same paragraph at about the same place.
            let share = Double(into) / Double(max(1, block.inserted.length))
            return (block.source.location + min(max(0, block.source.length - 1), Int(share * Double(block.source.length))), into)
        case .bilingual, .off:
            return (block.anchor, into)
        }
    }

    /// Where a stretch of source text is on screen. Parts hidden behind a translation are
    /// left out; they have nowhere to be drawn.
    func displayRanges(forSource range: NSRange) -> [NSRange] {
        guard range.length > 0 else { return [] }
        var result: [NSRange] = []
        for copy in copies {
            let start = max(range.location, copy.source)
            let end = min(NSMaxRange(range), copy.source + copy.length)
            guard start < end else { continue }
            let mapped = NSRange(location: copy.display + (start - copy.source), length: end - start)
            if let last = result.last, NSMaxRange(last) == mapped.location {
                result[result.count - 1] = NSRange(location: last.location, length: last.length + mapped.length)
            } else {
                result.append(mapped)
            }
        }
        return result
    }

    /// The source text a display selection covers, or nil when it takes in any translation:
    /// a highlight or note needs characters of the book itself.
    func sourceRange(forDisplay range: NSRange) -> NSRange? {
        guard !isTranslation(range) else { return nil }
        let start = sourcePosition(displayOffset: range.location)
        guard start.translationOffset == nil else { return nil }
        return NSRange(location: start.charOffset, length: range.length)
    }

    /// Whether any of `range` is translation rather than the book's own text.
    func isTranslation(_ range: NSRange) -> Bool {
        blocks.contains { block in
            range.length == 0 ? NSLocationInRange(range.location, block.inserted)
                : NSIntersectionRange(range, block.inserted).length > 0
        }
    }

    private func block(anchoredAt offset: Int) -> Block? {
        switch mode {
        case .translationOnly:
            return blocks.first { offset >= $0.source.location && offset < max(NSMaxRange($0.source), $0.source.location + 1) }
        case .bilingual, .off:
            return blocks.first { $0.anchor == offset }
        }
    }

    private func copy(containingSource offset: Int) -> Copy? {
        var low = 0, high = copies.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let copy = copies[middle]
            if offset < copy.source { high = middle - 1 }
            else if offset >= copy.source + copy.length { low = middle + 1 }
            else { return copy }
        }
        return nil
    }

    private func copy(containingDisplay offset: Int) -> Copy? {
        var low = 0, high = copies.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let copy = copies[middle]
            if offset < copy.display { high = middle - 1 }
            else if offset >= copy.display + copy.length { low = middle + 1 }
            else { return copy }
        }
        return nil
    }
}
