import Foundation
import SwiftUI

enum AppleBooksReaderControlPanel: Equatable {
    case menu

    static func panel(
        afterTapping target: AppleBooksReaderControlPanel,
        current: AppleBooksReaderControlPanel?
    ) -> AppleBooksReaderControlPanel? {
        current == target ? nil : target
    }
}

enum AppleBooksProgressScrubber {
    static func value(at locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return clamped(Double(locationX / width))
    }

    static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct AppleBooksReaderControls: View {
    @Binding var activePanel: AppleBooksReaderControlPanel?
    let progressValue: () -> Double
    let applyProgress: (Double) -> Void
    let progressDescription: (Double) -> String
    let secondaryActions: [ReaderSecondaryAction]
    /// The fifth menu row, under 主題與設定; marked when it needs Pro.
    var aiAssistant: ReaderSecondaryAction? = nil
    let onOpenTOC: () -> Void
    let onOpenBookmarks: () -> Void
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void
    /// The reader's own dark mode, which the last menu row switches.
    let isDarkMode: Bool
    let onToggleDarkMode: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sliderDraft: Double?
    @State private var progressFeedbackPhase = 0

    var body: some View {
        ZStack {
            readerScrim

            VStack {
                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: 0)

                    if activePanel == .menu {
                        menuPanel
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xs)
        }
        .animation(panelAnimation, value: activePanel)
        .sensoryFeedback(.impact(weight: .light), trigger: progressFeedbackPhase)
        .onChange(of: activePanel) { _, panel in
            if panel == nil {
                sliderDraft = nil
            }
        }
    }

    private var panelAnimation: Animation {
        reduceMotion ? DSAnimation.fast : DSAnimation.standard
    }

    private var readerScrim: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: DSColor.textPrimary, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                closePanels()
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    /// 双岛浮层：整块菜单是一颗毛玻璃浮岛（大圆角、细描边、明显投影），进度行、菜单
    /// 行、操作行都收进同一座岛内；去掉原本硬编码黑底，全部改用材质与 DS 语义色。
    private var menuPanel: some View {
        VStack(spacing: DSSpacing.sm) {
            progressMenuRow

            menuRow(localized("书签"), icon: "bookmark") {
                performPanelAction(onOpenBookmarks)
            }

            menuRow(localized("Search Book"), icon: "magnifyingglass") {
                performPanelAction(onOpenSearch)
            }

            menuRow(localized("Themes & Settings"), icon: "textformat.size") {
                performPanelAction(onOpenSettings)
            }

            if let aiAssistant {
                menuRow(aiAssistant.label, icon: aiAssistant.icon, isLocked: aiAssistant.isLocked) {
                    performPanelAction(aiAssistant.action)
                }
            }

            // 深色／白天: what 經典 and 現代 keep in their tool row. Last, so the rows
            // above stay where they are. The menu stays up — it is a switch, and the
            // page it changes shows behind the menu.
            menuRow(
                localized(isDarkMode ? "白天" : "深色"),
                icon: ReaderChromeToolItem.nightMode.systemImage(isNight: isDarkMode),
                action: onToggleDarkMode
            )

            if !secondaryActions.isEmpty {
                actionRow
            }
        }
        .padding(DSSpacing.md)
        .frame(width: DSLayout.readerAppleBooksPanelWidth + 24)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                .stroke(DSColor.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: DSColor.coverHeroShadow.opacity(0.3), radius: 16, y: 8)
    }

    /// Four capsules fill the panel's width exactly. A fifth used to stick out past its
    /// left edge, so beyond four the row scrolls, four at a time, starting from the
    /// trailing end where 聽書 sits.
    @ViewBuilder
    private var actionRow: some View {
        let items = Array(secondaryActions.reversed())
        let buttons = HStack(spacing: DSSpacing.sm) {
            ForEach(items) { item in
                actionButton(item)
            }
        }
        if items.count > DSLayout.readerAppleBooksVisibleActions {
            // The scroll view clips to its bounds; the vertical room keeps the capsules'
            // floating shadow, and the row still sits where the unscrolled one does.
            ScrollView(.horizontal, showsIndicators: false) {
                buttons
                    .padding(.vertical, DSSpacing.md)
            }
            .defaultScrollAnchor(.trailing)
            .frame(width: DSLayout.readerAppleBooksPanelWidth)
            .padding(.vertical, -DSSpacing.md)
        } else {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                buttons
            }
        }
    }

