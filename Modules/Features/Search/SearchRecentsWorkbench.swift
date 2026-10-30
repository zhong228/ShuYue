import SwiftUI

// MARK: - 最近区域工作台

/// The 检索 page's recents, laid out as a workbench instead of the old list.
/// On a phone the two sections stack vertically, each full width — the side-by-side
/// columns crammed the tag cloud and the cover rail into half-width slivers
/// (v1.3.6 feedback). On a regular-width canvas (iPad) the two columns remain.
struct SearchRecentsWorkbench: View {
    let queries: [String]
    let books: [RecentReadingSelection.Entry]
    let onSearch: (String) -> Void
    let onClearQueries: () -> Void
    let onOpenBook: (ReadingBook) -> Void
    let onClearBooks: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    queriesSection
                    booksSection
                }
            } else {
                HStack(alignment: .top, spacing: DSSpacing.xl) {
                    queriesSection
                    booksSection
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 最近搜索：通栏标签云；空态给出轻量占位而不是留白。
    private var queriesSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            SearchRecentsWorkbenchHeader(
                title: localized("最近搜索"),
                clearAccessibilityLabel: localized("清除最近搜索"),
                onClear: onClearQueries
            )
            if queries.isEmpty {
                EmptyRecentsHint(
                    text: localized("搜索过的关键词会显示在这里"),
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                QueryTagCloud(queries: queries, onSearch: onSearch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 最近閱讀：通栏封面轨道；空态同样给出轻量占位。
    private var booksSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            SearchRecentsWorkbenchHeader(
                title: localized("最近阅读"),
                clearAccessibilityLabel: localized("清除最近阅读"),
                onClear: onClearBooks
            )
            if books.isEmpty {
                EmptyRecentsHint(
                    text: localized("读过的书会显示在这里，方便继续"),
                    systemImage: "book"
                )
            } else {
                RecentBooksRail(
                    books: books,
                    colorScheme: colorScheme,
                    onOpenBook: onOpenBook,
                    onSearch: onSearch
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A section head of the workbench: title in bold serif, 清除 on the same
/// baseline at the trailing end, in the secondary color so it reads as a
/// quiet utility rather than a competing action.
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
                .font(DSFont.footnote)
                .foregroundStyle(DSColor.textSecondary)
                .contentShape(Rectangle().inset(by: -DSSpacing.sm))
                .accessibilityLabel(clearAccessibilityLabel)
        }
    }
}

/// 空区块的轻量占位：图标加一行说明，让空态保持结构感而不是一片留白。
private struct EmptyRecentsHint: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: systemImage)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .fill(DSColor.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .stroke(DSColor.border.opacity(0.6), lineWidth: 1)
        )
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

/// The 最近搜索 tags wrapped into however many lines fit the width, using a
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
            .padding(.vertical, DSSpacing.xs)
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
                    .shadow(
                        color: DSColor.searchListCoverShadow,
                        radius: DSLayout.searchListCoverShadowRadius,
                        y: DSLayout.searchListCoverShadowY
                    )
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

#Preview("最近搜索与最近阅读工作台") {
    ScrollView {
        SearchRecentsWorkbench(
            queries: ["红楼梦", "三体", "斗罗大陆", "凡人修仙传"],
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
