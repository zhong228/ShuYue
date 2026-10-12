import CoreText
import Testing
import UIKit
@testable import YueduCoreText
@testable import yuedu_app

@Suite(.serialized)
@MainActor
struct ContinuousScrollFrameBudgetTests {
    @Test func viewportJustificationMatchesPreparedContinuousPixels() throws {
        let fixtures = [
            "<p>" + String(repeating: "春眠不覺曉，處處聞啼鳥。夜來風雨聲花落知多少！", count: 12) + "</p>",
            "<p>" + String(repeating: "office affinity quiet garden word spacing. ", count: 14) + "</p>",
            "<p style='letter-spacing:1.25px'>" + String(repeating: "字距 Latin office 春眠不覺曉。", count: 12) + "</p>",
            "<p>" + String(repeating: "中文 <b>粗體文字</b><i> italic </i>👩🏽‍💻 é　 ", count: 12) + "</p>",
            "<p lang='en' style='hyphens:auto'>" + String(repeating: "extraordinary soft\u{00AD}hyphenation representation. ", count: 12) + "</p>",
            "<p style='text-align-last:justify'>" + String(repeating: "مرحبا بالعالم שלום עולם 中文。 ", count: 12) + "</p>",
            "<p>" + String(repeating: "नमस्ते दुनिया ภาษาไทย 中文 text. ", count: 12) + "</p>",
            "<p style='text-indent:1.5em'>" + String(repeating: "段落縮排與標點《測試》——，。\n", count: 12) + "<br>最後一行</p>"
        ]
        for (fixture, body) in fixtures.enumerated() {
            for width: CGFloat in [213, 392] {
                var config = BrowserLayoutConfig(renderWidth: width, renderHeight: 810, rootFontSize: 20)
                config.defaultTextAlignment = .justified
                config.fontResolver = { _, _, _, size in UIFont.systemFont(ofSize: size) }
                let html = "<body style='margin:0'>" + body + "</body>"
                let reference = try HTMLLayoutDocument(html: html, configuration: config)
                    .prepareContinuous().makeDocument()
                let session = try HTMLLayoutDocument(html: html, configuration: config).makeViewportSession()
                let rect = CGRect(x: 0, y: 0, width: width, height: reference.contentHeight + 1)
                let actual = try session.layout(in: rect)
                #expect(actual.sourceText == reference.sourceText)
                #expect(abs(actual.contentHeight - reference.contentHeight) < 0.01)
                for scale: CGFloat in [1, 3] {
                    let expectedPixels = raster(reference.items(in: rect), size: rect.size, scale: scale).pngData()
                    let actualPixels = raster(actual.items(in: rect), size: rect.size, scale: scale).pngData()
                    #expect(actualPixels == expectedPixels, "fixture \(fixture), width \(width), scale \(scale)")
                }
            }
        }
    }

