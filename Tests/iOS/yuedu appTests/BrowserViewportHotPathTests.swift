@testable import YueduCoreText
import Testing
import UIKit
@testable import yuedu_app

@Suite(.serialized)
@MainActor
struct BrowserViewportHotPathTests {
    @Test func viewportSizedPaintBatchesPreservePixelsAndMeasureRasterCost() throws {
        let seed = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 384)).image { context in
            for i in 0..<12 {
                (i.isMultiple(of: 2) ? UIColor.red : UIColor.blue).setFill()
                context.fill(CGRect(x: 0, y: i * 32, width: 32, height: 32))
            }
        }
        let data = try #require(seed.pngData())
        let png = try #require(UIImage(data: data))
        let html = "<body style='margin:0'><img src='stripe.png' style='display:block;width:100px;height:1200px'>" + String(repeating:
            "<p style='margin:12px 0'>中文 English <b>bold text</b> continuous drawing.</p>", count: 180) + "</body>"
        let session = try HTMLLayoutDocument(input: .currentCompatibility(html: html, cssTexts: []),
            configuration: BrowserLayoutConfig(renderWidth: 320, renderHeight: 800),
            imageLoader: { _ in png }).makeViewportSession()
        let document = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 5000))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        func tile(_ rect: CGRect) -> UIImage {
            UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: rect.size))
                document.items(in: rect).draw(in: context.cgContext)
            }
        }
        func composite(cap: CGFloat, bleed: CGFloat = 0) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 320, height: 4000), format: format).image { context in
                for y in stride(from: CGFloat(0), to: 4000, by: cap) {
                    let rect = CGRect(x: 0, y: y, width: 320, height: min(cap, 4000 - y))
                    let paint = rect.insetBy(dx: 0, dy: -bleed)
                    context.cgContext.saveGState()
                    context.cgContext.clip(to: rect)
                    tile(paint).draw(in: paint)
                    context.cgContext.restoreGState()
                }
            }
        }
        for scale in [CGFloat(1), CGFloat(3)] {
            format.scale = scale
            try autoreleasepool {
                let before = composite(cap: 2000)
                let after = composite(cap: 800, bleed: 1)
                let beforeData = try #require(before.pngData())
                let afterData = try #require(after.pngData())
                if beforeData != afterData {
                    let directory = FileManager.default.temporaryDirectory
                    let oldURL = directory.appendingPathComponent("viewport-paint-before-\(Int(scale)).png")
                    let newURL = directory.appendingPathComponent("viewport-paint-after-\(Int(scale)).png")
                    try beforeData.write(to: oldURL)
                    try afterData.write(to: newURL)
                    print("[ViewportPixels] before=\(oldURL.path) after=\(newURL.path)")
                }
                #expect(beforeData == afterData,
                    "changing paint boundaries must preserve pixels at \(scale)x")
            }
        }
        // Alternate sizes so font warm-up does not consistently favour one.
        var elapsed: [Int: [Double]] = [:]
        for cap in [2000, 800, 800, 2000, 2000, 800] {
            autoreleasepool {
                let rect = CGRect(x: 0, y: 0, width: 320, height: cap)
                let start = SourcePerfTrace.now
                let image = tile(rect)
                let ms = (SourcePerfTrace.now - start) * 1000
                #expect(image.cgImage?.height == cap * Int(format.scale))
                elapsed[cap, default: []].append(ms)
                SourcePerfTrace.record("test.viewport.paintBatch", "height=\(cap)", since: start, thresholdMs: 0)
            }
        }
        print("[ViewportHotPath] paintBatchMs=\(elapsed)")
    }

    @Test func renderDiagnosticsIdentifyImagesWithoutLeakingContent() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 24)).image { _ in }
        let page = BrowserLayoutPageView(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
        page.continuousSpineIndex = 3
        page.continuousDocumentRect = CGRect(x: 0, y: 1600, width: 320, height: 800)
        page.displayList = DisplayList(items: (0..<100).map { node in
            .image(DisplayImageItem(source: "private-book-title.png", image: image,
                sourceRange: NSRange(location: 0, length: 1), nodeID: node, linkTarget: nil,
                writingMode: .horizontal, rect: .init(rawValue: CGRect(x: 0, y: 0, width: 12, height: 24)), alt: "private text"))
        })
        let metadata = page.continuousRenderMetadata()
        #expect(metadata.spineIndex == 3)
        #expect(metadata.resourceID?.contains("images=100") == true)
        #expect(metadata.resourceID?.contains("node=7:") == true)
        #expect(metadata.resourceID?.contains("node=8:") == false)
        #expect(metadata.logDescription.contains("private") == false)
        #expect(metadata.logDescription.count < 2048)
    }

    @Test func engineKeepsViewportPaintBoundariesAfterMeasurementAndRetirement() async throws {
        let settings = EPUBTestFixtures.renderSettings()
        let html = "<body>" + String(repeating: "<p>中文 continuous drawing test paragraph.</p>", count: 200) + "</body>"
        let builder = MockAttributedStringBuilder(texts: [html])
        let delegate = CoreTextPageEngine(attributedBuilder: builder, renderSettings: settings,
            offsetStore: CharOffsetStore(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let browser = BrowserLayoutPageEngine(resource: MockBrowserLayoutResource(chapters: [
            .init(title: "Chapter", href: "0.xhtml", html: html, css: [])]),
            delegate: delegate, settings: settings, mode: .browserAuto)
        browser.usesViewportScrolling = true
        await browser.start(renderSize: CGSize(width: 344, height: 800), bookId: "paint-boundaries")
        let engine = CoreTextScrollEngine(builder: builder, renderSettings: settings)
        engine.browserAutoEngine = browser
        await engine.start(initialChapter: 0, contentWidth: 320, viewportExtent: 800, loadAdjacentChapters: false)
        func checkBoundaries() throws {
            var bottom: CGFloat = 0
            for item in engine.chunks {
                guard case .browser(let tile) = item else { Issue.record("expected browser tile"); continue }
                #expect(tile.documentRect.height <= 800)
                #expect(tile.documentRect.minY == bottom, "no gaps or overlapping paint tiles")
                bottom = tile.documentRect.maxY
            }
            #expect(bottom == engine.browserChapter(at: 0)?.document.contentHeight)
        }
        try checkBoundaries()
        for y in [0, 1600, 3200, 1600, 0] {
            engine.requestViewport(chapter: 0, bounds: CGRect(x: 0, y: y, width: 320, height: 1800))
            await engine.waitForViewportIdle()
            try checkBoundaries()
            engine.trimViewportChapters(keeping: [])
            await engine.waitForViewportIdle()
        }
        engine.requestViewport(chapter: 0, bounds: CGRect(x: 0, y: 0, width: 320, height: 1800))
        await engine.waitForViewportIdle()
        guard case .browser(let tile) = try #require(engine.chunks.first) else {
            Issue.record("expected browser tile"); return
        }
        let cell = BrowserScrollTileCell(frame: CGRect(x: 0, y: 0, width: 344, height: 820))
        cell.configure(tile: tile, horizontalInset: 12, leadingSpacing: 20)
        let renderedTop = cell.interactiveView.convert(CGPoint(x: 12, y: 20), from: cell)
        #expect(cell.tileLocalPoint(fromRenderingPoint: renderedTop) == .zero,
            "sampling bleed must not shift progress or selection coordinates")
        #expect(cell.renderingDocumentRect.minY + renderedTop.y == tile.documentRect.minY)
        #expect(cell.interactiveView.superview?.clipsToBounds == true)
        #expect(cell.interactiveView.superview?.frame == CGRect(x: 12, y: 20, width: 320, height: tile.documentRect.height))
    }

    @Test func intervalQueriesMatchLinearSearchAcrossOverlapsGapsAndTies() {
        let ranges: [ClosedRange<CGFloat>] = [20...40, -10...10, 10...20, 0...60, 10...20, 80...80]
            + (0..<1000).map { i in
                let start = CGFloat((i * 7919) % 12000)
                return start...(start + CGFloat(i % 91))
            }
        var index = BrowserViewportIntervalIndex(ranges)
        // Exercise unchanged ordering, reordered geometry, and a resized tree.
        for updated in [ranges, Array(ranges.reversed()), Array(ranges.dropFirst(23))] {
            index.update(updated)
            for y in stride(from: CGFloat(-30), through: 12100, by: 2.5) {
                let expected = updated.indices.min {
                    max(updated[$0].lowerBound - y, y - updated[$0].upperBound, 0)
                        < max(updated[$1].lowerBound - y, y - updated[$1].upperBound, 0)
                }
                #expect(index.nearest(to: y) == expected)
            }
        }
        #expect(BrowserViewportIntervalIndex().nearest(to: 0) == nil)
    }

    @Test func sourcePositionSurvivesResourceEvictionAndReverseLayout() throws {
        let html = "<body>" + (0..<80).map { "<p id='p\($0)' style='margin:18px'>\($0) "
            + String(repeating: "中文 English ", count: 20) + "</p>" }.joined() + "</body>"
        let session = try HTMLLayoutDocument(html: html,
            configuration: BrowserLayoutConfig(renderWidth: 320, renderHeight: 600)).makeViewportSession()
        for p in [40, 20, 60, 20, 0] {
            let offset = try #require(session.anchorOffsets["p\(p)"])
            _ = try session.layout(in: CGRect(x: 0, y: session.documentY(for: offset), width: 320, height: 1800), anchorOffset: offset)
            let y = session.documentY(for: offset) + 1
            let before = session.sourceOffset(at: y)
            #expect(abs(before - offset) < 60)
            session.discardRenderingResources()
            #expect(session.sourceOffset(at: y) == before)
            _ = try session.layout(in: CGRect(x: 0, y: y - 1, width: 320, height: 1800), anchorOffset: offset)
            #expect(session.sourceOffset(at: session.documentY(for: offset) + 1) == before)
        }
    }

    @Test func positionQueriesAndGeometryUpdatesAreMeasuredSeparately() throws {
        let html = "<body>" + (0..<1000).map {
            "<p id='p\($0)' style='margin:12px 0'>Paragraph \($0) "
                + String(repeating: "中文 continuous content ", count: 8) + "</p>"
        }.joined() + "</body>"
        let session = try HTMLLayoutDocument(html: html,
            configuration: BrowserLayoutConfig(renderWidth: 320, renderHeight: 600)).makeViewportSession()
        _ = try session.layout(in: CGRect(x: 0, y: 0, width: 320, height: 2400))
        let extent = max(1, Int(session.document.contentHeight))
        let start = SourcePerfTrace.now
        var checksum = 0
        for i in 0..<2000 {
            checksum += session.sourceOffset(at: CGFloat((i * 7919) % extent) + 0.375)
        }
        let elapsed = (SourcePerfTrace.now - start) * 1000
        SourcePerfTrace.record("test.viewport.positionQueries", "queries=2000 paragraphs=1000", since: start, thresholdMs: 0)
        print("[ViewportHotPath] queriesMs=\(elapsed) checksum=\(checksum)")
        #expect(checksum > 0)
        let layoutStart = SourcePerfTrace.now
        for p in [20, 40, 20, 60, 40] {
            let offset = try #require(session.anchorOffsets["p\(p)"])
            _ = try session.layout(in: CGRect(x: 0, y: session.documentY(for: offset), width: 320, height: 2400), anchorOffset: offset)
            #expect(session.document.documentPoint(forCharOffset: offset) != nil)
        }
        SourcePerfTrace.record("test.viewport.positionGeometry", "updates=5", since: layoutStart, thresholdMs: 0)
    }
}
