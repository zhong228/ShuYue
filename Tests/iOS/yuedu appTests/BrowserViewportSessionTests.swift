@testable import YueduCoreText
import Testing
import UIKit
@testable import yuedu_app

@Suite(.serialized)
@MainActor
struct BrowserViewportSessionTests {
    @Test func firstViewportDoesNotShapeTheWholeChapterAndReverseAfterTrimKeepsGeometry() throws {
        let html = "<body>" + (0..<300).map { "<p id='p\($0)'>\($0) " + String(repeating: "閱讀 viewport text ", count: 20) + "</p>" }.joined() + "</body>"
        let config = BrowserLayoutConfig(renderWidth: 320, renderHeight: 600, rootFontSize: 17)
        let session = try HTMLLayoutDocument(html: html, configuration: config).makeViewportSession()
        #expect(session.shapedLineCount == 0)
        let first = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1800))
        let fingerprint = textGeometry(first, within: 0..<600)
        #expect(!fingerprint.isEmpty)
        #expect(session.shapedLineCount < 150)
        #expect(session.estimatedBoxCount > 200)
        let initialCount = session.shapedLineCount
        _ = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1800))
        #expect(session.shapedLineCount == initialCount)
        let target = try #require(session.anchorOffsets["p200"])
        _ = try session.layout(in: CGRect(x: 0, y: session.documentY(for: target), width: 320, height: 1800), anchorOffset: target)
        #expect(session.shapedLineCount < initialCount + 200, "jump must not lay out all preceding paragraphs")
        session.discardRenderingResources()
        #expect(session.retainedLineCount == 0)
        let restored = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1800), anchorOffset: 0)
        #expect(textGeometry(restored, within: 0..<600) == fingerprint)
    }

    @Test func eagerAndDemandedGeometryMatchForNestedFloatRubyAndInlineStyles() throws {
        let html = """
        <body><div style="border:2px solid red;padding:9px;margin:12px">
        <p><span style="float:left;width:60px">浮動元素 float</span>這是<ruby>漢字<rt>かんじ</rt></ruby>與 <b>bold</b>、<i>italic</i> 以及 English text。</p>
        <p style="text-indent:2em;margin:14px 0">\(String(repeating: "更多的文字 text ", count: 45))</p>
        <div style="padding:8px"><p>nested paragraph</p><p>結束</p></div></div></body>
        """
        let config = BrowserLayoutConfig(renderWidth: 320, renderHeight: 600, rootFontSize: 17)
        let input = HTMLLayoutDocument(html: html, configuration: config)
        let eager = try input.prepareContinuous(validateCapabilities: false).makeDocument()
        let session = try input.makeViewportSession()
        let demanded = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 100_000))
        #expect(demanded.sourceText == eager.sourceText)
        #expect(textGeometry(demanded, within: 0..<100_000) == textGeometry(eager, within: 0..<100_000))
        #expect(abs(demanded.contentHeight - eager.contentHeight) < 0.01)
    }

    @Test func veryLongParagraphStopsAtDemandAndResumesFromMeasuredCheckpoints() throws {
        let html = "<body><p>" + String(repeating: "long paragraph 超長段落 ", count: 3000) + "</p></body>"
        let session = try HTMLLayoutDocument(html: html, configuration: BrowserLayoutConfig(renderWidth: 320, renderHeight: 600)).makeViewportSession()
        _ = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 1200))
        #expect(session.shapedLineCount < 120)
        let firstCount = session.shapedLineCount
        _ = try session.layout(in: CGRect(x: 0, y: 900, width: 320, height: 1200))
        #expect(session.shapedLineCount > firstCount)
        #expect(session.shapedLineCount < firstCount + 100)
        let measured = session.measuredLineCount
        session.discardRenderingResources()
        _ = try session.layout(in: CGRect(x: 0, y: 900, width: 320, height: 1200))
        #expect(session.measuredLineCount == measured)
    }

    @Test func imagesBackgroundAndParagraphSeamsMatchAfterIncrementalMeasurement() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 90, height: 180)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 90, height: 180))
        }
        let html = "<body style='background-image:url(bg.png)'>" + (0..<24).map { i in
            "<div style='margin:13px 0;padding:7px'><p id='p\(i)'>\(i) " + String(repeating: "連續文字 seam ", count: 20)
            + "</p>" + (i.isMultiple(of: 3) ? "<img src='image.png' style='width:120px'/>" : "") + "</div>"
        }.joined() + "</body>"
        let input = HTMLLayoutDocument(input: .currentCompatibility(html: html, cssTexts: []), configuration: BrowserLayoutConfig(renderWidth: 320, renderHeight: 600),
                                       imageLoader: { _ in image })
        // The session leaves the page background to its host (`BrowserPageBackground`).
        let eager = try input.prepareContinuous(validateCapabilities: false).makeDocument(paintsPageBackground: false)
        let session = try input.makeViewportSession()
        #expect(session.facts.pageBackground?.imageSource == "bg.png")
        for i in 0..<24 {
            let anchor = try #require(session.anchorOffsets["p\(i)"])
            _ = try session.layout(in: CGRect(x: 0, y: session.documentY(for: anchor), width: 320, height: 900), anchorOffset: anchor)
        }
        #expect(abs(session.document.contentHeight - eager.contentHeight) < 0.01)
        for i in [0, 8, 16, 23, 16, 8, 0] {
            let anchor = try #require(session.anchorOffsets["p\(i)"])
            session.discardRenderingResources()
            let restored = try session.layout(in: CGRect(x: 0, y: session.documentY(for: anchor), width: 320, height: 900), anchorOffset: anchor)
            let y = session.materializedBounds.minY
            #expect(textGeometry(restored, within: y..<(y + 600)) == textGeometry(eager, within: y..<(y + 600)))
            let images = restored.displayList.items.compactMap { if case .image(let i) = $0, i.isBackgroundPaint || (i.rect.maxY > y && i.rect.minY < y + 600) { return "\(i.source)|\(i.rect)|\(i.sourceRange)" }; return nil }
            let reference = eager.displayList.items.compactMap { if case .image(let i) = $0, i.isBackgroundPaint || (i.rect.maxY > y && i.rect.minY < y + 600) { return "\(i.source)|\(i.rect)|\(i.sourceRange)" }; return nil }
            #expect(images == reference)
        }
    }

    @Test func firstViewportWorkIsMeasuredSeparatelyFromWholeChapterPreparation() throws {
        let html = "<body>" + String(repeating: "<p>" + String(repeating: "中文 English <b>bold</b> <i>italic</i> ", count: 15) + "</p>", count: 180) + "</body>"
        let input = HTMLLayoutDocument(html: html, configuration: BrowserLayoutConfig(renderWidth: 360, renderHeight: 800))
        let start = SourcePerfTrace.now
        let eager = try SourcePerfTrace.span("test.viewport.eager", thresholdMs: 0) { try input.prepareContinuous(validateCapabilities: false).makeDocument() }
        let eagerMS = (SourcePerfTrace.now - start) * 1000
        let contentStart = SourcePerfTrace.now
        let session = try SourcePerfTrace.span("test.viewport.content", thresholdMs: 0) { try input.makeViewportSession(validateCapabilities: false) }
        let contentMS = (SourcePerfTrace.now - contentStart) * 1000
        let layoutStart = SourcePerfTrace.now
        let first = try SourcePerfTrace.span("test.viewport.first", thresholdMs: 0) { try session.layout(in: CGRect(x: 0, y: 0, width: 360, height: 2400)) }
        let firstMS = (SourcePerfTrace.now - layoutStart) * 1000
        #expect(textGeometry(first, within: 0..<800) == textGeometry(eager, within: 0..<800))
        #expect(session.estimatedBoxCount > 150)
        print("[ViewportPerf] eagerMS=\(eagerMS) contentMS=\(contentMS) first2400ptMS=\(firstMS) shaped=\(session.shapedLineCount) retained=\(session.retainedLineCount) estimates=\(session.estimatedBoxCount)")
    }

    @Test func sourceOffsetsStayUTF16ExactAcrossUnicodeAndThousandsOfInlineRuns() {
        var builder = SourceTextBuilder()
        var expected = ""
        for index in 0..<2000 {
            let part = ["中", "👩🏽‍💻", "e\u{301}", "\n", "abc", ""][index % 6]
            let start = (expected as NSString).length
            let range = builder.append(part)
            expected += part
            #expect(range == NSRange(location: start, length: (part as NSString).length))
            #expect(builder.currentOffset == (expected as NSString).length)
        }
        #expect(builder.text == expected)
    }

    @Test func consumerInsetsAndPaintResourcesSurviveRepeatedDemandAndTileTranslation() throws {
        let config = BrowserLayoutConfig(renderWidth: 320, renderHeight: 600,
            contentInsets: UIEdgeInsets(top: 19, left: 11, bottom: 23, right: 17))
        let input = HTMLLayoutDocument(html: "<body><p>中文與 <b>bold</b> <i>italic</i></p><p>末段</p></body>", configuration: config)
        let eager = try input.prepareContinuous(validateCapabilities: false).makeDocument()
        let session = try input.makeViewportSession()
        let bounds = CGRect(x: 0, y: 0, width: 348, height: 600)
        let first = try session.layout(in: bounds)
        #expect(first.contentSize == eager.contentSize)
        #expect(textGeometry(first, within: 0..<600) == textGeometry(eager, within: 0..<600))
        let original = first.displayList.items.compactMap { if case .text(let t) = $0 { return t.preparedDrawing }; return nil }
        #expect(!original.isEmpty)
        let repeated = try session.layout(in: bounds)
        let translated = repeated.items(in: bounds.offsetBy(dx: 0, dy: 1)).items.compactMap {
            if case .text(let t) = $0 { return t.preparedDrawing }; return nil
        }
        #expect(original.count == translated.count)
        for (a, b) in zip(original, translated) { #expect(a === b) }
    }

    private func textGeometry(_ document: BrowserScrollDocument, within range: Range<CGFloat>) -> [String] {
        document.displayList.items.compactMap {
            guard case .text(let t) = $0, range.contains(t.rect.minY) else { return nil }
            return "\(t.sourceRange)|\(t.text)|\(t.rect)|\(t.baselineY)|\(t.font.fontDescriptor)".replacingOccurrences(of: "0x[0-9a-f]+", with: "", options: .regularExpression)
        }
    }
}
