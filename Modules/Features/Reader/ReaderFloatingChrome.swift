import SwiftUI

/// L6「极简悬浮控制」：阅读器唯一的 chrome，取代 classic / modern / Apple Books
/// 三套切换。
///
/// 点屏幕中央呼出两个悬浮控制岛（双岛浮层语言）：
/// - 顶部控制岛：返回圆形浮钮（左）、标题长条胶囊（中，书签/搜索小圆钮收进两端）、
///   更多圆形浮钮（右）。
/// - 底部控制岛：一块整体悬浮玻璃岛（大圆角、细描边、明显投影、距屏幕边缘留白），
///   上段是章节进度区（章节名 + 百分比置于滑轨上方两端，上一章/下一章箭头内嵌滑轨
///   同行两端），下段是四个带填充态的方形按钮——目录 / 听书 / 深色 / 设置。
///
/// 颜色统一经材质与 DS 语义色解析，深浅色自适应：外觀 → 閱讀界面 → 自定義 里对 classic
/// 的覆盖继续生效；阅读器的界面三选一只影响设置页的预览，不再改变实际 chrome。
struct ReaderFloatingChrome: View {
    /// The built-in background the reader sits on: what the bar's colours are read from.
    let readerTheme: ReaderTheme
    /// 顶部控制岛的章节名（已按阅读器的繁简转换处理）。
    let chapterTitle: String
    let isBookmarked: Bool
    let overlayContentMaxWidth: CGFloat
    let canGoPrevChapter: Bool
    let canGoNextChapter: Bool
    /// 底部页码反馈「第 x 章 · 已完成 xx%」。
    let pageStatusText: String
    let chapterSliderProgressValue: () -> Double
    let applyChapterSliderProgress: (Double) -> Void
    let chapterTitleForProgress: (Double) -> String
    let onBack: () -> Void
    let onOpenSearch: () -> Void
    let onToggleBookmark: () -> Void
    /// 「更多」菜单的书级操作（刷新／換源／下載／開啟網頁／AI 助手／AI 翻譯）。
    let menuActions: [ReaderSecondaryAction]
    /// 書籍詳情，更多菜单最后一行——在线书才有。
    let onOpenBookDetail: (() -> Void)?
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void
    let onOpenTOC: () -> Void
    let onOpenSettings: () -> Void
    let onOpenTTS: () -> Void
    /// 深色／白天：阅读器切换自己的深色模式，背景跟着变。
    let onToggleDarkMode: () -> Void

    @ObservedObject private var settings = GlobalSettings.shared

    /// iOS 17 only：「更多」的每行都开 sheet，而 sheet 在另一个 sheet/popover 收起
    /// 期间请求会被系统丢掉——菜单改为 chooser sheet，选择在它真正收起后执行
    /// （Technotes/iOS17MenuModalPresentation.md）。
    @State private var showsLegacyMenu = false
    @State private var legacyMenuSequence = DismissalSequencedPresentation<MenuRoute>()

    private enum MenuRoute: Hashable {
        case action(ReaderSecondaryAction.ID)
        case bookDetail
    }

    @State private var chapterSliderDraft: Double? = nil

    /// The reader's own dark mode, which 深色／白天 switches — not whether the background
    /// it sits on is 黑色, which a dark saved background does in light mode too.
    private var isDarkMode: Bool { settings.readerDarkMode }

    private var sliderProgress: Double {
        chapterSliderDraft ?? chapterSliderProgressValue()
    }

    private var progressPercentText: String {
        String(format: "%.0f%%", sliderProgress * 100)
    }

    private var showsMoreMenu: Bool {
        !menuActions.isEmpty || onOpenBookDetail != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
    }

    // MARK: - 顶部控制岛（双岛：左圆钮 / 中标题胶囊 / 右圆钮）

    private var topBar: some View {
        HStack(spacing: 12) {
            // 左：返回圆形浮钮
            Button(action: onBack) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(DSColor.separator.opacity(0.5), lineWidth: 0.5))
                        .shadow(color: DSColor.coverHeroShadow.opacity(0.3), radius: 10, y: 5)
                    Image(systemName: "chevron.left")
                        .font(DSFont.fixed(size: 17, weight: .medium))
                        .foregroundStyle(DSColor.textPrimary)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reader_back_button")
            .accessibilityLabel(localized("退出阅读"))

            // 中：标题胶囊，书签/搜索收进两端
            HStack(spacing: 6) {
                bookmarkMicroButton
                Text(chapterTitle)
                    .font(DSFont.fixed(size: 15, weight: .medium))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                searchMicroButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(DSColor.separator.opacity(0.5), lineWidth: 0.5))
                    .shadow(color: DSColor.coverHeroShadow.opacity(0.3), radius: 12, y: 6)
            )
            .accessibilityElement(children: .contain)

