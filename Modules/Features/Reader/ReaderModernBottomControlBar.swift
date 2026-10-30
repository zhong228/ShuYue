import SwiftUI

/// The 現代 interface's bottom chrome: one floating rounded glass island, inset from
/// every edge, holding the chapter line, the chapter progress slider, and the same
/// four tools 經典 offers — 目錄 / 書籤 / 深色 / 設置.
///
/// It wears the shared 界面效果 surface language: a single `.ultraThinMaterial` island
/// (大圆角、细描边、明显投影、距屏幕边缘留白), with the progress section above a
/// divider and the four tools as filled rounded-square buttons below — so it reads as
/// the same 双岛浮层 family as the other three chrome sets, not a different design.
///
/// The book-scoped actions (刷新 / 換源 / 下載 / 聽書) are deliberately *not* here;
/// 現代 puts them in `ReaderModernBookCard` behind the cover thumbnail.
struct ReaderModernBottomControlBar: View {
    /// The built-in background the reader sits on: what the bar's colours are read from.
    let readerTheme: ReaderTheme
    let overlayContentMaxWidth: CGFloat
    let canGoPrevChapter: Bool
    let canGoNextChapter: Bool
    let chapterTitle: String
    let chapterPageInfo: String
    let chapterSliderProgressValue: () -> Double
    let applyChapterSliderProgress: (Double) -> Void
    let chapterTitleForProgress: (Double) -> String
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void
    let onOpenTOC: () -> Void
    let onOpenBookmarks: () -> Void
    /// 深色／白天: the reader switches its own dark mode, and the background with it.
    let onToggleDarkMode: () -> Void
    let onOpenSettings: () -> Void

    @ObservedObject private var settings = GlobalSettings.shared

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

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

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

    // MARK: - 上段：进度区

    private var progressSection: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapterTitle)
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    Text(chapterPageInfo)
                        .font(DSFont.footnote.monospacedDigit())
                        .foregroundStyle(DSColor.textSecondary)
                }
                Spacer(minLength: 0)
                Text(progressPercentText)
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

    // MARK: - 下段：按钮区（带填充态的方形按钮，等距分布）

    private var toolGrid: some View {
        HStack(spacing: 0) {
            squareToolButton(id: "tableOfContents", systemImage: "list.bullet", label: localized("目录")) { onOpenTOC() }
            Spacer()
            squareToolButton(id: "bookmarks", systemImage: "bookmark", label: localized("书签")) { onOpenBookmarks() }
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
}

#Preview("Modern Bottom Control Bar") {
    @Previewable @State var theme: ReaderTheme = .sepia

    ZStack {
        theme.backgroundColor.ignoresSafeArea()

        Text(String(repeating: "正文垫在浮动底栏后面，检查是否穿透。", count: 24))
            .font(DSFont.fixed(size: 17))
            .foregroundColor(theme.textColor)
            .padding(20)

        ReaderModernBottomControlBar(
            readerTheme: theme,
            overlayContentMaxWidth: 640,
            canGoPrevChapter: true,
            canGoNextChapter: true,
            chapterTitle: "第四回 薄命女偏逢薄命郎 葫芦僧乱判葫芦案",
            chapterPageInfo: "7 / 18",
            chapterSliderProgressValue: { 0.32 },
            applyChapterSliderProgress: { _ in },
            chapterTitleForProgress: { _ in "第五回" },
            onPrevChapter: {},
            onNextChapter: {},
            onOpenTOC: {},
            onOpenBookmarks: {},
            onToggleDarkMode: {},
            onOpenSettings: {}
        )
    }
}
