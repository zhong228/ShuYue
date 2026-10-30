import SwiftUI

/// Feed routes freeze the selected location rather than resolving a live list.
struct OPDSFeedRoute: Hashable {
    let catalogID: String
    let url: String
    let title: String
}

struct OPDSImportView: View {
    var kind: RemoteLibraryKind = .opds

    var body: some View {
        RemoteLibraryBrowserView(kind: kind)
    }
}

/// Saved connections own browsing independently from backup destinations.
struct RemoteLibraryBrowserView: View {
    let kind: RemoteLibraryKind
    @Environment(\.appDependencies) private var dependencies
    @EnvironmentObject private var store: BookStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalogStore = RemoteLibraryConnectionStore.shared

    private var connections: [RemoteLibraryConnection] {
        catalogStore.catalogs.filter { $0.kind == kind }
    }

    var body: some View {
        NavigationStack {
            List {
                if kind == .calibre {
                    Section {
                        NavigationLink {
                            CalibreWirelessView(store: store, service: dependencies.calibreWireless)
                        } label: {
                            SettingsRowLabel(localized("电脑传书"), systemImage: "desktopcomputer")
                        }
                    }.interfaceSectionSurface()
                    if connections.isEmpty {
                        // Receiving from the desktop is available without a
                        // Content Server connection. Keep the empty state in
                        // the list so it cannot cover that navigation row.
                        Section { emptyLibraryView }.interfaceSectionSurface()
                    }
                }
                Section {
                    ForEach(connections) { connection in
                        connectionLink(connection)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { catalogStore.remove(connection) } label: {
                                    Label(localized("删除"), systemImage: "trash")
                                }
                            }
                    }
                }
                .interfaceSectionSurface()
                if kind == .opds {
                    Section(localized("范例目录")) {
                        ForEach(OPDSCatalogStore.presets.filter { preset in
                            !connections.contains { $0.url == preset.url }
                        }, id: \.url) { preset in
                            Button {
                                catalogStore.add(name: preset.name, url: preset.url, username: nil, password: nil)
                            } label: {
                                Label(preset.name, systemImage: "plus")
                            }
                        }
                    }
                    .interfaceSectionSurface()
                }
            }
            .softScrollEdges()
            .overlay {
                if connections.isEmpty && kind == .webDAV { emptyLibraryView }
            }
            .navigationTitle(kind.libraryTitle)
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .bookshelf)
            .navigationDestination(for: OPDSFeedRoute.self) { route in
                OPDSFeedView(route: route)
            }
            .navigationDestination(for: WebDAVDirectoryRoute.self) { route in
                WebDAVDirectoryView(route: route)
            }
            .navigationDestination(for: RemoteLibraryBookRoute.self) { route in
                RemoteLibraryBookDetailView(item: route.item)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label(localized("关闭"), systemImage: "xmark").labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RemoteLibraryConnectionEditor(kind: kind)
                    } label: {
                        Label(localized("新增伺服器"), systemImage: "plus").labelStyle(.iconOnly)
                    }
                }
            }
        }
    }

    private var emptyLibraryView: some View {
        ContentUnavailableView {
            UnavailableLabel(localized("尚未加入书库"), systemImage: "books.vertical")
        } description: {
            Text(localized("加入伺服器即可浏览书籍并开始阅读。")).foregroundStyle(DSColor.textSecondary)
        } actions: {
            NavigationLink(localized("新增伺服器")) {
                RemoteLibraryConnectionEditor(kind: kind)
            }
        }
    }

    @ViewBuilder
    private func connectionLink(_ connection: RemoteLibraryConnection) -> some View {
        if kind == .webDAV, let root = catalogStore.webDAVClient(for: connection).rootURL {
            NavigationLink(value: WebDAVDirectoryRoute(connectionID: connection.id, url: root, title: connection.name)) {
                connectionLabel(connection)
            }
        } else {
            NavigationLink(value: OPDSFeedRoute(catalogID: connection.id, url: connection.url, title: connection.name)) {
                connectionLabel(connection)
            }
        }
    }

    private func connectionLabel(_ connection: RemoteLibraryConnection) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(connection.name).foregroundStyle(DSColor.textPrimary)
            Text(connection.url).font(DSFont.caption).foregroundStyle(DSColor.textSecondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RemoteLibraryConnectionEditor: View {
    let kind: RemoteLibraryKind
    var connection: RemoteLibraryConnection?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalogStore = RemoteLibraryConnectionStore.shared
    @State private var name: String
    @State private var url: String
    @State private var username: String
    @State private var password: String
    @State private var syncProgress: Bool
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testTask: Task<Void, Never>?

    init(kind: RemoteLibraryKind, connection: RemoteLibraryConnection? = nil) {
        self.kind = kind
        self.connection = connection
        _syncProgress = State(initialValue: connection?.syncProgress ?? false)
        _name = State(initialValue: connection?.name ?? "")
        _url = State(initialValue: connection?.url ?? "")
        _username = State(initialValue: connection?.username ?? "")
        _password = State(initialValue: connection.flatMap { RemoteLibraryConnectionStore.shared.password(for: $0) } ?? "")
    }

    private var normalizedURL: URL? { RemoteLibraryConnection.normalizedURL(url, kind: kind) }

    var body: some View {
        Form {
            Section {
                TextField(localized("伺服器名称（选填）"), text: $name)
                TextField(localized("伺服器网址"), text: $url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            } header: {
                Text(localized("伺服器设定"))
                    .foregroundStyle(DSColor.textSecondary)
            } footer: {
                if kind == .calibre {
                    Text(localized("输入 Calibre 或 Calibre-Web 伺服器网址；完整 OPDS 网址也可使用。"))
                        .dsSectionFooter()
                } else if kind == .webDAV {
                    Text(localized("书库连线独立储存，修改此处不会变更 WebDAV 同步设定。"))
                        .dsSectionFooter()
                }
            }
            .interfaceSectionSurface()
            Section(localized("认证（选填）")) {
                TextField(localized("使用者名称"), text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(localized("密码"), text: $password)
            }
            .interfaceSectionSurface()
            if kind == .calibre {
                Section {
                    Toggle(localized("回传至 Calibre 网页阅读器"), isOn: $syncProgress)
                } footer: {
                    Text(localized("使用 Calibre 内容伺服器帐号回传 EPUB 位置，可在电脑的网页阅读器续读。") + "\n\n" + localized("Calibre 桌面独立阅读器与 Calibre-Web 不支援此续读方式。"))
                        .dsSectionFooter()
                }.interfaceSectionSurface()
            }
            Section {
                Button(action: testConnection) {
                    HStack {
                        Text(localized("测试连线"))
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(normalizedURL == nil || isTesting)
                if let testResult { Text(testResult).foregroundStyle(DSColor.textSecondary) }
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .navigationTitle(localized(connection == nil ? "新增伺服器" : "编辑伺服器"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .bookshelf)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: save) {
                    Label(localized("储存"), systemImage: "checkmark").labelStyle(.iconOnly)
                }
                .disabled(normalizedURL == nil)
            }
        }
        .onDisappear { testTask?.cancel() }
        .onChange(of: url) { _, _ in testTask?.cancel(); isTesting = false; testResult = nil }
        .onChange(of: username) { _, _ in testTask?.cancel(); isTesting = false; testResult = nil }
        .onChange(of: password) { _, _ in testTask?.cancel(); isTesting = false; testResult = nil }
    }

    private func save() {
        guard let url = normalizedURL else { return }
        if var connection {
            connection.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if connection.name.isEmpty { connection.name = url.host ?? url.absoluteString }
            connection.url = url.absoluteString
            connection.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            connection.syncProgress = syncProgress
            catalogStore.update(connection, password: password)
        } else {
            var added = catalogStore.add(name: name, url: url.absoluteString, username: username, password: password, kind: kind)
            added.syncProgress = syncProgress
            catalogStore.update(added, password: nil)
        }
        dismiss()
    }

    private func testConnection() {
        guard let url = normalizedURL else { return }
        isTesting = true
        testResult = nil
        let user = username
        let secret = password
        testTask = Task { @MainActor in
            do {
                try await catalogStore.testConnection(url: url, kind: kind, username: user, password: secret)
                try Task.checkCancellation()
                testResult = localized("连线成功")
            } catch {
                guard !Task.isCancelled else { return }
                testResult = error.localizedDescription
            }
            isTesting = false
            if let testResult { UIAccessibility.post(notification: .announcement, argument: testResult) }
        }
    }
}

struct OPDSFeedView: View {
    let route: OPDSFeedRoute
    @ObservedObject private var catalogStore = RemoteLibraryConnectionStore.shared
    @State private var entries: [OPDSEntry] = []
    @State private var nextPageURL: URL?
    @State private var search: OPDSSearch?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var didLoad = false
    @State private var loadError: String?
    @State private var failedWhileLoadingMore = false
    @State private var searchText = ""
    @State private var requestTask: Task<Void, Never>?

    private var connection: RemoteLibraryConnection? {
        catalogStore.connection(id: route.catalogID)
    }

    private var client: OPDSClient? {
        connection.map { RemoteLibraryConnectionStore.shared.client(for: $0) }
    }

    var body: some View {
        List {
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(DSColor.textSecondary)
                    Button(localized("重试")) {
                        if failedWhileLoadingMore {
                            requestTask = Task { await loadMore() }
                        } else { submitSearch() }
                    }
                    .disabled(isLoading || isLoadingMore)
                }
                .interfaceSectionSurface()
            }
            Section {
                ForEach(entries) { entry in row(for: entry) }
                if nextPageURL != nil {
                    Button {
                        requestTask = Task { await loadMore() }
                    } label: {
                        HStack {
                            Text(localized("载入更多"))
                            Spacer()
                            if isLoadingMore { ProgressView() }
                        }
                    }
                    .disabled(isLoadingMore || isLoading)
                }
            }
            .interfaceSectionSurface()
        }
        .softScrollEdges()
        .overlay {
            if isLoading && entries.isEmpty && loadError == nil {
                ProgressView(localized("正在载入书库"))
            } else if !isLoading && entries.isEmpty && loadError == nil {
                ContentUnavailableView {
                    UnavailableLabel(localized("此目录没有内容"), systemImage: "books.vertical")
                }
            }
        }
        .navigationTitle(route.title)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .bookshelf)
        .searchable(text: $searchText, prompt: localized("搜寻此目录"))
        .onSubmit(of: .search, submitSearch)
        .onChange(of: searchText) { oldValue, newValue in
            if !oldValue.isEmpty && newValue.isEmpty { submitSearch() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let connection {
                    Menu {
                        if let url = URL(string: route.url) {
                            NavigationLink(localized("管理远端书库")) {
                                RemoteLibraryManagementView(connectionID: connection.id, directoryURL: url)
                            }
                        }
                        NavigationLink {
                            RemoteLibraryConnectionEditor(kind: connection.kind, connection: connection)
                        } label: {
                            Label(localized("编辑伺服器"), systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Label(localized("书库操作"), systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteLibraryDidChange)) { note in
            guard note.userInfo?["connectionID"] as? String == route.catalogID else { return }
            submitSearch()
        }
        .refreshable { await loadInitial() }
        .task(id: route.url) {
            // Returning from a book keeps the loaded page and search intact.
            guard !didLoad else { return }
            await loadInitial()
        }
    }

    @ViewBuilder
    private func row(for entry: OPDSEntry) -> some View {
        if entry.isNavigation, let dest = entry.navigationURL {
            NavigationLink(value: OPDSFeedRoute(catalogID: route.catalogID, url: dest.absoluteString, title: entry.title)) {
                Label(entry.title, systemImage: "folder.fill").foregroundStyle(DSColor.textPrimary)
            }
        } else {
            NavigationLink(value: RemoteLibraryBookRoute(entry: entry, connectionID: route.catalogID)) {
                HStack(spacing: DSSpacing.md) {
                    BookCoverImage(
                        coverURL: entry.displayCoverURL?.absoluteString ?? "",
                        title: entry.title,
                        author: entry.author,
                        session: connection.map { RemoteLibraryConnectionStore.shared.httpClient(for: $0).session }
                    )
                    .frame(width: DSLayout.searchResultCoverWidth, height: DSLayout.searchResultCoverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(entry.title).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                        if let author = entry.author {
                            Text(author).font(DSFont.caption).foregroundStyle(DSColor.textSecondary).lineLimit(1)
                        }
                        if entry.bestAcquisition == nil {
                            Text(localized("此格式暂不支援阅读")).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func submitSearch() {
        requestTask?.cancel()
        requestTask = Task { await loadInitial() }
    }

    private func loadInitial() async {
        isLoading = true
        loadError = nil
        failedWhileLoadingMore = false
        guard let client, let url = URL(string: route.url) else {
            loadError = localized("书库连线已移除，请重新加入伺服器。")
            isLoading = false
            return
        }
        do {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestURL: URL
            if !query.isEmpty {
                guard let search, let resolved = try await client.searchFeedURL(search: search, query: query) else {
                    loadError = localized("此目录不支援搜寻")
                    isLoading = false
                    return
                }
                requestURL = resolved
            } else { requestURL = url }
            let feed = try await client.fetchFeed(requestURL, isSearch: !query.isEmpty)
            try Task.checkCancellation()
            entries = feed.entries
            nextPageURL = feed.nextPageURL
            if query.isEmpty { search = feed.search }
            didLoad = true
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let client, let nextPageURL, !isLoadingMore else { return }
        isLoadingMore = true
        loadError = nil
        failedWhileLoadingMore = false
        defer { isLoadingMore = false }
        do {
            let feed = try await client.fetchFeed(nextPageURL, isSearch: !searchText.isEmpty)
            try Task.checkCancellation()
            let existing = Set(entries.map(\.id))
            entries.append(contentsOf: feed.entries.filter { !existing.contains($0.id) })
            self.nextPageURL = feed.nextPageURL
        } catch {
            guard !Task.isCancelled else { return }
            failedWhileLoadingMore = true
            loadError = error.localizedDescription
        }
    }
}

extension RemoteLibraryKind {
    var libraryTitle: String {
        switch self {
        case .opds: localized("OPDS 书库")
        case .webDAV: localized("WebDAV 书库")
        case .calibre: localized("Calibre 书库")
        }
    }
}

#Preview {
    OPDSImportView().environmentObject(BookStore())
}
