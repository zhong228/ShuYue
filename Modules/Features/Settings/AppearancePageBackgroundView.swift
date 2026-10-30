import SwiftUI
import UIKit

/// 外觀主題 › 頁面背景: the colours and pictures behind each page, for the scope being
/// edited, with a preview. Its own page since 2026-09-29, grouped as the reference the
/// user handed over: one section of settings, the preview under it. The rows are the
/// ones 外觀主題 used to carry inline, unchanged in what they do.
struct AppearancePageBackgroundView: View {
    @ObservedObject private var settings = GlobalSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var pageBackgroundScope: AppearancePageBackgroundScope = .global
    @State private var importFailure: String?

    var body: some View {
        ScrollView {
            AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
            VStack(spacing: DSSpacing.lg) {
                // 分组卡片：页面背景设置与预览各成卡片，替代系统 Form Section（2026-10-25）。
                DSSettingsGroupCard(title: localized("页面背景"), footer: {
                    Text(localized("没有单独设定的分页，用「全域预设」的背景。"))
                        .dsSectionFooter()
                }) {
                    DSSettingsCardPicker(
                        title: localized("编辑范围"),
                        systemImage: "rectangle.stack",
                        selection: $pageBackgroundScope
                    ) {
                        ForEach(AppearancePageBackgroundScope.allCases) { scope in
                            Text(scope.localizedTitle).tag(scope)
                        }
                    }
                    DSSettingsCardDivider()
                    colorRow(titleKey: "亮色主色调", scheme: .light, slot: .primary)
                    DSSettingsCardDivider()
                    colorRow(titleKey: "亮色辅色调", scheme: .light, slot: .secondary)
                    DSSettingsCardDivider()
                    colorRow(titleKey: "深色主色调", scheme: .dark, slot: .primary)
                    DSSettingsCardDivider()
                    colorRow(titleKey: "深色辅色调", scheme: .dark, slot: .secondary)
                    DSSettingsCardDivider()
                    imagePickerRow(scheme: .light)
                    if hasBackgroundImage(scheme: .light) {
                        DSSettingsCardDivider()
                        imageOpacityRow(scheme: .light)
                    }
                    DSSettingsCardDivider()
                    imagePickerRow(scheme: .dark)
                    if hasBackgroundImage(scheme: .dark) {
                        DSSettingsCardDivider()
                        imageOpacityRow(scheme: .dark)
                    }
                }

                DSSettingsGroupCard(title: localized("预览")) {
                    previewCard
                        .dsSettingsCardRow(minHeight: 0)
                        .padding(.vertical, DSSpacing.sm)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.xs)
            .padding(.bottom, DSSpacing.xxl * 2)
        }
        }
        .softScrollEdges()
        .navigationTitle(localized("页面背景"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .alert(
            localized("汇入失败"),
            isPresented: Binding(
                get: { importFailure != nil },
                set: { if !$0 { importFailure = nil } }
            )
        ) {
            Button(localized("确定"), role: .cancel) {}
        } message: {
            Text(importFailure ?? "")
        }
    }

    // MARK: - Colours

    private func colorRow(titleKey: String, scheme: ColorScheme, slot: PageBackgroundColorSlot) -> some View {
        ColorPicker(selection: colorBinding(scheme: scheme, slot: slot), supportsOpacity: false) {
            Text(localized(titleKey))
                .foregroundStyle(DSColor.textPrimary)
        }
        .dsSettingsCardRow()
    }

    private func colorBinding(scheme: ColorScheme, slot: PageBackgroundColorSlot) -> Binding<Color> {
        Binding(
            get: {
                let config = settings.pageBackgroundConfig(for: pageBackgroundScope)
                let stored = slot == .primary
                    ? config.primaryHex(for: scheme)
                    : config.secondaryHex(for: scheme)
                if let stored {
                    return Color(uiColor: AppearanceThemePreset.hex(stored))
                }
                if pageBackgroundScope != .global {
                    let globalConfig = settings.pageBackgroundConfig(for: .global)
                    let globalStored = slot == .primary
                        ? globalConfig.primaryHex(for: scheme)
                        : globalConfig.secondaryHex(for: scheme)
                    if let globalStored {
                        return Color(uiColor: AppearanceThemePreset.hex(globalStored))
                    }
                }
                return Color(uiColor: AppearanceThemePreset.hex(
                    Self.defaultHex(scheme: scheme, slot: slot)
                ))
            },
            set: { value in
                guard let hex = UIColor(value).rgbHex else { return }
                var config = settings.pageBackgroundConfig(for: pageBackgroundScope)
                if slot == .primary {
                    config.setPrimaryHex(hex, for: scheme)
                } else {
                    config.setSecondaryHex(hex, for: scheme)
                }
                settings.updatePageBackgroundConfig(config, for: pageBackgroundScope)
            }
        )
    }

    /// Placeholder swatch values shown before the user picks anything; chosen to
    /// match the stock system page look for each appearance.
    private static func defaultHex(scheme: ColorScheme, slot: PageBackgroundColorSlot) -> UInt32 {
        if scheme == .dark {
            return slot == .primary ? 0x1C1C1E : 0x2C2C2E
        }
        return slot == .primary ? 0xF2F2F7 : 0xFFFFFF
    }

    // MARK: - Pictures

    private func hasBackgroundImage(scheme: ColorScheme) -> Bool {
        settings.pageBackgroundConfig(for: pageBackgroundScope).imageFileName(for: scheme) != nil
    }

    /// The whole row opens the picker: the picture, once chosen, shows at its end.
    private func imagePickerRow(scheme: ColorScheme) -> some View {
        let titleKey = scheme == .dark ? "深色背景图" : "亮色背景图"
        let fileName = settings.pageBackgroundConfig(for: pageBackgroundScope).imageFileName(for: scheme)
        return ImageSourcePickerButton(
            accessibilityTitle: localized(titleKey),
            extraActions: fileName == nil ? [] : [
                ImageSourcePickerAction(
                    title: localized("移除背景图"),
                    systemImage: "trash",
                    isDestructive: true,
                    action: {
                        settings.clearPageBackgroundImage(
                            scope: pageBackgroundScope,
                            appearance: scheme
                        )
                    }
                )
            ],
            onPick: { result in handlePick(result, for: scheme) }
        ) {
            LabeledContent {
                if let fileName,
                   let image = AppearancePageBackgroundImageStore.shared.image(fileName: fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
                                .stroke(DSColor.border, lineWidth: 0.5)
                        )
                        .accessibilityHidden(true)
                } else {
                    Text(localized("选择"))
                        .foregroundStyle(DSColor.textSecondary)
                }
            } label: {
                Text(localized(titleKey))
                    .foregroundStyle(DSColor.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsSettingsCardRow()
    }

    private func imageOpacityRow(scheme: ColorScheme) -> some View {
        SettingsSliderRow(
            title: localized(scheme == .dark ? "深色不透明度" : "亮色不透明度"),
            systemImage: "drop.halffull",
            valueText: opacityPercentText(scheme: scheme),
            value: opacityBinding(scheme: scheme),
            range: 0...1,
            step: 0.05
        )
        .dsSettingsCardRow(minHeight: 0)
    }

    private func opacityBinding(scheme: ColorScheme) -> Binding<Double> {
        Binding(
            get: {
                let config = settings.pageBackgroundConfig(for: pageBackgroundScope)
                let stored = config.imageOpacity(for: scheme)
                if stored != 1.0 { return stored }
                if pageBackgroundScope != .global {
                    let globalConfig = settings.pageBackgroundConfig(for: .global)
                    let globalStored = globalConfig.imageOpacity(for: scheme)
                    if globalStored != 1.0 { return globalStored }
                }
                return 1.0
            },
            set: { value in
                var config = settings.pageBackgroundConfig(for: pageBackgroundScope)
                config.setImageOpacity(value, for: scheme)
                settings.updatePageBackgroundConfig(config, for: pageBackgroundScope)
            }
        )
    }

    /// The one source for both the printed percentage and the slider's VoiceOver
    /// value, so what is spoken can never drift from what is shown.
    private func opacityPercentText(scheme: ColorScheme) -> String {
        String(format: "%.0f%%", opacityBinding(scheme: scheme).wrappedValue * 100)
    }

    private func handlePick(_ result: Result<PickedImageSource, PickedImageError>, for scheme: ColorScheme) {
        let scope = pageBackgroundScope
        do {
            switch result {
            case .success(.data(let data)):
                try settings.importPageBackgroundImage(data: data, scope: scope, appearance: scheme)
            case .success(.file(let url)):
                try settings.importPageBackgroundImage(from: url, scope: scope, appearance: scheme)
            case .failure(let error):
                importFailure = localized(error.messageKey)
            }
        } catch let error as AppearancePageBackgroundImageError {
            importFailure = localized(error.messageKey)
        } catch {
            AppLogger.error("⟐ page background picture import failed", error: error)
            importFailure = localized("无法读取图片。")
        }
    }

    // MARK: - Preview

    /// Live preview of the effective background for the edited scope in the current
    /// appearance (with global fallback), or the stock look when the scope has nothing
    /// configured.
    private var previewCard: some View {
        let slice = settings.resolvedPageBackgroundSlice(
            for: pageBackgroundScope,
            colorScheme: colorScheme
        )
        let modeName = colorScheme == .dark ? localized("深色模式") : localized("亮色模式")
        return ZStack {
            if let slice {
                AppearancePageBackgroundLayerView(slice: slice)
            } else {
                DSColor.groupedBackground
            }
            VStack(spacing: DSSpacing.sm) {
                Text(localized("背景预览"))
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Text("\(pageBackgroundScope.localizedTitle) · \(modeName)")
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                Text(localized("弱文字样例"))
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary.opacity(0.72))
            }
            .padding(DSSpacing.lg)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
        .shadow(color: Color.primary.opacity(0.15), radius: 16, x: 0, y: 6)
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.5),
                            .clear,
                            .black.opacity(0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
                .blur(radius: 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Which end of the page-background gradient a colour row edits.
private enum PageBackgroundColorSlot {
    case primary
    case secondary
}

#Preview {
    NavigationStack {
        AppearancePageBackgroundView()
    }
}