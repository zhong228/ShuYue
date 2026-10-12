@testable import YueduCoreText
import Testing
import UIKit
@testable import yuedu_app

/// 詭秘之主 (2026-09-23), 捲動 mode: a chapter's `body { background: #fff
/// url(fm01.jpg) top center; background-attachment: fixed; background-size: cover }`
/// was painted inside the content column, cover-sized to the whole chapter (a
/// blurred image some 9000pt wide), as paint fragments that arrived after the
/// text; and a heading with `margin-left: -1em` was cut at the column's edge.
@Suite(.serialized)
@MainActor
struct BrowserScrollPageBackgroundTests {
    private let screen = CGRect(x: 0, y: 0, width: 440, height: 900)
    private let inset: CGFloat = 30
    private let chapterTop: CGFloat = 100
    private var contentWidth: CGFloat { screen.width - inset * 2 }
    private let artwork = BrowserLayoutTestSupport.makeImage(size: CGSize(width: 72, height: 156),
                                                             color: UIColor(white: 0.93, alpha: 1))

    private func chapter(fixed: Bool, paragraphs: Int = 120, heading: String = "") throws -> BrowserScrollChapter {
        let attachment = fixed ? "background-attachment:fixed;" : ""
        let html = "<html><body style=\"margin:0; background:#ffffff url(bg.jpg) no-repeat center;"
            + " background-position:top center; \(attachment) background-size:cover\">" + heading
            + (0..<paragraphs).map { "<p>段落 \($0) " + String(repeating: "中文內容 ", count: 12) + "</p>" }.joined()
            + "</body></html>"
        let owner = try BrowserViewportLayoutOwner(document: HTMLLayoutDocument(html: html,
            configuration: BrowserLayoutConfig(renderWidth: contentWidth, renderHeight: screen.height),
            images: ["bg.jpg": artwork]))
        return BrowserScrollChapter(spineIndex: 0, layoutOwner: owner, snapshot: owner.initialSnapshot,
            backgroundColor: .lightGray, usesReaderBackground: false, pageBackgroundImage: artwork)
    }

    private func mount(_ chapter: BrowserScrollChapter, viewport: CGRect) -> ReaderViewportFragmentHost {
        let host = ReaderViewportFragmentHost(frame: CGRect(x: 0, y: 0, width: screen.width, height: 40_000))
        update(host, chapter, viewport: viewport)
        return host
    }

    private func update(_ host: ReaderViewportFragmentHost, _ chapter: BrowserScrollChapter, viewport: CGRect) {
        host.update([.init(chapter: chapter, origin: CGPoint(x: inset, y: chapterTop), width: contentWidth)],
                    viewport: viewport, scale: 3)
    }

    private func backdrop(_ host: ReaderViewportFragmentHost) throws -> BrowserChapterBackdropView {
        try #require(host.subviews.compactMap { $0 as? BrowserChapterBackdropView }.first)
    }

    @Test func theChapterLeavesItsPageBackgroundToTheHost() throws {
        let chapter = try chapter(fixed: true)
        let background = try #require(chapter.pageBackground)
        #expect(background.isFixed)
        #expect(background.imageSource == "bg.jpg")
        var white: CGFloat = 0, alpha: CGFloat = 0
        #expect(background.color?.getWhite(&white, alpha: &alpha) == true && white > 0.99 && alpha > 0.99)
        let painted = chapter.document.displayList.items.contains {
            switch $0 {
            case .fill(let fill): fill.isBackgroundPaint
            case .image(let image): image.isBackgroundPaint
            case .text: false
            }
        }
        #expect(!painted, "the chapter's documents do not paint the page background")
        let fragments = chapter.document.paintFragments(in: CGRect(x: -inset, y: 0, width: screen.width, height: 3000), scale: 3)
        #expect(fragments.allSatisfy { $0.renderingRect.width <= screen.width })
    }

