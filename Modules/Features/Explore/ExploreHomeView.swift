import Combine
import SwiftUI

// MARK: - Explore Home (书城)

/// The landing screen of the 书城 (Bookstore) tab, redesigned as a channel feed: five
/// horizontally scrolling channel capsules (精选/排行榜/新书/分类/我的页面) switch the
/// content below, the 精选 channel opens with a 今日推荐 hero that rotates featured
/// books, and the source picker moved out of the hero into a bottom drawer opened from
/// the top-right toolbar. The station is deliberately distinct from MoYue's single-feed
/// 发现 page: channels instead of one stream, a drawer instead of an inline menu, and a
/// full-store search entry instead of the old search field.
struct ExploreHomeView: View {
    @EnvironmentObject private var store: BookStore
    @ObservedObject private var sourceStore = BookSourceStore.shared
    /// 書源頁佈局: the selected source's discover page on 书城 mirrors the same layout
    /// the source's own page uses (书城设置 › 布局) — 列表 or 杂志.
    @AppStorage(ExploreSettings.sourcePageLayoutKey)
    private var sourcePageLayout = ExploreSourcePageLayout.default
    /// The browser's page and history, kept by `BrowserView` across visits.
    @ObservedObject var browser: BrowserState

    @State private var exploreSources: [BookSource] = []
    @State private var showSourceManager = false
    @State private var navigation = ExploreNavigationPath()
    @State private var sourceActionSheet: BookSourceActionSheet?
    @State private var sourcePendingDeletion: BookSource?
    @State private var browserPresentation: BrowserPresentation?
    @State private var showsSettings = false
    @ObservedObject private var pageStore = CustomExplorePageStore.shared
    /// 新建频道's or 重命名频道's name prompt, and the name typed into it.
    @State private var pageNamePrompt: PageNamePrompt?
    @State private var pageName = ""
    @State private var pagePendingDeletion: CustomExplorePage?
    /// Currently selected source for the unified discover page.
    @State private var selectedSource: BookSource?
    /// 书城当前显示的频道（精选/排行榜/新书/分类/我的页面）。
    @State private var selectedChannel: BookstoreChannel = .featured
    /// 右上角书源图标打开的底部书源抽屉。
    @State private var showsSourceDrawer = false
    /// 书城选中书源的 URL，持久化后关闭 App 再打开仍保持选中（`ExploreSettings.selectedSourceURLKey`）。
    @AppStorage(ExploreSettings.selectedSourceURLKey) private var selectedSourceURL = ""
    @StateObject private var discoverVM = DiscoverViewModel()

    private struct BrowserPresentation: Identifiable {
        let id = UUID()
        let entry: BrowserEntry
    }

    /// One alert for both prompts: two on one view compete for one presenter.
    private enum PageNamePrompt: Identifiable {
        case create
        case rename(CustomExplorePage)

        var id: String {
            switch self {
            case .create: "create"
            case .rename(let page): page.id.uuidString
            }
        }

        var title: String {
            switch self {
            case .create: localized("新建频道")
            case .rename: localized("重命名频道")
            }
        }
    }

    /// Filter a source list by optional folder and free-text query; used by the
    /// custom-explore component picker's source chooser (not by this page's field,
    /// which is global book search behind the toolbar magnifier).
    static func sources(_ sources: [BookSource], inGroup group: String?, matching query: String) -> [BookSource] {
        sources.filter { source in
            if let group, !groupNames(of: source).contains(group) { return false }
            return query.isEmpty
                || source.bookSourceName.localizedStandardContains(query)
                || source.bookSourceGroup.localizedStandardContains(query)
        }
    }

