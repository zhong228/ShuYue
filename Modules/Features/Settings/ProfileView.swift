import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: BookStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var gs = GlobalSettings.shared
    @State private var showSourceList = false
    @State private var showDownloadManager = false
    @State private var showReplaceRules = false
    @State private var showBackupSync = false
    @State private var showCacheManagement = false
    @State private var showLanServer = false
    @State private var showLegadoMigration = false
    @State private var showTTSSettings = false
    @State private var showNetworkSettings = false
    @State private var showAISettings = false
    @State private var showAIPaywall = false
    #if DEBUG
    @State private var autoOpenDiagnostics = false
    #endif
    private let feedbackEmail = "172803068@qq.com"
    private let sourceCodeURL = URL(string: "https://github.com/zhong228/ShuYue/releases")

    private var feedbackMailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: localized("書悅 app 反饋"))
        ]
        return components.url
    }

    private var appLanguageFooter: String {
        // The footer points at the app's row in iOS Settings, which is titled by
        // CFBundleDisplayName (书悦) — not by CFBundleName, which trails the Xcode
        // product name (YueduReader) and would leak the upstream brand into the UI.
        let appName = Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? "ShuYue"
        let template = localized("跟隨系統語言。可在「設定 → %@ → 語言」單獨設定")
        return String(format: template, appName)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appearanceThemeName: String {
        gs.appearanceTheme(
            for: colorScheme,
            isProActive: subscriptionStore.hasAccess(.readerThemePacks)
        ).localizedName
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Brand Header ──
                Section {
                    ShuYueBrandHeaderCard(appVersion: appVersion)
                        .rootTabTitleScrollAnchor()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
                .listSectionSeparator(.hidden)

                // ── App Language ──
                Section(header: Text(localized("App 語言")).foregroundStyle(DSColor.textSecondary)) {
                    DSSettingsRow(
                        icon: "globe",
                        title: localized("語言"),
                        action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    )
                    .rootTabTitleScrollAnchor()

                    Text(appLanguageFooter)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.top, DSSpacing.xs)
                }

                // ── Appearance ──
                Section(header: Text(localized("外觀")).foregroundStyle(DSColor.textSecondary)) {
                    DSSettingsNavRow(
                        icon: "paintpalette.fill",
                        title: localized("外觀主題"),
                        value: appearanceThemeName
                    ) {
                        AppearanceThemeView()
                    }
                }

                // 書架顯示 (每列欄數, 預設封面) lives in 外觀主題's 介面 since 2026-09-29.

                // ── Book Source Management ──
                Section(header: Text(localized("書源管理")).foregroundStyle(DSColor.textSecondary)) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: DSSpacing.md), GridItem(.flexible(), spacing: DSSpacing.md)], spacing: DSSpacing.md) {
                        DSSettingsCard(icon: "books.vertical.fill", title: localized("管理書源"), action: { showSourceList = true })
                        DSSettingsCard(icon: "arrow.down.circle.fill", title: localized("下載管理"), detail: "\(downloadedBooksCount) \(localized("本"))", action: { showDownloadManager = true })
                        DSSettingsCard(icon: "network", title: localized("網路設定"), action: { showNetworkSettings = true })
                    }
                }

                // ── Reading Tools ──
                Section(header: Text(localized("閱讀工具")).foregroundStyle(DSColor.textSecondary)) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: DSSpacing.md), GridItem(.flexible(), spacing: DSSpacing.md)], spacing: DSSpacing.md) {
                        DSSettingsCard(icon: "waveform", title: localized("語音朗讀設定"), action: { showTTSSettings = true })
                        DSSettingsCard(icon: "sparkles", title: localized("AI 助手設定"), detail: isAILocked ? localized("需要 Pro") : aiAssistantDetail, isLocked: isAILocked, action: {
                            if isAILocked { showAIPaywall = true } else { showAISettings = true }
                        })
                        DSSettingsCard(icon: "text.magnifyingglass", title: localized("替換規則"), action: { showReplaceRules = true })
                    }
                }

                // ── Data Management ──
                Section(header: Text(localized("資料管理")).foregroundStyle(DSColor.textSecondary)) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: DSSpacing.md), GridItem(.flexible(), spacing: DSSpacing.md)], spacing: DSSpacing.md) {
                        DSSettingsCard(icon: "arrow.triangle.2.circlepath.icloud", title: localized("備份與同步"), detail: localized("iCloud、WebDAV"), action: { showBackupSync = true })
                        DSSettingsCard(icon: "externaldrive.fill", title: localized("快取管理"), action: { showCacheManagement = true })
                        DSSettingsCard(icon: "wifi", title: localized("局域網服務"), action: { showLanServer = true })
                        DSSettingsCard(icon: "arrow.down.doc.fill", title: localized("Legado 資料遷移"), action: { showLegadoMigration = true })
                    }
                }

                // ── About ──
                Section(header: Text(localized("關於")).foregroundStyle(DSColor.textSecondary)) {
                    DSSettingsNavRow(
                        icon: "info.circle.fill",
                        title: localized("關於 ShuYue"),
                        value: appVersion
                    ) {
                        AboutSupportView(
                            appVersion: appVersion,
                            feedbackEmail: feedbackEmail,
                            feedbackMailURL: feedbackMailURL,
                            sourceCodeURL: sourceCodeURL
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .rootTabTitle(localized("設置"), onScroll: .minimizesBar)
            // Back from 外觀主題: its 淺色／深色 preview ends here.
            .onAppear { gs.endAppearanceSlotPreview() }
            .navigationDestination(isPresented: pushedSourceListBinding) {
                BookSourceListView(embedsNavigationStack: false)
                    .environmentObject(store)
            }
            #if DEBUG
            // Screenshot/driver hook: `-open-diagnostics` pushes 診斷與回報 straight
            // from launch, so its appearance can be inspected without driving the tab
            // bar. Same shape as the `-browser-overlay` launch flags in
            // `yuedu_appApp.init()`, and compiled out of Release.
            .navigationDestination(isPresented: $autoOpenDiagnostics) {
                DiagnosticsView()
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-open-diagnostics") {
                    autoOpenDiagnostics = true
                }
            }
            #endif
            .sheet(isPresented: sheetSourceListBinding) {
                BookSourceListView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showDownloadManager) {
                DownloadManagementView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showNetworkSettings) {
                NetworkSettingsView()
            }
            .sheet(isPresented: $showAISettings) {
                AISettingsView()
            }
            .sheet(isPresented: $showAIPaywall) {
                PaywallView(highlightedFeature: .aiReading)
                    .environmentObject(subscriptionStore)
            }
            .sheet(isPresented: $showReplaceRules) {
                ReplaceRuleListView()
            }
            .sheet(isPresented: $showBackupSync) {
                BackupSyncView()
            }
            .sheet(isPresented: $showCacheManagement) {
                CacheManagementView()
            }
            .sheet(isPresented: $showLanServer) {
                LanServerView().environmentObject(store)
            }
            .sheet(isPresented: $showLegadoMigration) {
                LegadoMigrationView().environmentObject(store)
            }
            .sheet(isPresented: $showTTSSettings) {
                TTSSettingsView()
            }
        }
    }

    private var pushedSourceListBinding: Binding<Bool> {
        Binding(
            get: {
                showSourceList
                    && BookSourceManagementPresentationPolicy.prefersNavigationDestination
            },
            set: { if !$0 { showSourceList = false } }
        )
    }

    private var sheetSourceListBinding: Binding<Bool> {
        Binding(
            get: {
                showSourceList
                    && !BookSourceManagementPresentationPolicy.prefersNavigationDestination
            },
            set: { if !$0 { showSourceList = false } }
        )
    }

    private var downloadedBooksCount: Int {
        store.books.filter { $0.isOnline && $0.offlineDownloadState == .available }.count
    }

    /// AI is Pro, its settings included (`ReaderPremiumVisibilityPolicy.allowsAI`).
    private var isAILocked: Bool {
        !ReaderPremiumVisibilityPolicy(isProActive: subscriptionStore.isProActive).allowsAI
    }

    /// Says whether AI is usable at a glance. A reader who has not set it up should not have
    /// to open the screen to find out that.
    private var aiAssistantDetail: String {
        AIProviderStore.shared.hasConfiguredProfile ? localized("已啟用") : localized("未設定")
    }
}

