import Combine
import SwiftUI

@MainActor
final class CacheManagementViewModel: ObservableObject {
    @Published private(set) var snapshot = CacheStorageSnapshot()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: CacheManagementService

    init(service: CacheManagementService = CacheManagementService()) {
        self.service = service
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let service = service
        snapshot = await Task.detached(priority: .utility) {
            service.snapshot()
        }.value
        isLoading = false
    }

    func clear(_ category: CacheCategory) async {
        isLoading = true
        errorMessage = nil
        let service = service
        do {
            try await Task.detached(priority: .utility) {
                try service.clear(category)
            }.value
            snapshot = await Task.detached(priority: .utility) {
                service.snapshot()
            }.value
        } catch {
            AppLogger.error("CacheManagementView clear failed", error: error)
            errorMessage = localized("快取操作失败")
        }
        isLoading = false
    }

    func clearAll() async {
        isLoading = true
        errorMessage = nil
        let service = service
        do {
            try await Task.detached(priority: .utility) {
                try service.clearAll()
            }.value
            snapshot = CacheStorageSnapshot()
        } catch {
            AppLogger.error("CacheManagementView clear-all failed", error: error)
            errorMessage = localized("快取操作失败")
            snapshot = await Task.detached(priority: .utility) {
                service.snapshot()
            }.value
        }
        isLoading = false
    }
}

struct CacheManagementView: View {
    private enum CacheConfirmation: Identifiable {
        case category(CacheCategory)
        case all

        var id: String {
            switch self {
            case .category(let category): return "category-\(category.id)"
            case .all: return "all"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CacheManagementViewModel
    @State private var pendingConfirmation: CacheConfirmation?
    @State private var showError = false
    // 自动清理设置走 @AppStorage：值变化即触发 SwiftUI 重绘。裸 UserDefaults
    // 写入没有可观察状态，阈值选定后界面不刷新（"阈值无法切换"的根因）。
    @AppStorage(AutoCacheCleanup.enabledKey) private var autoCleanupEnabled = false
    @AppStorage(AutoCacheCleanup.thresholdKey) private var thresholdMB: Int = AutoCacheCleanup.defaultThresholdMB

    init(service: CacheManagementService = CacheManagementService()) {
        _viewModel = StateObject(
            wrappedValue: CacheManagementViewModel(service: service)
        )
    }

    var body: some View {
        NavigationStack {
            // 分组卡片：每个快取分类各成一张卡片，替代系统 Form Section（2026-10-25）。
            ScrollView {
                AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
                VStack(spacing: DSSpacing.lg) {
                    autoCleanupSection

                    if viewModel.isLoading && viewModel.snapshot.total == 0 {
                        DSSettingsGroupCard(title: "") {
                            HStack {
                                Spacer()
                                ProgressView(localized("正在读取快取大小…"))
                                Spacer()
                            }
                            .dsSettingsCardRow(minHeight: 0)
                            .padding(.vertical, DSSpacing.sm)
                        }
                    }

                    if viewModel.errorMessage != nil {
                        DSSettingsGroupCard(title: "") {
                            Label(
                                localized("快取操作失败"),
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundColor(DSColor.warning)
                            .dsSettingsCardRow()

                            DSSettingsCardDivider()

                            DSSettingsCardActionRow(
                                title: localized("重试"),
                                systemImage: "arrow.clockwise",
                                role: .standard
                            ) {
                                Task { await viewModel.refresh() }
                            }
                        }
                    }

                    ForEach(CacheCategory.allCases) { category in
                        cacheSection(for: category)
                    }

                    DSSettingsGroupCard(title: "", footer: {
                        Text(localized("书籍、设定与备份同步资料不会受影响。"))
                            .dsSectionFooter()
                    }) {
                        Button {
                            pendingConfirmation = .all
                        } label: {
                            HStack {
                                Spacer()
                                Text(localized("清除全部快取"))
                                    .foregroundColor(DSColor.destructive)
                                Spacer()
                            }
                        }
                        .disabled(viewModel.isLoading || viewModel.snapshot.total == 0)
                        .accessibilityHint(localized("将清除所有可重新下载的快取内容"))
                        .dsSettingsCardRow()
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xxl * 2)
            }
            }
            .softScrollEdges()
            .navigationTitle(localized("存储清理"))
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
            .task {
                await viewModel.refresh()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .alert(item: $pendingConfirmation) { confirmation in
                switch confirmation {
                case .category(let category):
                    Alert(
                        title: Text(localized("清除快取？")),
                        message: Text(localized(category.detailKey)),
                        primaryButton: .destructive(Text(localized(category.clearTitleKey))) {
                            pendingConfirmation = nil
                            Task { await viewModel.clear(category) }
                        },
                        secondaryButton: .cancel(Text(localized("取消"))) {
                            pendingConfirmation = nil
                        }
                    )
                case .all:
                    Alert(
                        title: Text(localized("清除全部快取？")),
                        message: Text(localized("将删除所有可重新下载的快取内容。书籍、设定与备份同步资料不会受影响。")),
                        primaryButton: .destructive(Text(localized("清除全部快取"))) {
                            pendingConfirmation = nil
                            Task { await viewModel.clearAll() }
                        },
                        secondaryButton: .cancel(Text(localized("取消"))) {
                            pendingConfirmation = nil
                        }
                    )
                }
            }
            .onChange(of: viewModel.errorMessage) { _, message in
                showError = message != nil
            }
            .alert(localized("操作失败"), isPresented: $showError) {
                Button(localized("确定"), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? localized("快取操作失败"))
            }
        }
    }

    /// 自动清理：开关 + 触发阈值。设置直接走 UserDefaults（AutoCacheCleanup），
    /// 与页面其余的手动清理卡片互不影响。
    private var autoCleanupSection: some View {
        DSSettingsGroupCard(title: localized("自动清理"), footer: {
            Text(localized("开启后每次启动检查一次：快取总量（不含诊断纪录）达到设定值时自动清除，无需手动操作。"))
                .dsSectionFooter()
        }) {
            Toggle(isOn: $autoCleanupEnabled) {
                SettingsRowLabel(localized("自动清理"), systemImage: "sparkles")
            }
            .tint(DSColor.appAccent)
            .dsSettingsCardRow()

            DSSettingsCardDivider()

            HStack {
                SettingsRowLabel(localized("清理阈值"), systemImage: "gauge.with.dots.needle.67percent")
                Spacer()
                Menu {
                    ForEach(AutoCacheCleanup.thresholdOptions, id: \.self) { mb in
                        Button {
                            thresholdMB = mb
                        } label: {
                            if thresholdMB == mb {
                                Label("\(mb) MB", systemImage: "checkmark")
                            } else {
                                Text("\(mb) MB")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("\(thresholdMB) MB")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(DSFont.caption2.weight(.semibold))
                    }
                    .foregroundStyle(DSColor.textSecondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
            .dsSettingsCardRow()
        }
    }

    private func cacheSection(for category: CacheCategory) -> some View {
        DSSettingsGroupCard(title: localized(category.titleKey), footer: {
            Text(localized(category.detailKey))
                .dsSectionFooter()
        }) {
            DSSettingsCardValueRow(
                localized("占用空间"),
                value: formattedByteCount(viewModel.snapshot[category])
            )

            DSSettingsCardDivider()

            DSSettingsCardActionRow(
                title: localized(category.clearTitleKey),
                systemImage: "trash",
                role: .standard
            ) {
                pendingConfirmation = .category(category)
            }
            .disabled(viewModel.isLoading || viewModel.snapshot[category] == 0)
        }
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    CacheManagementView()
}