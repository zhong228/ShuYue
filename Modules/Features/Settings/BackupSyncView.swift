import SwiftUI

struct BackupSyncView: View {
    @StateObject private var iCloudManager = ICloudSyncManager.shared
    @StateObject private var webDAVManager = WebDAVManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // 分组卡片：iCloud 与 WebDAV 两个同步入口合为一张卡片（2026-10-25）。
                    DSSettingsGroupCard(title: localized("備份與同步方式")) {
                        DSSettingsCardNavRow(
                            icon: "icloud.fill",
                            title: localized("iCloud 同步"),
                            detail: iCloudManager.statusTitle(isAppSignedIn: true)
                        ) {
                            ICloudSyncView()
                        }
                        DSSettingsCardDivider()
                        DSSettingsCardNavRow(
                            icon: "icloud.and.arrow.up.fill",
                            title: localized("WebDAV 同步"),
                            detail: webDAVDetail
                        ) {
                            WebDAVSyncView()
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xxl * 2)
            }
            .softScrollEdges()
            .navigationTitle(localized("云备份"))
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
                _ = await iCloudManager.refreshAccountStatus()
            }
        }
    }

    private var webDAVDetail: String {
        if webDAVManager.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localized("尚未設定伺服器")
        }
        return webDAVManager.lastSyncDate == nil
            ? localized("已設定，尚未同步")
            : localized("已設定")
    }
}

#Preview {
    BackupSyncView()
}