    /// Sized against one screen like paged mode's page, not against the chapter.
    @Test func thePageBackgroundImageIsSizedToOneScreen() throws {
        let background = try #require(try chapter(fixed: true).pageBackground)
        let rect = background.imageRect(for: artwork.size, onPageOf: screen.size)
        #expect(rect.minY == 0, "top center")
        #expect(abs(rect.midX - screen.midX) < 0.5)
        #expect(rect.width >= screen.width - 0.5 && rect.height >= screen.height - 0.5, "cover")
        #expect(rect.height < screen.height * 1.2)
    }

    @Test func aFixedPageBackgroundSpansTheScreenAndStaysWhileTheTextScrolls() throws {
        let chapter = try chapter(fixed: true)
        var viewport = screen.offsetBy(dx: 0, dy: 300)
        let host = mount(chapter, viewport: viewport)
        let backdrop = try backdrop(host)
        #expect(host.subviews.first === backdrop, "behind the chapter's text")
        #expect(backdrop.frame.minX == 0 && backdrop.frame.width == screen.width, "the reader's margins included")
        #expect(backdrop.frame.minY == chapterTop)
        // Shown by this update: no bitmap is painted for it.
        let page = try #require(backdrop.visiblePageFrames.first)
        #expect(abs(backdrop.frame.minY + page.minY - viewport.minY) < 0.01, "at the top of the screen")
        #expect(page.width == screen.width && page.height == screen.height)
        viewport = viewport.offsetBy(dx: 0, dy: 1700)
        update(host, chapter, viewport: viewport)
        let moved = try #require(backdrop.visiblePageFrames.first)
        #expect(abs(backdrop.frame.minY + moved.minY - viewport.minY) < 0.01, "still at the top of the screen")
        #expect(backdrop.visiblePageFrames.count == 1)
    }

    /// Without `fixed`, one page of artwork per screen height scrolls with the
    /// chapter, as a CoreText chapter's backdrop does.
    @Test func aScrollingPageBackgroundRepeatsOnePagePerScreen() throws {
        let chapter = try chapter(fixed: false)
        let viewport = screen.offsetBy(dx: 0, dy: 2000)
        let backdrop = try backdrop(mount(chapter, viewport: viewport))
        let frames = backdrop.visiblePageFrames
        #expect(!frames.isEmpty)
        #expect(frames.allSatisfy { $0.minY.truncatingRemainder(dividingBy: screen.height) == 0 && $0.height == screen.height })
        let shown = frames.map { $0.offsetBy(dx: 0, dy: backdrop.frame.minY) }
        #expect(shown.contains { $0.minY <= viewport.minY } && shown.contains { $0.maxY >= viewport.maxY },
                "the screen is covered")
    }

    /// A heading CSS hangs into the margin shows there, as on a page.
    @Test func textInTheMarginIsNotCutAtTheContentColumn() async throws {
        let chapter = try chapter(fixed: true, paragraphs: 2,
            heading: "<p style=\"margin:0 0 0 -1em; font-size:30px; line-height:40px\">其他</p>")
        // The chapter's text exists once its owner has laid it out.
        chapter.requestViewport(CGRect(x: 0, y: 0, width: contentWidth, height: screen.height))
        await chapter.waitForViewportIdle()
        let heading = chapter.document.displayList.items.compactMap { item -> CGRect? in
            if case .text(let text) = item, text.text.contains("其") { return text.rect.rawValue }
            return nil
        }.first
        #expect((heading?.minX ?? 0) < 0, "laid out into the margin: \(String(describing: heading))")
        let host = mount(chapter, viewport: screen)
        await host.waitForRasterIdle()
        let size = CGSize(width: screen.width, height: chapterTop + 60)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { host.layer.render(in: $0.cgContext) }
        let cg = try #require(image.cgImage)
        let context = try #require(CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
            bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var inkInMargin = 0
        for y in Int(chapterTop)..<cg.height {
            for x in 0..<Int(inset) {
                let i = (y * cg.width + x) * 4
                if pixels[i] < 110 && pixels[i + 1] < 110 && pixels[i + 2] < 110 { inkInMargin += 1 }
            }
        }
        #expect(inkInMargin > 20, "the heading's first glyph, left of the content column (\(inkInMargin) dark pixels)")
    }
}