    private static func groupNames(of source: BookSource) -> [String] {
        source.bookSourceGroup
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack(path: $navigation.path) {
            ScrollView {
                // Lazy, not eager: the page's sections (channel bar, hero banner and
                // the channel's discover feed) are realized as they scroll into view,
                // and the list layout's book rows become direct lazy children of this
                // stack — nesting them under an eager VStack materialized every row
                // (and every remote cover) at once (v1.0.25 feedback).
                LazyVStack(alignment: .leading, spacing: DSSpacing.xl) {
                    channelBar
                    if selectedChannel == .featured {
                        heroBanner
                    }
                    channelContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)
            }
            .rootTabSearchScrollEdges()
            .scrollDismissesKeyboard(.immediately)
            .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
            .pageBackgroundToolbar(for: .explore)
            .rootTabTitle(localized("書城"), onScroll: .minimizesBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showsSourceDrawer = true } label: {
                        Image(systemName: "books.vertical")
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(localized("切换书源来源"))
                    .disabled(exploreSources.isEmpty)
                    Button { navigation.push(.globalSearch()) } label: {
                        Image(systemName: "magnifyingglass")
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(localized("搜索書籍"))
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel(localized("书城设置"))
                }
            }
            .sheet(isPresented: $showsSourceDrawer) { sourceDrawer }
            .sheet(isPresented: $showsSettings) {
                ExploreSettingsSheet()
            }
            .onReceive(sourceStore.$sources) { _ in
                exploreSources = DiscoverViewModel.exploreSources(in: sourceStore)
                restorePersistedSourceIfNeeded()
            }
            .onChange(of: discoverVM.sections.map(\.id)) { _, sectionIDs in
                // 今日推荐依赖多个分类的第一页书单，而列表布局只加载选中分类。
                // 书源分类就绪后主动预加载前几个分类，推荐位无需在杂志/列表间
                // 切换才生效（今日推荐反馈 #1）。
                guard selectedChannel == .featured, selectedSource != nil else { return }
                for id in sectionIDs.prefix(4) {
                    discoverVM.loadSection(id)
                }
            }
            .sheet(isPresented: $showSourceManager) {
                BookSourceListView()
            }
            .bookSourceActionSheets(sheet: $sourceActionSheet, pendingDeletion: $sourcePendingDeletion)
            .fullScreenCover(item: $browserPresentation) { presentation in
                NavigationStack {
                    BrowserPage(browser: browser, entry: presentation.entry)
                }
                .environmentObject(store)
            }
            .navigationDestination(for: ExploreNavigationRoute.self, destination: destination)
            .alert(
                pageNamePrompt?.title ?? "",
                isPresented: Binding(
                    get: { pageNamePrompt != nil },
                    set: { if !$0 { pageNamePrompt = nil } }
                ),
                presenting: pageNamePrompt
            ) { prompt in
                TextField(localized("名稱"), text: $pageName)
                switch prompt {
                case .create:
                    Button(localized("新建")) { pageStore.createPage(named: pageName) }
                case .rename(let page):
                    Button(localized("確定")) { pageStore.renamePage(id: page.id, to: pageName) }
                }
                Button(localized("取消"), role: .cancel) {}
            }
            .confirmationDialog(
                String(format: localized("刪除「%@」？"), pagePendingDeletion?.name ?? ""),
                isPresented: Binding(
                    get: { pagePendingDeletion != nil },
                    set: { if !$0 { pagePendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pagePendingDeletion
            ) { page in
                Button(localized("刪除"), role: .destructive) { deletePage(page) }
                Button(localized("取消"), role: .cancel) {}
            } message: { _ in
                Text(localized("頁面裡的元件會一起刪除。"))
            }
        }
    }

    // MARK: - Channel Bar

    /// 频道胶囊条：五个频道 + 末尾加号胶囊（新建频道），右侧是卡片/列表布局切换。
    private var channelBar: some View {
        HStack(spacing: DSSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    ForEach(BookstoreChannel.allCases) { channel in
                        DSChip(
                            title: localized(channel.titleKey),
                            isSelected: selectedChannel == channel,
                            minWidth: DSLayout.capsuleControlMinWidth,
                            usesGlassSurface: false
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedChannel != channel { selectedChannel = channel }
                            }
                        }
                    }
                    Button {
                        pageName = ""
                        pageNamePrompt = .create
                    } label: {
                        DSCapsuleLabel(
                            title: localized("新建频道"),
                            systemImage: "plus",
                            usesGlassSurface: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localized("新建频道"))
                }
                .padding(.vertical, DSSpacing.xs)
            }
            .scrollIndicators(.hidden)
            layoutToggle
        }
    }

    /// 频道工具条右侧的卡片/列表布局切换（书城设置 › 布局）。
    @ViewBuilder
    private var layoutToggle: some View {
        if selectedChannel != .myPages, selectedSource != nil {
            HStack(spacing: 4) {
                ForEach(ExploreSourcePageLayout.allCases) { layout in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sourcePageLayout = layout
                        }
                    } label: {
                        Image(systemName: layout.systemImage)
                            .font(DSFont.fixed(size: 14, weight: .semibold))
                            .frame(width: DSLayout.capsuleControlHeight, height: DSLayout.capsuleControlHeight)
                            .background {
                                Capsule().fill(sourcePageLayout == layout ? DSColor.accent : DSColor.surface)
                            }
                            .foregroundStyle(sourcePageLayout == layout ? DSColor.textOnAccent : DSColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localized(layout.titleKey))
                }
            }
        }
    }

