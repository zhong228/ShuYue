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
            errorMessage = localized("快取操作失敗")
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
            errorMessage = localized("快取操作失敗")
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

    init(service: CacheManagementService = CacheManagementService()) {
        _viewModel = StateObject(
            wrappedValue: CacheManagementViewModel(service: service)
        )
    }

    var body: some View {
        NavigationStack {
            // 分组卡片：每个快取分类各成一张卡片，替代系统 Form Section（2026-10-25）。
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    if viewModel.isLoading && viewModel.snapshot.total == 0 {
                        DSSettingsGroupCard(title: "") {
                            HStack {
                                Spacer()
                                ProgressView(localized("正在讀取快取大小…"))
                                Spacer()
                            }
                            .dsSettingsCardRow(minHeight: 0)
                            .padding(.vertical, DSSpacing.sm)
                        }
                    }

                    if viewModel.errorMessage != nil {
                        DSSettingsGroupCard(title: "") {
                            Label(
                                localized("快取操作失敗"),
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundColor(DSColor.warning)
                            .dsSettingsCardRow()

                            DSSettingsCardDivider()

                            DSSettingsCardActionRow(
                                title: localized("重試"),
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
                        Text(localized("書籍、設定與備份同步資料不會受影響。"))
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
                        .accessibilityHint(localized("將清除所有可重新下載的快取內容"))
                        .dsSettingsCardRow()
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xxl * 2)
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
                    .accessibilityLabel(localized("關閉"))
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
                        message: Text(localized("將刪除所有可重新下載的快取內容。書籍、設定與備份同步資料不會受影響。")),
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
            .alert(localized("操作失敗"), isPresented: $showError) {
                Button(localized("確定"), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? localized("快取操作失敗"))
            }
        }
    }

    private func cacheSection(for category: CacheCategory) -> some View {
        DSSettingsGroupCard(title: localized(category.titleKey), footer: {
            Text(localized(category.detailKey))
                .dsSectionFooter()
        }) {
            DSSettingsCardValueRow(
                localized("佔用空間"),
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