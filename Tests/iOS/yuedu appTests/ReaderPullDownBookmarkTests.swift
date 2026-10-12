import Testing
import UIKit
@testable import yuedu_app

@Suite("Pull-down bookmark motion")
struct ReaderPullDownBookmarkMotionTests {
    @Test("only clearly downward drags may begin the gesture")
    func beginDirection() {
        #expect(ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 0, y: 300)))
        #expect(ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 100, y: 300)))
        // Upward drag belongs to the swipe-up exit gesture.
        #expect(!ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 0, y: -300)))
        // Horizontal-dominant drags stay with the page-turn gestures.
        #expect(!ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: -400, y: 300)))
        #expect(!ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 400, y: 300)))
        // Diagonal drags near 45° are ambiguous; require clear vertical dominance.
        #expect(!ReaderPullDownBookmarkMotion.shouldBegin(velocity: CGPoint(x: 300, y: 310)))
    }

    @Test("the two vertical reader gestures never both accept the same drag")
    func mutuallyExclusiveWithSwipeUpExit() {
        for velocity in [
            CGPoint(x: 0, y: 300), CGPoint(x: 0, y: -300),
            CGPoint(x: 120, y: 400), CGPoint(x: -120, y: -400),
            CGPoint(x: 400, y: 20), CGPoint(x: -400, y: -20),
        ] {
            let down = ReaderPullDownBookmarkMotion.shouldBegin(velocity: velocity)
            let up = ReaderSwipeUpExitMotion.shouldBegin(velocity: velocity)
            #expect(!(down && up), "both gestures claimed \(velocity)")
        }
    }