    // MARK: - Hero Banner (今日推荐)

    /// 精选频道的英雄位：今日推荐大卡自动轮播；没有可推荐的书时回退到品牌欢迎卡。
    @ViewBuilder
    private var heroBanner: some View {
        if let recommendations = todayRecommendations, !recommendations.isEmpty {
            TodayRecommendationBanner(
                items: recommendations,
                onOpenBook: { book in navigation.push(.book(book)) },
                onResumeBrowser: { openBrowser(.resume) }
            )
        } else {
            brandHeroCard
        }
    }

    /// 选中的书源加载完成后，从各分类的第一页轮流收集书作今日推荐（最多 6 本）。
    /// 每个分类先各取一本再进入第二轮，保证推荐覆盖多个分类而不是堆在同一分类；
    /// 名字含「推荐」的分类排在最前；同一本书（按 bookUrl）只推荐一次。
    private var todayRecommendations: [TodayRecommendation]? {
        let loaded = discoverVM.sections
            .filter { !$0.books.isEmpty }
            .sorted { lhs, rhs in
                let lhsRecommended = lhs.title.contains("推荐")
                let rhsRecommended = rhs.title.contains("推荐")
                guard lhsRecommended != rhsRecommended else { return false }
                return lhsRecommended
            }
        guard !loaded.isEmpty else { return nil }
        var picks: [TodayRecommendation] = []
        var seenURLs = Set<String>()
        var cursors = loaded.map { (section: $0, index: 0) }
        while picks.count < 6 {
            var progressed = false
            for i in cursors.indices where picks.count < 6 {
                guard cursors[i].index < cursors[i].section.books.count else { continue }
                let item = cursors[i].section.books[cursors[i].index]
                cursors[i].index += 1
                if seenURLs.insert(item.book.bookUrl).inserted {
                    picks.append(TodayRecommendation(book: item.book, section: cursors[i].section))
                }
                progressed = true
            }
            if !progressed { break }
        }
        return picks.isEmpty ? nil : picks
    }

