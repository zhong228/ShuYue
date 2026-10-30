import SwiftUI

/// Pre-run page (screenshot 1): explains the five validation stages, offers the
/// Legado check toggles and the bad/slow-source policy under "更多选项", and starts
/// the run. Presented from the source list; the run itself continues in the background
/// after dismissal.
struct BookSourceCheckOptionsView: View {
    let sourceCount: Int
    @State private var policy: BookSourceCheckPolicy
    let onStart: (BookSourceCheckPolicy) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        sourceCount: Int,
        initialPolicy: BookSourceCheckPolicy,
        onStart: @escaping (BookSourceCheckPolicy) -> Void
    ) {
        self.sourceCount = sourceCount
        self._policy = State(initialValue: initialPolicy)
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.xl) {
                    Spacer(minLength: DSSpacing.xl)

                    Image(systemName: "waveform.and.magnifyingglass")
                        .font(DSFont.fixed(size: 48))
                        .foregroundColor(DSColor.accent)

                    VStack(spacing: DSSpacing.sm) {
                        Text(localized("准备验证"))
                            .font(DSFont.title2.weight(.bold))
                            .foregroundStyle(DSColor.textPrimary)
                        Text(
                            String(
                                format: localized("将对 %d 个书源进行五阶段验证"), sourceCount)
                        )
                        .font(DSFont.subheadline)
                        .foregroundColor(DSColor.textSecondary)
                    }

                    stageCard

                    moreOptions

                    Button {
                        onStart(policy)
                        dismiss()
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: "play.fill")
                            Text(localized("开始验证"))
                        }
                        .font(DSFont.bodyBold)
                        .foregroundColor(DSColor.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSSpacing.md)
                        .background(DSColor.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(sourceCount == 0)

                    Text(localized("验证包含网络请求，可能需要较长时间，请耐心等待"))
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xl)
            }
            .softScrollEdges()
            .scrollIndicators(.hidden)
            .navigationTitle(localized("书源验证"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(localized("关闭"))
                }
            }
        }
    }

    private var stageCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            ForEach(ValidationStage.allCases) { stage in
                HStack(alignment: .top, spacing: DSSpacing.md) {
                    Image(systemName: stage.symbol)
                        .font(DSFont.body)
                        .foregroundColor(stageColor(stage))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stage \(stage.rawValue + 1) · \(stage.longTitle)")
                            .font(DSFont.bodyBold)
                            .foregroundStyle(DSColor.textPrimary)
                        Text(stage.explanation)
                            .font(DSFont.caption)
                            .foregroundColor(DSColor.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.lg)
        .interfaceCardSurface(in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
    }

    private func stageColor(_ stage: ValidationStage) -> Color {
        switch stage {
        case .search:      return .blue
        case .discovery:   return .green
        case .detail:      return .orange
        case .toc:         return .teal
        case .content:     return .purple
        }
    }

    private var moreOptions: some View {
        DisclosureGroup {
            VStack(spacing: DSSpacing.md) {
                checkToggles

                Divider()

                if policy.checkSearch {
                    TextField(localized("测试关键字"), text: $policy.keyword)
                        .textFieldStyle(.roundedBorder)
                }

                Picker(localized("超时"), selection: $policy.timeoutSeconds) {
                    ForEach(BookSourceCheckPolicy.timeoutOptionsSeconds, id: \.self) { seconds in
                        Text("\(seconds) \(localized("秒"))").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)

                Divider()

                Picker(localized("坏书源处理"), selection: $policy.badAction) {
                    ForEach(BookSourceCheckPolicy.BadAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .pickerStyle(.segmented)

                if policy.badAction == .delete {
                    Text(localized("删除无法复原，请谨慎选择"))
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Toggle(localized("停用过慢书源"), isOn: $policy.disableSlow)
                    .padding(.trailing, 2)

                if policy.disableSlow {
                    Picker(localized("过慢阈值"), selection: $policy.slowThresholdMs) {
                        ForEach(BookSourceCheckPolicy.slowOptionsMs, id: \.self) { ms in
                            Text("\(ms / 1000) \(localized("秒"))").tag(ms)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.top, DSSpacing.sm)
        } label: {
            Text(localized("更多选项"))
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundColor(DSColor.textPrimary)
        }
        .padding(DSSpacing.md)
        .interfaceCardSurface(in: RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
    }

    /// Legado `CheckSource` toggles: 檢查搜索 / 檢查發現 / 檢查詳情 / 檢查目錄 / 檢查正文.
    /// The checkInfo/checkCategory/checkContent coupling matches Legado exactly
    /// (checkInfo=false skips the whole detail/toc/content chain).
    private var checkToggles: some View {
        VStack(spacing: DSSpacing.sm) {
            Toggle(localized("检查搜索"), isOn: $policy.checkSearch)
            Toggle(localized("检查发现"), isOn: $policy.checkDiscovery)
            Toggle(localized("检查详情"), isOn: $policy.checkInfo)
            Toggle(localized("检查目录"), isOn: $policy.checkCategory)
            Toggle(localized("检查正文"), isOn: $policy.checkContent)
        }
        .padding(.trailing, 2)
    }
}

#Preview {
    BookSourceCheckOptionsView(
        sourceCount: 32,
        initialPolicy: BookSourceCheckPolicy()
    ) { _ in }
}
