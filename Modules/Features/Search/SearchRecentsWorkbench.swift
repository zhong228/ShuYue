import SwiftUI

// MARK: - 最近区域工作台

/// The 检索 page's recents, laid out as a workbench instead of the old list:
/// 最近搜索 as a wrapping tag cloud on the left and 最近閱讀 as a rail of cover
/// cards on the right, two columns side by side on every width. A missing
/// column's area is left blank so its neighbour still anchors the row.
struct SearchRecentsWorkbench: View {
    let queries: [String]
    let books: [RecentReadingSelection.Entry]
    let onSearch: (String) -> Void
    let onClearQueries: () -> Void
    let onOpenBook: (ReadingBook) -> Void
    let onClearBooks: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.lg) {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                SearchRecentsWorkbenchHeader(
                    title: localized("最近搜索"),
                    clearAccessibilityLabel: localized("清除最近搜索"),
                    onClear: onClearQueries
                )
                if queries.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    QueryTagCloud(queries: queries, onSearch: onSearch)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)

            VStack(alignment: .leading, spacing: DSSpacing.md) {
                SearchRecentsWorkbenchHeader(
                    title: localized("最近閱讀"),
                    clearAccessibilityLabel: localized("清除最近閱讀"),
                    onClear: onClearBooks
                )
                if books.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    RecentBooksRail(
                        books: books,
                        colorScheme: colorScheme,
                        onOpenBook: onOpenBook,
                        onSearch: onSearch
                    )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A section head of the workbench: title in bold serif, 清除 on the same
/// baseline at the trailing end.
private struct SearchRecentsWorkbenchHeader: View {
    let title: String
    /// 清除 alone does not say which list it empties.
    let clearAccessibilityLabel: String
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            Text(title)
                .font(DSFont.serifSectionTitle)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(localized("清除"), action: onClear)
                .buttonStyle(.borderless)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .contentShape(Rectangle().inset(by: -DSSpacing.sm))
                .accessibilityLabel(clearAccessibilityLabel)
        }
    }
}

// MARK: - 最近搜索标签云

/// A past search as a capsule: the words inside a rounded pill. Tapping it runs
/// the search again, as the old row did.
private struct QueryTag: View {
    let query: String

    var body: some View {
        Text(query)
            .font(DSFont.subheadline)
            .foregroundStyle(DSColor.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, DSSpacing.md)
            .frame(minHeight: 34)
            .background(DSColor.surface, in: Capsule())
            .overlay(Capsule().stroke(DSColor.border, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// The 最近搜索 tags wrapped into however many lines fit the column, using a
/// custom `FlowLayout` so a long list never scrolls away under a horizontal
/// rail.
private struct QueryTagCloud: View {
    let queries: [String]
    let onSearch: (String) -> Void

    var body: some View {
        FlowLayout(spacing: DSSpacing.sm) {
            ForEach(queries, id: \.self) { query in
                Button {
                    onSearch(query)
                } label: {
                    QueryTag(query: query)
                }
                .buttonStyle(.borderless)
                .accessibilityHint(localized("搜索"))
            }
        }
    }
}

// MARK: - 最近阅读横滑封面卡

/// The 最近閱讀 books as a horizontal rail of cover cards, each opening where it
/// was left or, for an off-shelf record, searching for its name.
private struct RecentBooksRail: View {
    let books: [RecentReadingSelection.Entry]
    let colorScheme: ColorScheme
    let onOpenBook: (ReadingBook) -> Void
    let onSearch: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DSSpacing.lg) {
                ForEach(books) { entry in
                    coverCard(entry)
                }
            }
            .padding(.trailing, DSSpacing.lg)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func coverCard(_ entry: RecentReadingSelection.Entry) -> some View {
        switch entry {
        case .shelf(let book):
            Button {
                onOpenBook(book)
            } label: {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    BookshelfCoverStyle.artwork(
                        for: book,
                        colorScheme: colorScheme,
                        displaySize: CGSize(
                            width: DSLayout.searchResultCoverWidth,
                            height: DSLayout.searchResultCoverHeight
                        )
                    )
                    .frame(
                        width: DSLayout.searchResultCoverWidth,
                        height: DSLayout.searchResultCoverHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                    Text(book.title)
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .frame(width: DSLayout.searchResultCoverWidth, alignment: .leading)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(book.title)
        case .record(let record):
            Button {
                onSearch(record.title)
            } label: {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    BookCoverImage(
                        coverURL: record.coverUrl,
                        title: record.title,
                        author: record.author
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
                    Text(record.title)
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .frame(width: DSLayout.searchResultCoverWidth, alignment: .leading)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityHint(localized("搜索"))
        }
    }
}

// MARK: - FlowLayout

/// A minimal wrapping layout: subviews flow left-to-right and wrap to new rows
/// when they would cross the proposed width. Used by the query tag cloud.
private struct FlowLayout: Layout {
    var spacing: CGFloat = DSSpacing.sm

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? max(x - spacing, 0) : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview("最近搜索與最近閱讀工作台") {
    ScrollView {
        SearchRecentsWorkbench(
            queries: ["紅樓夢", "三體", "斗羅大陸", "凡人修仙傳"],
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