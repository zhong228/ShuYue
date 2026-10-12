import SwiftUI

// MARK: - 顶部搜索框

/// The 检索 page's resident search field: a large rounded box with a magnifying
/// glass and a clear button, replacing the navigation bar's `.searchable`. The
/// quiet surface and border echo the rest of the workbench, not the scope row
/// of the old page.
struct SearchQueryField: View {
    @Binding var query: String
    let onSearch: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DSFont.body)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            TextField(localized("輸入書名或作者"), text: $query)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(onSearch)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityLabel(localized("清除搜索"))
                }
                .buttonStyle(.borderless)
                .accessibilityHidden(false)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .frame(height: DSLayout.minimumTapTarget)
        .background(
            DSColor.surface,
            in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                .stroke(DSColor.border, lineWidth: 1)
        )
    }
}

// MARK: - 检索范围书源 chips

/// One book source (or the 全部来源 shortcut) as a selectable capsule.
struct SearchSourceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DSFont.subheadline)
                .foregroundStyle(isSelected ? DSColor.appAccent : DSColor.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.md)
                .frame(minHeight: 32)
                .background(
                    isSelected ? DSColor.appAccentSoft : DSColor.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? DSColor.appAccentOutline : DSColor.border,
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The workbench's 检索范围: one horizontal row of source chips — 全部来源 plus
/// every enabled source — replacing the old scope dropdown capsule. Multiple
/// sources stay selected; tapping 全部来源 returns to the full range.
struct SearchSourceChipStrip: View {
    let sources: [BookSource]
    let scope: SearchSourceScope
    let onSelectAll: () -> Void
    let onToggle: (BookSource) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                SearchSourceChip(
                    title: localized("全部書源"),
                    isSelected: scope.mode == .all,
                    action: onSelectAll
                )
                ForEach(sources) { source in
                    SearchSourceChip(
                        title: source.bookSourceName,
                        isSelected: scope.mode == .custom
                            && scope.selectedSourceURLs.contains(
                                SearchSourceScope.sourceKey(for: source)
                            ),
                        action: { onToggle(source) }
                    )
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.xs)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

// MARK: - 按源分组的结果

/// One source's share of the results: a bold source head over a horizontal rail
/// of cover cards. Collapsed, each rail shows only the first books; expanding
/// shows every book the source returned.
struct SearchSourceResultSection: View {
    let sourceName: String
    let coverURL: (SearchBook) -> String
    let books: [SearchBook]
    let isExpanded: Bool
    let onOpen: (SearchBook) -> Void

    /// How many books a collapsed rail keeps.
    private static let collapsedBookLimit = 4

    private var visibleBooks: [SearchBook] {
        isExpanded ? books : Array(books.prefix(Self.collapsedBookLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(sourceName)
                .font(DSFont.serifSectionTitle)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DSSpacing.md) {
                    ForEach(visibleBooks) { book in
                        SearchSourceResultCard(
                            book: book,
                            coverURL: coverURL(book),
                            onOpen: { onOpen(book) }
                        )
                    }
                }
                .padding(.trailing, DSSpacing.lg)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

/// One book in a source's rail: the cover, the title over two lines and the
/// author, all inside the workbench's result-card width.
struct SearchSourceResultCard: View {
    let book: SearchBook
    let coverURL: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                BookCoverImage(
                    coverURL: coverURL,
                    title: book.displayName,
                    author: book.author
                )
                .frame(
                    width: DSLayout.searchResultCoverWidth,
                    height: DSLayout.searchResultCoverHeight
                )
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                .shadow(
                    color: DSColor.searchListCoverShadow,
                    radius: DSLayout.searchListCoverShadowRadius,
                    y: DSLayout.searchListCoverShadowY
                )
                Text(book.displayName)
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(width: DSLayout.searchResultCoverWidth, alignment: .leading)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                        .frame(width: DSLayout.searchResultCoverWidth, alignment: .leading)
                }
            }
        }
        .buttonStyle(.borderless)
    }
}

/// The full result area of the workbench: every chosen source in a labelled
/// section, then the 載入更多 button while more pages wait and, at the bottom,
/// the collapse / expand toggle for the whole page. A book that several sources
/// carry appears in each of their rails; opening any copy goes to the same
/// aggregated detail.
struct SearchGroupedResultsList: View {
    let sources: [BookSource]
    let results: [SearchBook]
    let isExpanded: Bool
    let canLoadMore: Bool
    let onExpandToggle: () -> Void
    let onLoadMore: () -> Void
    let onOpen: (SearchBook) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.xl) {
                ForEach(sources) { source in
                    let books = results(for: source)
                    if !books.isEmpty {
                        SearchSourceResultSection(
                            sourceName: source.bookSourceName,
                            coverURL: { book in
                                book.origins.first { $0.sourceId == source.id }?.coverUrl
                                    ?? book.coverUrl
                            },
                            books: books,
                            isExpanded: isExpanded,
                            onOpen: onOpen
                        )
                    }
                }
                if canLoadMore {
                    loadMoreButton
                        .frame(maxWidth: .infinity)
                }
                expandToggleBar
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.md)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func results(for source: BookSource) -> [SearchBook] {
        results.filter { book in
            book.origins.contains { $0.sourceId == source.id }
        }
    }

    /// 載入更多: fetch the next result page from every source that answered the
    /// last round and hasn't been exhausted yet.
    private var loadMoreButton: some View {
        Button {
            onLoadMore()
        } label: {
            Label(localized("載入更多"), systemImage: "arrow.down.circle")
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.appAccent)
                .frame(maxWidth: .infinity, minHeight: DSLayout.minimumTapTarget)
        }
        .buttonStyle(.borderless)
    }

    private var expandToggleBar: some View {
        Button(action: onExpandToggle) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(DSFont.footnote.weight(.semibold))
                Text(isExpanded ? localized("收起") : localized("展開全部"))
                    .font(DSFont.subheadline.weight(.semibold))
            }
            .foregroundStyle(DSColor.appAccent)
            .frame(maxWidth: .infinity, minHeight: DSLayout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isExpanded ? localized("收起") : localized("展開全部"))
    }
}

#Preview("检索工作台组件") {
    VStack(spacing: DSSpacing.lg) {
        SearchQueryField(query: .constant("三體"), onSearch: {})
        SearchSourceChipStrip(
            sources: [
                BookSource(bookSourceUrl: "https://example.com/a", bookSourceName: "示例源"),
                BookSource(bookSourceUrl: "https://example.com/b", bookSourceName: "另一個源"),
            ],
            scope: .all,
            onSelectAll: {},
            onToggle: { _ in }
        )
        ScrollView(.horizontal) {
            HStack {
                SearchSourceResultCard(
                    book: SearchBook(name: "三體", author: "劉慈欣", origins: []),
                    coverURL: "",
                    onOpen: {}
                )
            }
        }
    }
    .padding()
    .background(PageBackgroundView(scope: .search))
}