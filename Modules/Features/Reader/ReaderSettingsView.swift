import YueduCoreText
import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 阅读偏好的三个横向页面（版式 / 视觉 / 习惯）。
private enum ReaderSettingsPage: Int, CaseIterable, Identifiable, Hashable {
    case layout
    case visual
    case habits

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .layout: return "版式"
        case .visual: return "视觉"
        case .habits: return "习惯"
        }
    }

    /// A distinct SF Symbol per page so the capsule strip reads at a glance.
    var icon: String {
        switch self {
        case .layout: return "textformat"
        case .visual: return "paintbrush"
        case .habits: return "hand.tap"
        }
    }
}

struct ReaderSettingsView: View {
    @Binding var fontSize: CGFloat
    @Binding var theme: ReaderTheme
    var readerSafeTop: CGFloat = 0
    var readerSafeBottom: CGFloat = 0
    var capabilities: ReaderCapabilities = .reflowableText
    var allowsUserSelectedReaderFont = false
    var usesPublicationFontDefault = false
    var isVerticalWritingMode = false
    /// TXT and online books, which carry no writing mode of their own: 排版方向 shows.
    var allowsVerticalWritingMode = false
    var hasParagraphReviews = false
    var onOpenFontImporter: () -> Void
    var onOpenTouchZoneEditor: (() -> Void)?
    /// Hands a style/layout import to the reader's first-level presenter. Nil in
    /// contexts that already are one; see `ReaderSettingsPresentationPolicy`.
    var onOpenStyleImporter: ((ReaderStyleImportRoute) -> Void)?
    /// iOS 17: hands the paywall to the reader's first-level presenter, as the importers
    /// above do — a sheet asked for from inside this sheet can be dropped there. Nil where
    /// this view presents it itself.
    var onOpenPaywall: ((PremiumFeature) -> Void)?

    @StateObject private var readerConfig = ReaderConfig.shared
    @ObservedObject private var settings = GlobalSettings.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingFontImporter = false
    @State private var paywallFeature: PremiumFeature?
    @State private var fontImportError: FontImportError?
    @State private var layoutImportAlert: LayoutImportAlert?
    @State private var showingOverlayResetConfirmation = false
    @State private var showingLayoutResetConfirmation = false
    /// Set only on iOS 18+, where this sheet can own the picker itself.
    @State private var styleImportRoute: ReaderStyleImportRoute?
    /// 匯出閱讀設定's name prompt, and the name typed into it.
    @State private var showingReaderSettingsExport = false
    @State private var readerSettingsExportName = ""
    /// 三页面板当前页。
    @State private var selectedPage: ReaderSettingsPage = .layout

