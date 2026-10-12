@testable import YueduCoreText
import Foundation
import Testing
import UIKit
@testable import yuedu_app

/// Digests re-recorded 2026-09-23 for YueduCoreText 0.5.0. In the same environment the
/// package at 0.4.0 still reproduces every previous digest and 0.5.1 produces these, so the
/// change is 0.5.0's line box: half-leading from UIFont metrics (Helvetica's ascender carries
/// 0.15em, moving baselines 1.275pt at 17pt) and the parent strut below images and ruby.
/// Row-level evidence: docs/browser-layout/yueducoretext-0.5.0-baselines-2026-09-23.md.
@MainActor
struct BrowserLayoutInlineFormattingContextParityTests {
    private static let viewport = CGSize(width: 390, height: 844)
    private static let insets = UIEdgeInsets(top: 18, left: 16, bottom: 22, right: 16)

    private struct Fixture {
        let pipeline: BrowserLayoutDocument.BrowserLayoutPipelineResult
        let pages: [PageFragments]
    }

    private func fixture(
        body: String,
        css: String = "",
        imageLoader: ((String) -> UIImage?)? = nil
    ) throws -> Fixture {
        let contentWidth = Self.viewport.width - Self.insets.left - Self.insets.right
        let contentHeight = Self.viewport.height - Self.insets.top - Self.insets.bottom
        let config = BrowserLayoutConfig(
            renderWidth: contentWidth,
            renderHeight: contentHeight,
            rootFontSize: 17,
            fontFamilies: ["Helvetica"],
            textColor: .black,
            backgroundColor: .white,
            contentInsets: Self.insets
        )
        let document = BrowserLayoutDocument(
            html: "<html><body>\(body)</body></html>",
            cssTexts: ["html, body { margin:0; padding:0 } \(css)"],
            config: config,
            imageLoader: imageLoader
        )
        let pipeline = try document.makeLayout(
            containerSize: Self.viewport,
            fragmentHeight: contentHeight
        )
        let pages = PageFragmentation.fragment(
            box: pipeline.rootBox,
            pageSize: Self.viewport,
            contentInsets: Self.insets
        )
        return Fixture(pipeline: pipeline, pages: pages)
    }

    private func snapshot(
        _ fixture: Fixture,
        selectionRange: NSRange? = nil
    ) -> BrowserLayoutGeometryFingerprint.Snapshot {
        BrowserLayoutGeometryFingerprint.snapshot(
            pipeline: fixture.pipeline,
            pages: fixture.pages,
            selectionRange: selectionRange
        )
    }

    private func assertDigest(
        _ snapshot: BrowserLayoutGeometryFingerprint.Snapshot,
        equals expected: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(snapshot.digest == expected, sourceLocation: sourceLocation)
    }

    @Test func ordinaryProseGeometryFingerprintIsStable() throws {
        let prose = String(repeating: "Ordinary prose keeps every glyph and line break stable. ", count: 18)
        let value = try fixture(
            body: "<p class='prose'>\(prose)</p>",
            css: ".prose { margin:11px 9px 13px; padding:7px 5px; line-height:24px }"
        )
        assertDigest(
            snapshot(value),
            // This fixture intentionally has paragraph margin + padding, so it
            // is the one Phase-4E0 PRE artifact directly superseded by the
            // used-value correction: line breaking now uses the paragraph's
            // final content box instead of its provisional parent width.
            equals: "cba5c8c9d1be93ff915fd0b76ec30d4abad6b0bcea2aa7af8c17509476bb171c"
        )
    }

    @Test func multiRunLinkGeometryFingerprintIsStable() throws {
        let value = try fixture(
            body: "<p class='links'>Before <a href='note.xhtml#n1'>linked <strong>inline text</strong> across a line boundary</a> after.</p>",
            css: ".links { margin:0; width:210px; line-height:23px } strong { font-weight:700 }"
        )
        let list = DisplayListBuilder.build(
            for: try #require(value.pages.first),
            sourceText: value.pipeline.sourceText
        )
        let links = LinkInteractionRegionSet.build(
            from: list,
            spineIndex: 0,
            anchors: value.pipeline.linkAnchors
        )
        #expect(links.regions.count >= 2)
        assertDigest(
            snapshot(value),
            equals: "5749e56ceb90c0cf7539df2ed89b746d94dbf4ae0004d94978973a04f24b4023"
        )
    }

    @Test func horizontalRubyGeometryFingerprintIsStable() throws {
        let value = try fixture(
            body: "<p class='ruby'>甲<a href='note.xhtml'><ruby><span>漢字</span><rt>かんじ</rt></ruby></a>乙</p>",
            css: ".ruby { margin:0; line-height:28px } ruby { ruby-align:center; ruby-position:over }"
        )
        let annotations = BrowserLayoutTestSupport.allTextFragments(value.pages).filter {
            $0.renderedTextOverride == "かんじ"
        }
        #expect(annotations.count == 1)
        #expect(annotations.first?.sourceMapping == .wholeRange)
        assertDigest(
            snapshot(value),
            equals: "50cc27c4ae1f1885315f7a06732fe6ab12a81ff44283a1c3a26111f0fb6814ad"
        )
    }