/// 书悦's brand card, first row of 設定: the app icon, name, a one-line promise and
/// the build. A visual identity 閱讀 never had — the page can no longer be mistaken
/// for the upstream app's settings from its first row.
private struct ShuYueBrandHeaderCard: View {
    let appVersion: String

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image("MoYueLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(localized("書悅"))
                    .font(DSFont.title3.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
                Text(localized("自由開源 · 純淨的書源閱讀器"))
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(2)
                Text(String(format: localized("版本 %@"), appVersion))
                    .font(DSFont.caption2)
                    .foregroundStyle(DSColor.textTertiary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AboutSupportView: View {
    @Environment(\.openURL) private var openURL
    let appVersion: String
    let feedbackEmail: String
    let feedbackMailURL: URL?
    let sourceCodeURL: URL?

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("MoYueLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)

                    Text(localized("書悅"))
                        .font(DSFont.title3.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)

                    Text(localized("聯絡方式、版本資訊與政策協議"))
                        .font(DSFont.footnote)
                        .foregroundColor(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("版本資訊")).foregroundStyle(DSColor.textSecondary)) {
                HStack {
                    SettingsRowLabel(localized("版本"), systemImage: "number")
                    Spacer(minLength: 12)
                    Text(appVersion)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                }
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("開放原始碼")).foregroundStyle(DSColor.textSecondary)) {
                actionRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: localized("原始碼與開源授權"),
                    detail: localized("取得本版本對應原始碼與 MPL-2.0 授權"),
                    trailingIcon: "arrow.up.right"
                ) {
                    if let url = sourceCodeURL {
                        openURL(url)
                    }
                }
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("聯絡方式")).foregroundStyle(DSColor.textSecondary)) {
                actionRow(
                    icon: "envelope.fill",
                    title: localized("電子郵件"),
                    detail: feedbackEmail,
                    trailingIcon: "arrow.up.right"
                ) {
                    if let url = feedbackMailURL {
                        openURL(url)
                    }
                }
            }
            .interfaceSectionSurface()

            Section(header: Text(localized("診斷與回報")).foregroundStyle(DSColor.textSecondary)) {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    HStack(spacing: 12) {
                        DSIconBadge(
                            systemImage: "stethoscope",
                            gradient: DSBrandGradient.tint(for: "stethoscope"),
                            side: 30,
                            iconSize: 16
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("診斷與回報"))
                                .foregroundColor(DSColor.textPrimary)
                            Text(localized("應用診斷與問題回報"))
                                .font(DSFont.caption)
                                .foregroundColor(DSColor.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 12)
                    }
                }
                .foregroundColor(DSColor.textPrimary)
            }
            .interfaceSectionSurface()

