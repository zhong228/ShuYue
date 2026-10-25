import SwiftUI
import UniformTypeIdentifiers

struct GlobalFontSettingsView: View {
    @ObservedObject private var settings = GlobalSettings.shared
    @ObservedObject private var subscription = SubscriptionStore.shared
    @State private var showingImporter = false
    @State private var showsPaywall = false
    @State private var importError: GlobalFontImportError?
    @State private var fontToDelete: UserFontInfo?

    var body: some View {
        // 分组卡片：当前字体 / 已匯入字體 / 匯入入口，替代系统 Form 分组（2026-10-25）。
        ScrollView {
            VStack(spacing: DSSpacing.lg) {
                DSSettingsGroupCard(title: localized("全局字體"), footer: {
                    Text(localized("套用於 App 介面，閱讀正文仍使用閱讀設定。"))
                        .dsSectionFooter()
                }) {
                    selectionButton(
                        title: localized("系統字體"),
                        postScriptName: nil,
                        previewFont: GlobalAppTypography.font(.body, postScriptName: nil)
                    )
                    .padding(.horizontal, DSSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 54)
                }

                DSSettingsGroupCard(title: localized("已匯入字體")) {
                    if settings.userFonts.isEmpty {
                        Text(localized("尚未匯入字體"))
                            .font(DSFont.subheadline)
                            .foregroundStyle(DSColor.textSecondary)
                            .padding(.horizontal, DSSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 54)
                    } else {
                        ForEach(settings.userFonts) { font in
                            selectionButton(
                                title: font.displayName,
                                postScriptName: font.postScriptName,
                                previewFont: GlobalAppTypography.font(
                                    .body,
                                    postScriptName: font.postScriptName
                                )
                            )
                            // 卡片里没有 swipeActions，删除改由行内长按菜单提供，确认 alert 不变。
                            .contextMenu {
                                Button(role: .destructive) {
                                    fontToDelete = font
                                } label: {
                                    Label(localized("刪除"), systemImage: "trash")
                                }
                            }
                            .padding(.horizontal, DSSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 54)
                        }
                    }
                }

                DSSettingsGroupCard(title: localized("字體"), footer: {
                    Text(localized("匯入後，字體會同時出現在全局字體與閱讀設定。"))
                        .dsSectionFooter()
                }) {
                    // Pro: the entry locks, fonts imported earlier stay usable.
                    let locked = !ReaderPremiumVisibilityPolicy(isProActive: subscription.isProActive).allowsFontImport
                    DSSettingsCardRow(
                        icon: locked ? "lock.fill" : "plus",
                        title: localized("匯入字體..."),
                        detail: locked ? localized("需要 Pro") : nil,
                        isLocked: locked
                    ) {
                        if locked { showsPaywall = true } else { showingImporter = true }
                    }
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.xl)
        }
        .softScrollEdges()
        .navigationTitle(localized("全局字體"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .settings)
        .sheet(isPresented: $showsPaywall) {
            PaywallView(highlightedFeature: .customFonts)
                .environmentObject(subscription)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: Self.fontContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .alert(item: $importError) { error in
            Alert(
                title: Text(localized("字體匯入失敗")),
                message: Text(error.message),
                dismissButton: .default(Text(localized("確定")))
            )
        }
        .alert(
            localized("刪除此字體？"),
            isPresented: Binding(
                get: { fontToDelete != nil },
                set: { if !$0 { fontToDelete = nil } }
            ),
            presenting: fontToDelete
        ) { font in
            Button(localized("刪除"), role: .destructive) {
                settings.deleteUserFont(font)
                fontToDelete = nil
            }
            Button(localized("取消"), role: .cancel) {
                fontToDelete = nil
            }
        } message: { font in
            Text(
                font.displayName
                    + "\n"
                    + localized("刪除後，全局字體與閱讀設定將無法再使用此字體。")
            )
        }
    }

    private func selectionButton(
        title: String,
        postScriptName: String?,
        previewFont: Font
    ) -> some View {
        let isSelected = settings.selectedGlobalFontPostScript == postScriptName
        return Button {
            settings.selectedGlobalFontPostScript = postScriptName
        } label: {
            HStack {
                Text(title)
                    .font(previewFont)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DSColor.accent)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static let fontContentTypes: [UTType] = [
        .font,
        UTType(filenameExtension: "ttf") ?? .data,
        UTType(filenameExtension: "otf") ?? .data,
    ]

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try settings.importGlobalFont(from: url)
        } catch {
            importError = GlobalFontImportError(message: error.localizedDescription)
        }
    }
}

private struct GlobalFontImportError: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    NavigationStack {
        GlobalFontSettingsView()
    }
}
