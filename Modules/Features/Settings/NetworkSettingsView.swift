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
                        Text(localized("换源搜索时顺便抓取每个书源的目录，点选书源可立即切换；代价是搜索期间的网路请求加倍"))
                            .dsSectionFooter()
                    }) {
                        stepperRow(
                            icon: "arrow.left.arrow.right",
                            title: localized("并发数"),
                            description: localized("搜索/缓存/下载/校验等网络请求并发数，建议16个"),
                            value: $settings.searchConcurrency,
                            range: 1...30
                        )
                        DSSettingsCardDivider()
                        stepperRow(
                            icon: "pause.circle",
                            title: localized("自动暂停"),
                            description: localized("每搜索到N个精确结果(或5N个模糊结果)后自动暂停(0不暂停)，防止设备发烫和流量消耗过多"),
                            value: $settings.searchAutoPauseCount,
                            range: 0...50
                        )
                        DSSettingsCardDivider()
                        stepperRow(
                            icon: "clock.arrow.circlepath",
                            title: localized("搜索结果快取天数"),
                            description: localized("搜索时启用快取，避免重复搜索，预设快取 5 日"),
                            value: $settings.searchCacheDays,
                            range: 0...30
                        )
                        DSSettingsCardDivider()
                        DSSettingsCardToggle(
                            title: localized("换源时载入目录"),
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