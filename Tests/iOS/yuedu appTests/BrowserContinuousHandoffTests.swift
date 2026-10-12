import Testing
import UIKit
import YueduCoreText
@testable import yuedu_app

@MainActor
struct BrowserContinuousHandoffTests {
    @Test func verticalBackgroundPreparationPreservesTextAnchorsAndCache() async throws {
        let text = String(repeating: "直排背景排版交接，內容與閱讀位置必須保留。", count: 40)
        let html = "<body><p id='opening'>開頭</p><p id='body'>\(text)</p></body>"
        let resource = MockBrowserLayoutResource(chapters: [
            .init(title: "Vertical", href: "0.xhtml", html: html, css: [])
        ])
        var settings = EPUBTestFixtures.renderSettings()
        settings.writingMode = .verticalRTL
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let delegate = CoreTextPageEngine(attributedBuilder: MockAttributedStringBuilder(texts: [text]),
            renderSettings: settings, offsetStore: CharOffsetStore(directoryURL: directory))
        let engine = BrowserLayoutPageEngine(resource: resource, delegate: delegate,
                                            settings: settings, mode: .browserForced)
        let size = CGSize(width: 320, height: 600)
        await engine.start(renderSize: size, bookId: "vertical-handoff")
        let chapter = try #require(await engine.makeScrollChapter(at: 0, settings: settings, contentSize: size))
        #expect(chapter.document.sourceText.contains(text))
        #expect(chapter.document.anchorOffsets["body"] != nil)
        #expect(!chapter.document.displayList.items.isEmpty)
        #expect(chapter.document.contentSize.width > 0)
        #expect(chapter.document.contentSize.height > 0)
        let cached = try #require(await engine.makeScrollChapter(at: 0, settings: settings, contentSize: size))
        #expect(cached === chapter)
    }
}
