import SwiftUI

/// L6「极简悬浮控制」：阅读器唯一的 chrome，取代 classic / modern / Apple Books
/// 三套切换。
///
/// 点屏幕中央呼出两个悬浮控制岛：
/// - 顶部控制岛：返回、章节名、书签、搜索居左；原三横线菜单折叠为「更多」按钮，
///   收纳书级操作（刷新／换源／下载／网页打开，以及 AI 助手／AI 翻譯）。
/// - 底部控制岛：上一章｜进度滑条｜下一章；下一行收拢目录／设置／听书／深色四个
///   功能；页码反馈「第 x 章 · 已完成 xx%」并配一条底部细进度线。
///
/// 颜色统一经 `ReaderChromePalette(interface: .classic, ...)` 解析：外觀 →
/// 閱讀界面 → 自定義 里对 classic 的覆盖继续生效；阅读器的界面三选一只影响
/// 设置页的预览，不再改变实际 chrome（见 AppearanceThemeView）。
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

    private var palette: ReaderChromePalette {
        ReaderChromePalette(interface: .classic, theme: readerTheme, settings: settings)
    }

    /// The reader's own dark mode, which 深色／白天 switches — not whether the background
    /// it sits on is 黑色, which a dark saved background does in light mode too.
    private var isDarkMode: Bool { settings.readerDarkMode }

    private var sliderProgress: Double {
        chapterSliderDraft ?? chapterSliderProgressValue()
    }

    private var showsMoreMenu: Bool {
        !menuActions.isEmpty || onOpenBookDetail != nil
    }

    private var progressPercentText: String {
        String(format: "%.0f%%", sliderProgress * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
    }

    // MARK: - 顶部控制岛

    private var topBar: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(DSFont.fixed(size: 17, weight: .medium))
                    .foregroundColor(palette.topIcon)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }
            .accessibilityIdentifier("reader_back_button")
            .accessibilityLabel(localized("退出閱讀"))

            Text(chapterTitle)
                .font(DSFont.fixed(size: 15, weight: .medium))
                .foregroundColor(palette.topIcon)
                .lineLimit(1)
                .layoutPriority(1)

            Button(action: onToggleBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(DSFont.fixed(size: 17, weight: .medium))
                    .foregroundColor(isBookmarked ? DSColor.appAccent : palette.topIcon)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(localized("書籤"))
            .accessibilityValue(localized(isBookmarked ? "已加入" : "未加入"))

            Button(action: onOpenSearch) {
                Image(systemName: "magnifyingglass")
                    .font(DSFont.fixed(size: 17, weight: .medium))
                    .foregroundColor(palette.topIcon)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(localized("Search Book"))

            Spacer(minLength: 0)

            if showsMoreMenu {
                moreMenu
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, 10)
        .floatingSurface(
            in: RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous),
            fill: palette.topFill
        )
        .frame(maxWidth: overlayContentMaxWidth)
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.md)
        .tint(palette.topIcon)
    }

    // MARK: - 底部控制岛

    private var bottomBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: DSRadius.xxl) {
                chapterLine
                progressRow
                toolRow
                statusLine
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.md)
            .floatingSurface(
                in: RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous),
                fill: palette.bottomFill
            )
            .overlay(alignment: .top) {
                if chapterSliderDraft != nil {
                    scrubPreview
                }
            }
            .frame(maxWidth: overlayContentMaxWidth)
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.md)
            .tint(palette.bottomAccent)
            .animation(DSAnimation.fast, value: chapterSliderDraft == nil)
        }
    }

    /// 章节名 + 页码反馈，一行之内完成「在哪一章、走到哪」。
    private var chapterLine: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(chapterTitle)
                .font(DSFont.footnote)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(pageStatusText)
                .font(DSFont.footnote.monospacedDigit())
        }
        .foregroundStyle(palette.bottomIcon.opacity(0.62))
        .accessibilityElement(children: .combine)
    }

    private var progressRow: some View {
        HStack(spacing: DSSpacing.sm) {
            Button(action: onPrevChapter) {
                Image(systemName: "chevron.left")
                    .font(DSFont.fixed(size: 15, weight: .medium))
                    .foregroundStyle(palette.bottomIcon)
                    .opacity(canGoPrevChapter ? 1 : 0.3)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoPrevChapter)
            .accessibilityLabel(localized("上一章"))

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
            .accessibilityLabel(localized("閱讀進度"))
            .accessibilityValue(progressPercentText)

            Button(action: onNextChapter) {
                Image(systemName: "chevron.right")
                    .font(DSFont.fixed(size: 15, weight: .medium))
                    .foregroundStyle(palette.bottomIcon)
                    .opacity(canGoNextChapter ? 1 : 0.3)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoNextChapter)
            .accessibilityLabel(localized(canGoNextChapter ? "下一章" : "書末頁"))
        }
    }

    /// The fixed four: 目录／听书／深色／设置. 书签 lives in the top island, so it is not
    /// repeated here; 更多菜单里的刷新/换源/下载仍按 自定義 的可见性过滤。
    private var toolRow: some View {
        HStack(spacing: 0) {
            toolButton(
                item: ReaderChromeToolItem.tableOfContents,
                label: localized("目錄"),
                action: onOpenTOC
            )
            toolButton(
                item: ReaderChromeActionItem.playback,
                label: localized("聽書"),
                action: onOpenTTS
            )
            toolButton(
                item: ReaderChromeToolItem.nightMode,
                label: localized(isDarkMode ? "白天" : "深色"),
                active: isDarkMode,
                action: onToggleDarkMode
            )
            toolButton(
                item: ReaderChromeToolItem.settings,
                label: localized("設置"),
                action: onOpenSettings
            )
        }
    }

    @ViewBuilder
    private func toolButton(
        item: some ReaderChromeIconItem,
        label: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                toolGlyph(for: item, active: active)
                Text(label)
                    .font(DSFont.caption2)
                    .foregroundStyle(active ? palette.bottomAccent : palette.bottomIcon)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader_tool_\(item.storageID)")
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// An imported icon is drawn in its own colours — it is artwork the reader
    /// chose, not a symbol to tint. Only the fallback SF Symbol takes the palette.
    @ViewBuilder
    private func toolGlyph(for item: some ReaderChromeIconItem, active: Bool) -> some View {
        if let custom = settings.readerChromeIconImage(for: item) {
            Image(uiImage: custom)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: item.defaultSystemImage)
                .imageScale(.large)
                .foregroundStyle(active ? palette.bottomAccent : palette.bottomIcon)
        }
    }

    /// 页码反馈「第 x 章 · 已完成 xx%」下面的底部细进度线：全书进度。
    private var statusLine: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(pageStatusText)
                .font(DSFont.caption2)
                .foregroundStyle(palette.bottomIcon.opacity(0.62))
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bottomIcon.opacity(0.16))
                    Capsule()
                        .fill(palette.bottomAccent)
                        .frame(width: geo.size.width * min(max(sliderProgress, 0), 1))
                }
            }
            .frame(width: 72, height: 2)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 更多菜单

    @ViewBuilder
    private var moreMenu: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                legacyMenuSequence.cancel()
                showsLegacyMenu = true
            } label: {
                moreMenuGlyph
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
                        Label(localized("書籍詳情"), systemImage: "info.circle")
                    }
                }
            } label: {
                moreMenuGlyph
            }
            .accessibilityLabel(localized("更多"))
        }
    }

    private var moreMenuGlyph: some View {
        Image(systemName: "line.3.horizontal")
            .font(DSFont.fixed(size: 17, weight: .medium))
            .foregroundColor(palette.topIcon)
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
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
                title: localized("書籍詳情"),
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
        .floatingSurface(in: Capsule(), fill: DSColor.appAccent)
        .allowsHitTesting(false)
        .transition(.opacity.animation(DSAnimation.fast))
        .offset(y: -72)
    }
}

#Preview("Floating Chrome") {
    @Previewable @State var theme: ReaderTheme = .sepia

    ZStack {
        theme.backgroundColor.ignoresSafeArea()

        Text(String(repeating: "正文墊在浮動控制島後面，檢查是否穿透。", count: 24))
            .font(DSFont.fixed(size: 17))
            .foregroundColor(theme.textColor)
            .padding(20)

        ReaderFloatingChrome(
            readerTheme: theme,
            chapterTitle: "第四回 薄命女偏逢薄命郎 葫蘆僧亂判葫蘆案",
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