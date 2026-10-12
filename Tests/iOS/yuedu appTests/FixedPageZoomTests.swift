import Foundation
import Testing
import UIKit
@testable import yuedu_app

/// 固定頁閱讀器的放大：分頁只能有一層縮放、放大停下後 PDF 要重畫清楚、
/// 條漫的縮放要讓整條內容兩個方向都變大，以及單擊要等雙擊。
///
/// 分頁每一頁原本在 spread 的縮放層裡面，還包著一層自己的縮放；那層「關掉」了，
/// 雙指辨識器卻還在，接走每一次雙指縮放又什麼都不做，只剩雙擊能放大。
/// PDF 放大後重畫也掛在那層不會縮放的裡層上，所以從來沒觸發過。
@Suite("Fixed page zoom", .serialized)
@MainActor
struct FixedPageZoomTests {

    @Test("a spread is the only zoom layer", arguments: [1, 2])
    func spreadHasOneZoomLayer(pageCount: Int) {
        let pages = (0..<pageCount).map { index in
            FixedPage(
                id: index,
                imageURL: "",
                headers: [:],
                localURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("FixedPageZoomTests-missing-\(UUID().uuidString).png")
            )
        }
        let spread = FixedPageSpreadViewController(
            spreadIndex: 0,
            pages: pages,
            fixedPageReaderConfiguration: .recommendedDefault(for: .rtl),
            targetWidth: 400
        )
        spread.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        spread.view.layoutIfNeeded()

        let scrollViews = Self.descendants(of: spread.view).compactMap { $0 as? UIScrollView }
        #expect(scrollViews.count == 1)
        #expect(scrollViews.first is FixedPageZoomableScrollView)
        #expect(spread.pageControllers.count == pageCount)
    }

    @Test("a settled zoom re-renders a PDF page for it, and fitted again restores the 1x render")
    func settledZoomRerendersPDF() async throws {
        let (page, url) = try Self.makePDFPage()
        defer { try? FileManager.default.removeItem(at: url) }
        let spread = FixedPageSpreadViewController(
            spreadIndex: 0,
            pages: [page],
            fixedPageReaderConfiguration: .recommendedDefault(for: .ltr),
            targetWidth: 200
        )
        spread.view.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        spread.view.layoutIfNeeded()
        let pageController = try #require(spread.pageControllers.first)
        await pageController.loadTask?.value
        let fitted = try #require(pageController.imageView.image)

        spread.zoomDidSettle(atScale: 3)
        await pageController.refineTask?.value
        let zoomed = try #require(pageController.imageView.image)
        await PDFPageRasterizer.shared.purge()

        #expect(zoomed.size.width > fitted.size.width * 2)
        spread.zoomDidSettle(atScale: 1)
        #expect(pageController.imageView.image === fitted)
    }

    @Test("a spread comes back at the zoom it was left at, re-rendered and without the Live Text button")
    func spreadRestoresItsZoom() async throws {
        let (page, url) = try Self.makePDFPage()
        defer { try? FileManager.default.removeItem(at: url) }
        let viewport = CGSize(width: 200, height: 400)
        let zoom = FixedPageSpreadViewController.Zoom(
            scale: 2, contentOffset: CGPoint(x: 100, y: 150), viewportSize: viewport
        )
        let spread = FixedPageSpreadViewController(
            spreadIndex: 0,
            pages: [page],
            fixedPageReaderConfiguration: .recommendedDefault(for: .ltr),
            targetWidth: 200
        )
        spread.restoredZoom = zoom
        spread.controlsShown = true
        spread.view.frame = CGRect(origin: .zero, size: viewport)
        spread.view.layoutIfNeeded()
        let pageController = try #require(spread.pageControllers.first)
        // Until the page shows its image, the zoom to keep is still the restored one.
        #expect(spread.currentZoom == zoom)

        await pageController.loadTask?.value
        #expect(spread.currentZoom == zoom)
        // Zoomed in, the Live Text button stays away even with the controls up.
        #expect(!pageController.showsLiveTextButton)
        let fitted = try #require(pageController.imageView.image)
        await pageController.refineTask?.value
        await PDFPageRasterizer.shared.purge()
        #expect(try #require(pageController.imageView.image).size.width > fitted.size.width * 1.5)
    }

    @Test("a spread at its fitted size has no zoom to keep, and reports on leaving the screen")
    func fittedSpreadKeepsNoZoom() {
        let spread = FixedPageSpreadViewController(
            spreadIndex: 3,
            pages: [FixedPage(id: 0, imageURL: "", headers: [:])],
            fixedPageReaderConfiguration: .recommendedDefault(for: .rtl),
            targetWidth: 200
        )
        var reported: [Int] = []
        spread.onDisappear = { reported.append($0.spreadIndex) }
        spread.view.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        spread.view.layoutIfNeeded()
        #expect(spread.currentZoom == nil)
        spread.beginAppearanceTransition(false, animated: false)
        spread.endAppearanceTransition()
        #expect(reported == [3])
    }

    @Test("Live Text's button shows only with the controls up and the page not zoomed")
    func liveTextButtonRule() {
        #expect(FixedPageZoom.showsLiveTextButton(controlsShown: true, zoomScale: 1))
        #expect(!FixedPageZoom.showsLiveTextButton(controlsShown: false, zoomScale: 1))
        #expect(!FixedPageZoom.showsLiveTextButton(controlsShown: true, zoomScale: 2))
        // What a spring-back leaves behind still counts as fitted.
        #expect(FixedPageZoom.showsLiveTextButton(controlsShown: true, zoomScale: 1.005))
    }

