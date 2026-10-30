import SwiftUI
import UIKit

enum ReaderQuickPageTurnOption: String, CaseIterable, Identifiable, Hashable {
    case slide
    case cover
    case curl
    case fastFade
    case scroll

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .slide: return "Slide"
        case .cover: return "覆盖翻页"
        case .curl: return "Curl"
        case .fastFade: return "Fast Fade"
        case .scroll: return "Scroll"
        }
    }

    var iconName: String {
        switch self {
        case .slide: return "arrow.left.square"
        case .cover: return "square.on.square"
        case .curl: return "doc"
        case .fastFade: return "bolt.square"
        case .scroll: return "doc.plaintext"
        }
    }
}

/// Which saved-background page the quick panel has pushed.
enum ReaderBackgroundEditorRoute: Hashable {
    case new
    case edit(UUID)

    var backgroundID: UUID? {
        if case .edit(let id) = self { return id }
        return nil
    }
}

struct ReaderQuickThemePanelView: View {
    @Binding var fontSize: CGFloat
    @Binding var readerTheme: ReaderTheme
    let pageTurnOption: ReaderQuickPageTurnOption
    let isVerticalWritingMode: Bool
    let onSelectPageTurnOption: (ReaderQuickPageTurnOption) -> Void
    /// Enters auto-read mode and puts every surface away. It is only an entry:
    /// once running, the footer pill is the single route to the speed and the exit.
    let onStartAutoRead: () -> Void
    let onCustomize: () -> Void
    /// A locked control asked for the paywall. The reader closes this sheet and presents
    /// it from its own `onDismiss`, as it does for 自訂 — never a sheet on top of this one.
    var onOpenPaywall: ((PremiumFeature) -> Void)? = nil

    @ObservedObject private var settings = GlobalSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    /// The saved-background page pushed in this panel's own navigation.
    @State private var backgroundEditor: ReaderBackgroundEditorRoute?
    /// Measured height of the panel's own content, so the sheet is exactly as tall
    /// as what it holds. A fixed detent left a band of dead space under the last
    /// row whenever the content came out shorter than the constant.
    @State private var contentHeight = DSLayout.readerQuickPanelSheetHeight
    @State private var bottomSafeAreaInset: CGFloat = 0

    private let minFontSize = GlobalSettings.readerFontSizeRange.lowerBound
    private let maxFontSize = GlobalSettings.readerFontSizeRange.upperBound