    @Test("progress tracks downward travel and clamps to 0...1")
    func progressClamping() {
        #expect(ReaderPullDownBookmarkMotion.progress(forTranslationY: 0) == 0)
        #expect(ReaderPullDownBookmarkMotion.progress(forTranslationY: -120) == 0)
        let half = ReaderPullDownBookmarkMotion.progress(
            forTranslationY: ReaderPullDownBookmarkMotion.fullProgressTranslation / 2
        )
        #expect(abs(half - 0.5) < 0.0001)
        #expect(ReaderPullDownBookmarkMotion.progress(
            forTranslationY: ReaderPullDownBookmarkMotion.fullProgressTranslation * 3
        ) == 1)
    }

    @Test("the page follows the finger, then stiffens like an overscroll, and never passes its limit")
    func pageOffsetIsARubberBand() {
        let offset = ReaderPullDownBookmarkMotion.pageOffset(forTranslationY:)
        #expect(offset(0) == 0)
        #expect(offset(-80) == 0)
        // Near one to one at the start of the pull.
        #expect(abs(offset(10) - 10) < 0.5)
        // Monotonic, and each extra 50pt of finger buys less page than the last.
        let samples = stride(from: 0, through: 600, by: 50).map { offset(CGFloat($0)) }
        for (a, b) in zip(samples, samples.dropFirst()) { #expect(b > a) }
        let gains = zip(samples, samples.dropFirst()).map { $1 - $0 }
        for (a, b) in zip(gains, gains.dropFirst()) { #expect(b < a) }
        // Any pull a hand can make stays short of the limit; an absurd one
        // reaches it (exp underflows to 0) and still never goes past.
        #expect(offset(900) < ReaderPullDownBookmarkMotion.maxPageOffset)
        #expect(offset(10_000) <= ReaderPullDownBookmarkMotion.maxPageOffset)
    }

    @Test("at the commit point the page has come down far enough to show its hint")
    func commitPointOpensARealGap() {
        let commitTravel = ReaderPullDownBookmarkMotion.fullProgressTranslation
            * ReaderPullDownBookmarkMotion.commitProgress
        let offset = ReaderPullDownBookmarkMotion.pageOffset(forTranslationY: commitTravel)
        let hintHeight: CGFloat = 18
        // The hint rides with the page: where it sits on screen is the page's drop
        // plus its resting place above the page's top edge.
        let hintTop = offset + ReaderPullDownBookmarkMotion.hintCenterY(hintHeight: hintHeight)
            - hintHeight / 2
        // Clear of the Dynamic Island, whose bottom edge sits near 48pt.
        #expect(hintTop > 48)
    }

    @Test("a bare page grows its ribbon and a bookmarked page draws it back in, both finishing at the commit point")
    func ribbonRevealFollowsThePull() {
        let commit = ReaderPullDownBookmarkMotion.commitProgress
        let reveal = ReaderPullDownBookmarkMotion.ribbonReveal(progress:wasBookmarked:)
        #expect(reveal(0, false) == 0)
        #expect(abs(reveal(commit / 2, false) - 0.5) < 0.0001)
        #expect(reveal(commit, false) == 1)
        #expect(reveal(1, false) == 1)

        #expect(reveal(0, true) == 1)
        #expect(abs(reveal(commit / 2, true) - 0.5) < 0.0001)
        #expect(reveal(commit, true) == 0)
        #expect(reveal(1, true) == 0)
    }

    @Test("the hint waits just above the page's top edge, off screen at rest, and fades in early")
    func hintPlacement() {
        let y = ReaderPullDownBookmarkMotion.hintCenterY(hintHeight: 20)
        #expect(y + 10 == -ReaderPullDownBookmarkMotion.hintGap)
        #expect(y + 10 <= 0)
        #expect(ReaderPullDownBookmarkMotion.hintAlpha(forProgress: 0) == 0)
        #expect(ReaderPullDownBookmarkMotion.hintAlpha(forProgress: 0.2) == 0.5)
        #expect(ReaderPullDownBookmarkMotion.hintAlpha(forProgress: 0.4) == 1)
    }

    @Test("release commits past the distance threshold")
    func commitByDistance() {
        #expect(ReaderPullDownBookmarkMotion.shouldCommit(
            progress: ReaderPullDownBookmarkMotion.commitProgress, velocityY: 0
        ))
        #expect(!ReaderPullDownBookmarkMotion.shouldCommit(
            progress: ReaderPullDownBookmarkMotion.commitProgress - 0.05, velocityY: 0
        ))
        #expect(ReaderPullDownBookmarkMotion.phase(
            forProgress: ReaderPullDownBookmarkMotion.commitProgress
        ) == .armed)
        #expect(ReaderPullDownBookmarkMotion.phase(forProgress: 0.3) == .pulling)
    }

    @Test("fast downward fling commits early, but a stray flick cannot")
    func commitByVelocity() {
        #expect(ReaderPullDownBookmarkMotion.shouldCommit(
            progress: ReaderPullDownBookmarkMotion.flingMinimumProgress,
            velocityY: ReaderPullDownBookmarkMotion.commitVelocityY
        ))
        #expect(!ReaderPullDownBookmarkMotion.shouldCommit(
            progress: 0.05, velocityY: ReaderPullDownBookmarkMotion.commitVelocityY
        ))
        #expect(!ReaderPullDownBookmarkMotion.shouldCommit(progress: 0.4, velocityY: 200))
    }

    @Test("the hint says add on a bare page and remove on a bookmarked one")
    func hintWording() {
        #expect(ReaderPullDownBookmarkMotion.hintKey(isBookmarked: false, phase: .pulling) == "下拉加入書籤")
        #expect(ReaderPullDownBookmarkMotion.hintKey(isBookmarked: false, phase: .armed) == "放開加入書籤")
        #expect(ReaderPullDownBookmarkMotion.hintKey(isBookmarked: true, phase: .pulling) == "下拉移除書籤")
        #expect(ReaderPullDownBookmarkMotion.hintKey(isBookmarked: true, phase: .armed) == "放開移除書籤")
    }

    @Test("the confirmation says which way the bookmark went")
    func toastWording() {
        let added = ReaderBookmarkToast(isAdded: true)
        let removed = ReaderBookmarkToast(isAdded: false)
        #expect(added.titleKey == "已加入書籤")
        #expect(removed.titleKey == "已移除書籤")
        #expect(UIImage(systemName: added.systemImage) != nil)
        #expect(UIImage(systemName: removed.systemImage) != nil)
        // Two toasts in a row are two presentations, even saying the same thing.
        #expect(ReaderBookmarkToast(isAdded: true).id != ReaderBookmarkToast(isAdded: true).id)
    }

    @Test("every hint and confirmation is localized in every language")
    func wordingIsLocalized() {
        var keys: [String] = []
        for bookmarked in [true, false] {
            for phase in [ReaderPullDownBookmarkMotion.Phase.pulling, .armed] {
                keys.append(ReaderPullDownBookmarkMotion.hintKey(isBookmarked: bookmarked, phase: phase))
            }
            keys.append(ReaderBookmarkToast(isAdded: bookmarked).titleKey)
        }
        for key in keys {
            for language in ["zh-Hant", "zh-Hans", "en", "ja", "ko"] {
                guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                      let bundle = Bundle(path: path) else {
                    Issue.record("missing \(language).lproj")
                    continue
                }
                let value = bundle.localizedString(forKey: key, value: "⚠️", table: nil)
                #expect(value != "⚠️", "\(language) is missing \(key)")
            }
        }
    }
}

