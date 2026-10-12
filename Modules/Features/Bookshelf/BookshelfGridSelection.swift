import SwiftUI

// MARK: - Grid selection style

/// How a shelf-grid cover shows where it stands while 選取 is on, after Apple Books'
/// library in edit mode: a cover left out of the selection dims to
/// `DSLayout.bookshelfUnselectedCoverOpacity` under an empty ring; a selected one stays
/// at full strength, lifts, and carries a check.
enum BookshelfGridSelectionStyle {
    /// Where a selected cover grows from: two thirds of the way down, so most of the
    /// growth goes up into the gap above the cover and only a little toward its title.
    static let liftAnchor = UnitPoint(x: 0.5, y: 2.0 / 3.0)

    /// How much a selected cover grows in a grid of `coverSize` covers with
    /// `columnSpacing` between the columns.
    ///
    /// Apple Books grows a selected cover by about 11%, into the wide gutters of its
    /// two-column grid. This grid's gaps are fixed in points and much narrower, so the
    /// growth is held in points instead of as a ratio: `bookshelfSelectedCoverHeightGrowth`
    /// in height, and across the width no more than the column gap less `DSSpacing.xs`,
    /// so two selected neighbours still keep a gap. A fixed ratio that looks right on a
    /// phone's three columns runs into the title under the cover on an iPad's two.
    static func liftScale(coverSize: CGSize, columnSpacing: CGFloat) -> CGFloat {
        guard coverSize.width > 0, coverSize.height > 0 else { return 1 }
        let widthGrowth = max(columnSpacing - DSSpacing.xs, 0)
        let growth = min(
            widthGrowth / coverSize.width,
            DSLayout.bookshelfSelectedCoverHeightGrowth / coverSize.height
        )
        return min(1 + growth, DSLayout.bookshelfSelectedCoverMaximumScale)
    }
}

// MARK: - Selection mark

/// The circle in a grid cover's corner while 選取 is on, drawn as Apple Books draws it:
/// an empty white ring, or a black disc with a white ring and check once selected.
///
/// Decorative: the cell tells VoiceOver the same thing through its `.isSelected` trait.
struct BookshelfSelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(DSColor.coverSelectionMarkFill)
                Image(systemName: "checkmark")
                    .font(DSFont.fixed(size: DSLayout.bookshelfSelectionCheckmarkSize, weight: .bold))
                    .foregroundStyle(DSColor.coverSelectionMarkForeground)
            }
            Circle()
                .strokeBorder(
                    DSColor.coverSelectionMarkForeground,
                    lineWidth: DSLayout.bookshelfSelectionMarkLineWidth
                )
        }
        .frame(width: DSLayout.bookshelfSelectionMarkSize, height: DSLayout.bookshelfSelectionMarkSize)
        // One halo around the whole mark, not one per layer inside it.
        .compositingGroup()
        .shadow(color: DSColor.coverSelectionMarkShadow, radius: DSLayout.bookshelfSelectionMarkShadowRadius)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("選取標記") {
    // A white cover, where the ring leans on its halo, then the generated-cover colours.
    let covers = [DSColor.background] + DSColor.coverGradients.map { $0[0] }
    HStack(spacing: DSSpacing.sm) {
        ForEach(covers.indices, id: \.self) { index in
            VStack(spacing: DSSpacing.sm) {
                BookshelfSelectionMark(isSelected: false)
                BookshelfSelectionMark(isSelected: true)
            }
            .padding(DSSpacing.md)
            .background(covers[index])
        }
    }
    .padding()
    .background(DSColor.groupedBackground)
}
#endif
