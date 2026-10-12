import Foundation
import Testing
@testable import yuedu_app

/// Every AI answer is written in the reader's language: what they typed a question in, or the
/// interface language for a preset. It used to be 繁體中文 whatever the reader used.
@Suite("AI answer language")
struct AIAnswerLanguageTests {
    @Test(arguments: [
        ("这一章讲了什么？", AIAnswerLanguage.simplifiedChinese),
        ("這一章講了什麼？", .traditionalChinese),
        ("他后来怎么了", .simplifiedChinese),
        ("他後來怎麼了", .traditionalChinese),
        ("What happened to him after the fight?", .english),
        ("彼は誰ですか", .japanese),
        ("그는 누구야", .korean),
    ])
    func readerTextSetsTheLanguage(text: String, expected: AIAnswerLanguage) {
        for interface in [AIAnswerLanguage.traditionalChinese, .simplifiedChinese, .english] {
            #expect(AIAnswerLanguage.of(readerText: text, otherwise: interface) == expected)
        }
    }

    /// 他去哪了 is written alike in both scripts; the recognizer's split between them is a guess
    /// and must not decide the script.
    @Test func sharedCharactersKeepTheInterfaceScript() {
        #expect(AIAnswerLanguage.of(readerText: "他去哪了", otherwise: .simplifiedChinese) == .simplifiedChinese)
        #expect(AIAnswerLanguage.of(readerText: "他去哪了", otherwise: .traditionalChinese) == .traditionalChinese)
        #expect(AIAnswerLanguage.of(readerText: "他去哪了", otherwise: .english).isChinese)
    }

    @Test func textThatDoesNotSayKeepsTheInterfaceLanguage() {
        for text in ["林黛玉", "ok", "?", ""] {
            #expect(AIAnswerLanguage.of(readerText: text, otherwise: .simplifiedChinese) == .simplifiedChinese)
        }
    }

    @Test func presetsAnswerInTheInterfaceLanguageAndTypedTextInTheReaders() {
        let book = UUID()
        let text = "柳青在桥边找到铜钥匙。"
        let source = AIBookContentAdapter(bookID: book, chapters: [.init(index: 0, title: "Fixture", content: "")]) { _ in text }
            .atReadingPosition(spine: 0, renderedOffset: text.utf16.count, renderedText: text)
        func context(_ question: String, _ action: AIReadingAction) -> AIQuestionContext {
            var context = AIQuestionContext(bookID: book, question: question, source: source, boundary: source.boundary())
            context.action = action
            return context
        }
        for action in [AIReadingAction.chapterSummary, .recap, .explain, .translate, .annotationReview] {
            #expect(context(action.title, action).answerLanguage == .current)
        }
        #expect(context("柳青找到了什么？", .question).answerLanguage == .simplifiedChinese)
        #expect(context("柳青找到了什麼？", .question).answerLanguage == .traditionalChinese)
        var custom = context("我的提示詞", .custom)
        custom.customPrompt = AICustomPrompt(title: "我的提示詞", instruction: "Summarize the characters in this chapter.")
        #expect(custom.answerLanguage == .english)
    }

    @Test func theRuleNamesTheLanguageAndLetsTheReaderAskForAnother() {
        #expect(AIAnswerLanguage.simplifiedChinese.answerRule.hasPrefix("用簡體中文回答"))
        #expect(AIAnswerLanguage.english.answerRule.contains("讀者明確要求其他語言時，照讀者的要求"))
        #expect(!AIRAGPipeline.systemPrompt(for: [], language: .english).contains("繁體中文"))
    }
}
