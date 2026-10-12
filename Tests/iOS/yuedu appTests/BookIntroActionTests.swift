import Foundation
import Testing
@testable import yuedu_app

/// A 簡介 button's script runs in the book's source the way legado-E's
/// `BookInfoViewModel.onButtonClick` and MD3's `runIntroJs` run it.
@Suite("Book intro actions", .serialized)
@MainActor
struct BookIntroActionTests {
    private func source(jsLib: String = "") -> BookSource {
        var source = BookSource()
        source.bookSourceUrl = "intro-action-test-\(UUID().uuidString)"
        source.bookSourceName = "Intro action fixture"
        source.jsLib = jsLib
        return source
    }

    private let book = ReaderHTMLUtilities.LegadoSourceActionContext.BookSnapshot.detailPage(
        name: "測試書",
        author: "作者甲",
        coverURL: "https://example.com/cover.jpg",
        bookURL: "https://example.com/book/1",
        tocURL: "https://example.com/book/1/toc",
        intro: "簡介",
        runtimeVariables: [:]
    )

    private func run(
        _ script: String,
        in source: BookSource,
        variables: [String: String] = [:],
        toasts: AsyncStream<String>.Continuation? = nil
    ) async -> BookIntroActionOutcome {
        await LegadoReviewActionRunner.shared.runIntroAction(
            BookIntroAction(kind: .button, name: "按鈕", script: script),
            book: book,
            runtimeVariables: variables,
            source: source,
            presentToast: { toasts?.yield($0) }
        )
    }

    @Test("the script sees the detail page's book and its toasts reach the page", .timeLimit(.minutes(1)))
    func bindsBookAndToasts() async {
        let (toasts, continuation) = AsyncStream<String>.makeStream()
        let outcome = await run(
            "java.toast(book.name + '/' + book.author + '/' + book.bookUrl)",
            in: source(),
            toasts: continuation
        )
        var iterator = toasts.makeAsyncIterator()
        #expect(await iterator.next() == "測試書/作者甲/https://example.com/book/1")
        #expect(outcome.errorMessage == nil)
        #expect(outcome.page == nil)
        #expect(!outcome.refreshesBook)
    }

    @Test("jsLib functions and the book variable are in scope", .timeLimit(.minutes(1)))
    func callsJsLibWithBookVariable() async {
        let (toasts, continuation) = AsyncStream<String>.makeStream()
        let source = source(jsLib: "function hello(v){ java.toast('hi ' + v); }")
        _ = await run(
            #"hello(book.getVariable("custom"))"#,
            in: source,
            variables: [BookCustomVariable.key: "abc"],
            toasts: continuation
        )
        var iterator = toasts.makeAsyncIterator()
        #expect(await iterator.next() == "hi abc")
    }

    @Test("a page the script builds comes back for the detail page to show", .timeLimit(.minutes(1)))
    func returnsSourcePage() async {
        let outcome = await run(
            #"java.showBrowser("https://example.com/talk", "<html><body>討論</body></html>", "window.java=java;", "{}")"#,
            in: source()
        )
        let page = outcome.page?.sourceBrowserPage
        #expect(page?.baseURL == "https://example.com/talk")
        #expect(page?.html == "<html><body>討論</body></html>")
        #expect(page?.actionContext?.book.name == "測試書")
    }

    @Test("refreshBookInfo and refreshBookToc ask the detail page to reload", .timeLimit(.minutes(1)))
    func requestsRefresh() async {
        #expect(await run("java.refreshBookInfo()", in: source()).refreshesBook)
        #expect(await run("java.refreshBookToc()", in: source()).refreshesBook)
    }

    @Test("a script that throws reports its error", .timeLimit(.minutes(1)))
    func reportsErrors() async {
        let outcome = await run(#"throw new Error("boom")"#, in: source())
        #expect(outcome.errorMessage?.contains("boom") == true)
    }
}
