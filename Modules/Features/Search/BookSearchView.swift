import SwiftUI

private typealias BookSearchResultRoute = SearchResultRoute<SearchBook>

/// Everything the 检索 page pushes through its one item-based destination.
///
/// One destination, never one per kind. TestFlight build 5 gave 最近閱讀's reader a
/// second `navigationDestination(item:)` beside the results' own, and on iOS 17 the
/// result's detail then lost its own reader push: the second time through, the manga
/// reader would not open from the detail, or would not leave it on Back (iOS 17.5
/// simulator; `DetailReaderBackSwipeUITests.testSearchTabMangaResultOpensEveryTime`).
/// With this page still reading `DismissAction`, the same build froze on the first tap of
/// a result instead (Technotes/iOS17ReaderNavigationWatchdog.md). 最近閱讀's reader is
/// no longer pushed at all — see `recentReaderRoute`.
private enum SearchPagePush: Hashable {
    /// A search result, pushed from either a source rail's card or a group rail.
    case result(BookSearchResultRoute)
}

/// Resolves a push without capturing `BookSearchView` or its live `SearchAggregator`
/// (Technotes/iOS17SearchWatchdogPostmortem.md, guardrail 3).
private struct SearchPagePushDestination: View {
    let push: SearchPagePush

    var body: some View {
        switch push {
        case .result(let route):
            SearchResultDestination(route: route)
        }
    }
}

/// Resolves a frozen route without capturing `BookSearchView` or its live
/// `SearchAggregator`. The inherited store is forwarded explicitly to preserve
/// the existing detail-view environment contract.
private struct SearchResultDestination: View {
    let route: BookSearchResultRoute
    @EnvironmentObject private var bookStore: BookStore

    var body: some View {
        OnlineBookDetailDestination(.search(route.snapshot))
            .environmentObject(bookStore)
    }
}

/// 检索's title: a tab root's at the root of its tab, `.inline` where it is pushed.
private struct SearchPageTitle: ViewModifier {
    let isTabRoot: Bool

    func body(content: Content) -> some View {
        if isTabRoot {
            content.rootTabTitle(localized("檢索"), onScroll: .minimizesBar)
        } else {
            content
                .navigationTitle(localized("檢索"))
                .toolbarTitleDisplayMode(.inline)
        }
    }
}

/// The results' scroll edge: a tab root's under the 检索 tab's minimizing bar, the app's
/// soft edge where the page is pushed.
private struct SearchResultsScrollEdges: ViewModifier {
    let isTabRoot: Bool

    func body(content: Content) -> some View {
        if isTabRoot {
            content.rootTabSearchScrollEdges()
        } else {
            content.softScrollEdges()
        }
    }
}

// MARK: - Book Search View

/// The 检索 page, rebuilt as a workbench: a resident rounded search field up top,
/// the source scope as a row of selectable chips, per-source result groups under
/// them, and the recents as a tag cloud and cover-card rail while idle.
struct BookSearchView: View {
    var initialQuery: String = ""
    /// A scope for this search page only, never saved — Legado's 搜索 on one source
    /// (`searchScope.update(scope, save = false)`). `nil` uses the saved scope.
    var sessionScope: SearchSourceScope?
    /// The 检索 tab's own root, which carries a tab root's title; pushed from elsewhere,
    /// the page is `.inline` like any other.
    var isTabRoot = false

    @EnvironmentObject var bookStore: BookStore
    @StateObject private var aggregator = SearchAggregator()
    @StateObject private var scopeStore = SearchSourceScopeStore.shared
    @ObservedObject private var sourceStore = BookSourceStore.shared
    // No `@Environment(\.dismiss)` here: iOS 17 replaces DismissAction over and over
    // while a result's detail is pushed above this page, and every replacement re-runs
    // this body (Technotes/iOS17ReaderNavigationWatchdog.md).
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var errorMsg: String? = nil
    @State private var submittedQuery = ""
    @State private var needsSearchResubmission = false
    /// The session scope as the reader changes it on this page.
    @State private var editedSessionScope: SearchSourceScope?
    /// What this page has pushed through its one item-based destination.
    @State private var pushed: SearchPagePush?
    /// Whether every source's rail shows all its books, or only the first four.
    @State private var resultsAreExpanded = true
    /// A book opened from 最近閱讀, full screen over the search, as Apple Books opens a
    /// book from its search; closing it comes back to the list as it was left. 最近閱讀
    /// shows only while the search field is active, and pushed onto this stack the reader
    /// lost its hidden navigation bar: the active `UISearchController` puts back the bar
    /// it had collapsed as the push starts (`_navigationControllerWillShowViewController:`,
    /// right after SwiftUI hid it), which left a bar-high band above the classic top bar.
    @State private var recentReaderRoute: DetailReaderRoute?
    @AppStorage(RecentSearchQueries.storageKey) private var recentQueries = RecentSearchQueries()