    var body: some View {
        NavigationStack {
            // Scrolls rather than clips. The panel is no longer a fixed 508pt of
            // which 214 went to a background pager that only ever had one page, so
            // its height follows its content — and at the largest Dynamic Type
            // sizes that content is taller than any detent.
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    typeAndPageTurnCard
                    brightnessCard
                    readingBackgroundCard
                    quickActionRow
                }
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xl)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ReaderQuickPanelContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .softScrollEdges()
            .onPreferenceChange(ReaderQuickPanelContentHeightKey.self) { height in
                guard height > 0 else { return }
                contentHeight = height
            }
            .scrollBounceBehavior(.basedOnSize)
            // This panel supplies its own bottom padding. Let the scroll viewport
            // use the whole sheet instead of reserving another home-indicator band.
            .ignoresSafeArea(.container, edges: .bottom)
            .frame(maxWidth: DSLayout.readableCompactWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .pageBackgroundToolbar(for: .settings)
            // No title bar and no close button: the panel is a short sheet the
            // reader flicks away, and a navigation chrome on top of it ate height
            // the controls could use.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $backgroundEditor) { route in
                ReaderCustomBackgroundEditorView(
                    original: route.backgroundID.flatMap(settings.readerCustomBackground(id:)),
                    onSave: { saved in
                        // A new one is made to be worn; an edit leaves what is worn alone,
                        // and the reader repaints if it was this one.
                        if route == .new {
                            wear(saved)
                        }
                        backgroundEditor = nil
                    },
                    onDelete: { backgroundEditor = nil },
                    onRequestPaywall: { onOpenPaywall?($0) }
                )
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReaderQuickPanelSafeAreaBottomKey.self,
                    value: proxy.safeAreaInsets.bottom
                )
            }
        }
        .onPreferenceChange(ReaderQuickPanelSafeAreaBottomKey.self) {
            bottomSafeAreaInset = $0
        }
        // The grabber is the only way out now that the title bar is gone, so the
        // sheet must stay draggable and the indicator visible.
        // A height detent excludes the bottom safe area, which UIKit adds back.
        // Our measurement already includes the panel's complete bottom padding.
        // The saved-background page is a whole form, not a row of controls: the panel
        // opens to full height while it is up, and goes back to fitting its content.
        .presentationDetents(backgroundEditor == nil
            ? [.height(max(DSLayout.minimumTapTarget, contentHeight - bottomSafeAreaInset))]
            : [.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 卡片容器

    /// The panel's card chrome, matching the settings cards the app now wears:
    /// surface fill, soft shadow, hairline separator.
    private func quickPanelCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            content()
        }
        .padding(DSSpacing.lg)
        .background(
            DSColor.surface,
            in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                .stroke(DSColor.separator, lineWidth: 1)
        )
        .shadow(color: DSColor.shadow, radius: 8, y: 2)
    }

    /// A card's small section title, replacing a `Form` section header. An optional
    /// accent glyph leads it so every block reads as its own card at a glance.
    private func quickPanelCardHeader(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: DSSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.appAccent)
                    .accessibilityHidden(true)
            }
            Text(localized(title))
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    // MARK: - 字級 + 翻頁

    /// One card for the two things a reader reaches for mid-page. They used to sit
    /// apart with the page-turn style behind an icon-only `Menu` — a glyph that
    /// never said which style was active.
    private var typeAndPageTurnCard: some View {
        quickPanelCard {
            quickPanelCardHeader("版式", systemImage: "textformat.size")
            HStack(spacing: DSSpacing.md) {
                fontSizeStepper
                pageTurnMenu
                    .frame(width: DSLayout.readerQuickPanelTopMenuWidth)
            }
        }
    }

    /// 小 A ── 現在的字級 ── 大 A, reworked as a stepped capsule.
    ///
    /// The size used to be reported by a row of dots under this control that
    /// faded out after 1.8 seconds — it was gone by the time anyone looked for it,
    /// and its appearing and disappearing made the panel change height. The number
    /// now sits between the two circular accent buttons that change it and never moves.
    ///
    /// Both ends keep `.buttonRepeatBehavior(.enabled)`, so press-and-hold keeps
    /// stepping.
    private var fontSizeStepper: some View {
        HStack(spacing: DSSpacing.md) {
            fontSizeStepButton(
                -1,
                symbol: "minus",
                accessibilityKey: "缩小字体"
            )

            Text("\(Int(fontSize))")
                .font(DSFont.title3.weight(.medium).monospacedDigit())
                .foregroundStyle(DSColor.textPrimary)
                .frame(minWidth: DSSpacing.xxl)
                // The stepper is one control with one value; the buttons carry
                // their own labels, so the number would only repeat what VoiceOver
                // already announces when the value changes.
                .accessibilityHidden(true)

            fontSizeStepButton(
                1,
                symbol: "plus",
                accessibilityKey: "放大字体"
            )
        }
        .padding(DSSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
        .background(
            DSColor.surface,
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(DSColor.separator, lineWidth: 1)
        )
    }

    /// A `Menu` behind a capsule button.
    ///
    /// The menu is the stock control for picking one of several styles; what
    /// changed from the icon-only version is the label — it now says which style
    /// is active, so the reader does not have to open it to find out.
    private var pageTurnMenu: some View {
        Menu {
            Picker(
                localized("翻页"),
                selection: Binding(
                    get: { pageTurnOption },
                    set: { onSelectPageTurnOption($0) }
                )
            ) {
                ForEach(ReaderQuickPageTurnOption.allCases) { option in
                    Label(
                        localized(pageTurnTitleKey(for: option)),
                        systemImage: option.iconName
                    )
                    .font(DSFont.body)
                    .tag(option)
                }
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Text(localized(pageTurnTitleKey(for: pageTurnOption)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down")
                    .font(DSFont.footnote)
                    .accessibilityHidden(true)
            }
            .font(DSFont.subheadline)
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
            .background(DSColor.surface, in: Capsule())
            .overlay(Capsule().stroke(DSColor.separator, lineWidth: 1))
            .contentShape(Capsule())
        }
        .accessibilityLabel(localized("翻页"))
        .accessibilityValue(localized(pageTurnTitleKey(for: pageTurnOption)))
    }

    /// One circular accent button of the stepped font control. `.buttonRepeatBehavior(.enabled)`
    /// makes press-and-hold keep stepping, matching Apple Books.
    private func fontSizeStepButton(_ delta: CGFloat, symbol: String, accessibilityKey: String) -> some View {
        Button {
            adjustFontSize(delta)
        } label: {
            Image(systemName: symbol)
                .font(DSFont.title3.weight(.semibold))
                .foregroundStyle(DSColor.appAccent)
                .frame(
                    width: DSLayout.readerQuickPanelTopControlHeight,
                    height: DSLayout.readerQuickPanelTopControlHeight
                )
                .background(
                    DSColor.appAccentSoft,
                    in: Circle()
                )
                .overlay(
                    Circle().stroke(DSColor.appAccent.opacity(0.45), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(QuickPanelSegmentButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(localized(accessibilityKey))
    }

    // MARK: - Brightness

    private var brightnessCard: some View {
        quickPanelCard {
            quickPanelCardHeader("亮度管理", systemImage: "sun.max")
            HStack(spacing: DSSpacing.md) {
                Image(systemName: "sun.min.fill")
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.appAccent)
                Slider(
                    value: Binding(
                        get: { CGFloat(settings.readerBrightness) },
                        set: { value in
                            settings.followSystemBrightness = false
                            settings.readerBrightness = Double(value)
                            UIScreen.main.brightness = value
                        }
                    ),
                    in: 0.05...1.0
                )
                .tint(DSColor.appAccent)
                Image(systemName: "sun.max.fill")
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.appAccent)
            }
            .frame(minHeight: DSLayout.minimumTapTarget)
            .foregroundStyle(DSColor.textPrimary)
            // Only under 綁定閱讀主題: without it the reader follows the device by
            // itself and there is nothing to switch (the user's call, 2026-09-30).
            if settings.appearanceBindReaderTheme {
                Divider()
                    .overlay(DSColor.separator)
                followSystemAppearanceToggle
            }
        }
    }

    // MARK: - Reading backgrounds

    /// One card, one scrolling row — not the 3×2 paged grid this replaced: the four
    /// built-in backgrounds, then every saved one, each by name, then 自定義 to make
    /// another.
    private var readingBackgroundCard: some View {
        let resolution = settings.readerBackgroundResolution(mode: settings.readerMode, wornTheme: readerTheme)
        return quickPanelCard {
            quickPanelCardHeader("阅读背景", systemImage: "paintpalette")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.md) {
                    ForEach(ReaderTheme.allCases, id: \.self) { background in
                        readingBackgroundButton(background, resolution: resolution)
                            .frame(width: DSLayout.readerQuickPanelBackgroundTileWidth)
                    }
                    ForEach(settings.readerCustomBackgrounds) { background in
                        savedBackgroundButton(background, resolution: resolution)
                            .frame(width: DSLayout.readerQuickPanelBackgroundTileWidth)
                    }
                    newBackgroundButton
                        .frame(width: DSLayout.readerQuickPanelBackgroundTileWidth)
                }
                .padding(.vertical, DSSpacing.xs)
                .padding(.horizontal, 2)
            }
        }
    }

    /// Whether the reader's dark mode keeps to the device's appearance, where the two
    /// picks of 綁定閱讀主題 are worn. Off to start with; switching the reader against
    /// the device by hand turns it back off, since the two cannot both hold.
    private var followSystemAppearanceToggle: some View {
        Toggle(
            localized("跟随装置深浅色"),
            isOn: Binding(
                get: { settings.readerFollowSystemTheme },
                set: { applyFollowSystemAppearance($0) }
            )
        )
        .font(DSFont.body)
        .foregroundStyle(DSColor.textPrimary)
    }

    private func readingBackgroundButton(
        _ background: ReaderTheme,
        resolution: ReaderBackgroundResolution
    ) -> some View {
        // While the page is painted by 跟隨外觀主題 or by a saved background — a dark one
        // sits on 黑色 — no built-in one is the one in effect.
        let selected = !resolution.paintsWithAppearanceTheme
            && resolution.customBackground == nil
            && resolution.theme == background
        return Button {
            settings.appearanceBindReaderTheme = false
            settings.setReaderDarkMode(background == .night, deviceIsDark: colorScheme == .dark)
            // 黑色 is the reader's dark mode; the saved background stays the light mode's
            // and comes back with it. A light built-in one takes its place there.
            if background != .night {
                settings.readerCustomBackgroundID = nil
            }
            readerTheme = background
        } label: {
            backgroundSwatch(
                fill: background.previewBackgroundColor,
                image: nil,
                title: background.localizedTitle,
                selected: selected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(background.localizedTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func savedBackgroundButton(
        _ background: ReaderCustomBackground,
        resolution: ReaderBackgroundResolution
    ) -> some View {
        let selected = resolution.customBackground?.id == background.id
        return Button {
            wear(background)
        } label: {
            backgroundSwatch(
                fill: Color(uiColor: AppearanceThemePreset.hex(background.colorHex)),
                image: background.imageFileName.flatMap(ReaderCustomBackgroundStorageManager.shared.thumbnail(fileName:)),
                title: background.name,
                selected: selected
            )
        }
        .buttonStyle(.plain)
        // Plain buttons only, as on the theme grid: the delete confirmation is a submenu
        // because a modal raised from a context-menu action can be dropped on iOS 17
        // (Technotes/iOS17MenuModalPresentation.md).
        .contextMenu {
            Button {
                backgroundEditor = .edit(background.id)
            } label: {
                Label(localized("编辑"), systemImage: "slider.horizontal.3")
            }
            Menu {
                Button(role: .destructive) {
                    settings.deleteReaderCustomBackground(id: background.id)
                } label: {
                    Label(String(format: localized("删除「%@」"), background.name), systemImage: "trash")
                }
            } label: {
                Label(localized("删除"), systemImage: "trash")
            }
        }
        .accessibilityLabel(background.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: localized("编辑")) {
            backgroundEditor = .edit(background.id)
        }
    }

    private var newBackgroundButton: some View {
        Button {
            backgroundEditor = .new
        } label: {
            VStack(spacing: DSSpacing.xs) {
                ZStack {
                    Circle()
                        .fill(DSColor.surface)
                        .overlay(
                            Circle()
                                .stroke(DSColor.separator, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    Image(systemName: "plus")
                        .font(DSFont.title3.weight(.semibold))
                        .foregroundStyle(DSColor.appAccent)
                }
                .frame(width: Self.backgroundSwatchSize, height: Self.backgroundSwatchSize)

                Text(localized("自定义"))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("自定义"))
    }

    /// One background as a circular swatch with its name beneath: the colour or picture
    /// fills the disc, a selected one wears an accent ring plus an accent check badge,
    /// and its name turns accent. Built-in and saved backgrounds alike carry the name.
    private func backgroundSwatch(
        fill: Color,
        image: UIImage?,
        title: String,
        selected: Bool
    ) -> some View {
        VStack(spacing: DSSpacing.xs) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(fill)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.backgroundSwatchSize, height: Self.backgroundSwatchSize)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }

                if selected {
                    Image(systemName: "checkmark")
                        .font(DSFont.caption2.weight(.bold))
                        .foregroundStyle(DSColor.textOnAccent)
                        .frame(
                            width: Self.backgroundCheckBadgeSize,
                            height: Self.backgroundCheckBadgeSize
                        )
                        .background(DSColor.appAccent, in: Circle())
                        .offset(
                            x: Self.backgroundCheckBadgeSize / 3,
                            y: -Self.backgroundCheckBadgeSize / 3
                        )
                        .accessibilityHidden(true)
                }
            }
            .frame(width: Self.backgroundSwatchSize, height: Self.backgroundSwatchSize)
            .overlay(
                Circle()
                    .stroke(
                        selected ? DSColor.appAccent : DSColor.separator,
                        lineWidth: selected ? 3 : 1
                    )
            )

            Text(title)
                .font(DSFont.caption)
                .foregroundStyle(selected ? DSColor.appAccent : DSColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private static let backgroundSwatchSize: CGFloat = 56
    private static let backgroundCheckBadgeSize: CGFloat = 18

    // MARK: - 快捷動作

    /// The space the background pager gave back.
    ///
    /// 自動閱讀 comes first — that is where every reader that ships this feature
    /// puts it, and until now this app had no entry for it at all: the controller
    /// and its panel were both complete, but nothing ever set `showAutoReadPanel`.
    private var quickActionRow: some View {
        quickPanelCard {
            quickPanelCardHeader("快捷操作", systemImage: "bolt")
            HStack(spacing: DSSpacing.md) {
                Button {
                    onStartAutoRead()
                } label: {
                    Label(localized("自动阅读"), systemImage: "play.fill")
                }
                .buttonStyle(QuickPanelActionButtonStyle())

                Button(action: onCustomize) {
                    Label(localized("Customize"), systemImage: "gear")
                }
                .buttonStyle(QuickPanelActionButtonStyle())
            }
        }
    }

    // MARK: - Actions

    private func adjustFontSize(_ delta: CGFloat) {
        fontSize = GlobalSettings.clampedReaderFontSize((fontSize + delta).rounded())
    }

    /// Turning it on hands the reader's mode to the device; turning it off keeps whatever
    /// is on screen. The reader puts the background of the mode in place.
    private func applyFollowSystemAppearance(_ isOn: Bool) {
        settings.setReaderFollowsDevice(isOn, deviceIsDark: colorScheme == .dark)
    }

    /// A saved background, worn as the reader's own pick: the light mode's background.
    private func wear(_ background: ReaderCustomBackground) {
        readerTheme = settings.wearReaderCustomBackground(
            background,
            over: readerTheme,
            deviceIsDark: colorScheme == .dark
        )
    }

    private func pageTurnTitleKey(for option: ReaderQuickPageTurnOption) -> String {
        option == .scroll && isVerticalWritingMode ? "右往左" : option.titleKey
    }


}

/// Full-width quick-panel action button: tints accent while pressed, then springs
/// back on release. The accent keeps every action in the panel's one voice.
private struct QuickPanelActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Filled with the accent while auto-read is running, so the panel says what
    /// state the reader is in without a second row of text.
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.headline)
            .foregroundStyle(isProminent ? DSColor.textOnAccent : DSColor.appAccent)
            .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelControlHeight)
            .background(
                isProminent
                    ? DSColor.appAccent.opacity(configuration.isPressed ? 0.85 : 1)
                    : (configuration.isPressed ? DSColor.appAccentSoft : DSColor.surface),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isProminent ? Color.clear : DSColor.appAccent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: DSColor.shadow, radius: 6, y: 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(DSAnimation.fast, value: configuration.isPressed)
    }
}

/// The circular font-size step buttons: a gentle press-in, echoing the panel's
/// other controls, instead of a darker inset capsule.
private struct QuickPanelSegmentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .animation(DSAnimation.fast, value: configuration.isPressed)
    }
}

#Preview() {
    ReaderQuickThemePanelView(
        fontSize: .constant(18),
        readerTheme: .constant(.white),
        pageTurnOption: .curl,
        isVerticalWritingMode: false,
        onSelectPageTurnOption: { _ in },
        onStartAutoRead: {},
        onCustomize: {}
    )
}
