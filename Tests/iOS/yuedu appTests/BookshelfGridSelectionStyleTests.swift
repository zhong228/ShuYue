import CoreGraphics
import SwiftUI
import Testing
@testable import yuedu_app

@Suite("Bookshelf Grid Selection Style")
struct BookshelfGridSelectionStyleTests {
    /// One shelf grid, laid out the way `HomeView` lays it out.
    struct Grid: Sendable, CustomTestStringConvertible {
        let containerWidth: CGFloat
        let columns: Int
        let isRegularWidth: Bool

        /// `HomeView.gridColumnSpacing`.
        var columnSpacing: CGFloat { columns >= 5 ? DSSpacing.sm : DSSpacing.md }
        /// `HomeView.gridHorizontalInset`.
        var horizontalInset: CGFloat {
            isRegularWidth ? 32 : (columns >= 5 ? DSSpacing.lg : 20)
        }
        /// `HomeView.gridCoverDisplaySize`.
        var coverSize: CGSize {
            let available = containerWidth - horizontalInset * 2 - columnSpacing * CGFloat(columns - 1)
            let width = available / CGFloat(columns)
            return CGSize(width: width, height: width * 3 / 2)
        }
        var liftScale: CGFloat {
            BookshelfGridSelectionStyle.liftScale(coverSize: coverSize, columnSpacing: columnSpacing)
        }
        var testDescription: String {
            "\(Int(containerWidth))pt \(isRegularWidth ? "regular" : "compact"), \(columns) columns"
        }
    }

    /// Every column count, on phones and on an iPad up to the shelf's readable width.
    static let grids: [Grid] = {
        let phoneWidths: [CGFloat] = [375, 402, 440]
        let iPadWidths: [CGFloat] = [700, DSLayout.readableShelfWidth]
        let columnCounts = GlobalSettings.bookshelfGridColumnCountOptions
        let phones = phoneWidths.flatMap { width in
            columnCounts.map { Grid(containerWidth: width, columns: $0, isRegularWidth: false) }
        }
        let iPads = iPadWidths.flatMap { width in
            columnCounts.map { Grid(containerWidth: width, columns: $0, isRegularWidth: true) }
        }
        return phones + iPads
    }()

    @Test("no lift before the grid has measured its covers")
    func noLiftBeforeLayout() {
        #expect(BookshelfGridSelectionStyle.liftScale(coverSize: .zero, columnSpacing: DSSpacing.md) == 1)
    }

    @Test("a selected cover visibly lifts on a phone's default three columns")
    func defaultPhoneGridLifts() {
        let grid = Grid(
            containerWidth: 402,
            columns: GlobalSettings.defaultBookshelfGridColumnCount,
            isRegularWidth: false
        )
        #expect(grid.liftScale > 1.05)
    }

    @Test("a selected cover lifts, but never into its title or a selected neighbour", arguments: grids)
    func liftStaysInsideTheGaps(grid: Grid) {
        let scale = grid.liftScale
        #expect(scale > 1)
        #expect(scale <= DSLayout.bookshelfSelectedCoverMaximumScale)

        let anchor = BookshelfGridSelectionStyle.liftAnchor
        let heightGrowth = (scale - 1) * grid.coverSize.height
        // Down toward the title under the cover.
        #expect(heightGrowth * (1 - anchor.y) < DSLayout.bookshelfGridCoverTitleSpacing)
        // Up: the least room above any cover is the grid's own top inset.
        #expect(heightGrowth * anchor.y <= DSSpacing.md + 0.001)
        // Across: two selected neighbours each take their half of the column gap.
        let widthGrowth = (scale - 1) * grid.coverSize.width
        #expect(grid.columnSpacing - widthGrowth >= DSSpacing.xs - 0.001)
    }
}
