import SwiftUI

// MARK: - Book detail building blocks
//
// The online-book and audiobook detail pages are laid out as Apple Books lays out a
// book and Apple Podcasts a show: the artwork large and centred over a wash of
// itself, the title and author under it, the primary action directly beneath, then
// an information strip, the description, and the chapter list. Both pages compose
// these pieces; neither draws its own copy.

/// One action button on a detail page.
struct BookDetailAction {
    var title: String
    var systemImage: String
    var isBusy = false
    var isEnabled = true
    var action: () -> Void
}

// MARK: - Page scaffold

/// Scroll container, background and navigation chrome shared by the detail pages.
///
/// When the hero's actions scroll under the navigation bar, the book's title fades
/// into the bar and the primary action follows it as a compact button — the App
/// Store and Apple Books pattern — so the primary action is never more than one tap
/// away without a bar permanently covering the chapter list.
struct BookDetailScaffold<Hero: View, Content: View>: View {
    let title: String
    let compactAction: BookDetailAction
    var onRefresh: (() async -> Void)?
    @ViewBuilder var hero: Hero
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bottom edge of the hero, in global coordinates.
    @State private var heroBottom = CGFloat.greatestFiniteMagnitude
    /// Top edge of the visible scroll area (below the navigation bar), in global coordinates.
    @State private var visibleTop: CGFloat = 0

    private var heroScrolledAway: Bool { heroBottom < visibleTop }

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.xl) {
                hero
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .global).maxY
                    } action: { heroBottom = $0 }
                content
            }
            .padding(.bottom, DSSpacing.xxl)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY + proxy.safeAreaInsets.top
        } action: { visibleTop = $0 }
        .modifier(BookDetailRefreshModifier(onRefresh: onRefresh))
        // iOS 26's soft top edge fades whatever scrolls under the navigation bar into
        // the page background — it turned the cover wash under the bar into a flat
        // band. The cover shows through while it is on screen; once it has scrolled
        // away the edge effect returns to keep the bar's title and button legible.
        .softScrollEdges(hidingTop: !heroScrolledAway)
        .scrollIndicators(.hidden)
        .background(PageBackgroundView(scope: .global).ignoresSafeArea())
        .pageBackgroundToolbar(for: .global)
        .toolbarTitleDisplayMode(.inline)
        .hidesRootTabBar()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                    .opacity(heroScrolledAway ? 1 : 0)
                    .accessibilityHidden(!heroScrolledAway)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if heroScrolledAway {
                    Button(action: compactAction.action) {
                        Text(compactAction.title)
                            .font(DSFont.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(DSColor.accent)
                    .disabled(!compactAction.isEnabled || compactAction.isBusy)
                    .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.fast, value: heroScrolledAway)
    }
}

private struct BookDetailRefreshModifier: ViewModifier {
    let onRefresh: (() async -> Void)?

    func body(content: Content) -> some View {
        if let onRefresh {
            content.refreshable { await onRefresh() }
        } else {
            content
        }
    }
}

// MARK: - Hero

/// Artwork, title, author and the two actions at the top of a detail page.
struct BookDetailHero<Cover: View>: View {
    enum ArtworkShape {
        /// A book jacket, 2:3 like the shelf grid.
        case book
        /// Square audiobook artwork, as Podcasts shows a show.
        case square
    }

