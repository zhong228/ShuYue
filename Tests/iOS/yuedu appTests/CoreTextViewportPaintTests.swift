import CoreText
import Testing
import UIKit
import YueduCoreText
@testable import yuedu_app

@Suite(.serialized)
@MainActor
struct CoreTextViewportPaintTests {
    @Test func measurePaintBoundsOnIdenticalShapedLines() {
        // Alternate order over the SAME CTLines; neither path measures layout.
        // Distinct CJK glyphs exercise outline work hidden by repeated fixtures.
        let font = UIFont.systemFont(ofSize: 27)
        let lines = (0..<60).map { row in
            let text = String(String.UnicodeScalarView((0..<30).compactMap {
                UnicodeScalar(0x4E00 + row * 30 + $0)
            }))
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        }
        var totals: [String: [Double]] = [:]
        var area: CGFloat = 0
        for order in [[true, false], [false, true], [true, false], [false, true]] {
            for exact in order {
                let start = SourcePerfTrace.now
                for line in lines {
                    let bounds = exact ? CTLineGetImageBounds(line, nil) : TextLinePaintBounds.conservativeBounds(for: line)
                    area += bounds.width * bounds.height
                }
                let name = exact ? "outline" : "envelope"
                totals[name, default: []].append((SourcePerfTrace.now - start) * 1000)
                SourcePerfTrace.record("test.scroll.paintBounds", "mode=\(name) lines=\(lines.count)",
                                       since: start, thresholdMs: 0)
            }
        }
        #expect(area > 0)
        print("[PaintBoundsABBA] \(totals)")
    }

