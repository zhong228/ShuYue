import SwiftUI
import UIKit

// MARK: - Edit Source Sheet

/// Edits an existing RSS source: name, feed URL, and folder.
/// Changing the URL re-validates by fetching, then refreshes the cached articles.
/// If the new URL can't be reached the user is asked whether to keep it anyway
/// (the original address is preserved on cancel).
struct EditRSSSourceSheet: View {
    private static let rootFolderID = "__rss_root_folder__"

    let source: RSSSource
    @ObservedObject var store: RSSStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var url: String
    @State private var selectedFolderID: String
    @State private var isSaving = false
    @State private var showUnreachableConfirm = false
    @State private var errorMessage: String?

    init(source: RSSSource, store: RSSStore) {
        self.source = source
        self.store = store
        _name = State(initialValue: source.name)
        _url = State(initialValue: source.url)
        let folderID = store.orderedFolders().first { $0.name == source.sourceGroup }?.id
        _selectedFolderID = State(initialValue: folderID ?? Self.rootFolderID)
    }

    private var folders: [RSSFolder] { store.orderedFolders() }
    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedURL.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(localized("來源名稱")).foregroundStyle(DSColor.textSecondary)) {
                    TextField(localized("來源名稱"), text: $name)
                }
                .interfaceSectionSurface()

                Section(header: Text(localized("RSS 網址")).foregroundStyle(DSColor.textSecondary)) {
                    TextField("https://", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: url) { _, _ in errorMessage = nil }
                }
                .interfaceSectionSurface()

                Section(header: Text(localized("資料夾")).foregroundStyle(DSColor.textSecondary)) {
                    Picker(localized("資料夾"), selection: $selectedFolderID) {
                        Text(localized("無資料夾")).tag(Self.rootFolderID)
                        ForEach(folders) { folder in
                            Text(folder.name).tag(folder.id)
                        }
                    }
                }
                .interfaceSectionSurface()

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    .interfaceSectionSurface()
                }
            }
            .softScrollEdges()
            .navigationTitle(localized("編輯訂閱"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .rss)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView(localized("正在驗證網址…"))
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert(localized("無法解析此網址"), isPresented: $showUnreachableConfirm) {
                Button(localized("仍要儲存"), role: .destructive) {
                    commit()
                    dismiss()
                }
                Button(localized("取消"), role: .cancel) {}
            } message: {
                Text(localized("此 RSS 網址無法取得內容，是否仍要儲存？"))
            }
        }
    }

    @MainActor
    private func save() async {
        guard !trimmedURL.isEmpty else { return }

        guard let parsed = URL(string: trimmedURL),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            errorMessage = localized("RSS URL 無效")
            return
        }
        errorMessage = nil

        // Name / folder-only edits don't need a network round-trip.
        guard trimmedURL != source.url else {
            commit()
            dismiss()
            return
        }

        isSaving = true
        defer { isSaving = false }

        var probe = updatedSource()
        probe.faviconURL = nil
        probe.homepageURL = nil

        let fetcher = RSSFetcher()
        await fetcher.fetchItems(from: probe, metadata: nil)

        guard fetcher.error == nil else {
            showUnreachableConfirm = true
            return
        }

        store.clearFeedMetadata(for: source.id)
        commit()
        store.applyResolvedFeedURL(fetcher.resolvedFeedURL, homepageURL: fetcher.resolvedHomepageURL, to: source.id)
        if let response = fetcher.response {
            store.applyFeedResponse(response, for: source.id)
        } else {
            store.mergeFetchedItems(fetcher.items, for: source.id)
        }
        dismiss()
    }

    /// Builds the edited source, recomputing sort order when it moves to a new folder.
    private func updatedSource() -> RSSSource {
        var updated = source
        updated.name = trimmedName.isEmpty ? source.name : trimmedName
        updated.url = trimmedURL

        let folder = folders.first { $0.id == selectedFolderID }
        let newGroup = folder?.name
        if newGroup != source.sourceGroup {
            updated.sourceGroup = newGroup
            updated.sortOrder = store.nextSourceSortOrder(in: folder)
        }
        return updated
    }

    private func commit() {
        var updated = updatedSource()
        if trimmedURL != source.url {
            // The favicon/home page belonged to the old feed — let them re-resolve.
            updated.faviconURL = nil
            updated.homepageURL = nil
        }
        store.updateSource(updated)
    }
}

// MARK: - Organize Sheet

