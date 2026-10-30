import SwiftUI

// MARK: - Slider centreline alignment

/// Lets 上一章／下一章 line up with the progress slider itself rather than with the
/// column that also carries the 「4/12 · 25.60%」 line beneath it.
private enum ReaderSliderCenterAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

extension VerticalAlignment {
    static let readerSliderCenter = VerticalAlignment(ReaderSliderCenterAlignment.self)
}

struct ReaderBottomControlBar: View {
    /// The built-in background the reader sits on: what the bar's colours are read from.
    let readerTheme: ReaderTheme
    let overlayContentMaxWidth: CGFloat
    let showRefreshButton: Bool
    let showChangeSourceButton: Bool
    let showDownloadButton: Bool
    let downloadButtonIcon: String
    let canGoPrevChapter: Bool
    let canGoNextChapter: Bool
    let chapterPageInfo: String
    let totalProgressPercent: String
    let chapterSliderProgressValue: () -> Double
    let applyChapterSliderProgress: (Double) -> Void
    let chapterTitleForProgress: (Double) -> String
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void
    let onRefresh: () -> Void
    let onOpenChangeSource: () -> Void
    let onDownloadAction: () -> Void
    let onOpenTTS: () -> Void
    let onOpenTOC: () -> Void
    let onOpenBookmarks: () -> Void
    /// 深色／白天: the reader switches its own dark mode, and the background with it.
    let onToggleDarkMode: () -> Void
    let onOpenSettings: () -> Void

    @ObservedObject private var settings = GlobalSettings.shared

    @State private var chapterSliderDraft: Double? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 书级浮钮（刷新／换源／下载）—独立小浮簇，置于岛上
            bookScopedCircles
                .padding(.trailing, DSSpacing.md)
                .padding(.bottom, DSSpacing.xs)

            // 主玻璃岛
            mainIsland
                .padding(.horizontal, DSSpacing.md)
                .padding(.bottom, DSSpacing.md)
        }
    }

    /// The reader's own dark mode, which 深色／白天 switches — not whether the background
    /// it sits on is 黑色, which a dark saved background does in light mode too.
    private var isDarkMode: Bool { settings.readerDarkMode }

    private var mainIsland: some View {
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
        .animation(DSAnimation.fast, value: chapterSliderDraft == nil)
    }

    // MARK: - 上段：进度区

    private var progressSection: some View {
        VStack(spacing: DSSpacing.xs) {
            // 章节标题与「第 x 章 · y%」置于滑轨上方两端
            HStack(alignment: .firstTextBaseline) {
                Text(chapterTitleForProgress(chapterSliderProgressValue()))
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(chapterPageInfo) · \(totalProgressPercent)")
                    .font(DSFont.footnote.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
            }

            // 粗圆轨 + 强调色圆形滑块，上一章／下一章箭头内嵌同行两端
            HStack(spacing: DSSpacing.sm) {
                chapterArrow(forward: false) { onPrevChapter() }
                Slider(
                    value: Binding<Double>(
                        get: { chapterSliderDraft ?? chapterSliderProgressValue() },
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
                // A bare Slider announces a percentage of its 0…1 range and no name at all
                // (docs/design.md §7.1, third trap). Value shares `progressStatusText` with
                // the line printed underneath so the two can't drift apart.
                .accessibilityLabel(localized("阅读进度"))
                .accessibilityValue(progressStatusText)
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

    // MARK: - 下段：按钮区（带填充态的方形按钮，等距分布）

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
        // Derived from the item, not the label: the label is localized, so a
        // UI test looking for 目錄 would only ever find it in one language.
        .accessibilityIdentifier("reader_tool_\(id)")
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - 书级浮钮（刷新／换源／下载）

    private var bookScopedCircles: some View {
        HStack(spacing: DSSpacing.sm) {
            Spacer()
            if showRefreshButton, settings.isReaderChromeItemVisible(ReaderChromeActionItem.refresh) {
                glassCircleActionButton(item: .refresh, label: localized("刷新")) { onRefresh() }
            }
            if showChangeSourceButton, settings.isReaderChromeItemVisible(ReaderChromeActionItem.changeSource) {
                glassCircleActionButton(item: .changeSource, label: localized("换源")) {
                    onOpenChangeSource()
                }
            }
            if showDownloadButton, settings.isReaderChromeItemVisible(ReaderChromeActionItem.download) {
                glassCircleActionButton(item: .download, label: localized("下载")) { onDownloadAction() }
            }
        }
    }

    @ViewBuilder
    private func glassCircleActionButton(item: ReaderChromeActionItem, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .overlay(Circle().stroke(DSColor.separator.opacity(0.4), lineWidth: 0.5))
                    .shadow(color: DSColor.coverHeroShadow.opacity(0.2), radius: 6, y: 3)
                circleGlyph(for: item)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// An imported icon is drawn in its own colours — it is artwork the reader
    /// chose, not a symbol to tint.
    @ViewBuilder
    private func circleGlyph(for item: ReaderChromeActionItem) -> some View {
        if let custom = settings.readerChromeIconImage(for: item) {
            Image(uiImage: custom)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: item == .download ? downloadButtonIcon : item.defaultSystemImage)
                .font(DSFont.fixed(size: 18))
                .foregroundStyle(DSColor.textPrimary)
        }
    }

    /// The one source for both the printed progress line and the slider's VoiceOver value.
    private var progressStatusText: String {
        "\(chapterPageInfo)  ·  \(totalProgressPercent)"
    }

    /// The bubble that follows the slider while scrubbing, showing where a release
    /// would land. Same behaviour as before.
    private var scrubPreview: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f%%", (chapterSliderDraft ?? 0) * 100))
                .font(DSFont.fixed(size: 15, weight: .medium))
                .foregroundStyle(DSColor.textOnAccent)
            Text(chapterTitleForProgress(chapterSliderDraft ?? 0))
                .font(DSFont.fixed(size: 15, weight: .regular))
                .foregroundStyle(DSColor.textOnAccent)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Capsule().fill(DSColor.appAccent))
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .transition(.opacity.animation(DSAnimation.fast))
        .offset(y: -72)
    }
}

// Page text sits behind the floating circle buttons on purpose: that is the case where
// a transparent fill made them unreadable.
#Preview("Classic Bottom Control Bar") {
    @Previewable @State var theme: ReaderTheme = .sepia

    ZStack {
        theme.backgroundColor.ignoresSafeArea()

        Text(String(repeating: "书页正文挡在浮动按钮后面，检查按钮是否仍清楚可辨。", count: 12))
            .font(DSFont.fixed(size: 17))
            .foregroundColor(theme.textColor)
            .padding(24)

        ReaderBottomControlBar(
            readerTheme: theme,
            overlayContentMaxWidth: 520,
            showRefreshButton: true,
            showChangeSourceButton: true,
            showDownloadButton: true,
            downloadButtonIcon: "arrow.down.circle",
            canGoPrevChapter: true,
            canGoNextChapter: true,
            chapterPageInfo: "3 / 12",
            totalProgressPercent: "24%",
            chapterSliderProgressValue: { 0.24 },
            applyChapterSliderProgress: { _ in },
            chapterTitleForProgress: { _ in "第五章" },
            onPrevChapter: {},
            onNextChapter: {},
            onRefresh: {},
            onOpenChangeSource: {},
            onDownloadAction: {},
            onOpenTTS: {},
            onOpenTOC: {},
            onOpenBookmarks: {},
            onToggleDarkMode: {},
            onOpenSettings: {}
        )
    }
}