    @Test func paintEnvelopeContainsShapedInkWithoutGlyphOutlineQueries() {
        var transform = CGAffineTransform(a: 1.1, b: 0.12, c: 0.25, d: 0.9, tx: 0, ty: 0)
        let transformed = CTFontCreateWithName("TimesNewRomanPS-ItalicMT" as CFString, 31, &transform)
        let fonts: [CTFont] = [UIFont.systemFont(ofSize: 23), UIFont.italicSystemFont(ofSize: 29),
            CTFontCreateWithName("PingFangTC-Regular" as CFString, 27, nil), transformed]
        for font in fonts {
            for text in ["繁體中文一二三高低上下，閱讀文字。", "office ffi Ágj é Ấj", "العَرَبِيَّة עברית", "👩🏽‍💻 🏳️‍🌈 🧑‍🧑‍🧒‍🧒 👨‍🚀"] {
                let attributed = NSMutableAttributedString(string: text, attributes: [.font: font])
                attributed.addAttributes([.baselineOffset: 17, .kern: 3],
                    range: NSRange(location: 0, length: min(4, attributed.length)))
                let line = CTLineCreateWithAttributedString(attributed)
                let exact = CTLineGetImageBounds(line, nil)
                let envelope = TextLinePaintBounds.conservativeBounds(for: line)
                #expect(exact.isNull || envelope.insetBy(dx: -0.000001, dy: -0.000001).contains(exact),
                    "\(CTFontCopyPostScriptName(font)) \(text) ink=\(exact) envelope=\(envelope)")
            }
        }
    }

    @Test func measureLoadedChunkPaintPreparation() throws {
        let prepared = Array(chunks(styled: true).prefix(4))
        prepared.forEach { $0.materializeFrameIfNeeded() }
        var samples: [Double] = []
        var count = 0
        for _ in 0..<8 {
            for chunk in prepared {
                let start = SourcePerfTrace.now
                count += CoreTextPaintFragment.make(chunk: chunk, scale: 3).count
                samples.append((SourcePerfTrace.now - start) * 1000)
            }
        }
        samples.sort()
        #expect(count > 0)
        print("[PaintPreparation] samples=\(samples.count) medianMs=\(samples[samples.count / 2]) maxMs=\(samples.last!)")
        SourcePerfTrace.record("test.scroll.paintPreparation", "samples=\(samples.count) fragments=\(count)",
            since: SourcePerfTrace.now - samples.reduce(0, +) / 1000, thresholdMs: 0)
    }

    private func chunks(styled: Bool = false, chapter: Int = 0) -> [CoreTextChunk] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 11
        let text = (0..<45).map { i in
            "段落\(i) " + String(repeating: "繁體中文 office affinity 👩🏽‍💻 é，細小滑動。", count: 3 + i % 5)
        }.joined(separator: "\n")
        let string = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 23), .foregroundColor: UIColor.black, .paragraphStyle: paragraph
        ])
        if styled {
            let shadow = NSShadow()
            shadow.shadowOffset = CGSize(width: 2, height: 6)
            shadow.shadowBlurRadius = 3
            shadow.shadowColor = UIColor.gray
            string.addAttribute(HTMLAttributedStringBuilder.inlineBorderBoxAttribute,
                value: HTMLAttributedStringBuilder.InlineBorderBoxStyle(borderColor: .blue,
                    borderWidth: 5, cornerRadius: 4, fillColor: .yellow,
                    paddingHorizontal: 3, paddingVertical: 40),
                range: NSRange(location: 35, length: 500))
            string.addAttributes([.font: UIFont.italicSystemFont(ofSize: 29), .shadow: shadow,
                                  .underlineStyle: NSUnderlineStyle.single.rawValue],
                                 range: NSRange(location: 35, length: 250))
        }
        return CoreTextChunkSlicer.slice(attributedString: string, chapterIndex: chapter,
                                        contentWidth: 320).chunks
    }

    @Test func fragmentsMatchOriginalPixelsAndNeverChangeLayout() throws {
        for styled in [false, true] {
            for chunk in chunks(styled: styled).prefix(2) {
                let originalRange = chunk.charRange
                let originalHeight = chunk.height
                for scale: CGFloat in [1, 3] {
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = scale
                    let bounds = CGRect(x: 0, y: 0, width: chunk.width, height: chunk.height)
                    let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
                    let reference = renderer.image { _ in CoreTextChunkDrawView.draw(chunk, bounds: bounds) }
                    let fragments = CoreTextPaintFragment.make(chunk: chunk, scale: scale)
                    #expect(fragments.count > 2)
                    #expect(fragments.allSatisfy { $0.rect.height <= 512 })
                    let actual = renderer.image { context in
                        for fragment in fragments {
                            context.cgContext.saveGState()
                            context.cgContext.clip(to: fragment.rect)
                            CoreTextChunkDrawView.draw(chunk, bounds: bounds, lineIndices: fragment.lineIndices)
                            context.cgContext.restoreGState()
                        }
                    }
                    #expect(reference.pngData() == actual.pngData(), "styled=\(styled) scale=\(scale)")
                    #expect(chunk.charRange.location == originalRange.location && chunk.charRange.length == originalRange.length)
                    #expect(chunk.height == originalHeight)
                }
            }
        }
    }

    @Test func retainedLayersMatchWholeChunkAtFractionalScrollOffsets() async throws {
        let chunk = try #require(chunks(styled: true).first)
        let size = CGSize(width: chunk.width, height: 650)
        let host = ReaderViewportFragmentHost(frame: CGRect(x: 0, y: 0, width: chunk.width, height: chunk.height))
        let renderer = UIGraphicsImageRenderer(size: size, format: Self.rasterFormat(scale: 3))
        for y: CGFloat in [0, 210, 210 + 1.0 / 3, 211, 560, 210 + 1.0 / 3] {
            host.update([], coreText: [.init(chunk: chunk, origin: .zero)],
                        viewport: CGRect(origin: CGPoint(x: 0, y: y), size: size), scale: 3)
            await host.waitForRasterIdle()
            let reference = renderer.image { context in
                context.cgContext.translateBy(x: 0, y: -y)
                CoreTextChunkDrawView.draw(chunk, bounds: CGRect(x: 0, y: 0, width: chunk.width, height: chunk.height))
            }
            let actual = renderer.image { context in
                context.cgContext.translateBy(x: 0, y: -y)
                host.layer.render(in: context.cgContext)
            }
            try expectCompositedPixels(reference, actual, offset: y)
        }
    }

    @Test func smallReversalsRetainPaintAcrossChunkAndChapterBoundaries() async throws {
        let content = Array(chunks().prefix(2)) + Array(chunks(chapter: 1).prefix(2))
        let host = ReaderViewportFragmentHost()
        var y: CGFloat = 0
        let inputs = content.map { chunk in
            defer { y += chunk.height }
            return ReaderViewportFragmentHost.CoreTextInput(chunk: chunk, origin: CGPoint(x: 0, y: y))
        }
        for boundary in [content[0].height, content[0].height + content[1].height] {
            func update(_ offset: CGFloat) {
                host.update([], coreText: inputs, viewport: CGRect(x: 0, y: offset, width: 320, height: 650), scale: 3)
            }
            // Paint both ends once, then repeat the exact loaded-content motion.
            // Loaded means painted: each end's bitmaps arrive from the raster
            // worker before the next move, as they do between display frames.
            for offset in [boundary - 400, boundary - 250, boundary - 400] {
                update(offset)
                await host.waitForRasterIdle()
            }
            let initialDraws = host.redrawCount
            let start = SourcePerfTrace.now
            for _ in 0..<3 {
                for offset in stride(from: boundary - 400, through: boundary - 250, by: 1.0 / 3) { update(offset) }
                for offset in stride(from: boundary - 250, through: boundary - 400, by: -1.0 / 3) { update(offset) }
            }
            #expect(host.redrawCount == initialDraws, "loaded content must not be repainted at a cell boundary")
            #expect(host.lateFragmentCount == 0, "loaded content must stay painted while it moves")
            #expect(!host.visibleSurfaces.isEmpty)
            #expect(host.visibleSurfaces.allSatisfy { $0.coreTextFragment != nil && $0.hasRaster })
            #expect(host.estimatedBackingBytes <= ReaderViewportFragmentHost.retainedByteLimit)
            #expect(host.mainThreadRasterCount == 0)
            SourcePerfTrace.record("test.scroll.fragmentReversal", "updates=2706 redraw=\(host.redrawCount - initialDraws) bytes=\(host.estimatedBackingBytes)", since: start, thresholdMs: 0)
        }
    }

    @Test func evictionAndNewLayoutOwnerCannotLeaveOldText() async throws {
        let old = try #require(chunks().first)
        let replacement = try #require(chunks(styled: true).first)
        let host = ReaderViewportFragmentHost()
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 650)
        host.update([], coreText: [.init(chunk: old, origin: .zero)], viewport: viewport, scale: 3)
        let previous = host.visibleSurfaces
        host.update([], coreText: [.init(chunk: old, origin: .zero)],
                    viewport: viewport.offsetBy(dx: 0, dy: 200), scale: 3)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #expect(host.retainedSurfaceCount == host.visibleSurfaces.count)
        host.update([], coreText: [.init(chunk: replacement, origin: .zero)], viewport: viewport, scale: 3)
        #expect(previous.allSatisfy { $0.superview == nil })
        #expect(host.visibleSurfaces.allSatisfy { $0.coreTextFragment?.chunk === replacement })
        host.update([], coreText: [], viewport: viewport, scale: 3)
        #expect(host.retainedSurfaceCount == 0)
        host.update([], coreText: [.init(chunk: replacement, origin: .zero)], viewport: viewport, scale: 3)
        #expect(!host.visibleSurfaces.isEmpty)
        host.reset()
        #expect(host.retainedSurfaceCount == 0)
        #expect(host.subviews.isEmpty)
        // Bitmaps for evicted and reset owners still finish on the worker;
        // they must land nowhere.
        await host.waitForRasterIdle()
        #expect(host.retainedSurfaceCount == 0)
        #expect(host.subviews.isEmpty)
    }

    @Test func rasterWorkerMatchesMainThreadPaintAndNeverRunsOnMain() async throws {
        for styled in [false, true] {
            let chunk = try #require(chunks(styled: styled).first)
            let frameBefore = try #require(chunk.frame)
            for scale: CGFloat in [1, 3] {
                let size = CGSize(width: chunk.width, height: min(chunk.height, 900))
                let host = ReaderViewportFragmentHost(frame: CGRect(x: 0, y: 0, width: chunk.width, height: chunk.height))
                host.update([], coreText: [.init(chunk: chunk, origin: .zero)],
                            viewport: CGRect(origin: .zero, size: size), scale: scale)
                await host.waitForRasterIdle()
                let renderer = UIGraphicsImageRenderer(size: size, format: Self.rasterFormat(scale: scale))
                let reference = renderer.image { _ in
                    CoreTextChunkDrawView.draw(chunk, bounds: CGRect(x: 0, y: 0, width: chunk.width, height: chunk.height))
                }
                let actual = renderer.image { context in host.layer.render(in: context.cgContext) }
                try expectCompositedPixels(reference, actual, offset: 0)
                #expect(host.mainThreadRasterCount == 0, "styled=\(styled) scale=\(scale)")
                #expect(host.visibleSurfaces.allSatisfy { $0.hasRaster })
            }
            // The worker lays out its own frame; the main thread's stays put.
            #expect(chunk.frame === frameBefore)
        }
    }

    @Test func visibleFragmentsStayBlankUntilTheirBitmapArrives() async throws {
        let chunk = try #require(chunks().first)
        let host = ReaderViewportFragmentHost()
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 650)
        host.update([], coreText: [.init(chunk: chunk, origin: .zero)], viewport: viewport, scale: 3)
        // Nothing was painted synchronously: finished bitmaps are installed on a
        // later main-queue turn, never inside the scroll update.
        #expect(host.lateFragmentCount > 0)
        #expect(!host.visibleSurfaces.isEmpty)
        #expect(host.visibleSurfaces.allSatisfy { !$0.hasRaster })
        await host.waitForRasterIdle()
        #expect(host.visibleSurfaces.allSatisfy { $0.hasRaster })
        let requests = host.redrawCount
        host.update([], coreText: [.init(chunk: chunk, origin: .zero)], viewport: viewport, scale: 3)
        #expect(host.lateFragmentCount == 0)
        #expect(host.redrawCount == requests, "an installed bitmap is not requested again")
    }

    @Test func fragmentsAheadInTheDirectionOfTravelArePaintedBeforeTheyEnter() async throws {
        let content = Array(chunks().prefix(3))
        var y: CGFloat = 0
        let inputs = content.map { chunk in
            defer { y += chunk.height }
            return ReaderViewportFragmentHost.CoreTextInput(chunk: chunk, origin: CGPoint(x: 0, y: y))
        }
        let host = ReaderViewportFragmentHost()
        func update(_ offset: CGFloat) {
            host.update([], coreText: inputs, viewport: CGRect(x: 0, y: offset, width: 320, height: 650), scale: 3)
        }
        update(0)
        for offset in stride(from: CGFloat(20), through: 200, by: 20) { update(offset) }
        await host.waitForRasterIdle()
        // One more step of the same motion: everything entering the viewport and
        // the paint window was requested ahead of time, so nothing shows blank.
        update(220)
        #expect(host.lateFragmentCount == 0)
        #expect(host.visibleSurfaces.allSatisfy { $0.hasRaster })
        #expect(host.estimatedBackingBytes <= ReaderViewportFragmentHost.retainedByteLimit)
        // The same jump without the approach has nothing painted yet.
        let cold = ReaderViewportFragmentHost()
        cold.update([], coreText: inputs, viewport: CGRect(x: 0, y: 220, width: 320, height: 650), scale: 3)
        #expect(cold.lateFragmentCount > 0)
        await cold.waitForRasterIdle()
    }

    @Test func underlineSettingChangeRepaintsWithTheNewDecoration() async throws {
        let settings = GlobalSettings.shared
        let original = settings.readerTextUnderlineDecorationEnabled
        defer { settings.readerTextUnderlineDecorationEnabled = original }
        settings.readerTextUnderlineDecorationEnabled = false
        let chunk = try #require(chunks().first)
        let size = CGSize(width: chunk.width, height: 650)
        let host = ReaderViewportFragmentHost()
        host.update([], coreText: [.init(chunk: chunk, origin: .zero)], viewport: CGRect(origin: .zero, size: size), scale: 3)
        await host.waitForRasterIdle()
        let requests = host.redrawCount
        settings.readerTextUnderlineDecorationEnabled = true
        host.update([], coreText: [.init(chunk: chunk, origin: .zero)], viewport: CGRect(origin: .zero, size: size), scale: 3)
        #expect(host.redrawCount > requests, "a bitmap painted without the underline must be replaced")
        await host.waitForRasterIdle()
        let renderer = UIGraphicsImageRenderer(size: size, format: Self.rasterFormat(scale: 3))
        let reference = renderer.image { _ in
            CoreTextChunkDrawView.draw(chunk, bounds: CGRect(x: 0, y: 0, width: chunk.width, height: chunk.height))
        }
        let actual = renderer.image { context in host.layer.render(in: context.cgContext) }
        try expectCompositedPixels(reference, actual, offset: 0)
    }

    /// The raster worker's format: 8-bit sRGB at the screen scale.
    private static func rasterFormat(scale: CGFloat) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        return format
    }

    @Test func enteringSurfaceSubmitsOnlyItsLinesAndMeasuresBothPaths() throws {
        let chunk = try #require(chunks().first)
        let allLines = CTFrameGetLines(try #require(chunk.frame)) as! [CTLine]
        let fragments = CoreTextPaintFragment.make(chunk: chunk, scale: 3)
        #expect(fragments.allSatisfy { $0.lineIndices.count < allLines.count / 2 })
        let fragment = try #require(fragments.dropFirst(2).first)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        for fragmentOnly in [false, true] {
            let rect = fragmentOnly ? fragment.renderingRect : CGRect(x: 0, y: 0, width: chunk.width, height: chunk.height)
            let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
            let start = SourcePerfTrace.now
            for _ in 0..<12 {
                _ = renderer.image { context in
                    context.cgContext.translateBy(x: 0, y: -rect.minY)
                    CoreTextChunkDrawView.draw(chunk, bounds: CGRect(x: 0, y: 0, width: chunk.width, height: chunk.height),
                                              lineIndices: fragmentOnly ? fragment.lineIndices : nil)
                }
            }
            SourcePerfTrace.record("test.scroll.raster", "fragment=\(fragmentOnly) iterations=12 lines=\(fragmentOnly ? fragment.lineIndices.count : allLines.count)", since: start, thresholdMs: 0)
        }
    }
    @Test func mountedBackingStoresStayPaintedDuringSmallGestures() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 650))
        root.view.addSubview(scroll)
        let content = Array(chunks().prefix(3))
        var y: CGFloat = 0
        let inputs = content.map { chunk in
            defer { y += chunk.height }
            return ReaderViewportFragmentHost.CoreTextInput(chunk: chunk, origin: CGPoint(x: 0, y: y))
        }
        scroll.contentSize = CGSize(width: 320, height: y)
        func display(_ view: UIView) {
            guard !view.isHidden else { return }
            view.layer.displayIfNeeded()
            view.subviews.forEach(display)
        }
        var timings: [Bool: [Double]] = [:]
        for fragmented in [false, true, true, false] {
            let host = ReaderViewportFragmentHost(frame: CGRect(origin: .zero, size: scroll.contentSize))
            if fragmented { scroll.addSubview(host) }
            var oldViews: [Int: CoreTextChunkDrawView] = [:]
            let batchStart = SourcePerfTrace.now
            func step(_ offset: CGFloat, measuring: Bool = true) {
                let start = SourcePerfTrace.now
                scroll.contentOffset.y = offset
                if fragmented {
                    host.update([], coreText: inputs, viewport: scroll.bounds, scale: window.screen.scale)
                    display(host)
                } else {
                    for (i, input) in inputs.enumerated() {
                        let rect = CGRect(origin: input.origin, size: CGSize(width: 320, height: input.chunk.height))
                        if rect.intersects(scroll.bounds), oldViews[i] == nil {
                            let view = CoreTextChunkDrawView(frame: rect)
                            view.chunk = input.chunk
                            scroll.addSubview(view)
                            view.setNeedsDisplay()
                            view.layer.displayIfNeeded()
                            oldViews[i] = view
                        } else if !rect.intersects(scroll.bounds) {
                            oldViews.removeValue(forKey: i)?.removeFromSuperview()
                        }
                    }
                }
                CATransaction.flush()
                if measuring { timings[fragmented, default: []].append((SourcePerfTrace.now - start) * 1000) }
            }
            for offset in stride(from: CGFloat(1200), through: 3200, by: 12) { step(offset) }
            for offset in stride(from: CGFloat(3200), through: 1200, by: -12) { step(offset) }
            SourcePerfTrace.record("test.scroll.backingSubmission", "fragments=\(fragmented) steps=334", since: batchStart, thresholdMs: 0)
            if fragmented {
                step(1400, measuring: false); step(1500, measuring: false); step(1400, measuring: false)
                await host.waitForRasterIdle()
                let retained = host.visibleSurfaces
                let draws = retained.map(\.drawCount)
                #expect(draws.allSatisfy { $0 > 0 }, "actual backing stores must have been painted")
                for _ in 0..<5 {
                    for offset: CGFloat in [1400, 1412, 1436, 1472, 1500, 1472, 1436, 1412, 1400] { step(offset, measuring: false) }
                }
                await host.waitForRasterIdle()
                #expect(retained.map(\.drawCount) == draws,
                        "UIKit must reuse actual backing stores, not only keep configure counts stable")
                #expect(host.mainThreadRasterCount == 0)
                #expect(host.estimatedBackingBytes <= ReaderViewportFragmentHost.retainedByteLimit)
                print("[ScrollBackingReuse] surfaces=\(retained.count) additionalDraws=\(zip(retained, draws).reduce(0) { $0 + $1.0.drawCount - $1.1 }) bytes=\(host.estimatedBackingBytes)")
            }
            host.removeFromSuperview()
            oldViews.values.forEach { $0.removeFromSuperview() }
        }
        for mode in [false, true] {
            let values = try #require(timings[mode]).sorted()
            print("[ScrollBackingSubmission] fragments=\(mode) count=\(values.count) medianMs=\(values[values.count / 2]) p95Ms=\(values[Int(Double(values.count - 1) * 0.95)]) maxMs=\(values.last!)")
        }
    }

    @Test func externalPaintKeepsSelectionAndVoiceOverInTheCell() throws {
        let chunk = try #require(chunks().first)
        let cell = CoreTextChunkCollectionCell(frame: CGRect(x: 0, y: 0, width: 344, height: chunk.height))
        cell.rendersContentExternally = true
        cell.bind(chunk: chunk, axis: .vertical, horizontalInset: 12, verticalInset: 20,
                  leadingSpacing: 0, viewportSize: CGSize(width: 344, height: 650))
        cell.layoutIfNeeded()
        cell.applySelection(chapterIndex: chunk.chapterIndex, chapterRange: NSRange(location: 5, length: 8))
        #expect(!cell.overlay.selectionRects.isEmpty)
        #expect(cell.drawView.isAccessibilityElement)
        #expect(cell.drawView.accessibilityLabel?.isEmpty == false)
        var menuOpened = false
        cell.onAccessibilityMenu = { menuOpened = true }
        #expect(cell.drawView.accessibilityActivate())
        #expect(menuOpened)
        cell.drawView.layer.displayIfNeeded()
        #expect(cell.drawView.drawCount == 0, "interaction cell must not duplicate external content paint")
    }

    private func expectCompositedPixels(_ reference: UIImage, _ actual: UIImage, offset: CGFloat) throws {
        let expectedImage = try #require(reference.cgImage)
        let actualImage = try #require(actual.cgImage)
        #expect(expectedImage.width == actualImage.width && expectedImage.height == actualImage.height)
        func rgba(_ image: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: image.width,
                    height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }
        let expected = try rgba(expectedImage), rendered = try rgba(actualImage)
        var alphaDifferences = 0, changedPixels = 0, maximumRGBDifference = 0
        for i in stride(from: 0, to: expected.count, by: 4) {
            if expected[i + 3] != rendered[i + 3] { alphaDifferences += 1 }
            let delta = (0..<3).map { abs(Int(expected[i + $0]) - Int(rendered[i + $0])) }.max() ?? 0
            if delta > 0 { changedPixels += 1 }
            maximumRGBDifference = max(maximumRGBDifference, delta)
        }
        // The direct partition raster test above remains byte-exact. CALayer
        // compositing of overlapping antialiased colored borders adds an 8-bit
        // premultiplication rounding step (observed: 1 pixel, 1 RGB unit out of
        // 1,872,000 pixels). Alpha/coverage must still be identical; moving a
        // glyph or losing a border is not tolerated by this quantization bound.
        #expect(alphaDifferences == 0)
        #expect(maximumRGBDifference <= 1, "offset=\(offset), changed=\(changedPixels)")
        print("[FragmentCompositing] offset=\(offset) changedPixels=\(changedPixels) maxRGB=\(maximumRGBDifference) alphaDifferences=\(alphaDifferences)")
    }

}