@Suite("Page bookmark ribbon")
@MainActor
struct ReaderBookmarkRibbonTests {
    @Test("the ribbon hangs from the page's top edge at its right")
    func ribbonFrame() {
        let page = CGRect(x: 0, y: 0, width: 440, height: 956)
        let frame = ReaderBookmarkRibbon.frame(in: page)
        #expect(frame.minY == page.minY)
        #expect(frame.maxX == page.maxX - ReaderBookmarkRibbon.trailingInset)
        #expect(frame.width == ReaderBookmarkRibbon.width)
        #expect(frame.height == ReaderBookmarkRibbon.length)
        // Follows the page, e.g. the right half of a spread.
        let rightHalf = CGRect(x: 600, y: 0, width: 580, height: 820)
        #expect(ReaderBookmarkRibbon.frame(in: rightHalf).maxX == rightHalf.maxX - ReaderBookmarkRibbon.trailingInset)
    }

    @Test("the strip is cut with a V at its free end")
    func ribbonNotch() {
        let rect = CGRect(x: 0, y: 0, width: 16, height: 40)
        let path = ReaderBookmarkRibbon.path(in: rect)
        #expect(path.contains(CGPoint(x: 2, y: 38)))
        #expect(path.contains(CGPoint(x: 14, y: 38)))
        // The notch's mouth is outside the ribbon.
        #expect(!path.contains(CGPoint(x: 8, y: 39)))
        #expect(path.contains(CGPoint(x: 8, y: 30)))
    }

    @Test("reveal slides the strip out of the page top and fades it in")
    func revealMapping() {
        #expect(ReaderBookmarkRibbon.retraction(forReveal: 0) == ReaderBookmarkRibbon.length)
        #expect(ReaderBookmarkRibbon.retraction(forReveal: 1) == 0)
        #expect(ReaderBookmarkRibbon.retraction(forReveal: 2) == 0)
        #expect(ReaderBookmarkRibbon.alpha(forReveal: 0) == 0)
        #expect(ReaderBookmarkRibbon.alpha(forReveal: 1) == 1)
    }

    @Test("a bookmarked page's bars draw the ribbon for snapshots, and a live page's do not")
    func barsCarryTheRibbonForSnapshotsOnly() {
        let bars = ReaderPageBars(
            header: nil, footer: nil, headerTopOffset: 0, footerBottomOffset: 0, isBookmarked: true
        )
        #expect(!bars.isEmpty)
        #expect(!bars.removingBookmarkRibbon().isBookmarked)

        let page = CGRect(x: 0, y: 0, width: 200, height: 300)
        let ribbon = ReaderBookmarkRibbon.frame(in: page)
        let inside = CGPoint(x: ribbon.midX, y: ribbon.minY + 10)
        #expect(Self.isPainted(bars, page: page, at: inside))
        #expect(!Self.isPainted(bars.removingBookmarkRibbon(), page: page, at: inside))
        // Nothing drawn outside the ribbon's own frame.
        #expect(!Self.isPainted(bars, page: page, at: CGPoint(x: 20, y: 10)))
    }

