import SwiftUI

/// Pushed inside the existing Calibre library navigation stack. Starting
/// discovery is explicit so local-network permission is requested in context.
struct CalibreWirelessView: View {
    @ObservedObject var store: BookStore
    @ObservedObject var service: CalibreWirelessService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage("calibreWirelessHost") private var host = ""
    @AppStorage("calibreWirelessPort") private var port = "9090"
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                statusRow
                if service.state.isActive {
                    Button(localized("中断连线"), role: .destructive) { service.disconnect() }
                }
            } header: {
                Text(localized("连线状态"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("先在电脑 Calibre 的「连线／分享」启动无线装置连线。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()

            if !service.state.isActive {
                Section {
                    SecureField(localized("无线装置密码（选填）"), text: $password)
                        .textContentType(.password)
                } footer: {
                    Text(localized("输入 Calibre 无线装置设定的密码，仅供本次连线使用。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()

                Section {
                    ForEach(service.servers) { server in
                        Button {
                            service.connect(server: server, password: password, store: store)
                        } label: {
                            Label(server.name, systemImage: "desktopcomputer")
                        }
                    }
                    if service.isDiscovering && service.servers.isEmpty {
                        ProgressView(localized("正在搜寻附近的 Calibre…"))
                    }
                    if let error = service.discoveryError {
                        Text(error).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                        Button(localized("开启系统设定")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    Button(service.isDiscovering ? localized("停止搜寻") : localized("搜寻附近电脑")) {
                        if service.isDiscovering { service.stopDiscovery() }
                        else { service.startDiscovery() }
                    }
                } header: {
                    Text(localized("附近的 Calibre"))
                        .foregroundStyle(DSColor.textSecondary)
                } footer: {
                    Text(localized("需要同一区域网路，并允许本 App 存取本机网路。"))
                        .dsSectionFooter()
                }
                .interfaceSectionSurface()

                Section(localized("手动连线")) {
                    TextField(localized("电脑 IP 或主机名称"), text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField(localized("连接埠"), text: $port)
                        .keyboardType(.numberPad)
                    Button(localized("连线")) {
                        service.connect(host: host, port: UInt16(port) ?? 0, password: password, store: store)
                    }
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (UInt16(port) ?? 0) == 0)
                }
                .interfaceSectionSurface()
            }

            Section {
                if service.transfers.isEmpty {
                    Text(localized("尚未接收书籍"))
                        .foregroundStyle(DSColor.textSecondary)
                } else {
                    ForEach(service.transfers.reversed()) { transfer in
                        transferRow(transfer)
                    }
                }
            } header: {
                Text(localized("接收纪录"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("传送期间请保持此页开启，离开或切背景会中断。支援 EPUB、PDF、TXT、Markdown。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("电脑传书"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .bookshelf)
        .onDisappear {
            service.stopDiscovery()
            service.disconnect()
            password = ""
        }
        .onChange(of: scenePhase) { _, value in
            if value == .background {
                service.stopDiscovery()
                service.disconnect()
                password = ""
            }
        }
        .onChange(of: service.transfers) { previous, current in
            if let completed = current.last(where: { entry in
                entry.phase == .completed && previous.first(where: { $0.id == entry.id })?.phase != .completed
            }) {
                UIAccessibility.post(notification: .announcement, argument: completed.title + "，" + localized("已加入书架"))
            }
        }
        .onChange(of: service.state) { _, current in
            switch current {
            case .connected(let name):
                UIAccessibility.post(notification: .announcement, argument: localized("已连线") + "，" + name)
            case .failed(let message):
                UIAccessibility.post(notification: .announcement, argument: message)
            default: break
            }
        }
        .onChange(of: service.discoveryError) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
    }

    @ViewBuilder private var statusRow: some View {
        switch service.state {
        case .disconnected:
            Label(localized("尚未连线"), systemImage: "network")
                .foregroundStyle(DSColor.textSecondary)
        case .connecting:
            ProgressView(localized("正在连接 Calibre…"))
        case .connected(let name):
            ThemedLabeledContent(localized("已连线"), value: name)
        case .failed(let message):
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Label(localized("连线失败"), systemImage: "exclamationmark.triangle")
                Text(message).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    private func transferRow(_ transfer: CalibreTransferStatus) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(transfer.title).font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
            switch transfer.phase {
            case .receiving:
                ProgressView(value: Double(transfer.receivedBytes), total: Double(transfer.totalBytes)) {
                    Text(localized("正在接收"))
                        .foregroundStyle(DSColor.textPrimary)
                } currentValueLabel: {
                    Text(byteProgress(transfer))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .accessibilityValue(byteProgress(transfer))
            case .importing:
                ProgressView(localized("正在汇入书架…"))
            case .completed:
                Label(localized("已加入书架"), systemImage: "checkmark.circle")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
            case .failed(let message):
                Text(message).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            case .cancelled:
                Text(localized("已取消接收"))
                    .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    private func byteProgress(_ transfer: CalibreTransferStatus) -> String {
        let received = ByteCountFormatter.string(fromByteCount: transfer.receivedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: transfer.totalBytes, countStyle: .file)
        return "\(received) / \(total)"
    }
}

#Preview {
    NavigationStack {
        CalibreWirelessView(store: BookStore(), service: CalibreWirelessService())
    }
}