    let artworkShape: ArtworkShape
    let cover: Cover
    let title: String
    let author: String
    let meta: String
    let primary: BookDetailAction
    let secondary: BookDetailAction

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var artworkSize: CGSize {
        switch artworkShape {
        case .book:
            // 左右版式：封面收窄到 2:3 的 116×174，给书名与标签留出阅读宽度。
            CGSize(width: 116, height: 174)
        case .square:
            CGSize(width: 150, height: 150)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            // 封面在左、信息在右的落地版式（App Store 风格），取代旧的居中纵排。
            HStack(alignment: .top, spacing: DSSpacing.lg) {
                artwork
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text(title)
                        .font(DSFont.serifSectionTitle.weight(.bold))
                        .foregroundStyle(DSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Label(author, systemImage: "person.crop.circle")
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                    if !meta.isEmpty {
                        // 分类标签收拢为强调色小胶囊，最多三个，避免长串文字。
                        HStack(spacing: DSSpacing.xs) {
                            ForEach(Array(meta.components(separatedBy: " · ").prefix(3).enumerated()), id: \.offset) { _, tag in
                                Text(tag)
                                    .font(DSFont.caption2.weight(.medium))
                                    .foregroundStyle(DSColor.appAccent)
                                    .padding(.horizontal, DSSpacing.sm)
                                    .padding(.vertical, 3)
                                    .background(DSColor.appAccentSoft, in: Capsule())
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) { backdrop }
    }

    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
        return cover
            .frame(width: artworkSize.width, height: artworkSize.height)
            .clipShape(shape)
            .overlay(shape.stroke(DSColor.separator, lineWidth: 0.5))
            .shadow(
                color: DSColor.coverHeroShadow,
                radius: DSLayout.bookCoverHeroShadowRadius,
                y: DSLayout.bookCoverHeroShadowOffsetY
            )
            // The title below names the book; the artwork would only repeat it.
            .accessibilityHidden(true)
    }

    /// Side by side as Apple Books shows them; stacked once the text size no longer
    /// leaves room for both labels on one line.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DSSpacing.md) {
                primaryButton
                secondaryButton
            }
            VStack(spacing: DSSpacing.sm) {
                primaryButton
                secondaryButton
            }
        }
    }

    private var primaryButton: some View {
        Button(action: primary.action) {
            BookDetailActionLabel(action: primary, progressTint: DSColor.textOnAccent)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(DSColor.accent)
        .disabled(!primary.isEnabled || primary.isBusy)
    }

    private var secondaryButton: some View {
        Button(action: secondary.action) {
            BookDetailActionLabel(action: secondary, progressTint: DSColor.textPrimary)
        }
        // Neutral, so the accent belongs to the one primary action beside it.
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(DSColor.textPrimary)
        .disabled(!secondary.isEnabled || secondary.isBusy)
    }

    /// The artwork blurred into a wash behind the hero, as Apple Books does. It runs
    /// up past the hero's own top edge, under the navigation and status bars, so the
    /// bars float over the wash instead of the page background showing through them
    /// as a band. Purely decorative; Reduce Transparency drops it and the page
    /// background shows instead.
    @ViewBuilder
    private var backdrop: some View {
        if !reduceTransparency {
            GeometryReader { proxy in
                let extensionHeight = DSLayout.bookDetailBackdropTopExtension
                cover
                    .frame(width: proxy.size.width, height: proxy.size.height + extensionHeight)
                    .blur(radius: DSLayout.bookCoverHeroBackdropBlur, opaque: true)
                    .clipped()
                    .saturation(DSLayout.bookCoverHeroBackdropSaturation)
                    .opacity(DSLayout.bookCoverHeroBackdropOpacity)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.55),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .offset(y: -extensionHeight)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct BookDetailActionLabel: View {
    let action: BookDetailAction
    let progressTint: Color

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            if action.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(progressTint)
            } else {
                Image(systemName: action.systemImage)
                    .accessibilityHidden(true)
            }
            Text(action.title)
                .lineLimit(1)
        }
        .font(DSFont.body.weight(.semibold))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Information strip

/// One column of the information strip.
struct BookDetailInfoItem: Identifiable {
    let id: String
    let label: String
    let value: String
    /// A second line under the value. Shown in the accent colour when the item acts.
    var detail: String?
    var action: (() -> Void)?
    var accessibilityHint: String?
    var accessibilityInputLabels: [String] = []

    /// The current source, opening 換源. 來源 is what the item is, the source name its
    /// value, switching what activating it does; the visible 「換源」 stays reachable
    /// to Voice Control through the input labels.
    static func source(name: String, action: @escaping () -> Void) -> BookDetailInfoItem {
        BookDetailInfoItem(
            id: "source",
            label: localized("來源"),
            value: name,
            detail: localized("換源"),
            action: action,
            accessibilityHint: localized("點兩下切換書源"),
            accessibilityInputLabels: [localized("換源")]
        )
    }
}

/// Apple Books' strip of short facts under the hero, redrawn as one surface card:
/// equal columns separated by hairlines, scrolling sideways only once the text size
/// no longer fits them.
struct BookDetailInfoStrip: View {
    let items: [BookDetailInfoItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(equalWidths: true)
            ScrollView(.horizontal) {
                row(equalWidths: false)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, DSSpacing.sm)
        .padding(.horizontal, DSSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
        .padding(.horizontal, DSSpacing.lg)
    }

    private func row(equalWidths: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .frame(maxHeight: 34)
                }
                cell(item)
                    .frame(maxWidth: equalWidths ? .infinity : nil)
                    .padding(.horizontal, DSSpacing.sm)
            }
        }
        .fixedSize(horizontal: !equalWidths, vertical: true)
    }

    @ViewBuilder
    private func cell(_ item: BookDetailInfoItem) -> some View {
        if let action = item.action {
            Button(action: action) {
                cellContent(item)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.label)
            .accessibilityValue(item.value)
            .accessibilityHint(item.accessibilityHint ?? "")
            .accessibilityInputLabels(item.accessibilityInputLabels + [item.label])
            .accessibilityAddTraits(.isButton)
        } else {
            cellContent(item)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.label)
                .accessibilityValue(item.value)
        }
    }

    private func cellContent(_ item: BookDetailInfoItem) -> some View {
        VStack(spacing: DSSpacing.xs) {
            Text(item.label)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
            Text(item.value)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
            if let detail = item.detail {
                HStack(spacing: DSSpacing.xs) {
                    Text(detail)
                    if item.action != nil {
                        Image(systemName: "chevron.right")
                            .font(DSFont.caption2.weight(.semibold))
                    }
                }
                .font(DSFont.caption)
                .foregroundStyle(item.action == nil ? DSColor.textSecondary : DSColor.accent)
                .lineLimit(1)
            }
        }
        .frame(minHeight: DSLayout.minimumTapTarget)
    }
}

// MARK: - Section header

/// A section title in Apple's store style, with an optional trailing 「查看全部」.
/// 书悦式侧标：标题左缘一条品牌色圆头短竖条，与书架列表行的书卷饰条同源。
struct BookDetailSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DSFont.title3.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(DSColor.appAccent)
                        .frame(width: 4, height: 16)
                        .offset(x: -8)
                }
            Spacer(minLength: DSSpacing.sm)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: DSSpacing.xs) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(DSFont.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.accent)
                    .frame(minHeight: DSLayout.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Description

/// The description, clamped to four lines with Apple's trailing 「更多」.
///
/// Plain intros arrive cleaned by Legado's formatter; `<usehtml>`, `<md>` and
/// `<useweb>` intros keep their markup and render as HTML, Markdown or a web page
/// (`BookIntroContent`). Whether plain text overflows is estimated from its length and
/// line breaks rather than measured: measuring means laying out the full text a second
/// time at its intrinsic height, which `Technotes/iOS17SearchWatchdogPostmortem.md`
/// (guardrail 6) rules out for source-controlled text inside this scroll view on iOS 17.
struct BookDetailIntroSection: View {
    let text: String
    @Binding var isExpanded: Bool
    /// Base for relative links and images in a rich intro (the book's detail URL).
    var baseURL: String?
    /// Runs a `<usehtml>` intro's button or image script.
    var onAction: ((BookIntroAction) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var webContentHeight: CGFloat = 0
    /// Parsed once per intro, never in `body` (guardrail 5).
    @State private var markdown: AttributedString?
    @ScaledMetric(relativeTo: .subheadline) private var collapsedRichHeight: CGFloat = 88

    private static let collapsedLineLimit = 4
    /// Roughly four lines of CJK body text at the default text size on a phone.
    private static let collapsedCharacterEstimate = 80

    private var content: BookIntroContent { BookIntroContent(text) }

    private var mayOverflow: Bool {
        switch content {
        case .plain(let plain), .markdown(let plain):
            plain.count > Self.collapsedCharacterEstimate
                || plain.reduce(0) { $1.isNewline ? $0 + 1 : $0 } >= Self.collapsedLineLimit
        case .html, .web:
            webContentHeight > collapsedRichHeight
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            BookDetailSectionHeader(title: localized("簡介"))
            introBody
                .padding(DSSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BookDetailCardStyle.background)
                .overlay(BookDetailCardStyle.border)
            if mayOverflow {
                Button {
                    withAnimation(reduceMotion ? nil : DSAnimation.standard) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? localized("收合") : localized("更多"))
                        .font(DSFont.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.accent)
                        .frame(minHeight: DSLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .task(id: text) { parseMarkdownIfNeeded() }
    }

    @ViewBuilder
    private var introBody: some View {
        switch content {
        case .plain(let plain):
            Text(plain)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
        case .markdown(let source):
            Text(markdown ?? AttributedString(source))
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
        case .html(let markup):
            richBody(markup, mode: .fragment)
        case .web(let markup):
            richBody(markup, mode: .page)
        }
    }

    private func richBody(_ markup: String, mode: BookIntroWebView.Mode) -> some View {
        BookIntroWebView(
            markup: markup,
            mode: mode,
            baseURL: baseURL.flatMap(URL.init(string:)),
            contentHeight: $webContentHeight,
            onAction: onAction
        )
        .frame(height: isExpanded
            ? max(webContentHeight, 1)
            : min(max(webContentHeight, 1), collapsedRichHeight))
        .clipped()
    }

    /// `<md>` intros: inline Markdown (emphasis, links, code) with the source's line
    /// breaks kept. SwiftUI's `Text` draws no block elements, so headings and lists
    /// read as their text.
    private func parseMarkdownIfNeeded() {
        guard case .markdown(let source) = content else {
            markdown = nil
            return
        }
        do {
            markdown = try AttributedString(
                markdown: source,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            AppLogger.parse("⟐ <md> intro is not valid Markdown", error: error)
            markdown = AttributedString(source)
        }
    }
}

// MARK: - Chapters

/// Shared card chrome for the chapter lists, matching the card containers the rest
/// of the app's 书悦-style screens use (`DSColor.surface` fill, soft shadow, hairline
/// separator border). Keeping it in one place lets the detail preview and the full
/// chapter list stay in lockstep.
enum BookDetailCardStyle {
    static var background: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            .fill(DSColor.surface)
            .shadow(color: DSColor.shadow, radius: 3, x: 0, y: 1)
    }

    static var border: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            .stroke(DSColor.separator.opacity(0.5), lineWidth: 0.5)
    }

    static var divider: some View {
        Divider()
            .padding(.leading, DSSpacing.md)
    }
}

/// One chapter row, used both in the detail preview and in the full chapter list.
struct BookDetailChapterRow: View {
    enum Trailing {
        /// Opens the reader at the chapter.
        case disclosure
        /// Plays the chapter, as an episode row in Podcasts.
        case play
    }

    let title: String
    var caption: String?
    let isLocked: Bool
    let trailing: Trailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.md) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    if let caption {
                        Text(caption)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    Text(title)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: DSSpacing.sm)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.warning)
                        .accessibilityHidden(true)
                }
                switch trailing {
                case .disclosure:
                    Image(systemName: "chevron.right")
                        .font(DSFont.caption.weight(.semibold))
                        .foregroundStyle(DSColor.textTertiary)
                        .accessibilityHidden(true)
                case .play:
                    Image(systemName: "play.circle")
                        .font(DSFont.title3)
                        .foregroundStyle(DSColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, DSSpacing.md)
            .frame(minHeight: DSLayout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isLocked ? localized("付費章節") : "")
    }
}

/// The chapter section, redrawn as a chapter launcher: the newest chapter as a
/// highlighted banner, the first chapters as a two-column grid of numbered chips,
/// and a full-width 「查看全部目录」 card that names the total. Loading, error and
/// empty states stand in place of the grid.
struct BookDetailChapterSection: View {
    let title: String
    let chapters: [OnlineChapterRef]
    let isLoading: Bool
    let errorMessage: String?
    let latestChapter: String
    let onRetry: () -> Void
    /// Opens the chapter at its offset in `chapters`.
    let onSelect: (_ offset: Int) -> Void
    let onShowAll: () -> Void

    /// Six chips fill the two-column grid with three rows; the rest is one tap
    /// away through the 「查看全部目录」 card.
    static var previewLimit: Int { 6 }

    private static let columns = [
        GridItem(.flexible(), spacing: DSSpacing.sm),
        GridItem(.flexible(), spacing: DSSpacing.sm),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            BookDetailSectionHeader(title: title)
            if !latestChapter.isEmpty, !isLoading || !chapters.isEmpty {
                latestBanner
            }
            content
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    /// The newest chapter, pulled out of the grid into an accent-tinted banner so
    /// serial readers can see the update at a glance.
    private var latestBanner: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.appAccent)
                .frame(width: 28, height: 28)
                .background(DSColor.appAccentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("最新章節"))
                    .font(DSFont.caption2.weight(.semibold))
                    .foregroundStyle(DSColor.appAccent)
                Text(latestChapter)
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(
            DSColor.appAccentSoft.opacity(0.55),
            in: RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                .stroke(DSColor.appAccent.opacity(0.18), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && chapters.isEmpty {
            ProgressView(localized("載入目錄…"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.xl)
        } else if let errorMessage, chapters.isEmpty {
            VStack(spacing: DSSpacing.sm) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button(localized("重試"), action: onRetry)
                    .buttonStyle(.bordered)
                    .tint(DSColor.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.lg)
        } else if chapters.isEmpty {
            Text(localized("目錄為空"))
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.lg)
        } else {
            VStack(spacing: DSSpacing.sm) {
                chipGrid
                showAllCard
            }
        }
    }

    private var chipGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: DSSpacing.sm) {
            ForEach(
                Array(chapters.prefix(Self.previewLimit).enumerated()),
                id: \.element.id
            ) { offset, chapter in
                Button {
                    onSelect(offset)
                } label: {
                    chip(offset, chapter)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One numbered chapter chip: a serif index badge, the title, and a lock when
    /// the chapter is paid. Whole chip is the tap target.
    private func chip(_ offset: Int, _ chapter: OnlineChapterRef) -> some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
        return HStack(spacing: DSSpacing.xs) {
            Text("\(offset + 1)")
                .font(DSFont.fixed(size: 13, weight: .bold, design: .serif))
                .foregroundStyle(DSColor.appAccent)
                .frame(width: 30, height: 30)
                .background(DSColor.appAccentSoft, in: shape)
            Text(BookDetailChapterTitle.display(chapter, offset: offset))
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if chapter.isVip || chapter.isPay {
                Image(systemName: "lock.fill")
                    .font(DSFont.caption2)
                    .foregroundStyle(DSColor.warning)
                    .accessibilityHidden(true)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: DSLayout.minimumTapTarget - 14)
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
        .contentShape(Rectangle())
    }

    /// The full-list entry: brand-iconed, names the total, one row, always reachable.
    private var showAllCard: some View {
        Button(action: onShowAll) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "list.bullet.rectangle")
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textOnAccent)
                    .frame(width: 30, height: 30)
                    .background(DSColor.appAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(localized("查看全部目录"))
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 0)
                Text(String(format: localized("共 %d 章"), chapters.count))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Image(systemName: "chevron.right")
                    .font(DSFont.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .frame(minHeight: DSLayout.minimumTapTarget)
            .background(BookDetailCardStyle.background)
            .overlay(BookDetailCardStyle.border)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The full chapter list, presented from 「查看全部」.
struct BookDetailChapterListSheet: View {
    let chapters: [OnlineChapterRef]
    let trailing: BookDetailChapterRow.Trailing
    /// Called with the chapter's offset in `chapters`.
    let onSelect: (_ offset: Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.md) {
                Text(String(format: localized("共 %d 章"), chapters.count))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.top, DSSpacing.sm)
                VStack(spacing: 0) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { offset, chapter in
                        BookDetailChapterRow(
                            title: BookDetailChapterTitle.display(chapter, offset: offset),
                            isLocked: chapter.isVip || chapter.isPay,
                            trailing: trailing,
                            action: { onSelect(offset) }
                        )
                        if offset < chapters.count - 1 { BookDetailCardStyle.divider }
                    }
                }
                .background(BookDetailCardStyle.background)
                .overlay(BookDetailCardStyle.border)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(PageBackgroundView(scope: .global).ignoresSafeArea())
        .pageBackgroundToolbar(for: .global)
        .navigationTitle(localized("目錄"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label(localized("關閉"), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }
        }
    }
}

enum BookDetailChapterTitle {
    /// A chapter's title, or 「第 N 章」 for a source that leaves it empty.
    static func display(_ chapter: OnlineChapterRef, offset: Int) -> String {
        let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(format: localized("第 %d 章"), offset + 1) : title
    }
}

// MARK: - Remove-from-shelf confirmation

extension View {
    /// Removing a book also deletes its reading record, so it asks first, as Apple
    /// Books asks before removing a book from the library.
    func removeFromShelfConfirmation(
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            localized("要把這本書移出書架嗎？"),
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button(localized("移除書架"), role: .destructive, action: onConfirm)
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("這本書的閱讀進度和快取會一起刪除。"))
        }
    }
}

#Preview("詳情頁元件") {
    NavigationStack {
        BookDetailScaffold(
            title: "斗羅大陸",
            compactAction: BookDetailAction(title: "立即閱讀", systemImage: "book.fill", action: {})
        ) {
            BookDetailHero(
                artworkShape: .book,
                cover: BookCoverImage(coverURL: "", title: "斗羅大陸", author: "唐家三少"),
                title: "斗羅大陸",
                author: "唐家三少",
                meta: "玄幻 · 東方玄幻 · 熱血",
                primary: BookDetailAction(title: "立即閱讀", systemImage: "book.fill", action: {}),
                secondary: BookDetailAction(title: "加入書架", systemImage: "plus", action: {})
            )
        } content: {
            BookDetailInfoStrip(items: [
                BookDetailInfoItem(id: "wordCount", label: "字數", value: "298萬字"),
                BookDetailInfoItem(id: "chapters", label: "章節", value: "1,450"),
                .source(name: "示範書源") {},
            ])
            BookDetailIntroSection(
                text: "唐門外門弟子唐三，因偷學內門絕學為唐門所不容，跳崖明志卻來到了另一個世界——斗羅大陸。這裡沒有魔法，沒有鬥氣，沒有武術，卻有神奇的武魂。",
                isExpanded: .constant(false)
            )
        }
    }
}
