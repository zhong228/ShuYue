import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One screen-level message alert, so the import-failure and import-summary
/// paths share a presenter instead of competing for one.
struct ThemeScreenAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct AppearanceThemeView: View {
    @ObservedObject private var settings = GlobalSettings.shared
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The paywall, opened on the feature the locked control belongs to.
    @State private var paywallFeature: PremiumFeature?

    /// 新建's name prompt, and the name typed into it.
    @State private var showNewThemeAlert = false
    @State private var newThemeName = ""
    /// The theme a long press on its tile opened 重命名／删除 for.
    @State private var themeActionTarget: AppearanceThemePreset?
    /// The tile lifted by that long press — up before the alert, down once it goes.
    @State private var liftedThemeID: String?
    /// The theme being renamed, and the name typed so far.
    @State private var renameTarget: AppearanceThemePreset?
    @State private var renameText = ""
    /// The theme 主題管理's 删除主題 is asking about.
    @State private var deleteTarget: AppearanceThemePreset?
    @State private var showThemeImporter = false
    @State private var showResetAppearanceConfirm = false
    @State private var screenAlert: ThemeScreenAlert?
    /// The 匯入完成 sheet, up from the moment an import starts writing.
    @State private var importProgress: CustomizationImportProgress?
    /// Appearance the theme grid is editing: the 浅色／深色 tab's, which the whole window
    /// wears (`GlobalSettings.appearanceWindowColorScheme`), otherwise the one on screen.
    /// Read from the setting rather than `colorScheme` so a pick lands on the slot just
    /// chosen even before the window has redrawn in it.
    private var editingScheme: ColorScheme {
        guard settings.showsAppearanceSlotTab else { return colorScheme }
        return settings.appearanceSlotOnTab(windowColorScheme: colorScheme)
    }

    private var isProActive: Bool {
        subscriptionStore.hasAccess(.readerThemePacks)
    }

    /// Theme selected in the edited slot, as its *identity* — the grid compares
    /// ids and the 新建 / 保存 actions copy from it, so it must not be swapped for
    /// a derived dark palette here.
    private var selectedTheme: AppearanceThemePreset {
        settings.appearanceBaseTheme(
            for: editingScheme,
            isProActive: subscriptionStore.hasAccess(.readerThemePacks)
        )
    }

    /// Theme painting the app right now. Drives this screen's own tint.
    private var activeTheme: AppearanceThemePreset {
        settings.appearanceTheme(
            for: colorScheme,
            isProActive: subscriptionStore.hasAccess(.readerThemePacks)
        )
    }

    /// The selected theme when it is one of the user's own — the one 删除主題 acts on.
    private var selectedCustomTheme: AppearanceCustomTheme? {
        settings.customAppearanceThemes.first { $0.id == selectedTheme.id }
    }

    private var customThemes: [AppearanceThemePreset] {
        settings.customAppearanceThemes.map(AppearanceThemePreset.preset(from:))
    }