    /// Draws `bars` onto white, in a top-left-origin context like the page's, and
    /// reports whether anything landed on `point`.
    private static func isPainted(_ bars: ReaderPageBars, page: CGRect, at point: CGPoint) -> Bool {
        let width = Int(page.width), height = Int(page.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let painted = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // UIKit orientation: origin top-left, y down.
            ctx.translateBy(x: 0, y: page.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(page)
            bars.draw(in: page, context: ctx)
            // Row 0 of the buffer is the top row of the page.
            let offset = (Int(point.y) * width + Int(point.x)) * 4
            let rgb = (buffer[offset], buffer[offset + 1], buffer[offset + 2])
            return rgb != (255, 255, 255)
        }
        return painted
    }

    @Test("the live ribbon settles where the gesture left it, whatever the bars said meanwhile")
    func interactiveRibbonOwnsItsState() {
        let ribbon = ReaderBookmarkRibbonView(frame: CGRect(x: 0, y: 0, width: 16, height: 40))
        ribbon.setBookmarked(false, animated: false)
        ribbon.beginInteractive()
        ribbon.setInteractiveReveal(0.7)
        // A clock tick re-handing the old bars mid-pull is recorded, not shown.
        ribbon.setBookmarked(false, animated: true)
        ribbon.endInteractive(isBookmarked: true)
        #expect(ribbon.isBookmarked)
        // The store's bars catching up afterwards change nothing.
        ribbon.setBookmarked(true, animated: true)
        #expect(ribbon.isBookmarked)
    }
}

@Suite("Page bars carry the ribbon")
@MainActor
struct ReaderPageBarsRibbonTests {
    @Test("with both bars switched off, a bookmarked page still gets bars that hang its ribbon")
    func ribbonSurvivesHiddenBars() {
        let controller = ReaderPageBarsController()
        let environment = ReaderPageBarsEnvironment(
            layout: .default, headerEnabled: false, footerEnabled: false, readerTextColor: .black,
            headerHorizontalPadding: 16, footerHorizontalPadding: 16,
            headerTopOffset: 20, footerBottomOffset: 20, bookTitle: "西游记",
            now: Date(timeIntervalSince1970: 0), batteryLevel: 0.7, isCharging: false,
            readingDuration: 60, userInterfaceStyle: .light, displayScale: 1
        )
        var content = ReaderPageBarsPageContent(
            chapterTitle: "第一回", chapterPage: 3, chapterPageCount: 10,
            totalProgress: 0.1, estimatedRemainingTime: nil
        )
        controller.update(environment: environment, svgAssetStore: nil, pageContent: { _ in content })
        #expect(controller.bars(forGlobalPage: 2) == nil)

        content.isBookmarked = true
        controller.update(environment: environment, svgAssetStore: nil, pageContent: { _ in content })
        let bars = controller.bars(forGlobalPage: 2)
        #expect(bars?.isBookmarked == true)
        #expect(bars?.header == nil && bars?.footer == nil)
    }
}

@Suite("One bookmark per page")
struct ReaderPageBookmarkRangeTests {
    private func bookmark(
        spine: Int, offset: Int, kind: Bookmark.Kind = .bookmark
    ) -> Bookmark {
        Bookmark(
            chapterIndex: spine,
            chapterTitle: "第 \(spine + 1) 章",
            position: CoreTextReadingPosition(spineIndex: spine, charOffset: offset),
            length: kind == .bookmark ? 0 : 4,
            kind: kind
        )
    }

    @Test("the page owns its own half-open char range")
    func rangeContainment() {
        let range = ReaderPageBookmarkRange(spineIndex: 2, startOffset: 400, endOffset: 800)
        #expect(range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 400)))
        #expect(range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 799)))
        // The next page's first character belongs to the next page.
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 800)))
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 399)))
        // Another chapter is never this page.
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 3, charOffset: 400)))
    }

    @Test("an open-ended range runs to the end of its chapter")
    func openEndedRange() {
        let range = ReaderPageBookmarkRange(spineIndex: 1, startOffset: 1200)
        #expect(range.contains(CoreTextReadingPosition(spineIndex: 1, charOffset: 1200)))
        #expect(range.contains(CoreTextReadingPosition(spineIndex: 1, charOffset: 999_999)))
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 1, charOffset: 1199)))
        #expect(!range.contains(CoreTextReadingPosition(spineIndex: 2, charOffset: 1200)))
    }

    @Test("a re-laid-out page still finds the bookmark that drifted off its first character")
    func survivesRepagination() {
        // Saved at the old page start; a larger font pushed that character into
        // the middle of the page. Equality would miss it and duplicate the bookmark.
        let saved = bookmark(spine: 4, offset: 620)
        let afterFontChange = ReaderPageBookmarkRange(spineIndex: 4, startOffset: 540, endOffset: 900)
        #expect(afterFontChange.pageBookmarks(in: [saved]).map(\.id) == [saved.id])
    }

    @Test("highlights and underlines on the page are not page bookmarks")
    func annotationsAreNotBookmarks() {
        let page = ReaderPageBookmarkRange(spineIndex: 0, startOffset: 0, endOffset: 500)
        let items = [
            bookmark(spine: 0, offset: 10, kind: .underline),
            bookmark(spine: 0, offset: 20, kind: .highlight),
            bookmark(spine: 0, offset: 30),
        ]
        #expect(page.pageBookmarks(in: items).map(\.position.charOffset) == [30])
    }

    @Test("the page's bookmark is written at the page's first character")
    func bookmarkPositionIsPageStart() {
        let range = ReaderPageBookmarkRange(spineIndex: 7, startOffset: 1024, endOffset: 1400)
        #expect(range.bookmarkPosition == CoreTextReadingPosition(spineIndex: 7, charOffset: 1024))
    }

    @Test("legacy chapter-start bookmarks land on the chapter's first page")
    func legacyChapterStartBookmarksBelongToPageOne() {
        let legacy = Bookmark(
            chapterIndex: 5, chapterTitle: "第六章", position: .chapterStart(5)
        )
        let firstPage = ReaderPageBookmarkRange(spineIndex: 5, startOffset: 0, endOffset: 600)
        let secondPage = ReaderPageBookmarkRange(spineIndex: 5, startOffset: 600, endOffset: 1200)
        #expect(firstPage.pageBookmarks(in: [legacy]).count == 1)
        #expect(secondPage.pageBookmarks(in: [legacy]).isEmpty)
    }
}