    @Test("zooming the webtoon layout scales pages, gaps and the content in both directions")
    func webtoonLayoutScales() {
        var configuration = FixedPageReaderConfiguration.recommendedDefault(for: .webtoon)
        configuration.pageSpacing = 10
        configuration.pillarbox = true
        configuration.pillarboxAmount = 0.5
        let layout = FixedPageWebtoonLayout(fixedPageReaderConfiguration: configuration)
        let dataSource = CountingDataSource(count: 3)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            collectionViewLayout: layout
        )
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: CountingDataSource.reuseID)
        collectionView.dataSource = dataSource
        layout.setRatio(1.5, forItem: 0)
        layout.setRatio(0.5, forItem: 1)
        collectionView.layoutIfNeeded()
        let fitted = Self.itemFrames(in: layout, count: 3)
        let fittedSize = layout.collectionViewContentSize
        // Pillarboxed to half the width, centred.
        #expect(fitted[0] == CGRect(x: 100, y: 0, width: 200, height: 300))
        #expect(fitted[1] == CGRect(x: 100, y: 310, width: 200, height: 100))

        layout.zoomScale = 2
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()

        #expect(Self.itemFrames(in: layout, count: 3) == fitted.map {
            CGRect(x: $0.minX * 2, y: $0.minY * 2, width: $0.width * 2, height: $0.height * 2)
        })
        #expect(layout.collectionViewContentSize == CGSize(width: fittedSize.width * 2, height: fittedSize.height * 2))
    }

    @Test("a webtoon pinch keeps the content under the fingers and stays inside the list")
    func webtoonZoomKeepsAnchor() {
        let viewport = CGSize(width: 400, height: 800)
        let zoomedContent = CGSize(width: 800, height: 8000)

        // Content point (100, 1200) under the fingers at (100, 200), at 2x.
        let offset = FixedPageWebtoonViewController.zoomedContentOffset(
            anchor: CGPoint(x: 100, y: 1200), scale: 2, viewportPoint: CGPoint(x: 100, y: 200),
            contentSize: zoomedContent, viewportSize: viewport
        )
        #expect(offset == CGPoint(x: 100, y: 2200))

        // At the start and the end the offset stops at the edge rather than show past it.
        let start = FixedPageWebtoonViewController.zoomedContentOffset(
            anchor: CGPoint(x: 10, y: 10), scale: 2, viewportPoint: CGPoint(x: 200, y: 400),
            contentSize: zoomedContent, viewportSize: viewport
        )
        #expect(start == .zero)
        let end = FixedPageWebtoonViewController.zoomedContentOffset(
            anchor: CGPoint(x: 400, y: 4000), scale: 2, viewportPoint: .zero,
            contentSize: zoomedContent, viewportSize: viewport
        )
        #expect(end == CGPoint(x: 400, y: 7200))
    }

    @Test("a reader tap waits for the zoom double tap, and only for it")
    func readerTapWaitsForZoomDoubleTap() {
        let delegate = FixedPageReaderControlTapDelegate()
        let tap = UITapGestureRecognizer()
        let zoomDoubleTap = FixedPageDoubleTapZoomGestureRecognizer(target: nil, action: nil)
        let otherDoubleTap = UITapGestureRecognizer()
        otherDoubleTap.numberOfTapsRequired = 2

        #expect(zoomDoubleTap.numberOfTapsRequired == 2)
        #expect(delegate.gestureRecognizer(tap, shouldRequireFailureOf: zoomDoubleTap))
        #expect(!delegate.gestureRecognizer(tap, shouldRequireFailureOf: otherDoubleTap))
    }

    @Test("the zoom double tap sits out while switched off, and on controls")
    func doubleTapGate() {
        let page = UIView()
        let button = UIButton(type: .system)
        page.addSubview(button)
        #expect(FixedPageDoubleTapZoomGate.acceptsDoubleTap(isEnabled: true, on: page))
        #expect(!FixedPageDoubleTapZoomGate.acceptsDoubleTap(isEnabled: false, on: page))
        #expect(!FixedPageDoubleTapZoomGate.acceptsDoubleTap(isEnabled: true, on: button))
    }

    // MARK: - Helpers

    private static func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private static func itemFrames(in layout: UICollectionViewLayout, count: Int) -> [CGRect] {
        (0..<count).compactMap { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame }
    }

    /// 一頁 400 × 600 的 PDF，寫到 `LocalPDFArchive.archiveURL`。
    private static func makePDFPage() throws -> (FixedPage, URL) {
        let filename = "FixedPageZoomTests-\(UUID().uuidString).pdf"
        let url = LocalPDFArchive.archiveURL(for: filename)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).pdfData { context in
            context.beginPage()
            UIColor(white: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 50, y: 100, width: 300, height: 300))
        }
        try data.write(to: url)
        let page = FixedPage(
            id: 0,
            imageURL: url.absoluteString,
            headers: [:],
            localURL: nil,
            renderSource: .pdf(sourceFilename: filename, pageIndex: 0)
        )
        return (page, url)
    }
}

private final class CountingDataSource: NSObject, UICollectionViewDataSource {
    static let reuseID = "cell"
    let count: Int

    init(count: Int) {
        self.count = count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: Self.reuseID, for: indexPath)
    }
}
