import SwiftUI

/// A card of chips under a title, in equal columns as many to a row as fit — 發現頁設定's
/// cards, and the category picker of a custom explore page.
struct DiscoverChipCard<Content: View>: View {
    let title: String
    let minimumChipWidth: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(title)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            DiscoverChipGridLayout(minimumColumnWidth: minimumChipWidth, spacing: DSSpacing.sm) {
                content()
            }
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interfaceCardSurface(in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
    }
}

/// Where each chip of a `DiscoverChipCard` goes: equal columns, as many to a row as fit,
/// each chip's name on one line — a chip whose name does not fit one column takes two, or
/// as many as it needs up to the whole row, rather than wrapping. The chips keep their
/// order, so one too wide for what is left of a row starts the next.
struct DiscoverChipGrid {
    struct Slot: Equatable {
        let row: Int
        let column: Int
        let span: Int
    }

    let columns: Int
    let columnWidth: CGFloat
    let spacing: CGFloat

    /// As many columns as fit `width` at `minimumColumnWidth`, as an adaptive `GridItem`
    /// makes them.
    init(width: CGFloat, minimumColumnWidth: CGFloat, spacing: CGFloat) {
        columns = max(1, Int((width + spacing) / (minimumColumnWidth + spacing)))
        columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        self.spacing = spacing
    }

    /// Each chip's slot, from its width with its name on one line.
    func slots(oneLineWidths: [CGFloat]) -> [Slot] {
        var slots: [Slot] = []
        slots.reserveCapacity(oneLineWidths.count)
        var row = 0
        var column = 0
        for width in oneLineWidths {
            let needed = ((width + spacing) / (columnWidth + spacing)).rounded(.up)
            let span = Int(min(CGFloat(columns), max(1, needed)))
            if column + span > columns {
                row += 1
                column = 0
            }
            slots.append(Slot(row: row, column: column, span: span))
            column += span
        }
        return slots
    }

    func x(of slot: Slot) -> CGFloat {
        CGFloat(slot.column) * (columnWidth + spacing)
    }

    func width(of slot: Slot) -> CGFloat {
        columnWidth * CGFloat(slot.span) + spacing * CGFloat(slot.span - 1)
    }
}

/// Lays chips out in a `DiscoverChipGrid`, each centred on the tallest in its row.
private struct DiscoverChipGridLayout: Layout {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat

    /// Each chip's width with its name on one line.
    func makeCache(subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(.unspecified).width }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGFloat]) -> CGSize {
        let width = proposal.width ?? cache.reduce(spacing * CGFloat(max(cache.count - 1, 0)), +)
        let frames = frames(width: width, subviews: subviews, oneLineWidths: cache)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGFloat]) {
        let frames = frames(width: bounds.width, subviews: subviews, oneLineWidths: cache)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews, oneLineWidths: [CGFloat]) -> [CGRect] {
        let grid = DiscoverChipGrid(width: width, minimumColumnWidth: minimumColumnWidth, spacing: spacing)
        let slots = grid.slots(oneLineWidths: oneLineWidths)
        let heights = zip(subviews, slots).map { subview, slot in
            subview.sizeThatFits(ProposedViewSize(width: grid.width(of: slot), height: nil)).height
        }
        // Rows come in order, each slot in the row it opened or in the one before.
        var rowHeights: [CGFloat] = []
        for (slot, height) in zip(slots, heights) {
            if slot.row == rowHeights.count {
                rowHeights.append(height)
            } else {
                rowHeights[slot.row] = max(rowHeights[slot.row], height)
            }
        }
        var rowTops: [CGFloat] = []
        var top: CGFloat = 0
        for height in rowHeights {
            rowTops.append(top)
            top += height + spacing
        }
        return zip(slots, heights).map { slot, height in
            CGRect(
                x: grid.x(of: slot),
                y: rowTops[slot.row] + (rowHeights[slot.row] - height) / 2,
                width: grid.width(of: slot),
                height: height
            )
        }
    }
}
