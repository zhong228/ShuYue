import SwiftUI
import Combine

struct LanServerView: View {
    @StateObject private var server = LanWebServer.shared
    @ObservedObject private var gs = GlobalSettings.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BookStore

    var body: some View {
        NavigationStack {
            ScrollView {
                AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
                VStack(spacing: DSSpacing.lg) {
                    // 分组卡片：服务状态 / 开关 / 可用接口 三张卡片，替代系统 List Section（2026-10-25）。
                    statusCard
                    controlCard
                    endpointsCard
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xxl * 2)
            }
            }
            .softScrollEdges()
            .navigationTitle(localized("局域传书"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                server.bookProvider = store
            }
        }
    }

    // MARK: - Cards

    private var statusCard: some View {
        DSSettingsGroupCard(title: localized("服務狀態")) {
            HStack(spacing: 12) {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(server.isRunning ? localized("運行中") : localized("已停止"))
                    .foregroundColor(server.isRunning ? .green : DSColor.textSecondary)
                Spacer()
            }
            .dsSettingsCardRow()

            if server.isRunning && !server.localIPAddress.isEmpty {
                DSSettingsCardDivider()
                HStack {
                    Text(localized("地址"))
                        .foregroundColor(DSColor.textSecondary)
                    Spacer()
                    Text("http://" + server.localIPAddress + ":" + String(server.port))
                        .font(DSFont.monospaced())
                        .foregroundColor(DSColor.accent)
                        .textSelection(.enabled)
                }
                .dsSettingsCardRow()

                if !server.accessPIN.isEmpty {
                    DSSettingsCardDivider()
                    HStack {
                        Text(localized("PIN 碼"))
                            .foregroundColor(DSColor.textSecondary)
                        Spacer()
                        Text(server.accessPIN)
                            .font(DSFont.monospaced())
                            .foregroundColor(DSColor.accent)
                            .textSelection(.enabled)
                    }
                    .dsSettingsCardRow()
                }
            }
        }
    }

    private var controlCard: some View {
        DSSettingsGroupCard(title: localized("局域传书")) {
            Button {
                if server.isRunning {
                    server.stop()
                } else {
                    server.bookProvider = store
                    server.start()
                }
            } label: {
                HStack {
                    Spacer()
                    Text(server.isRunning ? localized("停止服務") : localized("啟動服務"))
                        .fontWeight(.semibold)
                        .foregroundColor(server.isRunning ? .red : DSColor.accent)
                    Spacer()
                }
                .dsSettingsCardRow()
            }
            .buttonStyle(.plain)
        }
    }

    private var endpointsCard: some View {
        DSSettingsGroupCard(title: localized("可用接口")) {
            endpointRow(method: "GET", path: "/", description: localized("書架列表"))
            DSSettingsCardDivider()
            endpointRow(method: "GET", path: "/book/:id", description: localized("書籍詳情"))
            DSSettingsCardDivider()
            endpointRow(method: "GET", path: "/api/sources", description: localized("書源列表"))
            DSSettingsCardDivider()
            endpointRow(method: "GET", path: "/health", description: localized("健康檢查"))
        }
    }

    // MARK: - Helpers

    private func endpointRow(method: String, path: String, description: String) -> some View {
        HStack(spacing: 10) {
            Text(method)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DSColor.accent.opacity(0.15))
                .foregroundColor(DSColor.accent)
                .cornerRadius(4)
            Text(path)
                .font(DSFont.monospaced())
                .foregroundColor(DSColor.textPrimary)
            Spacer()
            Text(description)
                .font(DSFont.caption)
                .foregroundColor(DSColor.textSecondary)
        }
        .dsSettingsCardRow(minHeight: 44)
    }
}