    private func actionButton(_ item: ReaderSecondaryAction) -> some View {
        Button {
            performPanelAction(item.action)
        } label: {
            ZStack {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().stroke(DSColor.separator.opacity(0.4), lineWidth: 0.5))
                Image(systemName: item.icon)
                    .font(DSFont.toolbarIconLarge)
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityHidden(true)
            }
            .frame(
                width: DSLayout.readerAppleBooksActionWidth,
                height: DSLayout.readerAppleBooksActionHeight
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
    }

    private var progressMenuRow: some View {
        let value = AppleBooksProgressScrubber.clamped(sliderDraft ?? progressValue())

        return HStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    let fillWidth = geometry.size.width * CGFloat(value)

                    Capsule()
                        .fill(DSColor.appAccent)
                        .frame(width: fillWidth)
                        .allowsHitTesting(false)

                    progressLabel(
                        value,
                        foreground: DSColor.textPrimary
                    )

                    progressLabel(
                        value,
                        foreground: DSColor.textOnAccent
                    )
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: fillWidth)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if sliderDraft == nil {
                                progressFeedbackPhase += 1
                            }
                            sliderDraft = AppleBooksProgressScrubber.value(
                                at: drag.location.x,
                                width: geometry.size.width
                            )
                        }
                        .onEnded { drag in
                            let value = AppleBooksProgressScrubber.value(
                                at: drag.location.x,
                                width: geometry.size.width
                            )
                            applyProgress(value)
                            sliderDraft = nil
                            progressFeedbackPhase += 1
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localized("阅读进度"))
                .accessibilityValue(progressAccessibilityValue(value))
                .accessibilityAdjustableAction { direction in
                    adjustProgress(direction)
                }
            }

            Button {
                performPanelAction(onOpenTOC)
            } label: {
                Image(systemName: "list.bullet")
                    .font(DSFont.toolbarIconLarge)
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(
                        width: DSLayout.readerAppleBooksControlSize,
                        height: DSLayout.readerAppleBooksMenuRowHeight
                    )
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("目录"))
        }
        .frame(height: DSLayout.readerAppleBooksMenuRowHeight)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().stroke(DSColor.separator.opacity(0.4), lineWidth: 0.5))
        )
    }

    private func progressLabel(_ value: Double, foreground: Color) -> some View {
        Text(String(format: localized("Contents · %@"), formattedPercent(value)))
            .font(DSFont.subheadline)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.leading, DSSpacing.lg)
    }

    /// `isLocked`: the row needs Pro — the badge takes the icon's place and the action
    /// opens the paywall. Rows sit inside the glass island, so they are plain text
    /// buttons with no individual capsule.
    private func menuRow(
        _ title: String,
        icon: String,
        isLocked: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.md) {
                Text(title)
                    .font(DSFont.subheadline)
                    .lineLimit(1)

                Spacer(minLength: DSSpacing.sm)

                if isLocked {
                    ProLockBadge()
                } else {
                    Image(systemName: icon)
                        .font(DSFont.toolbarIconLarge)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.md)
            .frame(height: DSLayout.readerAppleBooksMenuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isLocked ? localized("需要 Pro") : "")
        .accessibilityAddTraits(.isButton)
    }

    private func formattedPercent(_ value: Double) -> String {
        NumberFormatter.localizedString(
            from: NSNumber(value: min(max(value, 0), 1)),
            number: .percent
        )
    }

    private func progressAccessibilityValue(_ value: Double) -> String {
        let description = progressDescription(value)
        let percent = formattedPercent(value)
        return description.isEmpty ? percent : "\(percent), \(description)"
    }

    private func adjustProgress(_ direction: AccessibilityAdjustmentDirection) {
        let current = sliderDraft ?? progressValue()
        let delta: Double
        switch direction {
        case .increment:
            delta = DSLayout.readerAppleBooksProgressAccessibilityStep
        case .decrement:
            delta = -DSLayout.readerAppleBooksProgressAccessibilityStep
        @unknown default:
            return
        }
        let adjusted = AppleBooksProgressScrubber.clamped(current + delta)
        applyProgress(adjusted)
        sliderDraft = nil
    }

    private func closePanels() {
        withAnimation(panelAnimation) {
            activePanel = nil
            sliderDraft = nil
        }
    }

    private func performPanelAction(_ action: () -> Void) {
        closePanels()
        action()
    }
}

#Preview("Apple Books Reader Controls") {
    ZStack {
        ReaderTheme.white.backgroundColor
            .ignoresSafeArea()

        AppleBooksReaderControls(
            activePanel: .constant(.menu),
            progressValue: { 0.01 },
            applyProgress: { _ in },
            progressDescription: { _ in
                String(format: localized("第 %d 章"), 5)
            },
            secondaryActions: [
                ReaderSecondaryAction(
                    id: .playback,
                    icon: "headphones",
                    label: localized("听书"),
                    action: {}
                ),
                ReaderSecondaryAction(
                    id: .download,
                    icon: "arrow.down.circle",
                    label: localized("下载"),
                    action: {}
                ),
                ReaderSecondaryAction(
                    id: .changeSource,
                    icon: "arrow.left.and.right",
                    label: localized("换源"),
                    action: {}
                ),
                ReaderSecondaryAction(
                    id: .refresh,
                    icon: "arrow.clockwise",
                    label: localized("刷新"),
                    action: {}
                )
            ],
            onOpenTOC: {},
            onOpenBookmarks: {},
            onOpenSearch: {},
            onOpenSettings: {},
            isDarkMode: false,
            onToggleDarkMode: {}
        )
    }
}
