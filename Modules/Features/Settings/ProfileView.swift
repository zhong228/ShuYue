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
    @State private var showAppearanceTheme = false
    @State private var showDiagnostics = false
    @State private var showAbout = false
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
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // ── Brand Header + quick feedback ──
                    ShuYueBrandHeaderCard(appVersion: appVersion, feedbackURL: feedbackMailURL)
                        .rootTabTitleScrollAnchor()

                    // ── 界面语言 ──
                    profileGroup(title: localized("界面语言"), footer: appLanguageFooter) {
                        DSSettingsCard(icon: "globe", title: localized("语言")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }

                    // ── 外观与主题 ──
                    profileGroup(title: localized("外观与主题")) {
                        DSSettingsCard(
                            icon: "paintpalette.fill",
                            title: localized("视觉主题"),
                            detail: appearanceThemeName
                        ) {
                            showAppearanceTheme = true
                        }
                    }

                    // ── 数据与书源 ──
                    profileGroup(title: localized("数据与书源")) {
                        DSSettingsCard(icon: "books.vertical.fill", title: localized("书源库"), action: { showSourceList = true })
                        DSSettingsCard(icon: "arrow.down.circle.fill", title: localized("离线缓存"), detail: "\(downloadedBooksCount) \(localized("本"))", action: { showDownloadManager = true })
                        DSSettingsCard(icon: "network", title: localized("网络连接"), action: { showNetworkSettings = true })
                        DSSettingsCard(icon: "arrow.triangle.2.circlepath.icloud", title: localized("云备份"), detail: localized("iCloud、WebDAV"), action: { showBackupSync = true })
                        DSSettingsCard(icon: "externaldrive.fill", title: localized("存储清理"), action: { showCacheManagement = true })
                        DSSettingsCard(icon: "wifi", title: localized("局域传书"), action: { showLanServer = true })
                        DSSettingsCard(icon: "arrow.down.doc.fill", title: localized("导入阅读器数据"), action: { showLegadoMigration = true })
                    }

                    // ── 阅读与声音 ──
                    profileGroup(title: localized("阅读与声音")) {
                        DSSettingsCard(icon: "waveform", title: localized("听书引擎"), action: { showTTSSettings = true })
                        DSSettingsCard(icon: "sparkles", title: localized("智能伴读"), detail: isAILocked ? localized("需要 Pro") : aiAssistantDetail, isLocked: isAILocked, action: {
                            if isAILocked { showAIPaywall = true } else { showAISettings = true }
                        })
                        DSSettingsCard(icon: "text.magnifyingglass", title: localized("文字修正"), action: { showReplaceRules = true })
                    }

                    // ── 应用信息 ──
                    profileGroup(title: localized("应用信息")) {
                        DSSettingsCard(icon: "stethoscope", title: localized("帮助与诊断"), action: { showDiagnostics = true })
                        DSSettingsCard(icon: "info.circle.fill", title: localized("关于书悦"), detail: appVersion, action: { showAbout = true })
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.xl)
            }
            .softScrollEdges()
            .themedAppSurface(for: .settings)
            .rootTabTitle(localized("我的"), onScroll: .minimizesBar)
            // Back from 外观主题: its 浅色／深色 preview ends here.
            .onAppear { gs.endAppearanceSlotPreview() }
            .navigationDestination(isPresented: pushedSourceListBinding) {
                BookSourceListView(embedsNavigationStack: false)
                    .environmentObject(store)
            }
            .navigationDestination(isPresented: $showAppearanceTheme) {
                AppearanceThemeView()
            }
            .navigationDestination(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            .navigationDestination(isPresented: $showAbout) {
                AboutSupportView(
                    appVersion: appVersion,
                    feedbackEmail: feedbackEmail,
                    feedbackMailURL: feedbackMailURL,
                    sourceCodeURL: sourceCodeURL
                )
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

    /// 我的中心的「分组宫格」：小标题 + 两列功能卡片宫格，替代系统 List Section。
    /// 每组的卡片数量不定，宫格自动换行；footer 用于语言说明等补充文案。
    private func profileGroup<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(title)
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.top, DSSpacing.xs)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: DSSpacing.md),
                    GridItem(.flexible(), spacing: DSSpacing.md)
                ],
                spacing: DSSpacing.md
            ) {
                content()
            }

            if let footer {
                Text(footer)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.sm)
            }
        }
    }
}

/// 书悦's brand card, first row of 設定: the app icon, name, a one-line promise and
/// the build. A visual identity 閱讀 never had — the page can no longer be mistaken
/// for the upstream app's settings from its first row.
private struct ShuYueBrandHeaderCard: View {
    @Environment(\.openURL) private var openURL
    let appVersion: String
    let feedbackURL: URL?

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

            if let feedbackURL {
                Button {
                    openURL(feedbackURL)
                } label: {
                    Image(systemName: "envelope.fill")
                        .font(DSFont.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(DSColor.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("反馈"))
            }
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

            Section(header: Text(localized("帮助与诊断")).foregroundStyle(DSColor.textSecondary)) {
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
                            Text(localized("帮助与诊断"))
                                .foregroundColor(DSColor.textPrimary)
                            Text(localized("应用诊断与问题回报"))
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
        .navigationTitle(localized("关于书悦"))
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
