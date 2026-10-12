import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum RSSHomeActionRoute: Hashable, CaseIterable {
    case importURL
    case importLocal
    case exportJSON
    case settings
}

enum RSSSourceFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case read
    case favorite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return localized("全部订阅源")
        case .unread:
            return localized("未读订阅")
        case .read:
            return localized("已读订阅")
        case .favorite:
            return localized("收藏订阅")
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "tray.full"
        case .unread:
            return "circle.fill"
        case .read:
            return "checkmark.circle"
        case .favorite:
            return "star.fill"
        }
    }
}

struct RSSListView: View {
    @StateObject private var store = RSSStore.shared

    @State private var showDocumentPicker = false
    @State private var showJSONExporter = false
    @State private var showJSONURLSheet = false
    @State private var importMessage = ""
    @State private var showImportResult = false
    @State private var deleteTarget: RSSDeleteTarget?
    @State private var showSettings = false
    @State private var showLegacyTopActionChooser = false
    @State private var sourceInfoToShow: RSSSource?
    @State private var legacyTopActionSequence =
        DismissalSequencedPresentation<RSSHomeActionRoute>()
    @State private var sourceFilter: RSSSourceFilter = .all
    @State private var isRefreshingAll = false

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackgroundView(scope: .rss)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if filteredSources.isEmpty {
                            sourcesEmptyState
                        } else {
                            sourcesGridSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                    .rootTabTitleScrollAnchor()
                }
                .softScrollEdges()
                .scrollIndicators(.visible)
            }
            .rootTabTitle(localized("订阅源"), onScroll: .minimizesBar)
            .pageBackgroundToolbar(for: .rss)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    rssFilterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    rssTopToolbarControl
                }
            }
            .sheet(
                isPresented: $showLegacyTopActionChooser,
                onDismiss: presentLegacyTopActionAfterChooserDismissal
            ) {
                AdaptiveSheetContainer(maxWidth: DSLayout.readableCompactWidth) {
                    DismissalSequencedActionChooser(
                        title: localized("更多"),
                        actions: [
                            DismissalSequencedAction(
                                route: .importURL,
                                title: localized("網路匯入 Legado JSON"),
                                systemImage: "link.badge.plus"
                            ),
                            DismissalSequencedAction(
                                route: .importLocal,
                                title: localized("本機匯入 Legado JSON"),
                                systemImage: "doc.badge.plus"
                            ),
                            DismissalSequencedAction(
                                route: .exportJSON,
                                title: localized("匯出 Legado JSON"),
                                systemImage: "doc.badge.arrow.up",
                                isEnabled: !store.sources.isEmpty
                            ),
            DismissalSequencedAction(
                route: .settings,
                title: localized("管理订阅源"),
                systemImage: "gearshape"
            ),
                        ],
                        onSelect: { legacyTopActionSequence.select($0) }
                    )
                }
            }
            .sheet(isPresented: $showJSONURLSheet) {
                ImportLegadoJSONURLSheet(isPresented: $showJSONURLSheet, store: store)
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in
                    importLegadoJSON(url)
                    showDocumentPicker = false
                } onCancel: {
                    showDocumentPicker = false
                }
            }
            .fileExporter(
                isPresented: $showJSONExporter,
                document: RSSJSONDocument(sources: store.sources.sorted(by: { $0.sortOrder < $1.sortOrder })),
                contentType: .json,
                defaultFilename: "yuedu-rss-legado.json"
            ) { _ in }
            .sheet(isPresented: $showSettings) {
                RSSOrganizeSheet(store: store)
            }
            .sheet(item: $sourceInfoToShow) { source in
                RSSSourceInfoSheet(source: source, store: store)
            }
            .alert(localized("订阅源"), isPresented: $showImportResult) {
                Button(localized("確定"), role: .cancel) {}
            } message: {
                Text(importMessage)
            }
            .alert(
                deleteTarget?.title ?? localized("刪除"),
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                presenting: deleteTarget
            ) { target in
                Button(localized("刪除"), role: .destructive) {
                    performDelete(target)
                }
                Button(localized("取消"), role: .cancel) {}
            } message: { target in
                Text(target.message)
            }
        }
    }

    // MARK: - Sources Grid

    private var sourcesEmptyState: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: sourceFilter.systemImage)
                .font(.system(size: 40))
                .foregroundStyle(DSColor.textSecondary)
            Text(sourceFilter == .all ? localized("还没有订阅源") : localized("没有符合条件的订阅源"))
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .accessibilityElement(children: .combine)
    }

    private var filteredSources: [RSSSource] {
        switch sourceFilter {
        case .all:
            return store.sources
        case .unread:
            return store.sources.filter { store.unreadCount(for: $0.id) > 0 }
        case .read:
            return store.sources.filter { store.articles(for: $0.id).allSatisfy(\.isRead) && !store.articles(for: $0.id).isEmpty }
        case .favorite:
            return store.sources.filter { store.articles(for: $0.id).contains(where: \.isFavorite) }
        }
    }

    private var sourcesGridSection: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: DSSpacing.md)],
            alignment: .leading,
            spacing: DSSpacing.lg
        ) {
            ForEach(filteredSources, id: \.id) { source in
                NavigationLink {
                    RSSFeedView(source: source)
                } label: {
                    VStack(spacing: DSSpacing.sm) {
                        RSSFaviconView(source: source, size: 48)
                        Text(source.name)
                            .font(DSFont.footnote.weight(.medium))
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        sourceInfoToShow = source
                    } label: {
                        Label(localized("取得資訊"), systemImage: "info.circle")
                    }
                    Button(role: .destructive) {
                        deleteTarget = .source(source)
                    } label: {
                        Label(localized("删除"), systemImage: "trash")
                    }
                    Menu {
                        let targets = store.sources.filter { $0.id != source.id }
                        ForEach(targets, id: \.id) { target in
                            Button {
                                store.moveSource(source.id, after: target.id)
                            } label: {
                                Text(target.name)
                            }
                        }
                    } label: {
                        Label(localized("移动位置"), systemImage: "arrow.up.arrow.down")
                    }
                }
                .draggable(source.id)
                .dropDestination(for: String.self) { items, _ in
                    guard let draggedID = items.first, draggedID != source.id else {
                        return false
                    }
                    withAnimation(.snappy(duration: 0.25)) {
                        store.moveSource(draggedID, after: source.id)
                    }
                    return true
                }
            }
        }
    }

    private func performDelete(_ target: RSSDeleteTarget) {
        switch target {
        case .source(let source):
            store.removeSources(ids: [source.id])
        }
        deleteTarget = nil
    }

    private func importLegadoJSON(_ url: URL) {
        do {
            // DocumentPicker uses asCopy:true so URL is already a plain local
            // file (not security-scoped); no startAccessingSecurityScopedResource needed.
            let data = try Data(contentsOf: url)
            let sources = try LegadoSourceJSONParser.parse(data: data)
            let addedSources = store.addSourcesReturningAdded(sources)
            importMessage = String(format: localized("已匯入 %d 個订阅源"), addedSources.count)
            showImportResult = true
        } catch {
            importMessage = String(format: localized("Legado JSON 匯入失敗：%@"), error.localizedDescription)
            showImportResult = true
        }
    }

    @ViewBuilder
    private var rssTopToolbarControl: some View {
        if MenuModalPresentationPolicy.requiresDismissalSequencedChooser {
            Button {
                legacyTopActionSequence.cancel()
                showLegacyTopActionChooser = true
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(localized("更多"))
        } else {
            RSSHomeTopMenu(
                hasSources: !store.sources.isEmpty,
                onImportURL: { showJSONURLSheet = true },
                onImportLocal: { showDocumentPicker = true },
                onExportJSON: { showJSONExporter = true },
                onSettings: { showSettings = true }
            )
        }
    }

    private func presentLegacyTopActionAfterChooserDismissal() {
        guard let route = legacyTopActionSequence.consumeAfterDismissal() else {
            return
        }
        switch route {
        case .importURL:
            showJSONURLSheet = true
        case .importLocal:
            showDocumentPicker = true
        case .exportJSON:
            showJSONExporter = true
        case .settings:
            showSettings = true
        }
    }

    @ViewBuilder
    private var rssFilterMenu: some View {
        Menu {
            Picker("", selection: $sourceFilter) {
                ForEach(RSSSourceFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button {
                Task { await refreshAllSources() }
            } label: {
                Label(localized("刷新所有订阅"), systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshingAll || store.sources.isEmpty)

            Button {
                store.markAllRead(sourceID: nil, isRead: true)
            } label: {
                Label(localized("一键全部已读"), systemImage: "checkmark.circle")
            }
            .disabled(store.totalUnreadCount() == 0)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(DSFont.toolbarIcon)
        }
        .accessibilityLabel(localized("订阅筛选"))
        .foregroundColor(DSColor.textPrimary)
        .id("\(Locale.autoupdatingCurrent.identifier)_rss_source_filter_\(sourceFilter.rawValue)")
    }

    @MainActor
    private func refreshAllSources() async {
        guard !store.sources.isEmpty else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }
        await RSSFeedRefreshService.refreshAll()
    }

}

private enum RSSDeleteTarget: Identifiable {
    case source(RSSSource)

    var id: String {
        switch self {
        case .source(let source):
            return "source-\(source.id)"
        }
    }

    var title: String {
        switch self {
        case .source:
            return localized("刪除订阅源")
        }
    }

    var message: String {
        switch self {
        case .source(let source):
            return String(format: localized("確定要刪除「%@」订阅源嗎？"), source.name)
        }
    }

}

private struct RSSHomeTopMenu: View {
    let hasSources: Bool
    let onImportURL: () -> Void
    let onImportLocal: () -> Void
    let onExportJSON: () -> Void
    let onSettings: () -> Void

    var body: some View {
        Menu {
            Button {
                onImportURL()
            } label: {
                Label(localized("網路匯入 Legado JSON"), systemImage: "link.badge.plus")
            }

            Button {
                onImportLocal()
            } label: {
                Label(localized("本機匯入 Legado JSON"), systemImage: "doc.badge.plus")
            }

            Divider()

            Button {
                onExportJSON()
            } label: {
                Label(localized("匯出 Legado JSON"), systemImage: "doc.badge.arrow.up")
            }
            .disabled(!hasSources)

            Divider()

            Button {
                onSettings()
            } label: {
                Label(localized("管理订阅源"), systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(localized("更多"))
    }
}

// MARK: - JSON Document

struct RSSJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .data] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(sources: [RSSSource]) {
        data = (try? LegadoSourceJSONParser.export(sources: sources)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Import Legado JSON URL Sheet

private struct ImportLegadoJSONURLSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var store: RSSStore

    @State private var urlString = ""
    @State private var isLoading = false
    @State private var message = ""
    @State private var showMessage = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(localized("Legado JSON 網址")).foregroundStyle(DSColor.textSecondary)) {
                    TextField("https://.../sources/xxx.json", text: $urlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .interfaceSectionSurface()

                Section(header: Text(localized("常用订阅源倉庫")).foregroundStyle(DSColor.textSecondary)) {
                    Button {
                        urlString = "https://www.yckceo.com/yuedu/rss/json/id/193.json"
                    } label: {
                        HStack {
                            Image(systemName: "building.columns")
                            VStack(alignment: .leading) {
                                Text(localized("源倉庫（官方純淨）"))
                                    .font(DSFont.body)
                                Text("yckceo.com")
                                    .font(DSFont.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(DSColor.accent)
                        }
                    }
                }
                .interfaceSectionSurface()

            }
            .softScrollEdges()
            .navigationTitle(localized("從網址匯入 Legado JSON"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .rss)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await importFromURL() }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .alert(localized("匯入"), isPresented: $showMessage) {
                Button(localized("確定"), role: .cancel) {
                    if !message.hasPrefix("❌") { isPresented = false }
                }
            } message: {
                Text(message)
            }
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    ProgressView(localized("匯入中，請稍候…"))
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @MainActor
    private func importFromURL() async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            message = "❌ \(localized("订阅源網址無效"))"
            showMessage = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await MediaSession.shared.data(from: url)
            let sources = try LegadoSourceJSONParser.parse(data: data)
            let addedCount = store.addSources(sources)
            message = "\(localized("成功匯入")) \(addedCount) \(localized("個订阅源"))"
            showMessage = true
        } catch {
            message = "❌ \(String(format: localized("Legado JSON 匯入失敗：%@"), error.localizedDescription))"
            showMessage = true
        }
    }
}

private struct RSSSourceInfoSheet: View {
    let source: RSSSource
    @ObservedObject var store: RSSStore
    @Environment(\.dismiss) private var dismiss

    private var currentSource: RSSSource {
        store.source(id: source.id) ?? source
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(localized("基本資訊")).foregroundStyle(DSColor.textSecondary)) {
                    ThemedLabeledContent(localized("來源名稱"), value: currentSource.name)
                    ThemedLabeledContent(localized("訂閱源網址"), value: currentSource.url)
                    if let homepageURL = currentSource.homepageURL, !homepageURL.isEmpty {
                        ThemedLabeledContent(localized("首頁"), value: homepageURL)
                    }
                    if let faviconURL = currentSource.displayFaviconURL, !faviconURL.isEmpty {
                        ThemedLabeledContent(localized("圖示"), value: faviconURL)
                    }
                    if let group = currentSource.sourceGroup, !group.isEmpty {
                        ThemedLabeledContent(localized("資料夾"), value: group)
                    }
                }
                .interfaceSectionSurface()

                Section {
                    Button {
                        UIPasteboard.general.string = currentSource.url
                    } label: {
                        Label(localized("複製訂閱 URL"), systemImage: "doc.on.doc")
                    }

                    if let homepageURL = currentSource.homepageURL, let url = URL(string: homepageURL) {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Label(localized("開啟首頁"), systemImage: "safari")
                        }
                    }
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .navigationTitle(localized("取得資訊"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .rss)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label(localized("完成"), systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(localized("完成"))
                    .foregroundColor(DSColor.accent)
                }
            }
        }
    }
}

#Preview {
    RSSListView()
}