    /// The scope this page searches: its own session scope, else the saved one.
    private var activeScope: SearchSourceScope {
        editedSessionScope ?? sessionScope ?? scopeStore.scope
    }

    var enabledSources: [BookSource] { sourceStore.enabledSources }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowEmptyResult: Bool {
        !submittedQuery.isEmpty && trimmedQuery == submittedQuery
    }

    private var isSearchInProgress: Bool {
        aggregator.isSearching || aggregator.isPaused
    }

    var body: some View {
        AdaptiveContentContainer(maxWidth: DSLayout.readableExpandedWidth) {
            VStack(spacing: 0) {
                headerControls

                if isSearchInProgress {
                    SearchProgressControl(
                        progress: aggregator.progress,
                        currentSourceName: aggregator.currentSourceName,
                        isPaused: aggregator.isPaused,
                        onPause: { aggregator.pause() },
                        onResume: { aggregator.resume() }
                    )
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.sm)
                    .transition(.opacity)
                }

                ZStack {
                    if !aggregator.results.isEmpty {
                        resultList
                    } else if aggregator.isSearching {
                        // Progress and the pause control live in the workbench above.
                        ProgressView(localized("搜索中…"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .rootTabTitleScrollAnchor()
                    } else if aggregator.isPaused {
                        pausedPlaceholder
                            .rootTabTitleScrollAnchor()
                    } else if shouldShowEmptyResult {
                        emptyResultView
                            .rootTabTitleScrollAnchor()
                    } else {
                        SearchIdleContent(
                            isQueryEmpty: trimmedQuery.isEmpty,
                            onSearch: searchAgain,
                            onOpenBook: openRecentBook
                        ) {
                            hintView
                                .rootTabTitleScrollAnchor()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PageBackgroundView(scope: .search))
        }
        .background(PageBackgroundView(scope: .search).ignoresSafeArea())
        .pageBackgroundToolbar(for: .search)
        .modifier(SearchPageTitle(isTabRoot: isTabRoot))
        // The page's only item-based destination (see `SearchPagePush`). Every
        // result card routes through here, on iOS 17 and 18 alike; the old
        // split — value routing on iOS 18, item routing on iOS 17 — and its
        // UIKit table are gone with the rework.
        .navigationDestination(item: $pushed, destination: SearchPagePushDestination.init(push:))
        .fullScreenCover(item: $recentReaderRoute) { route in
            BookReaderView(bookId: route.id)
                .environmentObject(bookStore)
                .environment(\.readerNavigator, nil)
        }
        .onSubmit(of: .search) { doSearch() }
        .onChange(of: query) { _, newValue in
            // Mirror the old clear button: emptying the field resets the search.
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                submittedQuery = ""
                needsSearchResubmission = false
                aggregator.cancelAndClear()
            }
        }
        .alert(
            localized("搜索失敗"),
            isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })
        ) {
            Button(localized("確認")) { errorMsg = nil }
        } message: {
            Text(errorMsg ?? "")
        }
        .onAppear {
            aggregator.setResultPresentationActive(scenePhase == .active)
            if !initialQuery.isEmpty && query.isEmpty {
                query = initialQuery
                doSearch()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            aggregator.setResultPresentationActive(phase == .active)
        }
    }

    // MARK: Header

    /// The workbench's resident controls: the rounded search field and, beneath it,
    /// the source chips that replaced the old scope dropdown.
    private var headerControls: some View {
        VStack(spacing: DSSpacing.sm) {
            SearchQueryField(query: $query, onSearch: doSearch)
                .padding(.horizontal, DSSpacing.lg)
            if !enabledSources.isEmpty {
                SearchSourceChipStrip(
                    sources: enabledSources,
                    scope: activeScope,
                    onSelectAll: selectAllSources,
                    onToggle: toggleSource
                )
            }
        }
        .padding(.top, DSSpacing.md)
    }

    // MARK: Result List

    private var resultList: some View {
        SearchGroupedResultsList(
            sources: activeScope.resolvedSources(from: enabledSources),
            results: aggregator.results,
            isExpanded: resultsAreExpanded,
            canLoadMore: canLoadMore,
            onExpandToggle: {
                withAnimation(reduceMotion ? nil : DSAnimation.standard) {
                    resultsAreExpanded.toggle()
                }
            },
            onLoadMore: { aggregator.loadMore() },
            onOpen: { book in
                pushed = .result(BookSearchResultRoute(id: book.id, snapshot: book))
            }
        )
        .modifier(SearchResultsScrollEdges(isTabRoot: isTabRoot))
    }

    private var canLoadMore: Bool {
        aggregator.hasMoreResults && !aggregator.isSearching && !aggregator.isPaused
    }

    // MARK: Empty State

    /// Shown when a search was paused before any result came back. The workbench's
    /// progress block above carries the search on.
    private var pausedPlaceholder: some View {
        ContentUnavailableView {
            UnavailableLabel(localized("已暫停"), systemImage: "pause.circle")
        } description: {
            Text(localized("點擊繼續搜索剩餘書源"))
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    private var emptyResultView: some View {
        ContentUnavailableView {
            UnavailableLabel(
                String(format: localized("沒有找到「%@」"), submittedQuery),
                systemImage: "magnifyingglass"
            )
        } description: {
            Text(localized("嘗試換個關鍵字，或切換書源"))
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    @ViewBuilder
    private var hintView: some View {
        if enabledSources.isEmpty {
            ContentUnavailableView {
                UnavailableLabel(localized("尚未設置書源"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(localized("請先在書源管理中新增並啟用書源"))
                    .foregroundStyle(DSColor.textSecondary)
            }
        } else {
            ContentUnavailableView {
                UnavailableLabel(
                    needsSearchResubmission
                        ? localized("搜索範圍已更新，請再次搜索")
                        : localized("輸入書名或作者搜索"),
                    systemImage: "text.magnifyingglass"
                )
            } description: {
                Text(String(format: localized("已啟用 %d 個書源"), enabledSources.count))
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    // MARK: Search Logic

    private func applySearchSourceScope(_ newScope: SearchSourceScope) {
        guard newScope != activeScope else { return }
        if sessionScope != nil {
            editedSessionScope = newScope
        } else {
            scopeStore.save(newScope)
        }
        submittedQuery = ""
        needsSearchResubmission = !trimmedQuery.isEmpty
        aggregator.cancelAndClear()
    }

    /// 全部来源 chip: back to the whole enabled range.
    private func selectAllSources() {
        guard activeScope.mode != .all else { return }
        applySearchSourceScope(.all)
    }

    /// One source chip toggles that source in the custom scope. Selecting every
    /// enabled source — or unselecting the last one — folds back to 全部来源, so
    /// the scope never lands on an empty custom set.
    private func toggleSource(_ source: BookSource) {
        let key = SearchSourceScope.sourceKey(for: source)
        var selected: Set<String>
        switch activeScope.mode {
        case .all:
            selected = [key]
        case .custom:
            selected = activeScope.selectedSourceURLs
            if selected.contains(key) {
                selected.remove(key)
            } else {
                selected.insert(key)
            }
        }
        let significantKeys = Set(
            enabledSources
                .map(SearchSourceScope.sourceKey(for:))
                .filter { !$0.isEmpty }
        )
        if selected.isEmpty || selected == significantKeys {
            applySearchSourceScope(.all)
        } else {
            applySearchSourceScope(
                SearchSourceScope(mode: .custom, selectedSourceURLs: selected)
            )
        }
    }

    private func doSearch() {
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        let sources = activeScope.resolvedSources(from: enabledSources)
        guard !sources.isEmpty else {
            errorMsg = activeScope.mode == .custom
                ? localized("請至少選擇一個可用書源")
                : localized("沒有可用的書源，請先啟用書源")
            return
        }

        needsSearchResubmission = false
        submittedQuery = q
        recentQueries = recentQueries.recording(q)
        aggregator.search(query: q, sources: sources)
    }

    /// 最近搜索: the same search again, as if typed and submitted.
    private func searchAgain(_ recent: String) {
        query = recent
        doSearch()
    }

    /// 最近閱讀: back into the book where it was left, moved to the front of 最近閱讀
    /// as opening it from the shelf does.
    private func openRecentBook(_ book: ReadingBook) {
        bookStore.updateLastOpened(bookId: book.id)
        recentReaderRoute = DetailReaderRoute(id: book.id)
    }
}

// MARK: - OnlineBook Identifiable (for sheet item)
extension OnlineBook: Hashable {
    static func == (lhs: OnlineBook, rhs: OnlineBook) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SearchBook Identifiable (for sheet item)
extension SearchBook: Hashable {
    static func == (lhs: SearchBook, rhs: SearchBook) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview("检索") {
    NavigationStack {
        BookSearchView()
            .environmentObject(BookStore())
    }
}