@Suite("Bookmark chapter grouping")
struct ReaderBookmarkChapterGroupTests {
    private func bookmark(spine: Int, offset: Int) -> Bookmark {
        Bookmark(
            chapterIndex: spine,
            chapterTitle: "第 \(spine + 1) 章",
            position: CoreTextReadingPosition(spineIndex: spine, charOffset: offset)
        )
    }

    @Test("same-chapter bookmarks sit together, in reading order")
    func groupsFollowReadingOrder() {
        let groups = ReaderBookmarkChapterGroup.group([
            bookmark(spine: 3, offset: 200),
            bookmark(spine: 1, offset: 900),
            bookmark(spine: 3, offset: 0),
            bookmark(spine: 1, offset: 100),
            bookmark(spine: 3, offset: 1400),
        ])

        #expect(groups.map(\.chapterIndex) == [1, 3])
        #expect(groups[0].items.map(\.position.charOffset) == [100, 900])
        #expect(groups[1].items.map(\.position.charOffset) == [0, 200, 1400])
    }

    @Test("no bookmarks means no groups")
    func emptyInput() {
        #expect(ReaderBookmarkChapterGroup.group([]).isEmpty)
    }

    @Test("every bookmark lands in exactly one group")
    func groupingIsAPartition() {
        let items = (0..<12).map { bookmark(spine: $0 % 4, offset: $0 * 37) }
        let groups = ReaderBookmarkChapterGroup.group(items)
        #expect(groups.flatMap(\.items).count == items.count)
        #expect(Set(groups.flatMap(\.items).map(\.id)) == Set(items.map(\.id)))
        for group in groups {
            #expect(group.items.allSatisfy { $0.chapterIndex == group.chapterIndex })
        }
    }
}

@Suite("Bookmark card excerpt")
struct ReaderBookmarkExcerptTests {
    @Test("the chapter name the card already shows is dropped from the excerpt")
    func dropsRepeatedChapterTitle() {
        // 章首那一頁的排版文字就是「章名＋內文」。
        let excerpt = "第一回　灵根育孕源流出 心性修持大道生诗曰：盖闻天地之数"
        let title = "第一回 灵根育孕源流出 心性修持大道生"
        #expect(ReaderBookmarkExcerpt.body(of: excerpt, chapterTitle: title) == "诗曰：盖闻天地之数")
    }

    @Test("whitespace differences between the laid-out title and the TOC title do not matter")
    func ignoresWhitespaceShape() {
        #expect(ReaderBookmarkExcerpt.body(
            of: "第 三 章\n\n正文開始", chapterTitle: "第三章"
        ) == "正文開始")
        #expect(ReaderBookmarkExcerpt.body(
            of: "第三章正文開始", chapterTitle: "第 三 章"
        ) == "正文開始")
    }

    @Test("a mid-chapter page keeps its excerpt untouched")
    func keepsUnrelatedExcerpt() {
        let excerpt = "牛贺洲，曰南赡部洲，曰北俱芦洲。"
        #expect(ReaderBookmarkExcerpt.body(of: excerpt, chapterTitle: "第一回 灵根育孕源流出") == excerpt)
    }

    @Test("a partial match is not a prefix and is left alone")
    func partialTitleIsNotStripped() {
        // 摘錄比章名短：章名還沒比完就沒字了，不能當作命中。
        #expect(ReaderBookmarkExcerpt.body(of: "第一回", chapterTitle: "第一回 灵根育孕源流出") == "第一回")
    }

    @Test("a page that is nothing but the chapter name keeps it")
    func titleOnlyPageKeepsTheTitle() {
        #expect(ReaderBookmarkExcerpt.body(
            of: "第一回　灵根育孕源流出", chapterTitle: "第一回 灵根育孕源流出"
        ) == "第一回　灵根育孕源流出")
    }

    @Test("an empty title or excerpt is handled without trimming anything away")
    func emptyInputs() {
        #expect(ReaderBookmarkExcerpt.body(of: "正文", chapterTitle: "") == "正文")
        #expect(ReaderBookmarkExcerpt.body(of: "  ", chapterTitle: "第一回") == "")
    }
}