    /// 品牌欢迎卡：没有可轮播推荐时展示的渐变卡，保留浏览器入口。
    private var brandHeroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DSColor.appAccentDark, DSColor.appAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: DSColor.appAccent.opacity(0.24), radius: 12, x: 0, y: 6)
            // 书卷印章装饰：右上角一枚半透明白色书页纹理。
            GeometryReader { proxy in
                VStack(alignment: .trailing, spacing: -4) {
                    Text("书")
                        .font(DSFont.fixed(size: 76, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.16))
                    Text("SHUYUE")
                        .font(DSFont.fixed(size: 9, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.22))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 6)
                .padding(.trailing, 14)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(localized("发现好书"))
                    .font(DSFont.fixed(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text(localized("探索无尽阅读世界"))
                    .font(DSFont.callout)
                    .foregroundStyle(.white.opacity(0.9))
                Button { openBrowser(.resume) } label: {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "safari")
                            .font(DSFont.fixed(size: 13, weight: .semibold))
                        Text(localized("打开浏览器"))
                            .font(DSFont.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.xs)
                    .background {
                        RoundedRectangle(cornerRadius: DSRadius.md)
                            .fill(.white.opacity(0.25))
                    }
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .frame(height: 112)
    }

    // MARK: - Channel Content

    @ViewBuilder
    private var channelContent: some View {
        if selectedChannel == .myPages {
            myPagesSection
        } else {
            sourceChannelContent
        }
    }

    /// 书源相关的四个频道（精选/排行榜/新书/分类）共用选中的书源内容，按频道过滤分类。
    @ViewBuilder
    private var sourceChannelContent: some View {
        if let selectedSource {
            Group {
                switch sourcePageLayout {
                case .magazine:
                    DiscoverShowcaseView(
                        discover: discoverVM,
                        onOpenPage: { address in openBrowser(.open(address)) },
                        embedsScrollView: false,
                        sectionFilter: { selectedChannel.matches($0) }
                    )
                case .list:
                    DiscoverListLayoutView(
                        discover: discoverVM,
                        onOpenPage: { address in openBrowser(.open(address)) },
                        embedsScrollView: false,
                        sectionFilter: { selectedChannel.matches($0) }
                    )
                }
            }
            // 切换频道时重建选中分类、轮播索引等频道内状态。
            .id(selectedChannel)
        } else if !exploreSources.isEmpty {
            ContentUnavailableView {
                Label(localized("请先选择来源"), systemImage: "books.vertical")
            } actions: {
                Button(localized("切换书源来源")) { showsSourceDrawer = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(localized("暂未配置书源"), systemImage: "books.vertical")
            } actions: {
                Button(localized("前往管理")) { showSourceManager = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// 我的页面频道：用户自建的自定义页网格，加号胶囊新建。
    @ViewBuilder
    private var myPagesSection: some View {
        if pageStore.pages.isEmpty {
            ContentUnavailableView {
                Label(localized("新建频道"), systemImage: "plus.circle")
            } actions: {
                Button(localized("新建频道")) {
                    pageName = ""
                    pageNamePrompt = .create
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: DSSpacing.md)],
                spacing: DSSpacing.md
            ) {
                ForEach(pageStore.pages) { page in
                    NavigationLink(value: ExploreNavigationRoute.customPage(id: page.id)) {
                        QuickAccessCard(
                            icon: "doc.text",
                            title: page.name,
                            subtitle: localized("自定义页面"),
                            color: DSColor.appAccent,
                            action: { }
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu { pageActions(page) }
                }
            }
        }
    }

    // MARK: - Source Drawer

    /// 底部书源抽屉：列出书源、启用状态与当前选中项，替代原来的头部 Menu。
    private var sourceDrawer: some View {
        NavigationStack {
            Group {
                if exploreSources.isEmpty {
                    ContentUnavailableView {
                        Label(localized("暂未配置书源"), systemImage: "books.vertical")
                    } actions: {
                        Button(localized("前往管理")) {
                            showsSourceDrawer = false
                            showSourceManager = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(exploreSources) { source in
                                Button {
                                    selectSource(source)
                                } label: {
                                    HStack(spacing: DSSpacing.md) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source.bookSourceName)
                                                .font(DSFont.subheadline.weight(.medium))
                                                .foregroundStyle(DSColor.textPrimary)
                                                .lineLimit(1)
                                            Text(source.enabled ? localized("已啟用") : localized("已停用"))
                                                .font(DSFont.caption)
                                                .foregroundStyle(DSColor.textSecondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if selectedSource?.id == source.id {
                                            Image(systemName: "checkmark")
                                                .font(DSFont.subheadline.weight(.semibold))
                                                .foregroundStyle(DSColor.accent)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Section {
                            Button {
                                showsSourceDrawer = false
                                showSourceManager = true
                            } label: {
                                Label(localized("前往管理"), systemImage: "slider.horizontal.3")
                                    .foregroundStyle(DSColor.accent)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(localized("切换书源来源"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showsSourceDrawer = false } label: {
                        Label(localized("完成"), systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Actions

    private func openBrowser(_ entry: BrowserEntry) {
        browserPresentation = BrowserPresentation(entry: entry)
    }

    private func selectSource(_ source: BookSource) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedSource = source
            selectedSourceURL = source.bookSourceUrl
            discoverVM.selectSource(source)
            discoverVM.reload()
        }
        showsSourceDrawer = false
    }

    @ViewBuilder
    private func pageActions(_ page: CustomExplorePage) -> some View {
        Button {
            pageName = page.name
            pageNamePrompt = .rename(page)
        } label: {
            Label(localized("重命名频道"), systemImage: "pencil")
        }
        Button(role: .destructive) {
            pagePendingDeletion = page
        } label: {
            Label(localized("刪除"), systemImage: "trash")
        }
    }

    /// Deletes the page.
    private func deletePage(_ page: CustomExplorePage) {
        pageStore.deletePage(id: page.id)
    }

    /// 恢复上次选中的书城书源：关闭 App 再打开仍保持选中。
    ///
    /// 只在还没有选中书源时恢复（本次会话的显式选择优先于持久化值）。持久化指向的
    /// 书源被禁用或删除后，清空持久化值，避免下一次启动反复尝试恢复一个不存在的源。
    private func restorePersistedSourceIfNeeded() {
        guard selectedSource == nil, !selectedSourceURL.isEmpty,
              !exploreSources.isEmpty else { return }
        if let source = exploreSources.first(where: { $0.bookSourceUrl == selectedSourceURL }) {
            selectedSource = source
            discoverVM.selectSource(source)
            discoverVM.reload()
        } else {
            selectedSourceURL = ""
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(_ route: ExploreNavigationRoute) -> some View {
        switch route {
        case .source(let sourceURL):
            if let source = sourceStore.sources.first(where: { $0.bookSourceUrl == sourceURL }) {
                ExploreSourcePage(source: source) { address in
                    openBrowser(.open(address))
                }
            } else {
                deletedSourceState
            }
        case .customPage(let id):
            CustomExplorePageView(pageID: id)
        case .customPageEditor(let id):
            CustomExplorePageEditor(pageID: id)
        case .book(let book):
            OnlineBookDetailDestination(.book(book)).environmentObject(store)
        case .sourceCategory(let reference):
            if let source = reference.source, let item = reference.cardItem {
                DiscoverCategoryView(
                    section: DiscoverShowcaseSection(
                        item: item,
                        coverBaseURL: source.bookSourceUrl,
                        coverHeaders: source.parsedHeaders
                    ),
                    source: source
                )
            } else {
                deletedSourceState
            }
        case .searchInSource(let sourceURL):
            SearchView(sessionScope: SearchSourceScope(
                mode: .custom, selectedSourceURLs: [sourceURL]
            ))
            .environmentObject(store)
        case .globalSearch(let initialQuery):
            SearchView(initialQuery: initialQuery)
                .environmentObject(store)
        case .sourceManager:
            BookSourceListView(embedsNavigationStack: false)
        }
    }

    private var deletedSourceState: some View {
        ContentUnavailableView {
            UnavailableLabel(localized("書源已被刪除"), systemImage: "books.vertical")
        }
    }
}

// MARK: - 今日推荐轮播

/// 今日推荐轮播的一项：一本书连同它所属的分类（封面请求上下文与推荐原因）。
private struct TodayRecommendation: Identifiable {
    let id = UUID()
    let book: OnlineBook
    let section: DiscoverShowcaseSection
}

/// 精选频道英雄位的大卡：可横滑的分页轮播（自动轮换 + 手势滑动），圆点指示条。
private struct TodayRecommendationBanner: View {
    let items: [TodayRecommendation]
    let onOpenBook: (OnlineBook) -> Void
    let onResumeBrowser: () -> Void
    @State private var index = 0
    @State private var timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                TodayRecommendationCard(
                    item: item,
                    onOpenBook: onOpenBook,
                    onResumeBrowser: onResumeBrowser
                )
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 192)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 5) {
                ForEach(0..<items.count, id: \.self) { dot in
                    Capsule()
                        .fill(.white.opacity(dot == index ? 0.95 : 0.35))
                        .frame(width: dot == index ? 16 : 6, height: 6)
                    // Active page reads as a small bar; the rest stay round dots.
                        .animation(.easeInOut(duration: 0.25), value: index)
                }
            }
            .padding(.trailing, DSSpacing.md)
            .padding(.bottom, DSSpacing.xs)
            .accessibilityHidden(true)
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                index = (index + 1) % items.count
            }
        }
    }
}

/// 单页推荐卡：分层品牌渐变 + 封面 + 标题/作者/简介 + 「立即阅读」行动按钮。
private struct TodayRecommendationCard: View {
    let item: TodayRecommendation
    let onOpenBook: (OnlineBook) -> Void
    let onResumeBrowser: () -> Void

    /// 作者与来源分类拼成一行元信息；作者缺失时退回分类名。
    private var metaLine: String {
        [item.book.author, item.section.title]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// 简介压成一行文案；缺失时不再占位。
    private var introLine: String? {
        let trimmed = item.book.intro
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        ZStack {
            // ── Layered backdrop ──
            RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DSColor.appAccentDark, DSColor.appAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: DSColor.appAccent.opacity(0.24), radius: 12, x: 0, y: 6)
            RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.16), .clear],
                        center: .topTrailing,
                        startRadius: 8,
                        endRadius: 220
                    )
                )
            LinearGradient(
                colors: [.clear, .black.opacity(0.20)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous))
            // 书卷印章装饰：右上角一枚半透明白色书页纹理。
            GeometryReader { proxy in
                VStack(alignment: .trailing, spacing: -4) {
                    Text("书")
                        .font(DSFont.fixed(size: 76, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.14))
                    Text("SHUYUE")
                        .font(DSFont.fixed(size: 9, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.20))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 6)
                .padding(.trailing, 14)
                .accessibilityHidden(true)
            }

            // ── Content ──
            HStack(spacing: DSSpacing.md) {
                DiscoverCover(
                    display: DiscoverBookDisplay(book: item.book, intro: "", isAudiobook: false),
                    section: item.section,
                    size: CGSize(width: 92, height: 138)
                )
                .shadow(color: .black.opacity(0.35), radius: 7, x: 0, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Label(localized("今日推荐"), systemImage: "sparkles")
                            .font(DSFont.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.18), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.6))
                        Spacer(minLength: 0)
                    }

                    Text(item.book.name)
                        .font(DSFont.fixed(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)

                    if !metaLine.isEmpty {
                        Label(metaLine, systemImage: "person.crop.circle")
                            .font(DSFont.caption)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                    }

                    if let intro = introLine {
                        Text(intro)
                            .font(DSFont.caption2)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    // 行动行：主行动进详情页，浏览器入口降为次级胶囊，避免误触。
                    HStack(spacing: DSSpacing.sm) {
                        Text(localized("立即阅读"))
                            .font(DSFont.caption.weight(.semibold))
                            .foregroundStyle(DSColor.appAccentDark)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.92), in: Capsule())
                        Button(action: onResumeBrowser) {
                            Label(localized("浏览器"), systemImage: "safari")
                                .font(DSFont.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, DSSpacing.sm)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.16), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(localized("打开浏览器"))
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenBook(item.book) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(localized("今日推荐"))：\(item.book.name)，\(item.section.title)")
    }
}

// MARK: - QuickAccessCard

struct QuickAccessCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Image(systemName: icon)
                    .font(DSFont.fixed(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(DSColor.appAccentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                Text(title)
                    .font(DSFont.fixed(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(DSSpacing.md)
            .frame(width: 140, height: 108)
            .background(DSColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                    .stroke(DSColor.appAccentOutline, lineWidth: 0.6)
            }
            .shadow(color: DSColor.appAccent.opacity(0.10), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ExploreHomeView(browser: BrowserState())
        .environmentObject(BookStore())
}