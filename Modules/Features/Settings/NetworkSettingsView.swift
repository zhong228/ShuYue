import SwiftUI

struct NetworkSettingsView: View {
    @ObservedObject private var settings = GlobalSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
                VStack(spacing: DSSpacing.lg) {
                    // 分组卡片：网络请求的四个设置合为一张卡片，替代系统 Form Section（2026-10-25）。
                    DSSettingsGroupCard(title: localized("网络连接"), footer: {
                        Text(localized("換源搜索時順便抓取每個書源的目錄，點選書源可立即切換；代價是搜索期間的網路請求加倍"))
                            .dsSectionFooter()
                    }) {
                        stepperRow(
                            icon: "arrow.left.arrow.right",
                            title: localized("並發數"),
                            description: localized("搜索/缓存/下载/校验等网络请求并发数，建议16个"),
                            value: $settings.searchConcurrency,
                            range: 1...30
                        )
                        DSSettingsCardDivider()
                        stepperRow(
                            icon: "pause.circle",
                            title: localized("自動暫停"),
                            description: localized("每搜索到N个精確結果(或5N個模糊結果)後自動暫停(0不暫停)，防止設備發燙和流量消耗過多"),
                            value: $settings.searchAutoPauseCount,
                            range: 0...50
                        )
                        DSSettingsCardDivider()
                        stepperRow(
                            icon: "clock.arrow.circlepath",
                            title: localized("搜索結果快取天數"),
                            description: localized("搜索時啟用快取，避免重複搜索，預設快取 5 日"),
                            value: $settings.searchCacheDays,
                            range: 0...30
                        )
                        DSSettingsCardDivider()
                        DSSettingsCardToggle(
                            title: localized("換源時載入目錄"),
                            systemImage: "arrow.triangle.2.circlepath",
                            isOn: $settings.changeSourceLoadToc
                        )
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xxl * 2)
            }
            }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .navigationTitle(localized("网络连接"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    /// A settings row with a title, the current value, a native stepper, and a
    /// description. The value is shown next to the stepper (the stepper's own
    /// label stays hidden), and the stepper keeps its native appearance so the
    /// −/+ control blends into the card's surface.
    @ViewBuilder
    private func stepperRow(
        icon: String,
        title: String,
        description: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            DSIconBadge(
                systemImage: icon,
                gradient: DSBrandGradient.tint(for: icon),
                side: 30,
                iconSize: 16
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(DSFont.body)
                        .foregroundColor(DSColor.textPrimary)
                    Spacer()
                    Text("\(value.wrappedValue)")
                        .font(DSFont.bodyBold)
                        .monospacedDigit()
                        .foregroundColor(DSColor.textSecondary)
                    Stepper("", value: value, in: range)
                        .labelsHidden()
                        .fixedSize()
                }
                Text(description)
                    .font(DSFont.caption)
                    .foregroundColor(DSColor.textSecondary)
            }
        }
        .padding(.vertical, DSSpacing.sm)
        .dsSettingsCardRow(minHeight: 0)
    }
}

#Preview {
    NetworkSettingsView()
}