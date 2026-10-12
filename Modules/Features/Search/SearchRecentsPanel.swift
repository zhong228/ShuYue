import SwiftUI

// MARK: - Idle content

/// What the 检索 page shows when it has no search to show: while its query is empty,
/// 最近搜索 and 最近閱讀 — the workbench's tag cloud and cover-card rail — and
/// otherwise, or with neither to list, the page's own hint. The recents show before
/// the field is even tapped, so the tab greets a reader with what they were reading,
/// not a blank hint (v1.0.24 feedback).
struct SearchIdleContent<Hint: View>: View {
    let isQueryEmpty: Bool
    let onSearch: (String) -> Void
    let onOpenBook: (ReadingBook) -> Void
    let hint: Hint

    @EnvironmentObject private var bookStore: BookStore
    @AppStorage(RecentSearchQueries.storageKey) private var recentQueries = RecentSearchQueries()
    @AppStorage(RecentReadingSelection.clearedAtStorageKey) private var readingClearedAt: Double = 0
    @AppStorage(OffShelfReadRecords.storageKey) private var offShelfReads = OffShelfReadRecords()

    init(
        isQueryEmpty: Bool,
        onSearch: @escaping (String) -> Void,
        onOpenBook: @escaping (ReadingBook) -> Void,
        @ViewBuilder hint: () -> Hint
    ) {
        self.isQueryEmpty = isQueryEmpty
        self.onSearch = onSearch
        self.onOpenBook = onOpenBook
        self.hint = hint()
    }

    var body: some View {
        if isQueryEmpty {
            let books = RecentReadingSelection.entries(
                shelf: bookStore.books,
                records: offShelfReads.records,
                clearedAt: RecentReadingSelection.clearedAt(storedValue: readingClearedAt)
            )
            if recentQueries.queries.isEmpty, books.isEmpty {
                hint
            } else {
                ScrollView {
                    SearchRecentsWorkbench(
                        queries: recentQueries.queries,
                        books: books,
                        onSearch: onSearch,
                        onClearQueries: { recentQueries = RecentSearchQueries() },
                        onOpenBook: onOpenBook,
                        onClearBooks: { readingClearedAt = Date().timeIntervalSinceReferenceDate }
                    )
                    .padding(DSSpacing.lg)
                }
                .scrollDismissesKeyboard(.immediately)
                .softScrollEdges()
            }
        } else {
            hint
        }
    }
}

#Preview("最近搜索與最近閱讀工作台") {
    ScrollView {
        SearchRecentsWorkbench(
            queries: ["紅樓夢", "三體"],
            books: [],
            onSearch: { _ in },
            onClearQueries: {},
            onOpenBook: { _ in },
            onClearBooks: {}
        )
        .padding()
    }
    .background(PageBackgroundView(scope: .search))
}