    private var supportsFontSize: Bool { capabilities.contains(.fontSize) }
    private var supportsUserFont: Bool { supportsFontSize && allowsUserSelectedReaderFont }
    private var supportsLineHeight: Bool { capabilities.contains(.lineHeight) }
    private var supportsSpacing: Bool { capabilities.contains(.spacing) }
    private var supportsPageDisplay: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && supportsLineHeight && !settings.scrollMode
    }

    private var readerTint: Color {
        theme.accentColor
    }

    private let previewTextHeight: CGFloat = 220
    private let defaultLineHeightMultiple: CGFloat = 1.65
    private let defaultLetterSpacing: CGFloat = 0
    private let defaultParagraphSpacingMultiplier: CGFloat = 0.8
    private let defaultPageMarginH: CGFloat = 24
    private let defaultPageMarginV: CGFloat = 16

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            previewPanel
            Divider()

            // 三页横向面板：版式 / 视觉 / 习惯。胶囊图标标签条与页面滑动双向同步，
            // 替代原来一条长 Form 的顺序分区（2026-10-12）。
            settingsTabStrip
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.md)

            TabView(selection: $selectedPage) {
                layoutPage
                    .tag(ReaderSettingsPage.layout)
                visualPage
                    .tag(ReaderSettingsPage.visual)
                habitsPage
                    .tag(ReaderSettingsPage.habits)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .themedAppSurface(for: .settings)
        .navigationTitle(localized("阅读偏好"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss() // 點擊叉叉直接離開
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(localized("關閉"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(localized("完成"))
                }
            }
        }
        .tint(readerTint)
        .fileImporter(
            isPresented: $showingFontImporter,
            allowedContentTypes: Self.fontContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFontImport(result)
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(highlightedFeature: feature)
                .environmentObject(subscriptionStore)
        }
        .readerStyleImportPresentation(route: $styleImportRoute) { _ in }
        .alert(item: $fontImportError) { error in
            Alert(
                title: Text(localized("字體匯入失敗")),
                message: Text(error.message),
                dismissButton: .default(Text(localized("確定")))
            )
        }
        .alert(item: $layoutImportAlert) { alert in
            Alert(
                title: Text(localized(alert.titleKey)),
                message: Text(alert.message),
                dismissButton: .default(Text(localized("確定")))
            )
        }
        .alert(
            localized("重設頁首頁尾？"),
            isPresented: $showingOverlayResetConfirmation
        ) {
            Button(localized("重設"), role: .destructive) {
                resetReaderOverlayLayout()
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("這會恢復預設的欄位配置與樣式。"))
        }
        .alert(
            localized("重設排版？"),
            isPresented: $showingLayoutResetConfirmation
        ) {
            Button(localized("重設"), role: .destructive) {
                resetLayout()
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("行距、字距、段距與頁面邊距會回到預設值。"))
        }
        .onAppear {
            if settings.followSystemBrightness {
                syncBrightnessFromSystem()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in
            if settings.followSystemBrightness {
                syncBrightnessFromSystem()
            }
        }
    }

    // MARK: - 标签切换器

    /// 三页胶囊标签条：版式 / 视觉 / 习惯，每页一个图标 + 文字胶囊。与下方 TabView
    /// 双向同步，替代系统分段控件（2026-10-12）。
    private var settingsTabStrip: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(ReaderSettingsPage.allCases) { page in
                settingsTabButton(page)
            }
        }
        .padding(4)
        .background(DSColor.neutralControlFill, in: Capsule())
        .accessibilityLabel(localized("閱讀偏好分頁"))
    }

    private func settingsTabButton(_ page: ReaderSettingsPage) -> some View {
        let selected = selectedPage == page
        return Button {
            withAnimation(DSAnimation.standard) {
                selectedPage = page
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: page.icon)
                    .font(DSFont.fixed(size: 12, weight: .medium))
                Text(localized(page.titleKey))
                    .font(DSFont.fixed(size: 13, weight: .medium))
            }
            .foregroundColor(selected ? DSColor.textOnAccent : DSColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(selected ? readerTint : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 卡片基础件

    /// 卡片顶部的小标题：正文行前的一点明示，替代 Form Section 的 header。
    private func settingsCardHeader(_ title: String) -> some View {
        Text(title)
            .font(DSFont.subheadline.weight(.semibold))
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.md)
            .padding(.bottom, DSSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A row that pushes a page: icon badge, title, chevron — the card's own
    /// `NavigationLink` label instead of a `Form` disclosure row.
    private func navigationRowLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            SettingsRowLabel(title, systemImage: systemImage)
            Spacer(minLength: DSSpacing.sm)
            Image(systemName: "chevron.right")
                .font(DSFont.caption2)
                .foregroundStyle(DSColor.textSecondary.opacity(0.7))
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .contentShape(Rectangle())
    }

    /// The same row with the control's current value between title and chevron.
    private func navigationValueRowLabel(title: String, systemImage: String, value: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            SettingsRowLabel(title, systemImage: systemImage)
            Spacer(minLength: DSSpacing.sm)
            Text(value)
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(DSFont.caption2)
                .foregroundStyle(DSColor.textSecondary.opacity(0.7))
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .contentShape(Rectangle())
    }

    /// 阅读偏好页的滑块行：标题与当前值并排，右侧值收进主题色胶囊徽章，滑块以
    /// 细轨道 + 主题色填充 —— 与系统设置页的默认滑块区分开（2026-10-13）。
    private func readerSliderRow<Value: BinaryFloatingPoint>(
        title: String,
        systemImage: String,
        valueText: String,
        value: Binding<Value>,
        range: ClosedRange<Value>,
        step: Value.Stride,
        isEnabled: Bool = true
    ) -> some View where Value.Stride: BinaryFloatingPoint {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.sm) {
                SettingsRowLabel(title, systemImage: systemImage)
                Spacer(minLength: DSSpacing.sm)
                Text(valueText)
                    .font(DSFont.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(readerTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(readerTint.opacity(0.12), in: Capsule())
            }
            .accessibilityHidden(true)

            Slider(value: value, in: range, step: step)
                .tint(readerTint)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    // MARK: - 三页布局

    /// 版式页：排版生效范围 + 字体字号 + 间距边距。Hand-drawn cards instead of a Form —
    /// the grouped Form is the classic settings chrome this sheet no longer shares.
    private var layoutPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                scopeCard

                if supportsUserFont || supportsFontSize {
                    textCard
                }

                if supportsSpacing || supportsLineHeight {
                    layoutCard
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .softScrollEdges()
    }

    /// 视觉页：文字颜色 + 亮度管理。
    private var visualPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                textColorCard
                brightnessCard
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .softScrollEdges()
    }

    /// 习惯页：翻页习惯 / 眉脚编辑 / 阅读装饰 / 偏好备份。
    private var habitsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                if showsPagingSection {
                    pagingCard
                }

                headerFooterCard

                // Pro sections stay in view without Pro, locked: a reader has to see a
                // feature where it would be used to want it (2026-09-27).
                readerDecorationCard

                readerSettingsBackupCard
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .softScrollEdges()
    }

    private var premiumVisibility: ReaderPremiumVisibilityPolicy {
        ReaderPremiumVisibilityPolicy(isProActive: subscriptionStore.isProActive)
    }

    private var showsCommentBubbleSettings: Bool {
        premiumVisibility.showsCommentBubbleSettings(hasParagraphReviews: hasParagraphReviews)
    }

    /// Paged-only gestures: scroll mode has no page turns and no tap zones.
    private var showsPagingSection: Bool {
        !settings.scrollMode
    }

    // MARK: - 排版生效範圍

    /// Where every change below is kept. Named here rather than only on its own page,
    /// because it is what makes a change made under one theme vanish under another.
    private var scopeCard: some View {
        let themeItems = settings.readingSettingsScope.themeItems
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                ReadingSettingsScopeView()
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    SettingsRowLabel(
                        title: localized("排版生效範圍"),
                        systemImage: "paintpalette"
                    )
                    Spacer(minLength: DSSpacing.sm)
                    Text(scopeSummary(themeItems))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(DSFont.caption2)
                        .foregroundStyle(DSColor.textSecondary.opacity(0.7))
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DSColor.textPrimary)

            if !themeItems.isEmpty {
                Text(String(
                    format: localized("跟隨主題的設定，改動會存進目前的主題「%@」。"),
                    settings.readingSettingsThemeName
                ))
                .dsSectionFooter()
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
            }
        }
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
    }

    private func scopeSummary(_ themeItems: Set<ReadingSettingsScopeItem>) -> String {
        if themeItems.isEmpty { return localized("全部跟隨全域") }
        if themeItems.count == ReadingSettingsScopeItem.allCases.count { return localized("全部跟隨主題") }
        return String(format: localized("%d 項跟隨主題"), themeItems.count)
    }

    // MARK: - 文字

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCardHeader(localized("版式"))

            if supportsUserFont {
                fontSelector
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
            }

            if supportsFontSize {
                Stepper(value: fontSizeBinding, in: GlobalSettings.readerFontSizeRange, step: 1) {
                    LabeledContent {
                        Text(String(format: localized("ReaderOverlay.Format.Points"), Int(fontSize)))
                            .monospacedDigit()
                            .foregroundStyle(DSColor.textSecondary)
                    } label: {
                        SettingsRowLabel(
                            localized(ReadingSettingsScopeItem.fontSize.titleKey),
                            systemImage: ReadingSettingsScopeItem.fontSize.systemImage
                        )
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
            }

            Toggle(isOn: $readerConfig.readerFontBold) {
                SettingsRowLabel(
                    localized(ReadingSettingsScopeItem.bold.titleKey),
                    systemImage: ReadingSettingsScopeItem.bold.systemImage
                )
            }
            .tint(readerTint)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)

            if supportsFontSize {
                BookDetailCardStyle.divider
                Picker(selection: $settings.textConversion) {
                    ForEach(TextConversion.allCases, id: \.self) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                } label: {
                    SettingsRowLabel(localized("简繁切换"), systemImage: "character.book.closed")
                }
                .tint(readerTint)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
            }
        }
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
    }

    /// 文字颜色跟随当前阅读背景，归到视觉页与亮度管理相邻。
    private var textColorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCardHeader(localized(ReadingSettingsScopeItem.textColor.titleKey))

            ColorPicker(selection: readerTextColorBinding, supportsOpacity: false) {
                SettingsRowLabel(
                    localized(ReadingSettingsScopeItem.textColor.titleKey),
                    systemImage: ReadingSettingsScopeItem.textColor.systemImage
                )
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)

            if hasReaderTextColorOverride {
                BookDetailCardStyle.divider
                Button {
                    setReaderTextColor(nil)
                } label: {
                    SettingsRowLabel(localized("跟隨主題文字顏色"), systemImage: "arrow.counterclockwise", role: .action)
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
            }

            Text(String(
                format: localized("文字顏色只套用到目前的閱讀背景（%@）。"),
                wornSavedBackground?.name ?? theme.localizedTitle
            ))
            .dsSectionFooter()
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.xs)
            .padding(.bottom, DSSpacing.md)
        }
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
    }

    /// The saved background on the page, if one is: its text colour is its own, not the
    /// one set for the built-in background under it.
    private var wornSavedBackground: ReaderCustomBackground? {
        theme.activeReaderBackgroundID.flatMap(settings.readerCustomBackground(id:))
    }

    private var hasReaderTextColorOverride: Bool {
        if let background = wornSavedBackground { return background.textColorHex != nil }
        return settings.readerTextColorOverride(for: theme) != nil
    }

    /// Nil goes back to the colour the background picks for itself.
    private func setReaderTextColor(_ rgbHex: UInt32?) {
        if let background = wornSavedBackground {
            settings.setReaderCustomBackgroundTextColor(rgbHex, id: background.id)
        } else {
            settings.setReaderTextColorOverride(rgbHex, for: theme)
        }
    }

    /// Reads the color the reader is actually painting with, so opening the picker
    /// starts from what is on screen rather than from a blank swatch. Writing one
    /// stores it for the *current* reading background only.
    private var readerTextColorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: theme.uiTextColor) },
            set: { newColor in
                guard let rgbHex = UIColor(newColor).rgbHex else { return }
                setReaderTextColor(rgbHex)
            }
        )
    }

    private var fontSelector: some View {
        HStack(spacing: DSSpacing.sm) {
            Menu {
                Button {
                    settings.selectedReaderFontPostScript = nil
                } label: {
                    Label(defaultFontName, systemImage: settings.selectedReaderFontPostScript == nil ? "checkmark" : "f.cursive")
                }

                if !settings.userFonts.isEmpty {
                    Divider()
                    Section {
                        ForEach(settings.userFonts, id: \.id) { font in
                            Button {
                                settings.selectedReaderFontPostScript = font.postScriptName
                            } label: {
                                Label(
                                    font.displayName,
                                    systemImage: settings.selectedReaderFontPostScript == font.postScriptName ? "checkmark" : "f.cursive"
                                )
                            }
                        }
                    } header: {
                        Text(localized("已匯入字體"))
                            .foregroundStyle(DSColor.textSecondary)
                    }

                    Menu(localized("刪除字體")) {
                        ForEach(settings.userFonts, id: \.id) { font in
                            Button(role: .destructive) {
                                settings.deleteUserFont(font)
                            } label: {
                                Label(font.displayName, systemImage: "trash")
                            }
                        }
                    }
                }

                if !ReaderSettingsPresentationPolicy.requiresFirstLevelImporter {
                    Divider()
                    if premiumVisibility.allowsFontImport {
                        Button {
                            showingFontImporter = true
                        } label: {
                            Label(localized("匯入字體..."), systemImage: "plus")
                        }
                    } else {
                        // Locked: the second `Text` is the menu row's subtitle.
                        Button {
                            requestPaywall(.customFonts)
                        } label: {
                            Text(localized("匯入字體..."))
                            Text(localized("需要 Pro"))
                            Image(systemName: "lock.fill")
                        }
                    }
                }
            } label: {
                LabeledContent {
                    HStack(spacing: DSSpacing.xs) {
                        Text(currentFontName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(DSFont.footnote)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(DSColor.textSecondary)
                } label: {
                    SettingsRowLabel(
                        localized(ReadingSettingsScopeItem.font.titleKey),
                        systemImage: ReadingSettingsScopeItem.font.systemImage
                    )
                }
            }
            .buttonStyle(.plain)

            if ReaderSettingsPresentationPolicy.requiresFirstLevelImporter {
                let locked = !premiumVisibility.allowsFontImport
                Button {
                    if locked {
                        requestPaywall(.customFonts)
                    } else {
                        onOpenFontImporter()
                    }
                } label: {
                    Image(systemName: locked ? "lock.fill" : "plus")
                }
                .accessibilityLabel(localized("匯入字體..."))
                .accessibilityValue(locked ? localized("需要 Pro") : "")
            }
        }
    }

    // MARK: - 排版

    /// Spacing and the three body margins, together: they are all "how the text sits on
    /// the page", and they used to be two sections with two different ways to reset.
    ///
    /// 上下邊距 means the same thing in both modes. It used to not: paged mode took its
    /// vertical margin from the header/footer layout's hand-tuned "content reservation"
    /// while scroll mode used `pageMarginV`. The bars' heights are known now, so the
    /// margin no longer has to absorb them.
    private var layoutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCardHeader(localized("排版细节"))

            if allowsVerticalWritingMode {
                Picker(selection: $settings.readerWritingMode) {
                    Text(localized("横排")).tag(ReaderWritingMode.horizontal)
                    Text(localized("竖排")).tag(ReaderWritingMode.verticalRTL)
                } label: {
                    SettingsRowLabel(localized(ReadingSettingsScopeItem.writingMode.titleKey),
                                     systemImage: ReadingSettingsScopeItem.writingMode.systemImage)
                }
                .tint(readerTint)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
            }

            if supportsSpacing {
                readerSliderRow(
                    title: localized(ReadingSettingsScopeItem.lineSpacing.titleKey),
                    systemImage: ReadingSettingsScopeItem.lineSpacing.systemImage,
                    valueText: String(format: "%.2f", readerConfig.lineHeightMultiple),
                    value: $readerConfig.lineHeightMultiple,
                    range: 1.0...2.4,
                    step: 0.05
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
                readerSliderRow(
                    title: localized(ReadingSettingsScopeItem.letterSpacing.titleKey),
                    systemImage: ReadingSettingsScopeItem.letterSpacing.systemImage,
                    valueText: "\(String(format: "%.1f", readerConfig.letterSpacing)) pt",
                    value: $readerConfig.letterSpacing,
                    range: 0...12,
                    step: 0.5
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
                readerSliderRow(
                    title: localized(ReadingSettingsScopeItem.paragraphSpacing.titleKey),
                    systemImage: ReadingSettingsScopeItem.paragraphSpacing.systemImage,
                    valueText: String(format: "%.2f", readerConfig.paragraphSpacingMultiplier),
                    value: $readerConfig.paragraphSpacingMultiplier,
                    range: 0.3...1.2,
                    step: 0.05
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
            }

            if supportsLineHeight {
                readerSliderRow(
                    title: localized("左右邊距"),
                    systemImage: ReadingSettingsScopeItem.pageMargins.systemImage,
                    valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(readerConfig.pageMarginH)),
                    value: $readerConfig.pageMarginH,
                    range: 0...50,
                    step: 1
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
                readerSliderRow(
                    title: localized("上邊距"),
                    systemImage: "arrow.up.to.line",
                    valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(readerConfig.pageMarginTop)),
                    value: $readerConfig.pageMarginTop,
                    range: 0...50,
                    step: 1
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
                readerSliderRow(
                    title: localized("下邊距"),
                    systemImage: "arrow.down.to.line",
                    valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(readerConfig.pageMarginBottom)),
                    value: $readerConfig.pageMarginBottom,
                    range: 0...50,
                    step: 1
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
            }

            Button(role: .destructive) {
                showingLayoutResetConfirmation = true
            } label: {
                SettingsRowLabel(localized("重設排版"), systemImage: "arrow.counterclockwise", role: .destructive)
            }
            .disabled(!hasCustomLayout)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)

            if supportsLineHeight, !settings.scrollMode {
                Text(localized("上下边距同时是眉脚的容身空间，改动不会移动眉脚本身。"))
                    .dsSectionFooter()
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.top, DSSpacing.xs)
                    .padding(.bottom, DSSpacing.md)
            }
        }
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
    }

    private var hasCustomLayout: Bool {
        let spacing = supportsSpacing && (
            abs(readerConfig.lineHeightMultiple - defaultLineHeightMultiple) > 0.001
                || abs(readerConfig.letterSpacing - defaultLetterSpacing) > 0.001
                || abs(readerConfig.paragraphSpacingMultiplier - defaultParagraphSpacingMultiplier) > 0.001
        )
        let margins = supportsLineHeight && (
            abs(readerConfig.pageMarginH - defaultPageMarginH) > 0.001
                || abs(readerConfig.pageMarginTop - defaultPageMarginV) > 0.001
                || abs(readerConfig.pageMarginBottom - defaultPageMarginV) > 0.001
        )
        return spacing || margins
    }

    /// The bars' own space is computed from their height, so there is no separate
    /// reservation left to reset here — only what this section shows.
    private func resetLayout() {
        if supportsSpacing {
            readerConfig.lineHeightMultiple = defaultLineHeightMultiple
            readerConfig.letterSpacing = defaultLetterSpacing
            readerConfig.paragraphSpacingMultiplier = defaultParagraphSpacingMultiplier
        }
        if supportsLineHeight {
            readerConfig.pageMarginH = defaultPageMarginH
            readerConfig.pageMarginV = defaultPageMarginV
            readerConfig.pageMarginTop = defaultPageMarginV
            readerConfig.pageMarginBottom = defaultPageMarginV
        }
    }

    // MARK: - 頁首頁尾與標題

    /// Pushed pages, not sheets handed back to the reader to present. This sheet is
    /// already inside a `NavigationStack`, so pushing keeps the whole flow at one
    /// presentation level — the iOS 17 sheet-from-sheet trap never arises.
    private var headerFooterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCardHeader(localized("眉脚与标题"))

            NavigationLink {
                ReaderBarLayoutEditorView(
                    theme: theme,
                    readerSafeTop: readerSafeTop,
                    readerSafeBottom: readerSafeBottom
                )
            } label: {
                navigationRowLabel(
                    title: localized("頁首頁尾編輯"),
                    systemImage: ReadingSettingsScopeItem.headerFooter.systemImage
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(DSColor.textPrimary)

            if supportsLineHeight {
                BookDetailCardStyle.divider
                NavigationLink {
                    ChapterTitleStyleSettingsView(
                        onOpenImporter: { requestStyleImporter(.chapterTitleStyle) }
                    )
                } label: {
                    navigationRowLabel(
                        title: localized(ReadingSettingsScopeItem.chapterTitle.titleKey),
                        systemImage: ReadingSettingsScopeItem.chapterTitle.systemImage
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.textPrimary)
            }

            BookDetailCardStyle.divider
            Button(role: .destructive) {
                showingOverlayResetConfirmation = true
            } label: {
                SettingsRowLabel(localized("重設頁首頁尾"), systemImage: "arrow.counterclockwise", role: .destructive)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)

            Text(localized("正文与眉脚的间距在「排版细节」的上下边距调整。"))
                .dsSectionFooter()
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
        }
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
    }

    /// Writes the archive under `name` — 閱讀設定 when left blank — and hands it to the
    /// share sheet. The values are read now, on the main actor; the zip is made off it.
    private func exportReaderSettings(named name: String) {
        let inputs = ReaderSettingsExportSnapshot.make()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            do {
                let url = try await ReaderSettingsExportFile.write(
                    inputs,
                    named: trimmed.isEmpty ? localized("阅读偏好") : trimmed
                )
                SystemShareSheet.present(fileURL: url)
            } catch {
                AppLogger.error("⟐ reading settings export failed", error: error)
                layoutImportAlert = LayoutImportAlert(
                    titleKey: "匯出失敗",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func resetReaderOverlayLayout() {
        guard settings.saveReaderBarLayout(.default) else {
            layoutImportAlert = LayoutImportAlert(
                titleKey: "無法儲存頁首頁尾設定",
                message: localized("請稍後再試。")
            )
            return
        }
    }

    // MARK: - 閱讀裝飾

    private var readerDecorationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCardHeader(localized("阅读装饰"))

            if premiumVisibility.showsReaderDecoration {
                if showsCommentBubbleSettings {
                    NavigationLink {
                        ReaderCommentBubbleSettingsView()
                    } label: {
                        navigationRowLabel(
                            title: localized("氣泡設定"),
                            systemImage: ReadingSettingsScopeItem.commentBubble.systemImage
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.textPrimary)
                    BookDetailCardStyle.divider
                }

                NavigationLink {
                    ReaderDialogueBubbleSettingsView(
                        style: settings.dialogueBubbleStyle,
                        onOpenImporter: { requestStyleImporter(.dialogueBubble) },
                        onChange: { settings.dialogueBubbleStyle = $0 }
                    )
                } label: {
                    navigationValueRowLabel(
                        title: localized(ReadingSettingsScopeItem.dialogueBubble.titleKey),
                        systemImage: ReadingSettingsScopeItem.dialogueBubble.systemImage,
                        value: onOffText(settings.dialogueBubbleStyle.isEnabled)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.textPrimary)
                BookDetailCardStyle.divider

                NavigationLink {
                    RegexHighlightSettingsView(
                        configuration: settings.regexHighlightConfiguration,
                        onOpenImporter: { requestStyleImporter(.regexHighlights) },
                        onChange: { settings.regexHighlightConfiguration = $0 }
                    )
                } label: {
                    navigationValueRowLabel(
                        title: localized(ReadingSettingsScopeItem.regexHighlight.titleKey),
                        systemImage: ReadingSettingsScopeItem.regexHighlight.systemImage,
                        value: onOffText(settings.regexHighlightConfiguration.isEnabled)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.textPrimary)
                BookDetailCardStyle.divider

                NavigationLink {
                    ReaderTextUnderlineSettingsView()
                } label: {
                    navigationValueRowLabel(
                        title: localized(ReadingSettingsScopeItem.textUnderline.titleKey),
                        systemImage: ReadingSettingsScopeItem.textUnderline.systemImage,
                        value: onOffText(settings.readerTextUnderlineDecorationEnabled)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.textPrimary)
            } else {
                ForEach(Array(lockedDecorationItems.enumerated()), id: \.element.rawValue) { index, item in
                    if index > 0 {
                        BookDetailCardStyle.divider
                    }
                    SettingsLockedRow(
                        title: localized(item == .commentBubble ? "氣泡設定" : item.titleKey),
                        systemImage: item.systemImage
                    ) {
                        requestPaywall(.dialogueHighlight)
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                }
            }
        }
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
    }

    /// The same rows, in the same order, as with Pro.
    private var lockedDecorationItems: [ReadingSettingsScopeItem] {
        (hasParagraphReviews ? [.commentBubble] : []) + [.dialogueBubble, .regexHighlight, .textUnderline]
    }

    private func onOffText(_ isOn: Bool) -> String {
        localized(isOn ? "已開啟" : "已關閉")
    }

    // MARK: - 翻頁與手勢

    private var pagingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCardHeader(localized("翻页习惯"))

            if supportsPageDisplay {
                Picker(selection: $settings.readerSpreadMode) {
                    ForEach(ReaderSpreadMode.settingsCases, id: \.self) { mode in
                        Text(localized(spreadTitleKey(for: mode))).tag(mode)
                    }
                } label: {
                    SettingsRowLabel(localized("翻页方向"), systemImage: "rectangle.portrait.on.rectangle.portrait")
                }
                .tint(readerTint)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
            }

            Toggle(isOn: $settings.readerTapBothSidesNextPage) {
                SettingsRowLabel(localized("双侧翻页"), systemImage: "hand.tap")
            }
            .tint(readerTint)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            BookDetailCardStyle.divider

            Toggle(isOn: $settings.readerSwipeUpToExit) {
                SettingsRowLabel(localized("上滑离开"), systemImage: "rectangle.portrait.and.arrow.right")
            }
            .tint(readerTint)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            BookDetailCardStyle.divider

            Toggle(isOn: $settings.readerPullDownToBookmark) {
                SettingsRowLabel(localized("下拉加入书签"), systemImage: "bookmark")
            }
            .tint(readerTint)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)

            if let onOpenTouchZoneEditor {
                BookDetailCardStyle.divider
                if premiumVisibility.showsTouchZoneEditor {
                    Button {
                        dismiss()
                        DispatchQueue.main.async { onOpenTouchZoneEditor() }
                    } label: {
                        SettingsRowLabel(localized("触控区域"), systemImage: "square.grid.3x3", role: .action)
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                } else {
                    SettingsLockedRow(title: localized("触控区域"), systemImage: "square.grid.3x3") {
                        requestPaywall(.touchZoneEditor)
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                }
            }

            Text(localized("双侧翻页：点画面左右两侧都翻到下一页，中间仍呼出菜单。上滑离开与下拉加入书签都要滑过一半再松手。"))
                .dsSectionFooter()
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
        }
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
    }

    private func spreadTitleKey(for mode: ReaderSpreadMode) -> String {
        switch mode {
        case .singlePage: return "單頁"
        case .doublePage: return "雙頁"
        case .auto: return "單頁"
        }
    }

    // MARK: - 亮度

    /// 亮度管理卡片：跟随系统开关 + 手动亮度滑块，与视觉页其它卡片同一种容器。
    private var brightnessCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCardHeader(localized("亮度管理"))

            Toggle(isOn: followSystemBrightnessBinding) {
                SettingsRowLabel(localized("自动亮度"), systemImage: "sun.max")
            }
            .tint(readerTint)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            BookDetailCardStyle.divider

            readerSliderRow(
                title: localized("閱讀亮度"),
                systemImage: "sun.min",
                valueText: "\(Int(settings.readerBrightness * 100))%",
                value: readerBrightnessBinding,
                range: 0.05...1.0,
                step: 0.05,
                isEnabled: !settings.followSystemBrightness
            )
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
    }

    private var followSystemBrightnessBinding: Binding<Bool> {
        Binding(
            get: { settings.followSystemBrightness },
            set: { follow in
                settings.followSystemBrightness = follow
                if follow {
                    syncBrightnessFromSystem()
                } else {
                    UIScreen.main.brightness = CGFloat(settings.readerBrightness)
                }
            }
        )
    }

    private var readerBrightnessBinding: Binding<Double> {
        Binding(
            get: { settings.readerBrightness },
            set: { value in
                settings.readerBrightness = value
                if !settings.followSystemBrightness {
                    UIScreen.main.brightness = CGFloat(value)
                }
            }
        )
    }

    private func syncBrightnessFromSystem() {
        settings.readerBrightness = Double(UIScreen.main.brightness)
    }

    // MARK: - 閱讀設定備份

    /// 偏好备份卡片：匯出/匯入 the whole of 閱讀設定 in one file: layout parameters,
    /// the chapter title style, and the regex highlight rules. Each of those two styles
    /// keeps its own single-purpose export on its own page; this is the "move my whole
    /// reading setup to the new phone" file.
    private var readerSettingsBackupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCardHeader(localized("偏好备份"))

            if premiumVisibility.showsLayoutPresetImport {
                Button {
                    readerSettingsExportName = localized("阅读偏好")
                    showingReaderSettingsExport = true
                } label: {
                    SettingsRowLabel(localized("导出偏好"), systemImage: "square.and.arrow.up", role: .action)
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                // The file is named first, then shared: the file name is all that
                // tells one exported setup from another.
                .alert(localized("导出偏好"), isPresented: $showingReaderSettingsExport) {
                    TextField(localized("名稱"), text: $readerSettingsExportName)
                    Button(localized("匯出")) {
                        exportReaderSettings(named: readerSettingsExportName)
                    }
                    Button(localized("取消"), role: .cancel) {}
                }
                BookDetailCardStyle.divider

                Button {
                    requestStyleImporter(.readerSettings)
                } label: {
                    SettingsRowLabel(localized("导入偏好"), systemImage: "square.and.arrow.down", role: .action)
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
            } else {
                SettingsLockedRow(title: localized("导出偏好"), systemImage: "square.and.arrow.up") {
                    requestPaywall(.layoutPresetImport)
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                BookDetailCardStyle.divider
                SettingsLockedRow(title: localized("导入偏好"), systemImage: "square.and.arrow.down") {
                    requestPaywall(.layoutPresetImport)
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
            }

            Text(localized("包含排版细节、章节标题样式与正则高亮。导入也接受 legado 的 readConfig.json。"))
                .dsSectionFooter()
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
        }
        .background(BookDetailCardStyle.background)
        .overlay(BookDetailCardStyle.border)
    }

    // MARK: - Presenting

    /// A locked control's paywall: from this sheet on iOS 18, from the reader on iOS 17
    /// (`onOpenPaywall`), where a sheet asked for from inside this one can be dropped.
    private func requestPaywall(_ feature: PremiumFeature) {
        if let onOpenPaywall {
            onOpenPaywall(feature)
        } else {
            paywallFeature = feature
        }
    }

    /// iOS 17 cannot present a document picker from this sheet — hand it to the
    /// reader's first-level presenter instead. See
    /// `Technotes/iOS17MenuModalPresentation.md`.
    private func requestStyleImporter(_ route: ReaderStyleImportRoute) {
        guard ReaderSettingsPresentationPolicy.requiresFirstLevelImporter,
              let onOpenStyleImporter else {
            styleImportRoute = route
            return
        }
        // The caller dismisses this sheet and presents from its real `onDismiss`
        // — an event boundary, never a timed delay.
        onOpenStyleImporter(route)
    }

    // MARK: - Preview

    /// Preview font that reflects the user-selected reader font in real time;
    /// falls back to the system font when none is selected (or it can't be loaded).
    private func previewFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let isBold = readerConfig.readerFontBold
        let resolvedWeight: Font.Weight = isBold ? .bold : weight
        if let postScript = settings.selectedReaderFontPostScript,
           !postScript.isEmpty,
           let uiFont = UIFont(name: postScript, size: size) {
            if isBold,
               let descriptor = uiFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                return Font(UIFont(descriptor: descriptor, size: size) as CTFont)
            }
            return Font(uiFont as CTFont)
        }
        return .system(size: size, weight: resolvedWeight)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(localized("大"))
                    .font(previewFont(size: 34))

                Text(localized("小"))
                    .font(previewFont(size: 18))
                    .baselineOffset(-6)
            }
            Text(localized("  這是一段測試文字，用來測試字體大小和行距、字距、段落間距，以及不同主題下的閱讀舒適度。調整設定時，可以觀察文字密度、換行節奏與背景對比是否符合你的閱讀習慣。"))
                .font(previewFont(size: min(max(fontSize, 17), 24)))
                .lineSpacing(readerConfig.lineSpacing)
                .tracking(readerConfig.letterSpacing)
                .foregroundStyle(theme.textColor)
        }
        .padding(.horizontal, readerConfig.pageMarginH)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, minHeight: previewTextHeight, maxHeight: previewTextHeight, alignment: .topLeading)
        .clipped()
        .foregroundStyle(theme.textColor)
        .background(theme.backgroundColor)
    }

    // MARK: - Fonts

    private var fontSizeBinding: Binding<CGFloat> {
        Binding(
            get: { fontSize },
            set: { fontSize = GlobalSettings.clampedReaderFontSize($0) }
        )
    }

    private var defaultFontName: String {
        localized(usesPublicationFontDefault ? "書籍預設字體" : "系統字體")
    }

    private var currentFontName: String {
        guard let selected = settings.selectedReaderFontPostScript else { return defaultFontName }
        return settings.userFonts.first { $0.postScriptName == selected }?.displayName ?? selected
    }

    static let fontContentTypes: [UTType] = [
        .font,
        UTType(filenameExtension: "ttf") ?? .data,
        UTType(filenameExtension: "otf") ?? .data,
    ]

    private func handleFontImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try settings.importReaderFont(from: url)
        } catch {
            fontImportError = FontImportError(message: error.localizedDescription)
        }
    }
}

private struct FontImportError: Identifiable {
    let id = UUID()
    let message: String
}

private struct LayoutImportAlert: Identifiable {
    let id = UUID()
    let titleKey: String
    let message: String
}

#Preview {
    ReaderSettingsView(
        fontSize: .constant(18),
        theme: .constant(.sepia),
        capabilities: .reflowableText,
        allowsUserSelectedReaderFont: true,
        allowsVerticalWritingMode: true,
        onOpenFontImporter: {}
    )
}
