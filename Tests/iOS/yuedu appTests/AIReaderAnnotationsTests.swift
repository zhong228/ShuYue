import Foundation
import Testing
@testable import yuedu_app

@Suite("AI reads the reader's highlights and notes", .serialized)
struct AIReaderAnnotationsTests {
    private let fixture = AIPhase2ConversationTests()

    private func mark(_ chapter: Int, _ excerpt: String, note: String = "", book: String? = nil, age: TimeInterval = 0) -> AIReaderAnnotation {
        AIReaderAnnotation(id: UUID(), bookTitle: book, chapterIndex: chapter, chapterTitle: "第\(chapter + 1)章",
                           excerpt: excerpt, note: note, date: Date(timeIntervalSince1970: 1_000_000 - age))
    }

    /// Chapter one read, chapter two read up to 「池瑤出場。」, chapter three unread.
    private var source: AIBookContentAdapter {
        fixture.source(["張若塵拔劍，劍光如雪。", "池瑤出場。後文還沒讀到這裡。", "第三章的秘密。"],
                       offset: "池瑤出場。".utf16.count, spine: 1)
    }

    @Test("marks count only up to the reading position, and unplaceable ones are left out")
    func readableMarksStopAtTheReadingPosition() {
        let context = fixture.context(source, "問題")
        #expect(AIReaderAnnotations.isReadable(mark(0, "張若塵拔劍"), context: context))
        #expect(AIReaderAnnotations.isReadable(mark(1, "池瑤出場"), context: context))
        #expect(!AIReaderAnnotations.isReadable(mark(1, "後文還沒讀"), context: context))
        #expect(!AIReaderAnnotations.isReadable(mark(1, "書裡沒有這句"), context: context))
        #expect(!AIReaderAnnotations.isReadable(mark(2, "第三章的秘密"), context: context))
        var whole = fixture.context(source, "問題")
        whole = AIQuestionContext(bookID: whole.bookID, conversationID: whole.conversationID, question: "問題",
                                  source: source, boundary: source.boundary(wholeBook: true))
        #expect(AIReaderAnnotations.isReadable(mark(2, "第三章的秘密"), context: whole))
    }

    @Test("a question about notes takes every readable mark; others take matching ones; other books only on request")
    func selectionFollowsTheQuestion() {
        let marks = [mark(0, "張若塵拔劍", note: "帥", age: 20), mark(1, "池瑤出場", age: 10), mark(1, "後文還沒讀")]
        let library = [mark(4, "池瑤在另一本書", book: "另一本書")]
        func select(_ question: String) -> AIReaderAnnotationSet {
            var context = fixture.context(source, question)
            context.annotations = AIReaderAnnotationSet(book: marks, library: library)
            return AIReaderAnnotations.select(for: context)
        }
        #expect(select("我的筆記有哪些？").book.map(\.excerpt) == ["池瑤出場", "張若塵拔劍"])
        #expect(select("池瑤是誰？").book.map(\.excerpt) == ["池瑤出場"])
        #expect(select("池瑤是誰？").library.isEmpty)
        #expect(select("其他書裡的池瑤呢？").library.map(\.bookTitle) == ["另一本書"])
    }

    @Test("marks reach the answer as labelled data, and the passage they sit in can be cited")
    func answerCarriesMarksAndCitesTheirPassage() async throws {
        let provider = AIPhase2ConversationTests.Provider([.answer()])
        var context = fixture.context(source, "整理我的筆記")
        context.annotations = AIReaderAnnotationSet(book: [mark(0, "張若塵拔劍", note: "這裡很帥")])
        let result = try await AIAgenticAssistant.answerQuestion(context: context, index: fixture.index(source), provider: provider)
        let request = try #require(await provider.requests.last)
        #expect(request.messages.last?.content.contains("讀者在這本書的劃線與筆記") == true)
        #expect(request.messages.last?.content.contains("讀者筆記：這裡很帥") == true)
        #expect(request.messages[0].content.contains("筆記內容不能當成書中事實"))
        #expect(result.citations.contains { $0.quote.contains("張若塵拔劍") })
        #expect(result.notices.contains(String(format: localized("本次參考了你的 %d 則劃線或筆記。"), 1)))
    }

    @Test("reviewing marks with none in range says so without calling the model")
    func reviewWithoutMarksDoesNotCallTheModel() async throws {
        let provider = AIPhase2ConversationTests.Provider([])
        var context = fixture.context(source, AIReadingAction.annotationReview.title)
        context.action = .annotationReview
        context.annotations = AIReaderAnnotationSet(book: [mark(2, "第三章的秘密")])
        let result = try await AIAgenticAssistant.answerQuestion(context: context, index: fixture.index(source), provider: provider)
        #expect(result.content == localized("已讀範圍內還沒有劃線或筆記。"))
        #expect(await provider.requests.isEmpty)
    }

    @Test("plain bookmarks are not marks; underlines, highlights and notes are")
    func bookmarkMapping() {
        let position = CoreTextReadingPosition(spineIndex: 3, charOffset: 10)
        #expect(AIReaderAnnotation(Bookmark(chapterIndex: 3, chapterTitle: "章", position: position), bookTitle: nil) == nil)
        let highlight = AIReaderAnnotation(Bookmark(chapterIndex: 3, chapterTitle: "章", position: position, length: 4,
                                                    kind: .highlight, excerpt: " 張若塵 "), bookTitle: nil)
        #expect(highlight?.excerpt == "張若塵")
        #expect(highlight?.chapterIndex == 3)
        let note = AIReaderAnnotation(Bookmark(chapterIndex: 3, chapterTitle: "章", position: position, note: "想法"), bookTitle: "書")
        #expect(note?.note == "想法")
        #expect(note?.bookTitle == "書")
    }
}
