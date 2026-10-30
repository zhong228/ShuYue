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

    /// 全页统一强调色：书悦朱砂红 `DSColor.appAccent`，滑块 / 开关 / 选择器的焦点都收
    /// 到同一支笔，不再随阅读主题漂移（2026-10-30）。
    private var readerTint: Color {
        DSColor.appAccent
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

            // 三页横向面板：版式 / 视觉 / 习惯。下划线式顶部 Tab 与页面滑动双向同步，
            // 替代原来的胶囊标签条与一条长 Form 的顺序分区（2026-10-30）。
            settingsTabStrip

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
                    .accessibilityLabel(localized("关闭"))
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
                title: Text(localized("字体汇入失败")),
                message: Text(error.message),
                dismissButton: .default(Text(localized("确定")))
            )
        }
        .alert(item: $layoutImportAlert) { alert in
            Alert(
                title: Text(localized(alert.titleKey)),
                message: Text(alert.message),
                dismissButton: .default(Text(localized("确定")))
            )
        }
        .alert(
            localized("重设页首页尾？"),
            isPresented: $showingOverlayResetConfirmation
        ) {
            Button(localized("重设"), role: .destructive) {
                resetReaderOverlayLayout()
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("这会恢复预设的栏位配置与样式。"))
        }
        .alert(
            localized("重设排版？"),
            isPresented: $showingLayoutResetConfirmation
        ) {
            Button(localized("重设"), role: .destructive) {
                resetLayout()
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("行距、字距、段距与页面边距会回到预设值。"))
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

    /// 三页下划线式顶部 Tab：版式 / 视觉 / 习惯，等宽三段、文字 + 小图标。选中项文字
    /// 用 `DSColor.textPrimary` 并配底部 3pt 圆角强调色下划线，未选中 `DSColor.textSecondary`，
    /// 废弃原来的胶囊填充样式（2026-10-30）。与下方 TabView 双向同步。
    private var settingsTabStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(ReaderSettingsPage.allCases) { page in
                    settingsTabButton(page)
                }
            }
            Divider()
                .background(DSColor.separator)
        }
        .padding(.top, DSSpacing.sm)
        .padding(.horizontal, DSSpacing.lg)
        .accessibilityLabel(localized("阅读偏好分页"))
    }

    private func settingsTabButton(_ page: ReaderSettingsPage) -> some View {
        let selected = selectedPage == page
        return Button {
            withAnimation(DSAnimation.standard) {
                selectedPage = page
            }
        } label: {
            VStack(spacing: DSSpacing.xxs) {
                HStack(spacing: 5) {
                    Image(systemName: page.icon)
                        .font(DSFont.fixed(size: 13, weight: .medium))
                    Text(localized(page.titleKey))
                        .font(DSFont.subheadline.weight(.semibold))
                }
                .foregroundColor(selected ? DSColor.textPrimary : DSColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.sm)

                Capsule()
                    .fill(selected ? readerTint : Color.clear)
                    .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 卡片基础件

    /// 卡片顶部的小标题：正文行前的一点明示，替代 Form Section 的 header。朱砂短
    /// 刻度 + 主色标题，统一书卷视觉语言（2026-10-30）。
    private func settingsCardHeader(_ title: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Capsule()
                .fill(DSColor.appAccent)
                .frame(width: 3, height: 14)
            Text(title)
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.md)
        .padding(.bottom, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 卡片内的细分隔线：左右收进 `DSSpacing.md`，与行内容对齐，颜色 `DSColor.separator`。
    private var settingsDivider: some View {
        Divider()
            .background(DSColor.separator)
            .padding(.horizontal, DSSpacing.md)
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

    /// The same row with the control's current value between title and chevron. The
    /// value rides in a 通栏行卡的右对齐圆角胶囊（`DSColor.appAccentSoft` 背景）。
    private func navigationValueRowLabel(title: String, systemImage: String, value: String) -> some View {        HStack(spacing: DSSpacing.sm) {
            SettingsRowLabel(title, systemImage: systemImage)
            Spacer(minLength: DSSpacing.sm)
            Text(value)
                .font(DSFont.caption.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DSColor.appAccentSoft, in: Capsule())
            Image(systemName: "chevron.right")
                .font(DSFont.caption2)
                .foregroundStyle(DSColor.textSecondary.opacity(0.7))
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .contentShape(Rectangle())
    }

    /// 圆形按钮化步进器按钮：强调色图标 + `DSColor.appAccentSoft` 圆形底盘，替代系统
    /// 矩形步进器（2026-10-30）。
    private func circularStepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DSFont.fixed(size: 13, weight: .semibold))
                .foregroundStyle(DSColor.appAccent)
                .frame(width: 30, height: 30)
                .background(DSColor.appAccentSoft, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(localized("调整字号"))
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
                    .foregroundStyle(DSColor.appAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DSColor.appAccentSoft, in: Capsule())
            }
            .accessibilityHidden(true)

            Slider(value: value, in: range, step: step)
                .tint(readerTint)
                .controlSize(.large)
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
                        localized("排版生效范围"),
                        systemImage: "paintpalette"
                    )
                    Spacer(minLength: DSSpacing.sm)
                    Text(scopeSummary(themeItems))
                        .font(DSFont.caption.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DSColor.appAccentSoft, in: Capsule())
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
                    format: localized("跟随主题的设定，改动会存进目前的主题「%@」。"),
                    settings.readingSettingsThemeName
                ))
                .dsSectionFooter()
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
            }
        }
        .settingsCardStyle()
    }

    private func scopeSummary(_ themeItems: Set<ReadingSettingsScopeItem>) -> String {
        if themeItems.isEmpty { return localized("全部跟随全域") }
        if themeItems.count == ReadingSettingsScopeItem.allCases.count { return localized("全部跟随主题") }
        return String(format: localized("%d 项跟随主题"), themeItems.count)
    }

    // MARK: - 文字

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCardHeader(localized("版式"))

            if supportsUserFont {
                fontSelector
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                settingsDivider
            }

            if supportsFontSize {
                HStack(spacing: DSSpacing.sm) {
                    SettingsRowLabel(
                        localized(ReadingSettingsScopeItem.fontSize.titleKey),
                        systemImage: ReadingSettingsScopeItem.fontSize.systemImage
                    )
                    Spacer(minLength: DSSpacing.sm)
                    circularStepButton(systemImage: "minus") {
                        let next = floor(fontSizeBinding.wrappedValue) - 1
                        fontSizeBinding.wrappedValue = max(GlobalSettings.readerFontSizeRange.lowerBound, next)
                    }
                    Text(String(format: localized("ReaderOverlay.Format.Points"), Int(fontSizeBinding.wrappedValue)))
                        .font(DSFont.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(minWidth: 46)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DSColor.appAccentSoft, in: Capsule())
                    circularStepButton(systemImage: "plus") {
                        let next = ceil(fontSizeBinding.wrappedValue) + 1
                        fontSizeBinding.wrappedValue = min(GlobalSettings.readerFontSizeRange.upperBound, next)
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                settingsDivider
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
                settingsDivider
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
        .settingsCardStyle()
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
                settingsDivider
                Button {
                    setReaderTextColor(nil)
                } label: {
                    SettingsRowLabel(localized("跟随主题文字颜色"), systemImage: "arrow.counterclockwise", role: .action)
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
            }

            Text(String(
                format: localized("文字颜色只套用到目前的阅读背景（%@）。"),
                wornSavedBackground?.name ?? theme.localizedTitle
            ))
            .dsSectionFooter()
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.xs)
            .padding(.bottom, DSSpacing.md)
        }
        .settingsCardStyle()
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
                        Text(localized("已汇入字体"))
                            .foregroundStyle(DSColor.textSecondary)
                    }

                    Menu(localized("删除字体")) {
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
                            Label(localized("汇入字体..."), systemImage: "plus")
                        }
                    } else {
                        // Locked: the second `Text` is the menu row's subtitle.
                        Button {
                            requestPaywall(.customFonts)
                        } label: {
                            Text(localized("汇入字体..."))
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
                .accessibilityLabel(localized("汇入字体..."))
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
                settingsDivider
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
                settingsDivider
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
                settingsDivider
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
                settingsDivider
            }

            if supportsLineHeight {
                readerSliderRow(
                    title: localized("左右边距"),
                    systemImage: ReadingSettingsScopeItem.pageMargins.systemImage,
                    valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(readerConfig.pageMarginH)),
                    value: $readerConfig.pageMarginH,
                    range: 0...50,
                    step: 1
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                settingsDivider
                readerSliderRow(
                    title: localized("上边距"),
                    systemImage: "arrow.up.to.line",
                    valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(readerConfig.pageMarginTop)),
                    value: $readerConfig.pageMarginTop,
                    range: 0...50,
                    step: 1
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                settingsDivider
                readerSliderRow(
                    title: localized("下边距"),
                    systemImage: "arrow.down.to.line",
                    valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(readerConfig.pageMarginBottom)),
                    value: $readerConfig.pageMarginBottom,
                    range: 0...50,
                    step: 1
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                settingsDivider
            }

            Button(role: .destructive) {
                showingLayoutResetConfirmation = true
            } label: {
                SettingsRowLabel(localized("重设排版"), systemImage: "arrow.counterclockwise", role: .destructive)
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
        .settingsCardStyle()
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
                    title: localized("页首页尾编辑"),
                    systemImage: ReadingSettingsScopeItem.headerFooter.systemImage
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(DSColor.textPrimary)

            if supportsLineHeight {
                settingsDivider
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

            settingsDivider
            Button(role: .destructive) {
                showingOverlayResetConfirmation = true
            } label: {
                SettingsRowLabel(localized("重设页首页尾"), systemImage: "arrow.counterclockwise", role: .destructive)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)

            Text(localized("正文与眉脚的间距在「排版细节」的上下边距调整。"))
                .dsSectionFooter()
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
        }
        .settingsCardStyle()
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
                    titleKey: "汇出失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func resetReaderOverlayLayout() {
        guard settings.saveReaderBarLayout(.default) else {
            layoutImportAlert = LayoutImportAlert(
                titleKey: "无法储存页首页尾设定",
                message: localized("请稍后再试。")
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
                            title: localized("气泡设定"),
                            systemImage: ReadingSettingsScopeItem.commentBubble.systemImage
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.textPrimary)
                    settingsDivider
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
                settingsDivider

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
                settingsDivider

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
                        settingsDivider
                    }
                    SettingsLockedRow(
                        title: localized(item == .commentBubble ? "气泡设定" : item.titleKey),
                        systemImage: item.systemImage
                    ) {
                        requestPaywall(.dialogueHighlight)
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                }
            }
        }
        .settingsCardStyle()
    }

    /// The same rows, in the same order, as with Pro.
    private var lockedDecorationItems: [ReadingSettingsScopeItem] {
        (hasParagraphReviews ? [.commentBubble] : []) + [.dialogueBubble, .regexHighlight, .textUnderline]
    }

    private func onOffText(_ isOn: Bool) -> String {
        localized(isOn ? "已开启" : "已关闭")
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
                settingsDivider
            }

            Toggle(isOn: $settings.readerTapBothSidesNextPage) {
                SettingsRowLabel(localized("双侧翻页"), systemImage: "hand.tap")
            }
            .tint(readerTint)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            settingsDivider

            Toggle(isOn: $settings.readerSwipeUpToExit) {
                SettingsRowLabel(localized("上滑离开"), systemImage: "rectangle.portrait.and.arrow.right")
            }
            .tint(readerTint)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            settingsDivider

            Toggle(isOn: $settings.readerPullDownToBookmark) {
                SettingsRowLabel(localized("下拉加入书签"), systemImage: "bookmark")
            }
            .tint(readerTint)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)

            if let onOpenTouchZoneEditor {
                settingsDivider
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
        .settingsCardStyle()
    }

    private func spreadTitleKey(for mode: ReaderSpreadMode) -> String {
        switch mode {
        case .singlePage: return "单页"
        case .doublePage: return "双页"
        case .auto: return "单页"
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
            settingsDivider

            readerSliderRow(
                title: localized("阅读亮度"),
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
        .settingsCardStyle()
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
                    TextField(localized("名称"), text: $readerSettingsExportName)
                    Button(localized("汇出")) {
                        exportReaderSettings(named: readerSettingsExportName)
                    }
                    Button(localized("取消"), role: .cancel) {}
                }
                settingsDivider

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
                settingsDivider
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
        .settingsCardStyle()
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

    /// 顶部实时预览区：一张完整圆角预览卡（`DSRadius.xl`、按当前阅读主题着色背景、
    /// 内边距 `DSSpacing`），卡内居中 3–4 行固定样张，字号/行距实时跟随设置但**限制最大
    /// 显示尺寸**（固定容器高度 + `minimumScaleFactor`/`lineLimit`，绝不溢出重叠）。右上角
    /// 一枚小号强调色徽章显示当前字号。预览卡与下方设置区视觉分离（2026-10-30）。
    private var previewPanel: some View {
        previewCard
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.md)
    }

    private var previewCard: some View {
        ZStack(alignment: .topTrailing) {
            previewSample
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xxl)
                .padding(.bottom, DSSpacing.md)

            fontSizeBadge
                .padding(DSSpacing.sm)
        }
        .frame(maxWidth: .infinity, minHeight: previewTextHeight, maxHeight: previewTextHeight)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                .fill(theme.wrappedValue.backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                .stroke(DSColor.separator, lineWidth: 1)
        )
    }

    /// 右上角小号强调色徽章：当前字号（`%d pt`）。
    private var fontSizeBadge: some View {
        Text(String(format: localized("ReaderOverlay.Format.Points"), Int(fontSize)))
            .font(DSFont.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(DSColor.appAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DSColor.appAccentSoft, in: Capsule())
    }

    /// 居中样张：字号/行距实时跟随设置，但固定容器高度 + `minimumScaleFactor`/`lineLimit`
    /// 双重钳制，绝不溢出重叠（修掉旧版"大""小"标题与样张混排的 bug）。
    private var previewSample: some View {
        Text(localized("这是一段测试文字，用来测试字体大小和行距、字距、段落间距，以及不同主题下的阅读舒适度。调整设定时，可以观察文字密度、换行节奏与背景对比是否符合你的阅读习惯。"))
            .font(previewFont(size: min(max(fontSize, 17), 24)))
            .lineSpacing(readerConfig.lineSpacing)
            .tracking(readerConfig.letterSpacing)
            .foregroundStyle(theme.textColor)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Fonts

    private var fontSizeBinding: Binding<CGFloat> {
        Binding(
            get: { fontSize },
            set: { fontSize = GlobalSettings.clampedReaderFontSize($0) }
        )
    }

    private var defaultFontName: String {
        localized(usesPublicationFontDefault ? "书籍预设字体" : "系统字体")
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

// MARK: - 卡片容器修饰

private extension View {
    /// 统一圆角卡片容器：暖纸面 `DSColor.surface` + `DSRadius.xl` + 细分隔边框 + 轻投影，
    /// 替代原本朴素的 `BookDetailCardStyle`（2026-10-30）。
    func settingsCardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                    .fill(DSColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                    .stroke(DSColor.separator, lineWidth: 1)
            )
            .shadow(color: DSColor.shadow, radius: 10, x: 0, y: 4)
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
