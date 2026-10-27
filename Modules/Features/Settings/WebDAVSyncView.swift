import SwiftUI
import Combine

struct WebDAVSyncView: View {

    @StateObject private var manager = WebDAVManager.shared
    @ObservedObject private var gs = GlobalSettings.shared

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showConflictAlert = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
            VStack(spacing: DSSpacing.lg) {
                serverSection
                actionsSection
                statusSection
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.xl)
        }
        }
        .softScrollEdges()
        .navigationTitle(localized("WebDAV 同步"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .disabled(manager.isSyncing)
        .overlay {
            if manager.isSyncing {
                syncingOverlay
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button(localized("確定"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onChange(of: manager.pendingConflict != nil) { _, hasConflict in
            if hasConflict { showConflictAlert = true }
        }
        .alert(localized("偵測到備份衝突"), isPresented: $showConflictAlert) {
            Button(localized("使用雲端備份"), role: .destructive) {
                Task { try? await manager.resolveConflict(keepRemote: true) }
            }
            Button(localized("保留本地資料"), role: .cancel) {
                Task { try? await manager.resolveConflict(keepRemote: false) }
            }
        } message: {
            if let c = manager.pendingConflict {
                Text(conflictMessage(c))
            }
        }
    }

    private func conflictMessage(_ c: SyncConflict) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short; fmt.timeStyle = .short
        let remoteDate = fmt.string(from: c.remote.backupDate)
        let localDate  = fmt.string(from: c.localLastSync)
        return localized("雲端備份來自裝置「\(c.remote.deviceName)」（\(remoteDate)）。本裝置上次同步：\(localDate)。請選擇要使用哪個版本。")
    }

    // MARK: - Sections

    private var serverSection: some View {
        DSSettingsGroupCard(title: localized("伺服器設定")) {
            HStack {
                Text(localized("網址"))
                    .foregroundColor(DSColor.textSecondary)
                TextField("https://example.com/dav", text: $manager.serverUrl)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
            }
            .padding(.horizontal, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 54)

            DSSettingsCardDivider()

            HStack {
                Text(localized("帳號"))
                    .foregroundColor(DSColor.textSecondary)
                TextField(localized("使用者名稱"), text: $manager.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 54)

            DSSettingsCardDivider()

            HStack {
                Text(localized("密碼"))
                    .foregroundColor(DSColor.textSecondary)
                SecureField(localized("密碼"), text: $manager.password)
            }
            .padding(.horizontal, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 54)
        }
    }

    private var actionsSection: some View {
        DSSettingsGroupCard(title: localized("操作")) {
            DSSettingsCardRow(icon: "network", title: localized("測試連線")) {
                Task { await testConnection() }
            }

            DSSettingsCardDivider()

            DSSettingsCardRow(icon: "icloud.and.arrow.up", title: localized("備份到雲端")) {
                Task { await runBackup() }
            }

            DSSettingsCardDivider()

            DSSettingsCardRow(icon: "icloud.and.arrow.down", title: localized("從雲端還原")) {
                Task { await runRestore() }
            }
        }
    }

    private var statusSection: some View {
        DSSettingsGroupCard(title: localized("狀態")) {
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

    // MARK: - Actions

    private func testConnection() async {
        guard validateSettings() else { return }
        let ok = await manager.testConnection()
        await MainActor.run {
            alertTitle   = ok ? localized("連線成功") : localized("連線失敗")
            alertMessage = ok
                ? localized("已成功連線至 WebDAV 伺服器")
                : localized("無法連線，請確認網址、帳號及密碼")
            showAlert = true
        }
    }

    private func runBackup() async {
        guard validateSettings() else { return }
        do {
            try await manager.backup()
            await MainActor.run {
                alertTitle   = localized("備份成功")
                alertMessage = localized("資料已成功備份至雲端")
                showAlert    = true
            }
        } catch {
            presentError(error)
        }
    }

    private func runRestore() async {
        guard validateSettings() else { return }
        do {
            try await manager.restore()
            await MainActor.run {
                alertTitle   = localized("還原成功")
                alertMessage = localized("資料已還原，書庫與替換規則已即時更新")
                showAlert    = true
            }
        } catch {
            presentError(error)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func validateSettings() -> Bool {
        guard !manager.serverUrl.isEmpty else {
            alertTitle   = localized("設定不完整")
            alertMessage = localized("請填寫伺服器網址")
            showAlert    = true
            return false
        }
        return true
    }

    private func presentError(_ error: Error) {
        Task { @MainActor in
            alertTitle   = localized("操作失敗")
            alertMessage = error.localizedDescription
            showAlert    = true
        }
    }
}