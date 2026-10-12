import Foundation

/// A highlight, underline or note the reader made, as the assistant may read it.
///
/// The excerpt is the book's own text at that spot; the note is the reader's writing. The
/// prompt keeps them apart: a note is the reader's view, never evidence of what the book says.
struct AIReaderAnnotation: Equatable, Sendable {
    let id: UUID
    /// The other book's title, for marks from elsewhere on the shelf; `nil` for this book.
    let bookTitle: String?
    let chapterIndex: Int
    let chapterTitle: String
    let excerpt: String
    let note: String
    let date: Date
}

/// The reader's marks offered to one request.
struct AIReaderAnnotationSet: Equatable, Sendable {
    var book: [AIReaderAnnotation] = []
    /// Other books' marks. Filled only for questions that reach across the shelf.
    var library: [AIReaderAnnotation] = []
}

enum AIReaderAnnotations {
    /// A question about the reader's own marks gets all of them that are readable, newest first.
    static let noteTerms = ["筆記", "笔记", "劃線", "划线", "畫線", "画线", "標註", "标注", "標記", "标记", "摘錄", "摘录",
                            "highlight", "underline", "annotation", "my note"]
    /// A question reaching past this book searches the other books' marks too.
    static let libraryTerms = ["其他書", "其他书", "別本書", "别本书", "別的書", "别的书", "跨書", "跨书", "所有書", "所有书",
                               "書架", "书架", "other book", "my library"]
    /// Items and characters of marks per request, so they cannot crowd out the book's text.
    static let maximumItems = 30
    static let maximumCharacters = 4_000
    /// Marks matched by words when the question is not about marks as such.
    static let maximumMatches = 8

    static func asksAboutNotes(_ question: String) -> Bool {
        noteTerms.contains { question.localizedCaseInsensitiveContains($0) }
    }

    static func asksAcrossBooks(_ question: String) -> Bool {
        libraryTerms.contains { question.localizedCaseInsensitiveContains($0) }
    }

    /// The marks this request uses, within the spoiler boundary and the size limits.
    static func select(for context: AIQuestionContext) -> AIReaderAnnotationSet {
        let readable = context.annotations.book.filter { isReadable($0, context: context) }
        let book: [AIReaderAnnotation]
        if context.action == .annotationReview || asksAboutNotes(context.question) {
            book = readable.sorted { $0.date > $1.date }
        } else {
            var query = context.question
            if let selection = context.selection { query += "\n" + selection.text }
            book = ranked(readable, query: query)
        }
        var library: [AIReaderAnnotation] = []
        if asksAcrossBooks(context.question) { library = ranked(context.annotations.library, query: context.question) }
        var budget = maximumCharacters
        var count = 0
        func fits(_ mark: AIReaderAnnotation) -> Bool {
            let size = mark.excerpt.count + mark.note.count
            guard count < maximumItems, size <= budget else { return false }
            budget -= size; count += 1
            return true
        }
        let keptBook = book.filter(fits)
        return AIReaderAnnotationSet(book: keptBook, library: library.filter(fits))
    }

    /// Earlier chapters are always readable. In the chapter being read, a mark counts only
    /// when its excerpt is found in the source before the reading position — a mark that
    /// cannot be placed is left out rather than risk a later passage.
    static func isReadable(_ mark: AIReaderAnnotation, context: AIQuestionContext) -> Bool {
        let boundary = context.boundary
        if boundary.wholeBook || mark.chapterIndex < boundary.spineIndex { return true }
        guard mark.chapterIndex == boundary.spineIndex, !mark.excerpt.isEmpty,
              context.source.chunkSections.indices.contains(mark.chapterIndex) else { return false }
        let text = context.source.chunkSections[mark.chapterIndex].text
        guard let range = text.range(of: mark.excerpt) else { return false }
        return range.upperBound.utf16Offset(in: text) <= boundary.utf16Offset
    }

    private static func ranked(_ marks: [AIReaderAnnotation], query: String) -> [AIReaderAnnotation] {
        struct Scored { let mark: AIReaderAnnotation; let score: Double }
        var scored: [Scored] = []
        for mark in marks {
            let score = AIQuestionSourceReader.literalScore(query, text: mark.excerpt + "\n" + mark.note)
            if score > 0 { scored.append(Scored(mark: mark, score: score)) }
        }
        scored.sort { $0.score == $1.score ? $0.mark.date > $1.mark.date : $0.score > $1.score }
        return scored.prefix(maximumMatches).map(\.mark)
    }

    /// The marks as user-role data. Labelled so the model tells the reader's notes from the
    /// book, and other books from this one.
    static func promptBlock(_ marks: AIReaderAnnotationSet) -> String {
        func line(_ mark: AIReaderAnnotation) -> String {
            var text = "- "
            if let title = mark.bookTitle { text += "《\(title)》" }
            if !mark.chapterTitle.isEmpty { text += "〈\(mark.chapterTitle)〉" }
            if !mark.excerpt.isEmpty { text += "劃線原文：「\(mark.excerpt)」" }
            if !mark.note.isEmpty { text += (mark.excerpt.isEmpty ? "" : " ") + "讀者筆記：\(mark.note)" }
            return text
        }
        var blocks: [String] = []
        if !marks.book.isEmpty {
            blocks.append("讀者在這本書的劃線與筆記（讀者自己的標註；筆記是讀者的想法，不是書中事實）：\n"
                + marks.book.map(line).joined(separator: "\n"))
        }
        if !marks.library.isEmpty {
            blocks.append("讀者在其他書的劃線與筆記（不屬於這本書）：\n" + marks.library.map(line).joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    /// The indexed passages this book's marks sit in, so an answer can cite the original text.
    static func evidence(for marks: AIReaderAnnotationSet, index: AIBookRetrievalIndex,
                         context: AIQuestionContext) -> [AIQuestionEvidence] {
        var result: [AIQuestionEvidence] = []
        for mark in marks.book where !mark.excerpt.isEmpty {
            let probe = String(mark.excerpt.prefix(40))
            guard let chunk = index.chunks.first(where: {
                $0.start.spineIndex == mark.chapterIndex && context.boundary.contains($0) && $0.text.contains(probe)
            }), !result.contains(where: { $0.chunk.id == chunk.id }) else { continue }
            result.append(AIQuestionEvidence(chunk: chunk, parentChunkID: chunk.id, kind: .initial))
            if result.count >= 6 { break }
        }
        return result
    }
}