    @Test func inlineImageGeometryFingerprintIsStable() throws {
        let image = BrowserLayoutTestSupport.makeImage(
            size: CGSize(width: 120, height: 80),
            color: .red
        )
        let value = try fixture(
            body: "<p class='image'>before <a href='image.xhtml'><img src='fixture.png' alt='fixture'/></a> after</p>",
            css: ".image { margin:0; line-height:25px } img { width:72px; height:48px; max-width:100% }",
            imageLoader: { $0 == "fixture.png" ? image : nil }
        )
        #expect(BrowserLayoutTestSupport.allImageFragments(value.pages).count == 1)
        assertDigest(
            snapshot(value),
            equals: "1574c8f631367aff52768dd4e22f017d9a1dcffa151841d84a81cb90047731cc"
        )
    }

    @Test func leftAndRightFloatGeometryFingerprintIsStable() throws {
        let left = BrowserLayoutTestSupport.makeImage(
            size: CGSize(width: 90, height: 110),
            color: .blue
        )
        let right = BrowserLayoutTestSupport.makeImage(
            size: CGSize(width: 70, height: 85),
            color: .green
        )
        let prose = String(repeating: "Float exclusions constrain this line without changing source order. ", count: 12)
        let value = try fixture(
            body: "<div class='flow'><img class='left' src='left.png'/><img class='right' src='right.png'/><p>\(prose)</p></div>",
            css: ".flow, .flow p { margin:0; line-height:23px } img.left { float:left; width:90px; height:110px; margin:0 8px 6px 0 } img.right { float:right; width:70px; height:85px; margin:0 0 5px 7px }",
            imageLoader: { source in source == "left.png" ? left : (source == "right.png" ? right : nil) }
        )
        let floated = children(of: value.pipeline.rootBox).filter(\.isFloated)
        #expect(floated.count == 2)
        assertDigest(
            snapshot(value),
            equals: "3aaccfaaddda305b282166d256e5bb9a5d143add7423439adf698eb81a904171"
        )
    }

    @Test func paginationAndPageSourceRangesAreStable() throws {
        let paragraphs = (0..<34).map { index in
            "<p>Paragraph \(index): \(String(repeating: "pagination source mapping remains monotonic. ", count: 4))</p>"
        }.joined()
        let value = try fixture(
            body: paragraphs,
            css: "p { margin:0 0 12px; line-height:24px }"
        )
        #expect(value.pages.count > 2)
        let ranges = BrowserChapterLayout.buildPageRanges(
            value.pages,
            sourceText: value.pipeline.sourceText
        )
        #expect(zip(ranges, ranges.dropFirst()).allSatisfy { lhs, rhs in
            lhs.location <= rhs.location && lhs.location + lhs.length <= rhs.location + rhs.length
        })
        assertDigest(
            snapshot(value),
            equals: "c1452946a1c3d782156aa49e68e1d8cde7da3339b52808e41c3c565e4235ab10"
        )
    }

    @Test func selectionAndLinkHitGeometryIsStable() throws {
        let body = "<p class='selection'>The <a href='note.xhtml#target'>office ligature link</a> and selectable suffix remain exact.</p>"
        let value = try fixture(
            body: body,
            css: ".selection { margin:0; width:230px; line-height:25px }"
        )
        let selection = (value.pipeline.sourceText as NSString).range(of: "office")
        #expect(selection.location != NSNotFound)
        let firstPage = try #require(value.pages.first)
        let links = LinkInteractionRegionSet.build(
            from: DisplayListBuilder.build(for: firstPage, sourceText: value.pipeline.sourceText),
            spineIndex: 0,
            anchors: value.pipeline.linkAnchors
        )
        let firstLink = try #require(links.regions.first)
        #expect(links.hitTest(CGPoint(x: firstLink.pageLocalRect.midX, y: firstLink.pageLocalRect.midY)) != nil)
        assertDigest(
            snapshot(value, selectionRange: selection),
            equals: "00c2be59d03554286ef9bb99e6d8b138a452a39d923ca8f78e39f8c8cc5114da"
        )
    }

    @Test func repeatedLayoutProducesIdenticalFingerprint() throws {
        let body = "<p>Repeated shaping must preserve every scalar bit pattern. <ruby>漢<rt>かん</rt></ruby></p>"
        let css = "p { margin:0; padding:4px; line-height:26px }"
        let first = snapshot(try fixture(body: body, css: css))
        let second = snapshot(try fixture(body: body, css: css))
        #expect(first == second)
    }

    private func children(of box: BlockBox) -> [BlockBox] {
        [box] + box.children.flatMap(children(of:))
    }
}
