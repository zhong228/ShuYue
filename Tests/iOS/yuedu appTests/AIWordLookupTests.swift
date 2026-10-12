import Foundation
import Testing
@testable import yuedu_app

@Suite("AI word lookup")
struct AIWordLookupTests {

    @Test("words and short phrases get 查詞 in place of 解釋; longer selections keep 解釋")
    func selectionMenuSwapsExplainForShortSelections() {
        #expect(AIReadingAction.selectionMenu(for: "聖者") == [.question, .lookup, .translate])
        #expect(AIReadingAction.selectionMenu(for: String(repeating: "字", count: 20)) == [.question, .lookup, .translate])
        #expect(AIReadingAction.selectionMenu(for: String(repeating: "字", count: 21)) == [.question, .explain, .translate])
        #expect(AIReadingAction.selectionMenu(for: "第一句。\n第二句。") == [.question, .explain, .translate])
        #expect(!AIWordLookup.isCandidate("  \n "))
        #expect(AIWordLookup.isCandidate(" serendipity "))
        // An emoji sequence is one character, however many code units it takes.
        #expect(AIWordLookup.isCandidate(String(repeating: "👩🏽‍🚀", count: 20)))
    }

    @Test("the context is the selection's paragraph up to the end of its sentence, never the next one")
    func contextStopsAtTheSentenceEnd() {
        let text = "上一段不該出現。\n張若塵抬頭，看見池瑤踏入聖者境界。「這不可能！」他說。後面的劇情不能送出去。\n下一段。"
        let range = (text as NSString).range(of: "聖者")
        let context = AIWordLookup.context(in: text, range: range)
        #expect(context == "張若塵抬頭，看見池瑤踏入聖者境界。")

        let quoted = "他低聲說：「此乃聖者之物。」旁人皆驚。"
        let quote = AIWordLookup.context(in: quoted, range: (quoted as NSString).range(of: "聖者"))
        #expect(quote == "他低聲說：「此乃聖者之物。」")
    }

    @Test("long paragraphs send a bounded lead-in that never splits a character")
    func contextLeadInIsBounded() {
        let lead = String(repeating: "👩🏽‍🚀", count: 100)
        let text = lead + "目標詞在這裡。"
        let range = (text as NSString).range(of: "目標詞")
        let context = AIWordLookup.context(in: text, range: range)
        #expect(context.hasSuffix("目標詞在這裡。"))
        #expect(context.utf16.count <= AIWordLookup.leadingContext + "目標詞在這裡。".utf16.count)
        #expect(context.unicodeScalars.first == "👩")
    }

    @Test("the request carries the word, its sentence, the book and the answer language")
    func requestContents() {
        let request = AIWordLookup.request(term: "聖者", context: "踏入聖者境界。", bookTitle: "萬古神帝", language: .simplifiedChinese)
        #expect(request.messages.count == 2)
        #expect(request.messages[0].role == .system)
        #expect(request.messages[0].content.contains("用簡體中文回答"))
        #expect(request.messages[1].content == "書名：萬古神帝\n選取：聖者\n上下文：踏入聖者境界。")
    }

    @Test("interface languages map to the answer language")
    func answerLanguageMatching() {
        #expect(AIAnswerLanguage.matching("zh-Hant") == .traditionalChinese)
        #expect(AIAnswerLanguage.matching("zh-TW") == .traditionalChinese)
        #expect(AIAnswerLanguage.matching("zh-HK") == .traditionalChinese)
        #expect(AIAnswerLanguage.matching("zh-Hans") == .simplifiedChinese)
        #expect(AIAnswerLanguage.matching("zh-CN") == .simplifiedChinese)
        #expect(AIAnswerLanguage.matching("en-GB") == .english)
        #expect(AIAnswerLanguage.matching("ja_JP") == .japanese)
        #expect(AIAnswerLanguage.matching("pt-BR") == .english)
        #expect(AIAnswerLanguage.matching(nil) == .english)
    }

    @Test @MainActor func streamedAnswerFinishes() async {
        let model = AIWordLookupModel(term: "聖者", context: "踏入聖者境界。", bookTitle: nil, bookID: UUID(),
                                      provider: StreamingProvider(chunks: ["這裡指", "修煉境界。"]), origin: .testFixture)
        model.start()
        await model.wait()
        #expect(model.state == .finished("這裡指修煉境界。"))
    }

    @Test @MainActor func emptyAnswerIsAnError() async {
        let model = AIWordLookupModel(term: "聖者", context: "", bookTitle: nil, bookID: UUID(),
                                      provider: StreamingProvider(chunks: [" ", "\n"]), origin: .testFixture)
        model.start()
        await model.wait()
        #expect(model.state == .failed(LLMError.emptyOutput.localizedDescription))
    }

    private struct StreamingProvider: LLMProviding {
        let chunks: [String]
        let identifier = "lookup-fixture"
        let defaultModel = "fixture"
        func generate(_ request: LLMGenerationRequest, model: String?) async throws -> LLMRawResponse {
            .init(content: chunks.joined(), provider: identifier, model: defaultModel, finishReason: "stop")
        }
        func stream(_ request: LLMGenerationRequest, model: String?) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        }
    }
}