    @Test func onlyViewportTilesUseAsynchronousRasterAndKeepItAfterReuse() async throws {
        let owner = try BrowserViewportLayoutOwner(document: HTMLLayoutDocument(html: "<p>中文 viewport text</p>",
            configuration: BrowserLayoutConfig(renderWidth: 320, renderHeight: 600)))
        let snapshot = try await owner.layout(in: CGRect(x: 0, y: 0, width: 320, height: 600))
        let document = snapshot.document
        let viewportDriven = BrowserScrollChapter(spineIndex: 0, layoutOwner: owner, snapshot: snapshot,
            backgroundColor: .white, usesReaderBackground: false)
        let finalDocument = BrowserScrollChapter(spineIndex: 0, document: document,
            backgroundColor: .white, usesReaderBackground: false)
        func tile(_ chapter: BrowserScrollChapter) -> BrowserScrollTile {
            BrowserScrollTile(chapter: chapter, documentRect: CGRect(x: 0, y: 0, width: 320, height: 600),
                              charRange: CFRange(location: 0, length: (document.sourceText as NSString).length))
        }
        let cell = BrowserScrollTileCell(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        cell.configure(tile: tile(finalDocument), horizontalInset: 0, leadingSpacing: 0)
        #expect(!cell.interactiveView.layer.drawsAsynchronously)
        cell.configure(tile: tile(viewportDriven), horizontalInset: 0, leadingSpacing: 0)
        #expect(cell.interactiveView.layer.drawsAsynchronously)
        cell.prepareForReuse()
        cell.configure(tile: tile(viewportDriven), horizontalInset: 0, leadingSpacing: 0)
        #expect(cell.interactiveView.layer.drawsAsynchronously)
        cell.configure(tile: tile(finalDocument), horizontalInset: 0, leadingSpacing: 0)
        #expect(!cell.interactiveView.layer.drawsAsynchronously)
    }

    @Test func backingStoreSubmissionCostAndLatestSnapshotStayEquivalent() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let size = CGSize(width: 392, height: 810)
        let host = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.backgroundColor = .white
        let page = BrowserLayoutPageView(frame: CGRect(origin: CGPoint(x: 0, y: 40), size: size))
        page.usesContinuousScrolling = true
        page.backgroundColorFill = .white
        host.view.addSubview(page)
        var config = BrowserLayoutConfig(renderWidth: size.width, renderHeight: size.height, rootFontSize: 22)
        config.defaultTextAlignment = .justified
        let imageFormat = UIGraphicsImageRendererFormat()
        imageFormat.scale = 1
        let sourceImage = UIGraphicsImageRenderer(size: CGSize(width: 1029, height: 1280), format: imageFormat).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1029, height: 1280))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 137, y: 319, width: 593, height: 547))
        }
        // Preserve a PNG-backed provider, as used by the EPUB image adapter.
        let png = try #require(sourceImage.pngData())
        let decodedImage = try #require(UIImage(data: png))
        let paragraph = "<p>" + String(repeating: "春眠不覺曉，處處聞啼鳥。", count: 8) + "</p>"
        let html = "<body>" + String(repeating: paragraph + "<img src='figure.png' style='display:block;width:100%;height:auto'>", count: 12) + "</body>"
        let session = try HTMLLayoutDocument(html: html, configuration: config,
                                            images: ["figure.png": decodedImage]).makeViewportSession()
        let document = try session.layout(in: CGRect(x: 0, y: 0, width: size.width, height: size.height * 4))
        let lists = (0..<3).map { document.items(in: CGRect(x: 0, y: CGFloat($0) * size.height, width: size.width, height: size.height)) }
        for list in lists {
            #expect(list.items.contains { if case .image = $0 { return true }; return false })
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = page.contentScaleFactor
        var pixels: [Bool: Data] = [:]
        var snapshots: [Bool: UIImage] = [:]
        var times: [Bool: [Double]] = [:]
        for asynchronous in [false, true, true, false] {
            page.layer.drawsAsynchronously = asynchronous
            let batchStart = SourcePerfTrace.now
            for step in 0..<30 {
                let start = SourcePerfTrace.now
                page.displayList = lists[step % lists.count]
                page.setNeedsDisplay()
                page.layer.displayIfNeeded()
                CATransaction.flush()
                times[asynchronous, default: []].append((SourcePerfTrace.now - start) * 1000)
            }
            SourcePerfTrace.record("test.scroll.backingSubmission", "async=\(asynchronous) updates=30", since: batchStart, thresholdMs: 0)
            // Capture only after the newest screen update: an old asynchronous
            // raster must never overwrite the latest binding or leave it blank.
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                #expect(page.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true))
            }
            let data = try #require(image.pngData())
            if let previous = pixels[asynchronous] {
                #expect(previous == data, "repeated updates must retain the latest snapshot")
            }
            pixels[asynchronous] = data
            snapshots[asynchronous] = image
            #expect(page.displayList.hasSameContents(as: lists[2]))
        }
        let imageRects = lists[2].items.compactMap { item -> CGRect? in
            if case .image(let image) = item { return image.rect.rawValue }
            return nil
        }
        try compareRasterSnapshots(#require(snapshots[false]), #require(snapshots[true]), imageRects: imageRects)
        for mode in [false, true] {
            let values = try #require(times[mode]).sorted()
            print("[BackingStore] async=\(mode) samples=\(values.count) medianMs=\(values[values.count / 2]) p95Ms=\(values[Int(Double(values.count - 1) * 0.95)])")
        }
    }

    private func compareRasterSnapshots(_ reference: UIImage, _ actual: UIImage, imageRects: [CGRect]) throws {
        let expectedImage = try #require(reference.cgImage)
        let actualImage = try #require(actual.cgImage)
        let width = expectedImage.width, height = expectedImage.height
        #expect(actualImage.width == width && actualImage.height == height)
        func rgba(_ image: CGImage) throws -> [UInt32] {
            var result = [UInt32](repeating: 0, count: width * height)
            try result.withUnsafeMutableBytes { bytes in
                let context = try #require(CGContext(data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return result
        }
        let expected = try rgba(expectedImage), rendered = try rgba(actualImage)
        var boundaryDifferences = 0, unexpectedDifferences = 0
        for index in expected.indices where expected[index] != rendered[index] {
            let x = index % width, y = index / width
            let point = CGPoint(x: (CGFloat(x) + 0.5) / reference.scale,
                                y: (CGFloat(y) + 0.5) / reference.scale)
            // CA's synchronous and asynchronous rasterizers sample scaled PNG
            // boundaries differently. Require exact text and flat image pixels;
            // only an existing image boundary's one-native-pixel neighbourhood
            // may differ. This rejects blanks, stale content and shifted tiles.
            let inImage = imageRects.contains { $0.insetBy(dx: -1 / reference.scale, dy: -1 / reference.scale).contains(point) }
            let nearBoundary = inImage && (max(0, y - 1)...min(height - 1, y + 1)).contains { row in
                (max(0, x - 1)...min(width - 1, x + 1)).contains { col in
                    expected[row * width + col] != expected[index]
                }
            }
            if nearBoundary { boundaryDifferences += 1 } else { unexpectedDifferences += 1 }
        }
        #expect(unexpectedDifferences == 0, "text, image interiors and content geometry must remain identical")
        print("[BackingStorePixels] native=\(width)x\(height) imageBoundaryDifferences=\(boundaryDifferences) unexpectedDifferences=\(unexpectedDifferences)")
    }

    private func raster(_ list: DisplayList, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            list.draw(in: context.cgContext)
        }
    }
}
