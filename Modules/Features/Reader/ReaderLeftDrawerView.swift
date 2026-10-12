import SwiftUI

/// L6「左侧抽屉」：目录与书签的唯一入口，取代原先两个独立 sheet。
///
/// 需求 76：目录改为左侧滑出抽屉，含章节搜索、章节树、书签混排三个分段。
/// - 章节搜索：自定义搜索框实时过滤章节树；
/// - 章节树：完整章节目录，打开时定位到当前章节；
/// - 书签：书签／重点两段（沿用 `BookmarkListSection`）。
///
/// 本视图刻意不带 `NavigationStack`——阅读器用 `.overlay(alignment: .leading)`
/// 呈现，搜索也改用普通 `TextField`（`searchable` 依赖导航栈）。
/// 背景与描边沿用设置页的 `PageBackgroundView(scope: .settings)`，
/// 避免在阅读页面上再叠一层不透明面板破坏沉浸感。
struct ReaderLeftDrawerView: View {
    enum Segment: Hashable {
        case search
        case tree
        case bookmarks
    }

    let bookTitle: String
    let chapters: [BookChapter]
    let currentPage: Int
    let totalPages: Int
    let tocLayoutMode: TOCLayoutMode
    let pageOffsets: [UUID: Int]
    let showsPageNumbers: Bool
    let currentIndex: Int
    let currentChapterID: UUID?
    let onSelectChapter: (BookChapter) -> Void

    let bookmarks: [Bookmark]
    let pageNumber: (Bookmark) -> Int?
    let chapterTitle: (Int) -> String
    let onSelectBookmark: (Bookmark) -> Void
    let onSelectBookmarkChapter: (Int) -> Void
    let onDeleteBookmark: (Bookmark) -> Void

    @Binding var isPresented: Bool
    /// 打开抽屉时默认选中的分段：目录钮进来看章节，书签钮进来看书签。
    let initialSegment: Segment

    @State private var segment: Segment = .search
    @State private var searchText = ""
    @State private var bookmarkSegment: ReaderBookmarkListView.Segment = .bookmark
    @State private var bookmarkSelection = Set<UUID>()

    private var isSearching: Bool {
        segment == .search
            && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredChapters: [BookChapter] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chapters }
        return chapters.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayedChapters: [BookChapter] {
        segment == .tree ? chapters : filteredChapters
    }

    private var bookmarkItems: [Bookmark] {
        bookmarks.filter { $0.kind == .bookmark }
    }

    private var highlightItems: [Bookmark] {
        bookmarks.filter { $0.kind == .underline || $0.kind == .highlight }
    }

    private var currentBookmarkItems: [Bookmark] {
        bookmarkSegment == .bookmark ? bookmarkItems : highlightItems
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            segmentPicker
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)

