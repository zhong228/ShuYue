import CloudKit
import SwiftUI

struct ICloudSyncView: View {
    @StateObject private var manager = ICloudSyncManager.shared
    @ObservedObject private var gs = GlobalSettings.shared

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showDeleteConfirmation = false

    private var iCloudReady: Bool { manager.accountStatus == .available }

    var body: some View {
        ScrollView {
            AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
            VStack(spacing: DSSpacing.lg) {
                accountSection
                autoSyncSection
                actionsSection
                statusSection
                deleteSection
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.xl)
        }
        }
        .softScrollEdges()
        .navigationTitle(localized("iCloud 同步"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .disabled(manager.isSyncing)
        .overlay {
            if manager.isSyncing {
                syncingOverlay
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button(localized("确定"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .task {
            _ = await manager.refreshAccountStatus()
        }
    }

    private var accountSection: some View {
        DSSettingsGroupCard(title: localized("帐号状态"), footer: {
            if !iCloudReady {
                Text(manager.unavailableFooterText)
                    .dsSectionFooter()
            }
        }) {
            HStack {
                Label(manager.statusTitle(isAppSignedIn: true), systemImage: statusIcon)
                    .foregroundColor(statusColor)
                Spacer()
                if iCloudReady {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 54)
        }
    }

    private var autoSyncSection: some View {
        DSSettingsGroupCard(title: "", footer: {
            Text(localized("启动与切背景时自动同步书库、书源、替换规则、书档、阅读设定、气泡样式与自订阅读背景。多台装置会合并，不会互相覆盖。"))
                .dsSectionFooter()
        }) {
            DSSettingsCardToggle(
                title: localized("自动同步"),
                systemImage: "arrow.triangle.2.circlepath",
                isOn: $gs.iCloudAutoSync
            )
            .tint(DSColor.accent)
            .onChange(of: gs.iCloudAutoSync) { _, on in
                if on, iCloudReady { Task { try? await manager.sync(reason: "toggle-on") } }
            }
        }
    }

    private var actionsSection: some View {
        DSSettingsGroupCard(title: localized("操作")) {
            DSSettingsCardRow(icon: "arrow.triangle.2.circlepath.icloud", title: localized("立即同步")) {
                Task { await runSync() }
            }
            .disabled(!iCloudReady)

            DSSettingsCardDivider()

            DSSettingsCardRow(icon: "checkmark.icloud", title: localized("检查 iCloud 状态")) {
                Task { await refreshStatus() }
            }
        }
    }

    private var statusSection: some View {
        DSSettingsGroupCard(title: localized("状态")) {
            if let date = manager.lastSyncDate {
                HStack {
                    Text(localized("上次同步"))
                        .foregroundColor(DSColor.textSecondary)
                    Spacer()
                    Text(date, style: .relative)
                        .foregroundColor(DSColor.textPrimary)
                }
                .padding(.horizontal, DSSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 54)
            }

            if !manager.statusMessage.isEmpty {
                if manager.lastSyncDate != nil {
                    DSSettingsCardDivider()
                }
                Text(manager.statusMessage)
                    .foregroundColor(DSColor.textSecondary)
                    .font(DSFont.footnote)
                    .padding(.horizontal, DSSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 54)
            }
        }
    }

    /// Apart from the other actions, at the bottom: it cannot be undone.
    private var deleteSection: some View {
        DSSettingsGroupCard(title: "") {
            DSSettingsCardRow(icon: "trash", title: localized("删除 iCloud 上的资料")) {
                showDeleteConfirmation = true
            }
            .disabled(!iCloudReady)
        }
        .alert(localized("删除 iCloud 上的资料？"), isPresented: $showDeleteConfirmation) {
            Button(localized("删除"), role: .destructive) {
                Task { await runDeleteRemoteData() }
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(localized("会删除 iCloud 上的书库、书源、替换规则、书档、阅读设定、气泡样式与阅读背景，并关闭这台装置的自动同步。这台装置上的资料不受影响；其他装置开著自动同步时，会再上传它们的资料。"))
        }
    }

    private var statusIcon: String {
        iCloudReady ? "icloud.fill" : "exclamationmark.icloud"
    }

    private var statusColor: Color {
        switch manager.accountStatus {
        case .available:
            return DSColor.accent
        case .noAccount, .restricted, .temporarilyUnavailable:
            return .orange
        default:
            return .secondary
        }
    }

    private var syncingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                Text(manager.statusMessage)
                    .foregroundColor(.white)
                    .font(DSFont.subheadline)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .cornerRadius(DSRadius.xl)
        }
    }

    private func refreshStatus() async {
        let status = await manager.refreshAccountStatus()
        await MainActor.run {
            alertTitle = status == .available ? localized("iCloud 可用") : localized("iCloud 无法使用")
            alertMessage = manager.statusTitle(isAppSignedIn: true)
            showAlert = true
        }
    }

    private func runSync() async {
        do {
            try await manager.sync(reason: "manual")
            await MainActor.run {
                alertTitle = localized("同步成功")
                alertMessage = localized("书库、书源与替换规则已更新")
                showAlert = true
            }
        } catch {
            presentError(error)
        }
    }

    private func runDeleteRemoteData() async {
        // Off first: a sync on the way to the background would upload it all again,
        // mid-deletion or right after.
        await MainActor.run { gs.iCloudAutoSync = false }
        do {
            try await manager.deleteRemoteData()
            await MainActor.run {
                alertTitle = localized("已删除 iCloud 上的同步资料")
                alertMessage = localized("这台装置的自动同步已关闭。")
                showAlert = true
            }
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        Task { @MainActor in
            alertTitle = localized("操作失败")
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        ICloudSyncView()
    }
}