            // 右：更多圆形浮钮
            if showsMoreMenu {
                moreMenu
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: overlayContentMaxWidth)
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.md)
    }

    private var bookmarkMicroButton: some View {
        Button {
            onToggleBookmark()
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(DSFont.fixed(size: 13, weight: .medium))
                .foregroundStyle(isBookmarked ? DSColor.appAccent : DSColor.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().stroke(DSColor.separator.opacity(0.4), lineWidth: 0.5))
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .animation(DSAnimation.fast, value: isBookmarked)
        .accessibilityLabel(localized("书签"))
        .accessibilityValue(localized(isBookmarked ? "已加入" : "未加入"))
    }

    private var searchMicroButton: some View {
        Button {
            onOpenSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(DSFont.fixed(size: 13, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().stroke(DSColor.separator.opacity(0.4), lineWidth: 0.5))
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("Search Book"))
    }

    // MARK: - 底部控制岛（单块玻璃岛：进度区 + 四方形按钮）

    private var bottomBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: DSSpacing.md) {
                progressSection
                Divider().opacity(0.15)
                toolGrid
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: overlayContentMaxWidth)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                    .stroke(DSColor.separator.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: DSColor.coverHeroShadow.opacity(0.35), radius: 20, y: 10)
            .overlay(alignment: .top) {
                if chapterSliderDraft != nil {
                    scrubPreview
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.md)
            .tint(DSColor.appAccent)
            .animation(DSAnimation.fast, value: chapterSliderDraft == nil)
        }
    }

    private var progressSection: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(chapterTitle)
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(pageStatusText)
                    .font(DSFont.footnote.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }

            HStack(spacing: DSSpacing.sm) {
                chapterArrow(forward: false) { onPrevChapter() }
                Slider(
                    value: Binding<Double>(
                        get: { sliderProgress },
                        set: { chapterSliderDraft = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if editing {
                            chapterSliderDraft = chapterSliderProgressValue()
                        } else if let draft = chapterSliderDraft {
                            applyChapterSliderProgress(draft)
                            chapterSliderDraft = nil
                        }
                    }
                )
                .tint(DSColor.appAccent)
                .accessibilityLabel(localized("阅读进度"))
                .accessibilityValue(progressPercentText)
                chapterArrow(forward: true) { onNextChapter() }
            }
        }
    }

    private func chapterArrow(forward: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(DSFont.fixed(size: 15, weight: .medium))
                .foregroundStyle(
                    forward
                        ? (canGoNextChapter ? DSColor.textPrimary : DSColor.textSecondary)
                        : (canGoPrevChapter ? DSColor.textPrimary : DSColor.textSecondary)
                )
                .frame(width: 30, height: 30)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().stroke(DSColor.separator.opacity(0.3), lineWidth: 0.5))
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .disabled(forward ? !canGoNextChapter : !canGoPrevChapter)
        .accessibilityLabel(localized(forward ? (canGoNextChapter ? "下一章" : "书末页") : "上一章"))
    }

    /// The fixed four: 目录／听书／深色／设置. 书签 lives in the top island, so it is not
    /// repeated here; 更多菜单里的刷新/换源/下载仍按 自定義 的可见性过滤。
    private var toolGrid: some View {
        HStack(spacing: 0) {
            squareToolButton(id: "tableOfContents", systemImage: "list.bullet", label: localized("目录")) { onOpenTOC() }
            Spacer()
            squareToolButton(id: "playback", systemImage: "headphones", label: localized("听书")) { onOpenTTS() }
            Spacer()
            squareToolButton(
                id: "nightMode",
                systemImage: isDarkMode ? "sun.max.fill" : "moon.fill",
                label: localized(isDarkMode ? "白天" : "深色"),
                active: isDarkMode
            ) { onToggleDarkMode() }
            Spacer()
            squareToolButton(id: "settings", systemImage: "gearshape", label: localized("设置")) { onOpenSettings() }
        }
    }

    private func squareToolButton(
        id: String,
        systemImage: String,
        label: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(DSFont.fixed(size: 20, weight: .medium))
                Text(label)
                    .font(DSFont.fixed(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? DSColor.textOnAccent : DSColor.textPrimary)
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .fill(active ? DSColor.appAccent : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .stroke(DSColor.separator.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader_tool_\(id)")
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// The bubble that follows the slider while scrubbing, showing where a release
    /// would land. Same behaviour as the 經典 bar.
    private var scrubPreview: some View {
        VStack(spacing: 4) {
            Text(progressPercentText)
                .font(DSFont.subheadline.monospacedDigit())
                .foregroundStyle(DSColor.textOnAccent)
            Text(chapterTitleForProgress(sliderProgress))
                .font(DSFont.subheadline)
                .lineLimit(1)
                .foregroundStyle(DSColor.textOnAccent)
        }
        .padding(.horizontal, DSSpacing.xl)
        .padding(.vertical, DSSpacing.md)
        .background(Capsule().fill(DSColor.appAccent))
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .transition(.opacity.animation(DSAnimation.fast))
        .offset(y: -72)
    }

    // MARK: - 更多菜单（玻璃圆钮）

    private var moreMenuGlass: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().stroke(DSColor.separator.opacity(0.5), lineWidth: 0.5))
            .shadow(color: DSColor.coverHeroShadow.opacity(0.3), radius: 10, y: 5)
    }

    @ViewBuilder
    private var moreMenu: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                legacyMenuSequence.cancel()
                showsLegacyMenu = true
            } label: {
                ZStack {
                    moreMenuGlass
                    moreMenuGlyph
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            }
            .accessibilityLabel(localized("更多"))
            .sheet(isPresented: $showsLegacyMenu, onDismiss: runLegacyMenuChoice) {
                AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
                    DismissalSequencedActionChooser(
                        title: localized("更多"),
                        actions: legacyMenuActions,
                        onSelect: { legacyMenuSequence.select($0) }
                    )
                }
            }
        } else {
            Menu {
                ForEach(menuActions) { item in
                    Button(action: item.action) {
                        Text(item.label)
                        if item.isLocked {
                            Text(localized("需要 Pro"))
                        }
                        Image(systemName: item.isLocked ? "lock.fill" : item.icon)
                    }
                }
                if let onOpenBookDetail {
                    Button(action: onOpenBookDetail) {
                        Label(localized("书籍详情"), systemImage: "info.circle")
                    }
                }
            } label: {
                ZStack {
                    moreMenuGlass
                    moreMenuGlyph
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            }
            .accessibilityLabel(localized("更多"))
        }
    }

    private var moreMenuGlyph: some View {
        Image(systemName: "line.3.horizontal")
            .font(DSFont.fixed(size: 17, weight: .medium))
            .foregroundStyle(DSColor.textPrimary)
    }

    private var legacyMenuActions: [DismissalSequencedAction<MenuRoute>] {
        var actions = menuActions.map { item in
            DismissalSequencedAction(
                route: MenuRoute.action(item.id),
                title: item.label,
                systemImage: item.isLocked ? "lock.fill" : item.icon,
                subtitle: item.isLocked ? localized("需要 Pro") : nil
            )
        }
        if onOpenBookDetail != nil {
            actions.append(DismissalSequencedAction(
                route: .bookDetail,
                title: localized("书籍详情"),
                systemImage: "info.circle"
            ))
        }
        return actions
    }

    private func runLegacyMenuChoice() {
        switch legacyMenuSequence.consumeAfterDismissal() {
        case .action(let id):
            menuActions.first { $0.id == id }?.action()
        case .bookDetail:
            onOpenBookDetail?()
        case nil:
            break
        }
    }
}

