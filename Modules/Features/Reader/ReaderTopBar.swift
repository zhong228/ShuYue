import SwiftUI

struct ReaderTopBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let theme: ReaderTheme
    let chapterTitle: String
    let titleVisible: Bool
    let titleSize: CGFloat
    let titleTopSpacing: CGFloat
    let titleBottomSpacing: CGFloat
    let isBookmarked: Bool
    let overlayMaxWidth: CGFloat
    let onBack: () -> Void
    /// 全書搜尋 — the same sheet Apple Books opens from its 選單.
    let onOpenSearch: () -> Void
    let onToggleBookmark: () -> Void
    /// AI 助手 and AI 翻譯, the 三橫線 menu's first rows. A locked one (no Pro) is marked
    /// and its action opens the paywall.
    let menuActions: [ReaderSecondaryAction]
    /// 書籍詳情, the menu's last row — online books only.
    let onOpenBookDetail: (() -> Void)?

    @ObservedObject private var settings = GlobalSettings.shared
    /// iOS 17 only: the menu is a chooser sheet, and its choice runs from the sheet's real
    /// `onDismiss` (Technotes/iOS17MenuModalPresentation.md) — every row opens a sheet.
    @State private var showsLegacyMenu = false
    @State private var legacyMenuSequence = DismissalSequencedPresentation<MenuRoute>()

    private enum MenuRoute: Hashable {
        case action(ReaderSecondaryAction.ID)
        case bookDetail
    }

    private var showsMenu: Bool {
        !menuActions.isEmpty || onOpenBookDetail != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // 左：返回圆形毛玻璃浮钮
                Button {
                    onBack()
                } label: {
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

                // 中：标题长条胶囊，书签/搜索收进两端
                HStack(spacing: 6) {
                    bookmarkMicroButton
                    if titleVisible {
                        Text(chapterTitle)
                            .font(DSFont.fixed(size: titleSize, weight: .medium))
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
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

                // 右：菜单圆形毛玻璃浮钮
                if showsMenu {
                    menu
                } else {
                    Color.clear
                        .frame(width: 44, height: 44)
                }
            }
            .frame(maxWidth: overlayMaxWidth)
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, titleTopSpacing)
            .padding(.bottom, titleBottomSpacing)
            Spacer()
        }
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
        .scaleEffect(isBookmarked && !reduceMotion ? 1.12 : 1.0)
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

    // MARK: - 三橫線 menu（玻璃圆钮）

    private var menuGlass: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().stroke(DSColor.separator.opacity(0.5), lineWidth: 0.5))
            .shadow(color: DSColor.coverHeroShadow.opacity(0.3), radius: 10, y: 5)
    }

    @ViewBuilder
    private var menu: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                legacyMenuSequence.cancel()
                showsLegacyMenu = true
            } label: {
                ZStack {
                    menuGlass
                    menuGlyph
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            }
            .accessibilityLabel(localized("选单"))
            .sheet(isPresented: $showsLegacyMenu, onDismiss: runLegacyMenuChoice) {
                AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
                    DismissalSequencedActionChooser(
                        title: localized("选单"),
                        actions: legacyMenuActions,
                        onSelect: { legacyMenuSequence.select($0) }
                    )
                }
            }
        } else {
            Menu {
                ForEach(menuActions) { item in
                    Button(action: item.action) {
                        // A locked row keeps its name, trades its symbol for the lock the
                        // selection menu's 筆記 uses, and says why underneath. A menu reads
                        // a second `Text` in the label as the row's subtitle; inside a
                        // `Label`'s title it is dropped.
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
                    menuGlass
                    menuGlyph
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            }
            .accessibilityLabel(localized("选单"))
        }
    }

    private var menuGlyph: some View {
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

#Preview("经典顶栏") {
    ZStack(alignment: .top) {
        ReaderTheme.white.backgroundColor
            .ignoresSafeArea()
        ReaderTopBar(
            theme: .white,
            chapterTitle: "第一章",
            titleVisible: false,
            titleSize: 16,
            titleTopSpacing: 10,
            titleBottomSpacing: 10,
            isBookmarked: false,
            overlayMaxWidth: 700,
            onBack: {},
            onOpenSearch: {},
            onToggleBookmark: {},
            menuActions: [
                ReaderSecondaryAction(id: .aiAssistant, icon: "sparkles", label: "AI 助手", isLocked: true, action: {}),
                ReaderSecondaryAction(id: .translation, icon: "translate", label: "AI 翻译", isLocked: true, action: {}),
            ],
            onOpenBookDetail: {}
        )
    }
}