            Section {
                NavigationLink {
                    MoYueLegalDocumentView(document: .privacy)
                } label: {
                    HStack(spacing: 12) {
                        DSIconBadge(
                            systemImage: "hand.raised.fill",
                            gradient: DSBrandGradient.tint(for: "hand.raised.fill"),
                            side: 30,
                            iconSize: 16
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("隱私權政策"))
                                .foregroundColor(DSColor.textPrimary)
                            Text(localized("書悅數據處理與隱私說明"))
                                .font(DSFont.caption)
                                .foregroundColor(DSColor.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 12)
                    }
                }
                .foregroundColor(DSColor.textPrimary)

                NavigationLink {
                    MoYueLegalDocumentView(document: .userAgreement)
                } label: {
                    HStack(spacing: 12) {
                        DSIconBadge(
                            systemImage: "doc.text.fill",
                            gradient: DSBrandGradient.tint(for: "doc.text.fill"),
                            side: 30,
                            iconSize: 16
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("使用者協議"))
                                .foregroundColor(DSColor.textPrimary)
                            Text(localized("使用規則、書源與第三方內容責任"))
                                .font(DSFont.caption)
                                .foregroundColor(DSColor.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 12)
                    }
                }
                .foregroundColor(DSColor.textPrimary)
            } header: {
                Text(localized("政策與協議"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                Text(localized("使用書源與第三方來源前，請先閱讀相關條款。"))
                    .dsSectionFooter()
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized("關於 ShuYue"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
    }

    private func actionRow(
        icon: String,
        title: String,
        detail: String,
        trailingIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(DSFont.fixed(size: 18, weight: .medium))
                    .frame(width: 28, height: 28)
                    .foregroundColor(DSColor.textPrimary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundColor(DSColor.textPrimary)
                    Text(detail)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: trailingIcon)
                    .font(DSFont.caption)
                    .foregroundColor(DSColor.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environmentObject(BookStore())
        .environmentObject(SubscriptionStore.shared)
}