struct RSSOrganizeSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: RSSStore
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .inactive
    @State private var showAddFolder = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                let folders = store.orderedFolders()
                let rootSources = store.rootSources()

                if folders.isEmpty && rootSources.isEmpty {
                    Section {
                        Text(localized("还没有订阅源"))
                            .foregroundStyle(DSColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 60)
                    }
                    .listRowBackground(Color.clear)
                }

                if !folders.isEmpty {
                    Section(header: Text(localized("資料夾")).foregroundStyle(DSColor.textSecondary)) {
                        ForEach(folders) { folder in
                            NavigationLink {
                                RSSFolderSourcesView(folder: folder, store: store)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(DSColor.accent)
                                        .frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name)
                                            .font(DSFont.body)
                                            .foregroundStyle(DSColor.textPrimary)
                                        Text("\(store.sources(in: folder).count) \(localized("個訂閱源"))")
                                            .font(DSFont.caption)
                                            .foregroundStyle(DSColor.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .onMove { offsets, destination in
                            store.moveFolders(fromOffsets: offsets, toOffset: destination)
                        }
                        .onDelete { offsets in
                            // Deleting a folder only removes the grouping; the feeds
                            // inside it fall back to 未分類 instead of being dropped
                            // (v1.0.26 feedback).
                            let deleted = offsets.compactMap { folders.indices.contains($0) ? folders[$0] : nil }
                            for folder in deleted {
                                store.removeFolder(folder, deleteSources: false)
                            }
                        }
                    }
                }

                if !rootSources.isEmpty {
                    Section(header: Text(folders.isEmpty ? "" : localized("未分類")).foregroundStyle(DSColor.textSecondary)) {
                        NavigationLink {
                            RSSFolderSourcesView(folder: nil, store: store)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .foregroundStyle(DSColor.textSecondary)
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localized("未分類"))
                                        .font(DSFont.body)
                                        .foregroundStyle(DSColor.textPrimary)
                                    Text("\(rootSources.count) \(localized("個訂閱源"))")
                                        .font(DSFont.caption)
                                        .foregroundStyle(DSColor.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .softScrollEdges()
            .environment(\.editMode, $editMode)
            .navigationTitle(localized("管理订阅源"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .rss)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(reduceMotion ? nil : DSAnimation.standard) {
                                editMode = (editMode == .active) ? .inactive : .active
                            }
                        } label: {
                            if editMode == .active {
                                Text(localized("完成"))
                                    .fontWeight(.medium)
                            } else {
                                Image(systemName: "checklist")
                            }
                        }
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Button {
                    showAddFolder = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                        Text(localized("新增資料夾"))
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(DSColor.accent, in: Capsule())
                }
                .padding(.bottom, 20)
            }
            .alert(localized("新增資料夾"), isPresented: $showAddFolder) {
                TextField(localized("資料夾名稱"), text: $newFolderName)
                Button(localized("新增")) {
                    let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        _ = store.addFolder(named: name)
                    }
                    newFolderName = ""
                }
                Button(localized("取消"), role: .cancel) {
                    newFolderName = ""
                }
            } message: {
                Text(localized("請輸入資料夾名稱"))
            }
        }
    }
}

// MARK: - Folder Sources View

struct RSSFolderSourcesView: View {
    let folder: RSSFolder?
    @ObservedObject var store: RSSStore
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var selectionMode = false
    @State private var selectedSourceIDs = Set<String>()
    @State private var sourceToEdit: RSSSource?
    @State private var showDeleteConfirm = false
    @State private var showMoveSheet = false
    @State private var checkingInvalid = false
    @State private var invalidSourceIDs = Set<String>()
    @State private var checkProgress: (current: Int, total: Int)?
    @State private var checkResultMessage = ""
    @State private var showCheckResult = false

    /// Short-timeout session for the offline/broken-source check so a hanging
    /// feed does not stall the whole batch for the default 60s.
    private static let invalidCheckSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private var sources: [RSSSource] {
        if let folder { return store.sources(in: folder) }
        return store.rootSources()
    }