    private var gridColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 4 : 5
        return Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md), count: count)
    }

    var body: some View {
        // Grouped as the reference the user handed over (2026-09-29): which theme and how
        // it follows light and dark, then 介面 (what surrounds the content), 外觀 (the
        // theme's colours, the page behind it, its effects — each a page of its own),
        // and the themes themselves. A theme no longer opens a page of its own. Every
        // row wears `SettingsRowLabel`, as 設定 and 閱讀設定 do.
        // 分组卡片：视觉方案 / 界面 / 外观 / 主题库 四张卡片，替代系统 List Section
        // （2026-10-19）。网格本身保持卡片，行件统一为 DSSettingsGroupCard 节奏。
        AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    visionSection
                    interfaceSection
                    appearanceSection
                    themeManagementSection
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xxl * 2)
            }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
        }
        .navigationTitle(localized("视觉主题"))
        .toolbarTitleDisplayMode(.inline)
        .tint(activeTheme.isClassic ? nil : activeTheme.accentColor)
        .sheet(item: $paywallFeature) { feature in
            PaywallView(highlightedFeature: feature)
                .environmentObject(subscriptionStore)
        }
        .sheet(item: $importProgress) { progress in
            CustomizationImportOverviewView(progress: progress) {
                importProgress = nil
            }
        }
        // One alert modifier for the whole screen. Stacking several `.alert`s on
        // the same view is how one of them silently stops presenting — they all
        // compete for the same presenter.
        .alert(
            screenAlert?.title ?? "",
            isPresented: Binding(
                get: { screenAlert != nil },
                set: { if !$0 { screenAlert = nil } }
            ),
            presenting: screenAlert
        ) { _ in
            Button(localized("确定"), role: .cancel) {
                screenAlert = nil
            }
        } message: { alert in
            Text(alert.message)
        }
    }

    private var visionSection: some View {
        DSSettingsGroupCard(title: localized("视觉方案"), footer: {
            if !subscriptionStore.hasAccess(.readerThemePacks) {
                Text(localized("自定义应用配色、阅读配色与页面背景需开通会员。"))
            }
        }) {
            themeSelectionCard
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.sm)

            if !subscriptionStore.hasAccess(.readerThemePacks) {
                DSSettingsCardDivider()
                customizationRow
            }

            DSSettingsCardDivider()
            Text(localized("切换偏好"))
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.md)
                .padding(.bottom, DSSpacing.xs)
                .accessibilityAddTraits(.isHeader)
            DSSettingsCardToggle(
                title: localized("跟随系统"),
                systemImage: "circle.lefthalf.filled",
                isOn: appearanceFollowsSystemBinding
            )
            DSSettingsCardDivider()
            DSSettingsCardToggle(
                title: localized("单独设置深色主题"),
                systemImage: "moon",
                isOn: $settings.appearanceUsesSeparateDarkTheme
            )
            DSSettingsCardDivider()
            DSSettingsCardToggle(
                title: localized("绑定阅读主题"),
                systemImage: "book",
                isOn: $settings.appearanceBindReaderTheme
            )
            if settings.appearanceBindReaderTheme {
                DSSettingsCardDivider()
                boundReaderThemeRow(titleKey: "浅色阅读主题", systemImage: "sun.max", appearance: .light)
                DSSettingsCardDivider()
                boundReaderThemeRow(titleKey: "深色阅读主题", systemImage: "moon.fill", appearance: .dark)
                Text(localized("阅读器在浅色模式用浅色阅读主题，深色模式用深色阅读主题。要跟着装置的深浅色自动切换，在阅读器的「设置」面板开启「跟随装置深浅色」。"))
                    .dsSectionFooter()
                    .padding(.top, DSSpacing.sm)
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.standard, value: settings.appearanceBindReaderTheme)
    }

    /// A long press on a theme of the user's own: the tile pops up, and once it is up,
    /// 重命名／删除 comes up over it — the order a Home Screen icon lifts before its
    /// menu. The animation's own completion opens the alert, not a delay.
    private func liftTheme(_ preset: AppearanceThemePreset) {
        guard !reduceMotion else {
            liftedThemeID = preset.id
            themeActionTarget = preset
            return
        }
        withAnimation(DSAnimation.press, completionCriteria: .logicallyComplete) {
            liftedThemeID = preset.id
        } completion: {
            themeActionTarget = preset
        }
    }

    /// 重命名, from a tile's long press.
    private func beginRename(_ preset: AppearanceThemePreset) {
        renameText = preset.localizedName
        renameTarget = preset
    }

    /// The look's light/dark preferences live in 视觉方案's 切换偏好 rows
    /// alongside the theme grid (merged during the 我的/设置页 rebuild).

    /// What surrounds the content: the reader's chrome, the tab bar, the bookshelf grid
    /// and its covers, the launch screen. 每列欄數 and 預設封面 moved here from 設定's
    /// 書架顯示 (2026-09-29), where the theme they belong to could not be seen.
    private var interfaceSection: some View {
        DSSettingsGroupCard(title: localized("界面")) {
            DSSettingsCardNavRow(icon: "menubar.rectangle", title: localized("阅读器样式")) {
                AppearanceReaderInterfaceView()
            }
            DSSettingsCardDivider()
            // In view without Pro too, locked (2026-09-27).
            rootTabRow
            DSSettingsCardDivider()
            // 自绘菜单行：系统 menu picker 的 label 在卡片容器里不渲染，
            // 导致只剩居中的「4 列」，观感突兀。改为与相邻行一致的
            // 左图标标题 + 右侧当前值 + 下拉箭头。
            Menu {
                ForEach(GlobalSettings.bookshelfGridColumnCountOptions, id: \.self) { columnCount in
                    Button {
                        settings.bookshelfGridColumnCount = columnCount
                    } label: {
                        if settings.bookshelfGridColumnCount == columnCount {
                            Label(String(format: localized("%d 栏"), columnCount), systemImage: "checkmark")
                        } else {
                            Text(String(format: localized("%d 栏"), columnCount))
                        }
                    }
                }
            } label: {
                HStack {
                    SettingsRowLabel(localized("书库密度"), systemImage: "square.grid.3x3.fill")
                    Spacer()
                    HStack(spacing: 5) {
                        Text(String(format: localized("%d 栏"), settings.bookshelfGridColumnCount))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(DSFont.caption2.weight(.semibold))
                    }
                    .foregroundStyle(DSColor.textSecondary)
                }
                .padding(.horizontal, DSSpacing.md)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            DSSettingsCardDivider()
            DSSettingsCardNavRow(icon: "photo.stack.fill", title: localized("默认书封")) {
                DefaultCoverSettingsView()
            }
            DSSettingsCardDivider()
            launchImageRow
        }
    }

    /// The theme's own look, a page each: its colours and the global font, the page
    /// behind everything, and the interface effects.
    private var appearanceSection: some View {
        DSSettingsGroupCard(title: localized("外观")) {
            DSSettingsCardNavRow(
                icon: "paintpalette",
                title: localized("文字与配色"),
                value: settings.globalFontDisplayName
            ) {
                AppearanceColorsAndFontView()
            }
            DSSettingsCardDivider()
            if subscriptionStore.hasAccess(.readerThemePacks) {
                DSSettingsCardNavRow(icon: "photo.on.rectangle", title: localized("阅读壁纸")) {
                    AppearancePageBackgroundView()
                }
            } else {
                DSSettingsCardRow(
                    icon: "photo.on.rectangle",
                    title: localized("阅读壁纸"),
                    detail: localized("需要 Pro"),
                    isLocked: true
                ) {
                    paywallFeature = .readerThemePacks
                }
            }
            DSSettingsCardDivider()
            DSSettingsCardNavRow(
                icon: "sparkles",
                title: localized("动效与质感"),
                value: interfaceEffectsSummary
            ) {
                AppearanceInterfaceEffectsView()
            }
        }
    }

    // Deliberately outside the Pro gate. An appearance pack — ours or a QiReader
    // `.qitheme` — mostly carries things that are not Pro features at all: page
    // backgrounds, tab icons, default covers, the bundled font, interface effects,
    // reader layout, chapter title and comment bubble. Hiding the importer meant a
    // non-Pro user handed a pack had no way to open it, and no explanation either.
    // The custom theme a pack carries still needs Pro to take effect; `ContentView`'s
    // `resolvedAppTheme` already downgrades it on its own, so nothing here has to.
    private var themeManagementSection: some View {
        DSSettingsGroupCard(title: localized("主题库"), footer: {
            Text(localized("「导出主题」包含所有自定义主题、自带主题的配色、页面背景图、Tab 图标、启动图与阅读背景。"))
                .dsSectionFooter()
        }) {
            themeActionRows
        }
    }

    private var themeSelectionCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            if settings.showsAppearanceSlotTab {
                themeSlotPicker
            }
            currentThemeSummary
            LazyVGrid(columns: gridColumns, spacing: DSSpacing.lg) {
                // As coloured in 顏色與字體, not as shipped: the tile's dot and the ring
                // round the selected one are 強調色, so an edited accent shows here too.
                themeOption(settings.builtInThemePreset(AppearanceThemePreset.classic, isProActive: isProActive))
                ForEach(AppearanceThemePreset.freeSolidPresets) { preset in
                    themeOption(settings.builtInThemePreset(preset, isProActive: isProActive))
                }
                newThemeButton
            }
            // On the built-in grid, which is always there: a tile's own alert would go
            // with the tile, and the card below already has the long-press one — two on
            // one view compete for one presenter.
            .alert(
                localized("重命名主题"),
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                ),
                presenting: renameTarget
            ) { preset in
                TextField(localized("主题名称"), text: $renameText)
                Button(localized("确定")) {
                    settings.renameCustomAppearanceTheme(id: preset.id, to: renameText)
                }
                Button(localized("取消"), role: .cancel) {}
            }

            if !customThemes.isEmpty {
                themeGroupTitle(localized("自定义主题"))
                LazyVGrid(columns: gridColumns, spacing: DSSpacing.lg) {
                    ForEach(customThemes) { preset in
                        themeOption(preset)
                    }
                }
            }

            if !AppearanceThemePreset.bundledThemePacks.isEmpty {
                themeGroupTitle(localized("主题包"))
                LazyVGrid(columns: gridColumns, spacing: DSSpacing.lg) {
                    ForEach(AppearanceThemePreset.bundledThemePacks) { preset in
                        themeOption(preset)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : DSAnimation.standard, value: settings.showsAppearanceSlotTab)
        // The long press lands with a firm tap of the Taptic Engine as the tile lifts —
        // the medium one was too faint to notice (2026-09-29).
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: liftedThemeID) { _, lifted in
            lifted != nil
        }
        .onChange(of: themeActionTarget) { _, target in
            guard target == nil, liftedThemeID != nil else { return }
            withAnimation(reduceMotion ? nil : DSAnimation.standard) {
                liftedThemeID = nil
            }
        }
        // On the card, not the tile: 删除 removes the tile, and an alert torn down by its
        // own action can be left half-dismissed.
        .alert(
            themeActionTarget?.localizedName ?? "",
            isPresented: Binding(
                get: { themeActionTarget != nil },
                set: { if !$0 { themeActionTarget = nil } }
            ),
            presenting: themeActionTarget
        ) { preset in
            Button(localized("重命名")) {
                beginRename(preset)
            }
            Button(localized("删除"), role: .destructive) {
                settings.deleteCustomAppearanceTheme(id: preset.id)
            }
            Button(localized("取消"), role: .cancel) {}
        } message: { _ in
            Text(localized("删除后，使用此主题的外观会回到默认。"))
        }
    }

    /// Chooses which appearance the grid below is picking a theme for, and flips the
    /// whole app into it so the pick can be judged against the real thing. With 跟隨系統
    /// off that is the app's appearance, kept; with it on, a preview until 設定 is back.
    /// 深色 shows each theme's dark version, not one black theme. 浅色／深色 胶囊标签条
    /// 替代系统分段控件（2026-10-19），与阅读偏好的胶囊条同一套视觉。
    private var themeSlotPicker: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                themeSlotTab(localized("浅色"), scheme: .light)
                themeSlotTab(localized("深色"), scheme: .dark)
            }
            .padding(4)
            .background(DSColor.neutralControlFill, in: Capsule())
            .accessibilityLabel(localized("主题外观"))

            Text(localized(
                settings.appearanceFollowsSystem
                    ? "深色页签会以深色主题预览整个界面，选的是同一批主题的深色版本。"
                    : "跟随系统关闭时，App 固定使用这里选的浅色或深色。"
            ))
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    private func themeSlotTab(_ title: String, scheme: ColorScheme) -> some View {
        let selected = editingScheme == scheme
        return Button {
            withAnimation(DSAnimation.standard) {
                settings.pickAppearanceSlot(scheme)
            }
        } label: {
            Text(title)
                .font(DSFont.fixed(size: 13, weight: .medium))
                .foregroundColor(selected ? DSColor.textOnAccent : DSColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? activeTheme.accentColor : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 卡片顶部的当前方案摘要：主题名（衬线）+ 三个调色点，一眼看出正在使用的方案。
    private var currentThemeSummary: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(localized("当前方案"))
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
            Text(selectedTheme.localizedName)
                .font(DSFont.serifSectionTitle.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(
                    [selectedTheme.accentColor, selectedTheme.previewBackgroundColor, selectedTheme.textColor],
                    id: \.self
                ) { swatch in
                    Circle()
                        .fill(swatch)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(DSColor.separator, lineWidth: 0.5))
                }
            }
            Spacer(minLength: 0)
            if selectedTheme.requiresPro {
                Image(systemName: "crown.fill")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.appAccent)
                    .accessibilityLabel(localized("需要会员"))
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(DSColor.neutralControlFill, in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func themeGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(DSFont.subheadline.weight(.semibold))
            .foregroundStyle(DSColor.textSecondary)
            .padding(.top, DSSpacing.xs)
    }

    private func themeOption(_ preset: AppearanceThemePreset) -> some View {
        let locked = preset.requiresPro && !subscriptionStore.hasAccess(.readerThemePacks)
        // Ring marks the theme actually in effect (not a stored-but-locked pick).
        let selected = selectedTheme.id == preset.id
        // Only the user's own themes can be renamed or deleted.
        let editable = preset.isCustom && !locked
        // Preview in the appearance being edited: the dark slot shows this
        // theme's dark palette, which is what selecting it will apply.
        let displayed = preset.palette(for: editingScheme)
        return Button {
            guard !locked else {
                paywallFeature = .readerThemePacks
                return
            }
            settings.setAppearanceTheme(
                preset,
                for: editingScheme,
                // The window wears `editingScheme` (`appearanceWindowColorScheme`), so
                // that is the appearance on screen — `colorScheme` may not have caught up
                // with a tab picked a moment ago.
                activeAppearance: editingScheme
            )
        } label: {
            VStack(spacing: DSSpacing.sm) {
                ThemePreviewTile(
                    preset: displayed,
                    isSelected: selected,
                    isLocked: locked,
                    colorScheme: editingScheme
                )
                Text(preset.localizedName)
                    .font(DSFont.caption)
                    .foregroundStyle(locked ? DSColor.textDisabled : DSColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .frame(minHeight: 32, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        // A long press on a theme of the user's own asks 重命名 or 删除 in an alert —
        // not a context menu, whose actions could not raise an alert on iOS 17
        // (Technotes/iOS17MenuModalPresentation.md). 主題管理 has 删除主題 as a row too.
        .buttonStyle(ThemeTileButtonStyle(
            onLongPress: editable ? { liftTheme(preset) } : nil,
            isLifted: liftedThemeID == preset.id
        ))
        // Above its neighbours while it is lifted, or they would cover it.
        .zIndex(liftedThemeID == preset.id ? 1 : 0)
        .accessibilityActions {
            if editable {
                Button(localized("重命名")) { beginRename(preset) }
                Button(localized("删除")) { deleteTarget = preset }
            }
        }
        .accessibilityLabel(preset.localizedName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var newThemeButton: some View {
        Button {
            guard subscriptionStore.hasAccess(.readerThemePacks) else {
                paywallFeature = .readerThemePacks
                return
            }
            newThemeName = ""
            showNewThemeAlert = true
        } label: {
            VStack(spacing: DSSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .fill(DSColor.textSecondary.opacity(0.2))
                    Image(systemName: subscriptionStore.hasAccess(.readerThemePacks) ? "plus" : "lock.fill")
                        .font(DSFont.fixed(size: 24, weight: .semibold))
                        .foregroundStyle(selectedTheme.palette(for: editingScheme).accentColor)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                Text(localized("新建"))
                    .font(DSFont.caption)
                    .foregroundStyle(subscriptionStore.hasAccess(.readerThemePacks) ? DSColor.textPrimary : DSColor.textDisabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(minHeight: 32, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("新建"))
        // A name, then the whole look on screen — colours, page backgrounds, icons, font
        // and all — becomes the new theme, selected in the slot being edited. This was
        // two rows: 新建 copied the colours alone and opened an editor page, and
        // 保存為新主題 saved the whole look (2026-09-29).
        .alert(localized("新建主题"), isPresented: $showNewThemeAlert) {
            TextField(localized("主题名称"), text: $newThemeName)
            Button(localized("新建")) {
                settings.saveCurrentAppearanceAsTheme(
                    named: newThemeName,
                    basedOn: selectedTheme,
                    for: editingScheme
                )
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("当前的整套外观会存成这个新主题。"))
        }
    }

    private var appearanceFollowsSystemBinding: Binding<Bool> {
        Binding(
            get: { settings.appearanceFollowsSystem },
            set: {
                // Turned off, the appearance on the tab — previewed or not — is kept.
                settings.setAppearanceFollowsSystem(
                    $0,
                    currentColorScheme: editingScheme
                )
            }
        )
    }

    /// One appearance's reading-background pick, shown while 綁定閱讀主題 is on.
    private func boundReaderThemeRow(titleKey: String, systemImage: String, appearance: ColorScheme) -> some View {
        DSSettingsCardPicker(
            title: localized(titleKey),
            systemImage: systemImage,
            selection: Binding(
                get: { settings.boundReaderTheme(for: appearance) },
                set: { settings.setBoundReaderTheme($0, for: appearance) }
            )
        ) {
            ForEach(settings.boundReaderThemeOptions) { option in
                Text(settings.title(for: option)).tag(option)
            }
        }
    }

    /// Names whichever effects are on, so the row says something useful without
    /// opening it. Both off reads 已关闭.
    private var interfaceEffectsSummary: String {
        var parts: [String] = []
        if settings.interfaceGlowIntensity > 0 {
            parts.append(localized("光晕"))
        }
        if settings.interfaceFrostedGlass {
            parts.append(localized("毛玻璃"))
        }
        guard !parts.isEmpty else { return localized("已关闭") }
        // Locale-correct joiner ("光晕、毛玻璃" / "Glow, Frosted Glass") instead of a
        // hardcoded separator that only reads right in one language.
        return parts.formatted(.list(type: .and, width: .narrow))
    }

    /// Pro pushes the settings page; without Pro the row is the paywall.
    @ViewBuilder
    private var launchImageRow: some View {
        if subscriptionStore.hasAccess(.launchScreen) {
            DSSettingsCardNavRow(
                icon: "iphone",
                title: localized("开屏画面"),
                value: localized(settings.launchImageEnabled ? "已开启" : "已关闭")
            ) {
                LaunchImageSettingsView()
            }
        } else {
            DSSettingsCardRow(
                icon: "iphone",
                title: localized("开屏画面"),
                detail: localized("需要 Pro"),
                isLocked: true
            ) {
                paywallFeature = .launchScreen
            }
        }
    }

    @ViewBuilder
    private var rootTabRow: some View {
        if ReaderPremiumVisibilityPolicy(isProActive: subscriptionStore.isProActive).showsBottomTabCustomization {
            DSSettingsCardNavRow(icon: "square.grid.2x2", title: localized("导航栏")) {
                RootTabCustomizationView()
            }
        } else {
            DSSettingsCardRow(
                icon: "square.grid.2x2",
                title: localized("导航栏"),
                detail: localized("需要 Pro"),
                isLocked: true
            ) {
                paywallFeature = .bottomBarCustomization
            }
        }
    }

    // MARK: - Theme actions (save / export / import / reset)

    @ViewBuilder
    private var themeActionRows: some View {
        // One export for the whole look, named after the theme on screen. There used to
        // be two — 導出主題 (one theme's colours and page backgrounds) and 導出全部自定義 —
        // but a theme is the whole look now, as an imported pack is (2026-09-29).
        ShareLink(
            item: themeExportPayload,
            preview: SharePreview(selectedTheme.localizedName)
        ) {
            SettingsRowLabel(localized("导出方案"), systemImage: "square.and.arrow.up", role: .action)
        }
        .themeActionFrame()
        .buttonStyle(.plain)
        // 删除主題's confirmation, on a row that is always there: the 删除主題 row goes
        // with the theme, and an alert torn down by its own action can be left
        // half-dismissed.
        .alert(
            String(format: localized("删除「%@」？"), deleteTarget?.localizedName ?? ""),
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { preset in
            Button(localized("删除"), role: .destructive) {
                settings.deleteCustomAppearanceTheme(id: preset.id)
            }
            Button(localized("取消"), role: .cancel) {}
        } message: { _ in
            Text(localized("删除后，使用此主题的外观会回到默认。"))
        }

        DSSettingsCardDivider()

        Button {
            showThemeImporter = true
        } label: {
            SettingsRowLabel(localized("导入方案"), systemImage: "square.and.arrow.down", role: .action)
        }
        .themeActionFrame()
        .buttonStyle(.plain)
        .fileImporter(
            isPresented: $showThemeImporter,
            allowedContentTypes: [
                .json,
                .yueduReaderStyle,
                UTType(filenameExtension: "qitheme") ?? .data,
            ],
            allowsMultipleSelection: false,
            onCompletion: handleThemeImport
        )

        if let custom = selectedCustomTheme {
            DSSettingsCardDivider()
            Button(role: .destructive) {
                deleteTarget = AppearanceThemePreset.preset(from: custom)
            } label: {
                SettingsRowLabel(localized("删除主题"), systemImage: "trash", role: .destructive)
            }
            .themeActionFrame()
            .buttonStyle(.plain)
        }

        // A built-in theme's only: it has a default look to go back to. A theme of the
        // user's own — an imported pack included — is its own look, and is renamed or
        // deleted instead (2026-09-29).
        if selectedCustomTheme == nil {
            DSSettingsCardDivider()
            Button(role: .destructive) {
                showResetAppearanceConfirm = true
            } label: {
                SettingsRowLabel(localized("恢复默认"), systemImage: "arrow.counterclockwise", role: .destructive)
            }
            .themeActionFrame()
            .buttonStyle(.plain)
            .alert(localized("恢复默认？"), isPresented: $showResetAppearanceConfirm) {
                Button(localized("恢复默认"), role: .destructive) {
                    settings.resetAppearanceToDefault()
                }
                Button(localized("取消"), role: .cancel) {}
            } message: {
                Text(localized("主题、自带主题的配色、页面背景、Tab 图标、全局字体、界面效果、阅读界面与启动图会回到默认。你的主题、主题包、书架与封面设定、阅读设置都会保留。"))
            }
        }
    }

    /// Cheap to build — values and file names now, bytes at share time — so it is
    /// safe in a row SwiftUI rebuilds with its parent.
    private var themeExportPayload: AppearanceCustomizationExportPayload {
        AppearanceCustomizationExportPayload(
            filename: AppearanceCustomizationExportPayload.filename(for: selectedTheme.localizedName),
            snapshot: settings.appearanceCustomizationSnapshot()
        )
    }

    private func handleThemeImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            if QiThemeImporter.hasQiThemeExtension(url) {
                handleQiThemeImport(data)
                return
            }
            Task { @MainActor in
                do {
                    let summary = try await settings.importAppearanceCustomizationPackage(from: data)
                    let selected = summary.selectedThemeID.flatMap { id in
                        settings.customAppearanceThemes.first { $0.id == id }
                    }
                    // Up only once the import has finished — after an `await`, so never
                    // while the document picker is still on its way out.
                    importProgress = CustomizationImportProgress(phase: .finished(
                        CustomizationImportOverview(appearance: summary, selectedTheme: selected)
                    ))
                } catch let error as AppearanceThemeImportError {
                    showImportFailure(localized(error.messageKey))
                } catch {
                    showImportFailure(localized("汇入主题失败。"))
                }
            }
        } catch let error as AppearanceThemeImportError {
            showImportFailure(localized(error.messageKey))
        } catch {
            showImportFailure(localized("汇入主题失败。"))
        }
    }

    /// QiReader packs are a foreign archive: their manifest lives under a UUID directory,
    /// so `ReaderStylePackage` cannot read them and they get their own parse before any of
    /// the native routes are tried.
    private func handleQiThemeImport(_ data: Data) {
        Task { @MainActor in
            do {
                // Nothing to ask: the pack's reading setup is its theme's own.
                applyQiTheme(try await QiThemeImportService.load(data))
            } catch let error as QiThemeImportError {
                showImportFailure(error.errorDescription ?? localized("汇入主题失败。"))
            } catch {
                showImportFailure(localized("汇入主题失败。"))
            }
        }
    }

    private func applyQiTheme(_ theme: QiThemeImport) {
        // Installing a pack's font takes a moment; the sheet shows it happening.
        let progress = CustomizationImportProgress()
        importProgress = progress
        Task { @MainActor in
            do {
                let outcome = try await QiThemeImportService.apply(theme)
                progress.phase = .finished(CustomizationImportOverview(qiTheme: outcome))
            } catch {
                AppLogger.error("⟐ qitheme import failed", error: error)
                progress.phase = .failed(
                    (error as? LocalizedError)?.errorDescription ?? localized("汇入主题失败。")
                )
            }
        }
    }

    private func showImportFailure(_ message: String) {
        screenAlert = ThemeScreenAlert(title: localized("汇入失败"), message: message)
    }

    /// Free-user upsell row; hidden entirely once Pro is active.
    private var customizationRow: some View {
        Button {
            paywallFeature = .readerThemePacks
        } label: {
            HStack(spacing: DSSpacing.md) {
                // Pro is marked with the app's own icon, as on the 閱讀Pro row and page.
                AppIconImage(size: DSLayout.settingsRowIconSize)
                Text(localized("主题自定义"))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 0)
                Text(localized("需要 Pro"))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Image(systemName: "lock.fill")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, DSSpacing.md)
    }
}

/// 主题库动作行的行高与点击区：与卡片内其它行同一节奏（54pt 高、水平 12pt 边距）。
private extension View {
    func themeActionFrame() -> some View {
        self
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(.horizontal, DSSpacing.md)
            .contentShape(Rectangle())
    }
}

private struct ThemePreviewTile: View {
    let preset: AppearanceThemePreset
    let isSelected: Bool
    let isLocked: Bool
    let colorScheme: ColorScheme

    private let tileHeight: CGFloat = 72

    var body: some View {
        // Rigid cell-width × fixed-height frame + clip so an image preview
        // (scaledToFill) can never overflow into the neighbouring tile.
        previewBackground
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .overlay(alignment: .topLeading) {
                if !preset.isImagePreset {
                    swatchContent
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Selected seal: a checkmark beside the ring, so the pick reads at a
                // glance even where the ring is hard to see (light tile on light card).
                if isSelected && !isLocked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DSFont.subheadline.weight(.semibold))
                        .foregroundStyle(preset.accentColor)
                        .background(Circle().fill(Color.white.opacity(0.92)))
                        .padding(5)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if isLocked {
                    ZStack {
                        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                            .fill(Color.black.opacity(0.16))
                        Image(systemName: "lock.fill")
                            .font(DSFont.fixed(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .stroke(isSelected ? preset.accentColor : Color.clear, lineWidth: 3)
            )
            .shadow(
                color: isSelected ? preset.accentColor.opacity(0.32) : Color.black.opacity(0.08),
                radius: isSelected ? 7 : 3,
                x: 0,
                y: isSelected ? 4 : 1
            )
    }

    /// Mini "reader page" sketch shown on solid-color swatches.
    private var swatchContent: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Circle()
                .fill(preset.accentColor)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1))

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(preset.textColor)
                    .frame(width: 52, height: 5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(preset.textColor.opacity(0.78))
                    .frame(width: 40, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(preset.textColor.opacity(0.42))
                    .frame(width: 48, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(preset.textColor.opacity(0.42))
                    .frame(width: 30, height: 4)
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.md)
    }

    @ViewBuilder
    private var previewBackground: some View {
        if preset.isImagePreset,
           let url = preset.backgroundImageURL(colorScheme: colorScheme),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    preset.previewBackgroundColor,
                    preset.dialogueColor.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct AppearanceReaderInterfaceView: View {
    @ObservedObject private var settings = GlobalSettings.shared

    /// The reading background the reader is currently painting with, so the preview
    /// shows the chrome against the surface it will actually sit on. Read once per
    /// body pass: the reading background can only change from inside the reader, which
    /// this page is never on screen for.
    private var previewTheme: ReaderTheme { ReaderTheme.loadPersisted() }

    private func palette(for interface: ReaderChromeInterface) -> ReaderChromePalette {
        ReaderChromePalette(interface: interface, theme: previewTheme, settings: settings)
    }

    var body: some View {
        // 分组卡片：「自定義」一张卡片，替代系统 Form Section（2026-10-25）。
        AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // ShuYue 只保留「极简悬浮控制」单套方案：点屏幕中央呼出顶部与底部
                    // 控制岛，不再提供 classic / modern / Apple Books 三套 chrome 切换。
                    customizationSection(for: .classic)
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xxl * 2)
            }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
        }
        .navigationTitle(localized("阅读器样式"))
        .toolbarTitleDisplayMode(.inline)
    }

    /// Only the slots the chosen interface actually paints — 現代's navigation bar is
    /// system glass with no fill of ours, and only 經典 floats circles over the page.
    private func customizationSection(for interface: ReaderChromeInterface) -> some View {
        DSSettingsGroupCard(
            title: localized("自定义"),
            footer: {
                Text(localized("点按屏幕中央呼出顶部与底部控制岛。顶部是返回／章节名／书签／搜索，右侧「更多」收纳刷新、换源、下载与网页打开；底部是进度滑条、上一章、下一章，以及目录、设置、听书、深色。未调整的部分跟随目前的阅读主题。"))
                    .dsSectionFooter()
            }
        ) {
            chromePreview(for: interface)
                .dsSettingsCardRow(minHeight: 0)
                .padding(.vertical, DSSpacing.sm)

            ForEach(ReaderChromeSlot.slots(for: interface)) { slot in
                DSSettingsCardDivider()
                colorRow(slot, interface: interface)
                    .dsSettingsCardRow(minHeight: 0)
                    .padding(.vertical, DSSpacing.xs)
            }

            DSSettingsCardDivider()

            NavigationLink {
                ReaderChromeIconSettingsView()
            } label: {
                HStack {
                    Text(localized("阅读栏图标"))
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: DSSpacing.md)
                    Text(iconSummary)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .dsSettingsCardRow()

            if settings.hasReaderChromeOverride(interface: interface) {
                DSSettingsCardDivider()
                Button {
                    settings.resetReaderChrome(interface: interface)
                } label: {
                    Label(localized("跟随阅读主题"), systemImage: "arrow.counterclockwise")
                }
                .dsSettingsCardRow()
            }
        }
    }

    /// 目錄／書籤／深色／設置 and 刷新／換源／下載／聽書 status, so the row says
    /// something without opening it.
    private var iconSummary: String {
        let custom = settings.readerChromeIcons.count
        let hidden = settings.readerChromeHiddenIDs.count
        var parts: [String] = []
        if custom > 0 { parts.append(String(format: localized("已换 %d 个"), custom)) }
        if hidden > 0 { parts.append(String(format: localized("已隐藏 %d 个"), hidden)) }
        guard !parts.isEmpty else { return localized("默认") }
        return parts.formatted(.list(type: .and, width: .narrow))
    }

    private func colorRow(_ slot: ReaderChromeSlot, interface: ReaderChromeInterface) -> some View {
        ColorPicker(selection: colorBinding(slot, interface: interface), supportsOpacity: false) {
            Text(localized(slot.titleKey))
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
        }
    }

    /// Opens on the colour that is on screen right now rather than a blank swatch,
    /// the same contract as the reader's 文字顏色 picker. Writing one stores an
    /// override; clearing every override is the 跟随阅读主题 button, not a colour.
    private func colorBinding(
        _ slot: ReaderChromeSlot,
        interface: ReaderChromeInterface
    ) -> Binding<Color> {
        Binding(
            get: { palette(for: interface).color(for: slot) },
            set: { settings.setReaderChromeColor(UIColor($0).rgbHex, interface: interface, slot: slot) }
        )
    }

    /// The real chrome, drawn with the real palette on the real reading background —
    /// the section is about how the reader looks, so swatches would not answer the
    /// only question anyone has here.
    @ViewBuilder
    private func chromePreview(for interface: ReaderChromeInterface) -> some View {
        let palette = palette(for: interface)
        VStack(spacing: 0) {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: "chevron.left")
                Spacer(minLength: 0)
                if interface == .modern {
                    Circle()
                        .fill(palette.panelFill)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(palette.topIcon.opacity(0.25), lineWidth: 0.5))
                } else {
                    Image(systemName: "bookmark")
                    Image(systemName: "line.3.horizontal")
                }
            }
            .font(DSFont.fixed(size: 13, weight: .medium))
            .foregroundStyle(palette.topIcon)
            .padding(.horizontal, DSSpacing.md)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(interface == .classic ? palette.topFill : previewTheme.backgroundColor)

            ZStack(alignment: .bottom) {
                previewTheme.backgroundColor
                    .frame(height: interface == .classic ? 44 : 24)

                if interface == .classic {
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        ForEach(visiblePreviewActions.filter(\.isClassicCircle), id: \.self) { item in
                            previewActionGlyph(item, palette: palette)
                        }
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.bottom, DSSpacing.sm)
                }
            }

            bottomPreview(interface: interface, palette: palette)
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        // One decorative element: VoiceOver gets the values from the rows below,
        // not from a stack of unlabelled symbols.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func bottomPreview(
        interface: ReaderChromeInterface,
        palette: ReaderChromePalette
    ) -> some View {
        let bar = VStack(spacing: DSSpacing.sm) {
            Capsule()
                .fill(palette.bottomAccent)
                .frame(height: 3)
            HStack(spacing: 0) {
                ForEach(settings.visibleReaderChromeToolItems) { item in
                    previewToolGlyph(for: item, palette: palette)
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)

        switch interface {
        case .classic:
            bar
                .frame(maxWidth: .infinity)
                .background(palette.bottomFill)
        case .modern:
            // 現代's bottom bar floats, inset from every edge, over the page.
            bar
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .fill(palette.bottomFill)
                )
                .padding(DSSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(previewTheme.backgroundColor)
        }
    }

    /// Only the actions that are both applicable in general and switched on — the
    /// preview should not advertise a button the reader has hidden.
    private var visiblePreviewActions: [ReaderChromeActionItem] {
        ReaderChromeActionItem.allCases.filter { settings.isReaderChromeItemVisible($0) }
    }

    @ViewBuilder
    private func previewActionGlyph(
        _ item: ReaderChromeActionItem,
        palette: ReaderChromePalette
    ) -> some View {
        Group {
            if let image = settings.readerChromeIconImage(for: item) {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: item.defaultSystemImage)
                    .font(DSFont.fixed(size: 11))
                    .foregroundStyle(palette.circleIcon)
            }
        }
        .frame(width: 24, height: 24)
        .background(palette.circleFill, in: Circle())
        .overlay(Circle().stroke(palette.circleBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func previewToolGlyph(
        for item: ReaderChromeToolItem,
        palette: ReaderChromePalette
    ) -> some View {
        Group {
            if let image = settings.readerChromeIconImage(for: item) {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: item.systemImage(isNight: previewTheme == .night))
                    .font(DSFont.fixed(size: 14))
                    .foregroundStyle(palette.bottomIcon)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A theme tile: a tap selects; a long press on one of the user's own themes opens
/// 重命名／删除. Primitive, so the two cannot both fire — a long-press gesture added to
/// a plain button would still select the theme on the release that ends it.
private struct ThemeTileButtonStyle: PrimitiveButtonStyle {
    /// Nil for a theme that has nothing to rename or delete.
    let onLongPress: (() -> Void)?
    /// Its 重命名／删除 is up, or on its way.
    var isLifted = false

    func makeBody(configuration: Configuration) -> some View {
        ThemeTileButtonBody(configuration: configuration, onLongPress: onLongPress, isLifted: isLifted)
    }
}

/// The tile under a finger grows while it is held — a long press is on its way — and
/// pops up once it lands (2026-09-29). Under Reduce Motion it stays put and the haptic
/// alone says the press landed.
private struct ThemeTileButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let onLongPress: (() -> Void)?
    let isLifted: Bool

    @State private var isPressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pressingScale: CGFloat = 1.05
    private static let liftedScale: CGFloat = 1.12

    var body: some View {
        if let onLongPress {
            configuration.label
                .scaleEffect(scale)
                .animation(pressAnimation, value: isPressing)
                .onTapGesture { configuration.trigger() }
                .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress) { pressing in
                    isPressing = pressing
                }
        } else {
            configuration.label
                .onTapGesture { configuration.trigger() }
        }
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        if isLifted { return Self.liftedScale }
        return isPressing ? Self.pressingScale : 1
    }

    /// Growing takes most of the hold, so a quick tap barely moves the tile; letting go
    /// early settles it at once.
    private var pressAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return isPressing ? DSAnimation.slow : DSAnimation.fast
    }
}

#Preview {
    NavigationStack {
        AppearanceThemeView()
            .environmentObject(SubscriptionStore.shared)
    }
}

#Preview("阅读界面") {
    NavigationStack {
        AppearanceReaderInterfaceView()
    }
}