#Preview("Floating Chrome") {
    @Previewable @State var theme: ReaderTheme = .sepia

    ZStack {
        theme.backgroundColor.ignoresSafeArea()

        Text(String(repeating: "正文垫在浮动控制岛后面，检查是否穿透。", count: 24))
            .font(DSFont.fixed(size: 17))
            .foregroundColor(theme.textColor)
            .padding(20)

        ReaderFloatingChrome(
            readerTheme: theme,
            chapterTitle: "第四回 薄命女偏逢薄命郎 葫芦僧乱判葫芦案",
            isBookmarked: false,
            overlayContentMaxWidth: 640,
            canGoPrevChapter: true,
            canGoNextChapter: true,
            pageStatusText: "第 4 章 · 已完成 32.5%",
            chapterSliderProgressValue: { 0.325 },
            applyChapterSliderProgress: { _ in },
            chapterTitleForProgress: { _ in "第五回" },
            onBack: {},
            onOpenSearch: {},
            onToggleBookmark: {},
            menuActions: [
                ReaderSecondaryAction(id: .refresh, icon: "arrow.clockwise", label: "刷新", action: {}),
                ReaderSecondaryAction(id: .aiAssistant, icon: "sparkles", label: "AI 助手", isLocked: true, action: {}),
            ],
            onOpenBookDetail: {},
            onPrevChapter: {},
            onNextChapter: {},
            onOpenTOC: {},
            onOpenSettings: {},
            onOpenTTS: {},
            onToggleDarkMode: {}
        )
    }
}