            switch segment {
            case .search:
                searchBar
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.sm)
                tocContent(displayedChapters)
            case .tree:
                tocContent(displayedChapters)
            case .bookmarks:
                bookmarkContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PageBackgroundView(scope: .settings).ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            headerCloseButton
                .padding(DSSpacing.xs)
        }
        .onAppear {
            segment = initialSegment
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(bookTitle)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.lg)
        .padding(.bottom, DSSpacing.xs)
    }

    private var headerCloseButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(DSFont.fixed(size: 15, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 32, height: 32)
                .background(.thinMaterial, in: Circle())
        }
        .accessibilityLabel(localized("關閉"))
    }

    // MARK: - Segment Picker

    private var segmentPicker: some View {
        Picker("", selection: $segment) {
            Text(localized("搜索章節")).tag(Segment.search)
            Text(localized("章節目錄")).tag(Segment.tree)
            Text(localized("書籤")).tag(Segment.bookmarks)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Chapter Search

    private var searchBar: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
            TextField(localized("搜索章節"), text: $searchText)
                .textFieldStyle(.plain)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .accessibilityLabel(localized("清除"))
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .fill(DSColor.textSecondary.opacity(0.08))
        )
    }

    // MARK: - Chapter Tree

    private func tocContent(_ list: [BookChapter]) -> some View {
        Group {
            if list.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if tocLayoutMode == .verticalRTLColumns {
                verticalTOCList(list)
            } else {
                tocList(list)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func verticalTOCList(_ list: [BookChapter]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                VerticalTOCView(
                    chapters: list,
                    currentIndex: currentIndex,
                    currentChapterID: currentChapterID,
                    pageOffsets: pageOffsets,
                    showsPageNumbers: showsPageNumbers,
                    onSelectChapter: { chapter in
                        onSelectChapter(chapter)
                        isPresented = false
                    }
                )
            }
        }
        .scrollIndicators(.hidden)
    }

    private func tocList(_ list: [BookChapter]) -> some View {
        ScrollViewReader { proxy in
            List {
                if totalPages > 0, segment == .tree {
                    pageCountText
                        .padding(.vertical, DSSpacing.sm)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }

                ForEach(list) { chapter in
                    chapterRow(chapter)
                }
            }
            .softScrollEdges()
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .onAppear {
                guard segment == .tree else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if chapters.first(where: { $0.index == currentIndex }) != nil {
                        // No animation: the list opens on the current chapter, it
                        // does not travel there each time the drawer comes up.
                        proxy.scrollTo(currentIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private var pageCountText: some View {
        Text(String(format: localized("第 %d 頁（共 %d 頁）"), currentPage + 1, totalPages))
            .font(DSFont.fixed(size: 14))
            .foregroundStyle(DSColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func pageNumber(for chapter: BookChapter) -> Int {
        if let offset = pageOffsets[chapter.id] {
            return offset + 1
        }
        return chapter.index + 1
    }

    private func chapterRow(_ chapter: BookChapter) -> some View {
        Button {
            onSelectChapter(chapter)
            isPresented = false
        } label: {
            HStack(spacing: 0) {
                if chapter.level > 0 {
                    Color.clear
                        .frame(width: CGFloat(chapter.level) * 16)
                }

                Text(chapter.title)
                    .font(
                        chapter.level == 0
                        ? .system(size: 14, weight: .semibold)
                        : .system(size: 12, weight: .regular)
                    )
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2)

                Spacer()

                if showsPageNumbers {
                    Text("\(pageNumber(for: chapter))")
                        .font(DSFont.fixed(size: 18, weight: .regular, design: .monospaced))
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .frame(height: 48)
            .padding(.horizontal, 30)
            .background {
                if chapter.id == currentChapterID {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DSColor.appAccent.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden, edges: chapter.id == chapters.first?.id ? .top : [])
        .listRowSeparator(.visible, edges: .bottom)
        .listRowSeparatorTint(Color.secondary.opacity(0.18))
        .id(chapter.index)
    }

    // MARK: - Bookmarks

    private var bookmarkContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $bookmarkSegment) {
                Text(localized("書籤")).tag(ReaderBookmarkListView.Segment.bookmark)
                Text(localized("重點")).tag(ReaderBookmarkListView.Segment.highlight)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.sm)

            BookmarkListSection(
                isBookmark: bookmarkSegment == .bookmark,
                items: currentBookmarkItems,
                pageNumber: pageNumber,
                chapterTitle: chapterTitle,
                onSelect: { bm in
                    onSelectBookmark(bm)
                    isPresented = false
                },
                onSelectChapter: { index in
                    onSelectBookmarkChapter(index)
                    isPresented = false
                },
                onDelete: onDeleteBookmark,
                selection: $bookmarkSelection
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview("抽屉 - 章节") {
    Rectangle()
        .fill(Color.black.opacity(0.35))
        .ignoresSafeArea()
        .overlay(alignment: .leading) {
            ReaderLeftDrawerView(
                bookTitle: "範例書名",
                chapters: [
                    BookChapter(index: 0, title: "第一章 序幕", content: ""),
                    BookChapter(index: 1, title: "第二章 啟程", content: ""),
                    BookChapter(index: 2, title: "第三章 抉擇", content: ""),
                ],
                currentPage: 1,
                totalPages: 240,
                tocLayoutMode: .horizontalList,
                pageOffsets: [:],
                showsPageNumbers: true,
                currentIndex: 0,
                currentChapterID: nil,
                onSelectChapter: { _ in },
                bookmarks: [],
                pageNumber: { _ in nil },
                chapterTitle: { _ in "" },
                onSelectBookmark: { _ in },
                onSelectBookmarkChapter: { _ in },
                onDeleteBookmark: { _ in },
                isPresented: .constant(true),
                initialSegment: .tree
            )
            .frame(width: 380)
        }
}