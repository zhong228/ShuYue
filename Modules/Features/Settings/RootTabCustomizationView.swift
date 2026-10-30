import SwiftUI
import UniformTypeIdentifiers

struct RootTabCustomizationView: View {
    @ObservedObject private var settings = GlobalSettings.shared
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @State private var showPaywall = false
    @State private var iconImportError: RootTabIconImportError?

    private var canCustomize: Bool {
        subscriptionStore.hasAccess(.bottomBarCustomization)
    }

    var body: some View {
        // 分组卡片：付费锁 / 顯示頁面 / Tab 圖標 / 各 Tab 图标 成卡片，替代系统 Form Section
        // （2026-10-19）。行内自定义视图（滑桿、图片选择）保留原控件，只给卡片节奏。
        ScrollView {
            AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
            VStack(spacing: DSSpacing.lg) {
                if !canCustomize {
                    DSSettingsGroupCard(title: localized("底部 Tab")) {
                        DSSettingsCardRow(
                            icon: "lock.fill",
                            title: localized("底部 Tab 自定义需要 Pro"),
                            isLocked: true
                        ) {
                            showPaywall = true
                        }
                    }
                }

                visibleTabsSection
                tabPresentationSection

                ForEach(RootTabItem.allCases) { tab in
                    iconSection(for: tab)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.xl)
        }
        }
        .softScrollEdges()
        .navigationTitle(localized("底部 Tab"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .alert(item: $iconImportError) { error in
            Alert(
                title: Text(localized("图标导入失败")),
                message: Text(error.message),
                dismissButton: .default(Text(localized("确定")))
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(highlightedFeature: .bottomBarCustomization)
                .environmentObject(subscriptionStore)
        }
    }

    private var visibleTabsSection: some View {
        DSSettingsGroupCard(title: localized("显示页面"), footer: {
            Text(localized("至少保留一个内容页，设定固定显示，避免无法恢复页面。"))
                .dsSectionFooter()
        }) {
            ForEach(RootTabItem.allCases) { tab in
                if tab.isAlwaysVisible {
                    HStack {
                        SettingsRowLabel(localized(tab.titleKey), systemImage: tab.defaultSystemImage)
                        Spacer(minLength: DSSpacing.md)
                        Text(localized("固定显示"))
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .dsSettingsCardRow()
                } else {
                    DSSettingsCardToggle(
                        title: localized(tab.titleKey),
                        systemImage: tab.defaultSystemImage,
                        isOn: visibleBinding(for: tab)
                    )
                    .disabled(!canCustomize)
                }
                if tab != RootTabItem.allCases.last {
                    DSSettingsCardDivider()
                }
            }
        }
    }

    private var tabPresentationSection: some View {
        DSSettingsGroupCard(title: localized("Tab 图标"), footer: {
            Text(localized("不调整时保持系统 Tab 默认大小；开启自订大小后才套用滑杆。"))
                .dsSectionFooter()
        }) {
            Toggle(isOn: hidesLabelsBinding) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(localized("隐藏标签文字"))
                        .foregroundStyle(DSColor.textPrimary)
                    Text(localized("开启后 Tab 栏只显示图标，不显示文字标签"))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .disabled(!canCustomize)
            .dsSettingsCardRow(minHeight: 0)
            .padding(.vertical, DSSpacing.sm)

            DSSettingsCardDivider()

            Toggle(isOn: customIconSizeEnabledBinding) {
                HStack {
                    Text(localized("自订图标大小"))
                        .foregroundStyle(DSColor.textPrimary)
                    Spacer(minLength: DSSpacing.md)
                    Text(settings.usesCustomRootTabIconSize ? iconSizeText : localized("系统默认"))
                        .font(settings.usesCustomRootTabIconSize ? DSFont.body.monospacedDigit() : DSFont.body)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .disabled(!canCustomize)
            .dsSettingsCardRow()

            if settings.usesCustomRootTabIconSize {
                DSSettingsCardDivider()

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack {
                        Text(localized("图标大小"))
                            .foregroundStyle(DSColor.textPrimary)
                        Spacer()
                        Text(iconSizeText)
                            .font(DSFont.body.monospacedDigit())
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    Slider(
                        value: iconSizeBinding,
                        in: 22...36,
                        step: 1
                    )
                    .disabled(!canCustomize)
                    // A bare Slider has no name and announces a fraction of its
                    // range instead of the size printed above it.
                    // docs/design.md §7.1, third trap.
                    .accessibilityLabel(localized("图标大小"))
                    .accessibilityValue(iconSizeText)
                }
                .dsSettingsCardRow(minHeight: 0)
                .padding(.vertical, DSSpacing.sm)
            }
        }
    }

    private func iconSection(for tab: RootTabItem) -> some View {
        DSSettingsGroupCard(title: localized(tab.titleKey)) {
            ForEach(RootTabIconSlot.allCases) { slot in
                iconRow(tab: tab, slot: slot)
                if slot != RootTabIconSlot.allCases.last {
                    DSSettingsCardDivider()
                }
            }
        }
    }

    private func iconRow(tab: RootTabItem, slot: RootTabIconSlot) -> some View {
        let asset = settings.rootTabIconAsset(for: tab, slot: slot)
        return HStack(spacing: DSSpacing.md) {
            tabIconPreview(tab: tab, slot: slot)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(localized(slot.titleKey))
                    .foregroundStyle(DSColor.textPrimary)
                Text(asset?.originalFileName ?? localized("未选择图片"))
                    .font(DSFont.caption)
                    .foregroundStyle(asset == nil ? DSColor.textSecondary : DSColor.accent)
                    .lineLimit(1)
            }

            Spacer(minLength: DSSpacing.md)

            ImageSourcePickerButton(
                accessibilityTitle: "\(localized(tab.titleKey)) · \(localized(slot.titleKey))",
                contentTypes: Self.iconContentTypes,
                extraActions: asset == nil ? [] : [
                    ImageSourcePickerAction(
                        title: localized("移除图片"),
                        systemImage: "trash",
                        isDestructive: true,
                        action: { settings.deleteRootTabIcon(tab: tab, slot: slot) }
                    )
                ],
                onPick: { result in handleIconPick(result, tab: tab, slot: slot) }
            ) {
                Label(localized("选择图片"), systemImage: "photo")
                    .font(DSFont.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(!canCustomize)
        }
        .dsSettingsCardRow()
    }

    @ViewBuilder
    private func tabIconPreview(tab: RootTabItem, slot: RootTabIconSlot) -> some View {
        if let asset = settings.rootTabIconAsset(for: tab, slot: slot),
           let url = settings.rootTabIconURL(for: asset),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: tab.defaultSystemImage)
                .font(DSFont.fixed(size: 24, weight: .regular))
                .foregroundStyle(DSColor.textPrimary)
                .frame(width: 44, height: 44)
        }
    }

    private var hidesLabelsBinding: Binding<Bool> {
        Binding(
            get: { settings.rootTabHidesLabels },
            set: { value in
                guard canCustomize else {
                    showPaywall = true
                    return
                }
                settings.rootTabHidesLabels = value
            }
        )
    }

    /// The one source for the printed size and the slider's VoiceOver value, so what
    /// is spoken can never drift from what is shown. Only read while
    /// `usesCustomRootTabIconSize` is true, which is when both call sites render.
    private var iconSizeText: String {
        "\(Int(settings.rootTabIconSize)) pt"
    }

    private var iconSizeBinding: Binding<Double> {
        Binding(
            get: {
                settings.usesCustomRootTabIconSize
                    ? settings.rootTabIconSize
                    : GlobalSettings.initialCustomRootTabIconSize
            },
            set: { value in
                guard canCustomize else {
                    showPaywall = true
                    return
                }
                settings.rootTabIconSize = value
            }
        )
    }

    private var customIconSizeEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.usesCustomRootTabIconSize },
            set: { value in
                guard canCustomize else {
                    showPaywall = true
                    return
                }
                settings.rootTabIconSize = value
                    ? GlobalSettings.initialCustomRootTabIconSize
                    : GlobalSettings.defaultRootTabIconSize
            }
        )
    }

    private func visibleBinding(for tab: RootTabItem) -> Binding<Bool> {
        Binding(
            get: { settings.isRootTabVisible(tab) },
            set: { value in
                guard canCustomize else {
                    showPaywall = true
                    return
                }
                settings.setRootTab(tab, visible: value)
            }
        )
    }

    private func handleIconPick(
        _ result: Result<PickedImageSource, PickedImageError>,
        tab: RootTabItem,
        slot: RootTabIconSlot
    ) {
        guard canCustomize else {
            showPaywall = true
            return
        }
        do {
            switch result {
            case .success(.data(let data)):
                try settings.importRootTabIcon(
                    data: data,
                    // Photos gives no file name; the row shows this under the slot.
                    originalFileName: localized("相簿图片"),
                    tab: tab,
                    slot: slot
                )
            case .success(.file(let url)):
                try settings.importRootTabIcon(from: url, tab: tab, slot: slot)
            case .failure(let error):
                iconImportError = RootTabIconImportError(message: localized(error.messageKey))
            }
        } catch {
            iconImportError = RootTabIconImportError(message: error.localizedDescription)
        }
    }

    private static let iconContentTypes: [UTType] = [
        .image,
        UTType(filenameExtension: "webp") ?? .data,
    ]
}

private struct RootTabIconImportError: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    NavigationStack {
        RootTabCustomizationView()
            .environmentObject(SubscriptionStore.shared)
    }
}