    var body: some View {
        List {
            if sources.isEmpty {
                Section {
                    Text(localized("此資料夾沒有訂閱源"))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(sources) { source in
                    sourceRow(source)
                }
                .onMove { offsets, destination in
                    store.moveSources(inFolderNamed: folder?.name, fromOffsets: offsets, toOffset: destination)
                }
            }
        }
        .listStyle(.insetGrouped)
        .softScrollEdges()
        .environment(\.editMode, $editMode)
        .navigationTitle(folder?.name ?? localized("未分類"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .rss)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if !selectionMode {
                        Button {
                            withAnimation {
                                editMode = (editMode == .active) ? .inactive : .active
                            }
                        } label: {
                            if editMode == .active {
                                Text(localized("完成"))
                                    .fontWeight(.medium)
                            } else {
                                Image(systemName: "checklist")
                            }
                        }
                    }
                    Button {
                        withAnimation {
                            selectionMode.toggle()
                            editMode = .inactive
                            if !selectionMode {
                                selectedSourceIDs.removeAll()
                            }
                        }
                    } label: {
                        Text(selectionMode ? localized("完成") : localized("選擇"))
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selectionMode {
                selectionToolbar
            }
        }
        .sheet(item: $sourceToEdit) { source in
            EditRSSSourceSheet(source: source, store: store)
        }
        .sheet(isPresented: $showMoveSheet) {
            RSSMoveSourcesSheet(store: store, sourceIDs: selectedSourceIDs) {
                selectedSourceIDs.removeAll()
                selectionMode = false
            }
        }
        .alert(localized("刪除"), isPresented: $showDeleteConfirm) {
            Button(localized("刪除"), role: .destructive) {
                store.removeSources(ids: Array(selectedSourceIDs))
                selectedSourceIDs.removeAll()
                selectionMode = false
            }
            Button(localized("取消"), role: .cancel) {}
        } message: {
            Text(String(format: localized("確定要刪除 %d 個訂閱源嗎？"), selectedSourceIDs.count))
        }
        .alert(localized("檢測完成"), isPresented: $showCheckResult) {
            Button(localized("確定"), role: .cancel) {}
        } message: {
            Text(checkResultMessage)
        }
        .overlay {
            if checkingInvalid, let progress = checkProgress {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("\(progress.current) / \(progress.total)")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private var selectionToolbar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Button {
                    if selectedSourceIDs.count == sources.count {
                        selectedSourceIDs.removeAll()
                    } else {
                        selectedSourceIDs = Set(sources.map(\.id))
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: selectedSourceIDs.count == sources.count ? "checkmark.circle.fill" : "checkmark.circle")
                        Text(localized("全選"))
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    let allIDs = Set(sources.map(\.id))
                    selectedSourceIDs = allIDs.symmetricDifference(selectedSourceIDs)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.2.circlepath")
                        Text(localized("反選"))
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    showMoveSheet = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "folder.badge.plus")
                        Text(localized("移動到分組"))
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(selectedSourceIDs.isEmpty)

                Button {
                    Task { await checkInvalid() }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(localized("檢測"))
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    guard !selectedSourceIDs.isEmpty else { return }
                    showDeleteConfirm = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "trash")
                        Text(localized("刪除"))
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(selectedSourceIDs.isEmpty)
                .tint(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: RSSSource) -> some View {
        Button {
            if selectionMode {
                toggleSelection(source.id)
            } else {
                sourceToEdit = source
            }
        } label: {
            HStack(spacing: 12) {
                if selectionMode {
                    Image(systemName: selectedSourceIDs.contains(source.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedSourceIDs.contains(source.id) ? DSColor.accent : DSColor.textSecondary)
                        .imageScale(.large)
                }

                RSSFaviconView(source: source, size: 24)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(source.url)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .lineLimit(1)
                        if invalidSourceIDs.contains(source.id) {
                            Text(localized("失效"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 0)

                if !selectionMode {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .tint(.primary)
        .swipeActions(edge: .trailing) {
            if !selectionMode {
                Button(role: .destructive) {
                    store.removeSources(ids: [source.id])
                } label: {
                    Label(localized("刪除"), systemImage: "trash")
                }
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedSourceIDs.contains(id) {
            selectedSourceIDs.remove(id)
        } else {
            selectedSourceIDs.insert(id)
        }
    }

    @MainActor
    private func checkInvalid() async {
        checkingInvalid = true
        defer { checkingInvalid = false }
        invalidSourceIDs.removeAll()

        let targets = !selectedSourceIDs.isEmpty
            ? sources.filter { selectedSourceIDs.contains($0.id) }
            : sources

        for (index, source) in targets.enumerated() {
            checkProgress = (index + 1, targets.count)
            let fetcher = RSSFetcher(session: Self.invalidCheckSession)
            await fetcher.fetchItems(from: source, metadata: store.feedMetadata(for: source.id))
            if fetcher.error != nil {
                invalidSourceIDs.insert(source.id)
            }
        }
        checkProgress = nil

        if invalidSourceIDs.isEmpty {
            checkResultMessage = localized("檢測完成，所有訂閱源均有效")
        } else {
            checkResultMessage = String(format: localized("檢測完成：%d 個訂閱源失效"), invalidSourceIDs.count)
        }
        showCheckResult = true
    }
}

// MARK: - Move Sources Sheet

struct RSSMoveSourcesSheet: View {
    @ObservedObject var store: RSSStore
    let sourceIDs: Set<String>
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        moveSources(to: nil)
                    } label: {
                        HStack {
                            Text(localized("無資料夾"))
                            Spacer()
                            Image(systemName: "tray")
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    }
                }

                let folders = store.orderedFolders()
                if !folders.isEmpty {
                    Section(header: Text(localized("資料夾")).foregroundStyle(DSColor.textSecondary)) {
                        ForEach(folders) { folder in
                            Button {
                                moveSources(to: folder)
                            } label: {
                                HStack {
                                    Text(folder.name)
                                    Spacer()
                                    Image(systemName: "folder")
                                        .foregroundStyle(DSColor.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .softScrollEdges()
            .navigationTitle(localized("移動到分組"))
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .rss)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localized("取消")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func moveSources(to folder: RSSFolder?) {
        store.moveSources(ids: Array(sourceIDs), to: folder)
        dismiss()
        onComplete()
    }
}

#Preview("Edit Source") {
    EditRSSSourceSheet(
        source: RSSSource(name: "Example Feed", url: "https://example.com/feed.xml"),
        store: RSSStore.shared
    )
}

#Preview("Organize") {
    RSSOrganizeSheet(store: RSSStore.shared)
}
