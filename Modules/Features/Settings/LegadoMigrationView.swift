import SwiftUI
import UniformTypeIdentifiers

struct LegadoMigrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var manager = LegadoMigrationManager.shared
    @ObservedObject private var gs = GlobalSettings.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bookStore: BookStore

    @State private var showFilePicker = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
                ScrollView {
                    AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
                    VStack(spacing: DSSpacing.lg) {
                        descriptionSection
                        importSection
                        if let result = manager.importResult {
                            resultSection(result)
                        }
                        if !manager.statusLog.isEmpty {
                            logSection
                        }
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.top, DSSpacing.sm)
                    .padding(.bottom, DSSpacing.xl)
                }
                }
                .softScrollEdges()
            .navigationTitle(localized("导入阅读器数据"))
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
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json, UTType(filenameExtension: "txt") ?? .plainText]
            ) { result in
                switch result {
                case .success(let url):
                    Task {
                        guard url.startAccessingSecurityScopedResource() else {
                            manager.appendLog("Failed to obtain file access permission")
                            return
                        }
                        defer { url.stopAccessingSecurityScopedResource() }
                        guard let data = try? Data(contentsOf: url) else {
                            manager.appendLog("Failed to read file content")
                            return
                        }
                        await manager.importFromJSON(data: data, bookStore: bookStore)
                    }
                case .failure(let error):
                    manager.appendLog("File selection failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Sections

    private var descriptionSection: some View {
        DSSettingsGroupCard(title: localized("说明")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("支援从 Legado（阅读）Android 应用汇入："))
                    .font(DSFont.subheadline)
                    .foregroundColor(DSColor.textPrimary)
                Text("• " + localized("书源 JSON（书源备份 / 分享档）"))
                    .font(DSFont.caption)
                    .foregroundColor(DSColor.textSecondary)
                Text("• " + localized("书籍 JSON（书架备份档）"))
                    .font(DSFont.caption)
                    .foregroundColor(DSColor.textSecondary)
                Text(localized("请从 Legado → 备份与恢复 中汇出对应 JSON 档案后选择汇入。"))
                    .font(DSFont.caption)
                    .foregroundColor(DSColor.textSecondary)
                    .padding(.top, 2)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 54)
        }
    }

    private var importSection: some View {
        DSSettingsGroupCard(title: localized("汇入")) {
            DSSettingsCardRow(icon: "doc.badge.plus", title: localized("选择 JSON 档案")) {
                showFilePicker = true
            }
            .disabled(manager.isImporting)

            if manager.isImporting {
                DSSettingsCardDivider()
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: manager.progress)
                        .tint(DSColor.accent)
                    Text(localized("汇入中，请稍候…"))
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, DSSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 54)
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ result: LegadoMigrationManager.ImportResult) -> some View {
        DSSettingsGroupCard(title: localized("结果")) {
            if result.sourcesImported > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(String(format: localized("书源：%d 个"), result.sourcesImported))
                        .foregroundStyle(DSColor.textPrimary)
                }
                .padding(.horizontal, DSSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 54)
            }
            if result.booksImported > 0 {
                if result.sourcesImported > 0 {
                    DSSettingsCardDivider()
                }
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(String(format: localized("书籍：%d 本"), result.booksImported))
                        .foregroundStyle(DSColor.textPrimary)
                }
                .padding(.horizontal, DSSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 54)
            }
            if result.sourcesImported == 0 && result.booksImported == 0 && result.errors.isEmpty {
                Text(localized("未汇入任何资料"))
                    .foregroundColor(DSColor.textSecondary)
                    .padding(.horizontal, DSSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 54)
            }
            ForEach(Array(result.errors.enumerated()), id: \.offset) { index, error in
                if index > 0 || result.sourcesImported > 0 || result.booksImported > 0 {
                    DSSettingsCardDivider()
                }
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(DSFont.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, DSSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 54)
            }
        }
    }

    private var logSection: some View {
        DSSettingsGroupCard(title: localized("记录")) {
            ScrollViewReader { proxy in
                ScrollView {
                    AdaptiveContentContainer(maxWidth: DSLayout.readableFormWidth) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(
                            Array(manager.statusLog.suffix(20).enumerated()),
                            id: \.offset
                        ) { index, entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(DSColor.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 4)
                }
                }
                .softScrollEdges()
                .frame(maxHeight: 200)
                .onChange(of: manager.statusLog.count) { _, count in
                    let lastIndex = min(count, 20) - 1
                    if lastIndex >= 0 {
                        withAnimation(reduceMotion ? nil : DSAnimation.fast) { proxy.scrollTo(lastIndex, anchor: .bottom) }
                    }
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 54)
        }
    }
}