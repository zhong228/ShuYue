import Foundation

enum AIReadingAction: String, Codable, CaseIterable, Sendable {
    case question, explain, translate, chapterSummary, recap, custom, annotationReview
    /// AI 查詞. Answered on its own card, never through the assistant's question pipeline.
    case lookup

    var title: String {
        switch self {
        case .question: return localized("問 AI")
        case .explain: return localized("AI 解釋")
        case .translate: return localized("AI 翻譯")
        case .chapterSummary: return localized("本章已讀摘要")
        case .recap: return localized("前情回顧")
        case .custom: return localized("自訂提示詞")
        case .annotationReview: return localized("整理我的劃線")
        case .lookup: return localized("AI 查詞")
        }
    }

    /// The AI items of the reader's selection menu. A word or short phrase gets 查詞 in place
    /// of 解釋, so the menu stays the same length.
    static func selectionMenu(for text: String) -> [AIReadingAction] {
        [.question, AIWordLookup.isCandidate(text) ? .lookup : .explain, .translate]
    }
}

/// A selection is tied to source coordinates, never to the current page number.
struct AIReadingSelection: Codable, Equatable, Sendable {
    let bookID: UUID
    let spineIndex: Int
    let range: NSRange
    let text: String
    var originalText: String? = nil
    var displayText: String { originalText ?? text }

    func validated(in source: AIBookContentAdapter, boundary: AIReadingBoundary) -> Bool {
        guard bookID == source.chunkBookID, boundary.sourceVersion == source.contentFingerprint,
              source.chunkSections.indices.contains(spineIndex), range.location >= 0,
              range.length > 0, range.location <= Int.max - range.length,
              let swiftRange = Range(range, in: source.chunkSections[spineIndex].text),
              NSRange(swiftRange, in: source.chunkSections[spineIndex].text) == range,
              source.chunkSections[spineIndex].text.indices.contains(swiftRange.lowerBound),
              (swiftRange.upperBound == source.chunkSections[spineIndex].text.endIndex || source.chunkSections[spineIndex].text.indices.contains(swiftRange.upperBound)),
              text.utf16.count == range.length,
              String(source.chunkSections[spineIndex].text[swiftRange]) == text else { return false }
        return boundary.allows(.init(spineIndex: spineIndex, charOffset: NSMaxRange(range), progress: 0))
    }
}

struct AIReadingLaunch: Identifiable, Sendable {
    let id = UUID()
    let action: AIReadingAction
    var selection: AIReadingSelection?
    var renderedChapterText: String? = nil

    func resolvingSelection(in source: AIBookContentAdapter) -> Self {
        guard let selection, let renderedChapterText,
              source.chunkBookID == selection.bookID, source.chunkSections.indices.contains(selection.spineIndex),
              let renderedRange = Range(selection.range, in: renderedChapterText),
              String(renderedChapterText[renderedRange]) == selection.text else { return self }
        let text = source.chunkSections[selection.spineIndex].text
        guard let range = AITextCoordinates.mappedRange(selection.range, from: renderedChapterText, to: text),
              let swiftRange = Range(range, in: text) else { return self }
        var result = self
        var resolved = AIReadingSelection(bookID: selection.bookID, spineIndex: selection.spineIndex, range: range, text: String(text[swiftRange]))
        resolved.originalText = selection.text
        result.selection = resolved
        result.renderedChapterText = nil
        return result
    }
}

struct AICustomPrompt: Identifiable, Codable, Equatable, Sendable {
    enum Context: String, Codable, CaseIterable, Sendable {
        case selection, chapter, book
        var title: String {
            switch self {
            case .selection: return localized("選取文字")
            case .chapter: return localized("目前章節")
            case .book: return localized("本書問答")
            }
        }
    }
    var id = UUID()
    var title: String
    var instruction: String
    var context: Context = .book
    var isEnabled = true
}
