import SwiftUI

// MARK: - 探索 entries

/// What an 探索 entry shows beside its name.
enum ExploreArtwork: Equatable {
    case symbol(String)
    /// An emoji or a character, drawn as the entry's picture.
    case glyph(String)
}

/// How many tiles share a row of 探索's grid, and what a tile looks like at that width.
/// Two across leaves room for Apple Music's 16:9 card; three or four across, a 16:9 tile
/// is too short to hold a name under its glyph, so the tile squares up.
enum ExploreGridDensity: Int, CaseIterable, Identifiable, Comparable {
    case two = 2
    case three = 3
    case four = 4

    static let `default` = ExploreGridDensity.two

    var id: Int { rawValue }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The density the reader chose, a column narrower as the text grows so a name
    /// still fits its tile. Accessibility sizes don't use the grid at all.
    static func fitting(_ chosen: Int, dynamicTypeSize: DynamicTypeSize) -> ExploreGridDensity {
        let density = ExploreGridDensity(rawValue: chosen) ?? .default
        switch dynamicTypeSize {
        case .xLarge: return min(density, .three)
        case .xxLarge, .xxxLarge: return .two
        default: return density
        }
    }

    var aspectRatio: CGFloat { self == .two ? DSLayout.exploreTileAspectRatio : 1 }

    var titleFont: Font {
        switch self {
        case .two: DSFont.headline
        case .three: DSFont.subheadline.weight(.semibold)
        case .four: DSFont.footnote.weight(.semibold)
        }
    }

    /// The glyph at the default text size; the tile scales it with Dynamic Type.
    var artworkSize: CGFloat {
        switch self {
        case .two: DSLayout.exploreTileArtworkSize
        case .three: DSLayout.exploreTileCompactArtworkSize
        case .four: DSLayout.exploreTileSmallArtworkSize
        }
    }

    var padding: CGFloat { self == .four ? DSSpacing.sm : DSSpacing.md }
}

/// One 探索 entry in the page's layout: a tile in the grid, or a card of its own in the
/// list. Both sit on the app's card surface, so they are white like every other card
/// and turn to glass with 分組卡片.
struct ExploreEntryLabel: View {
    enum Layout: Equatable {
        case grid(ExploreGridDensity)
        case list
    }

    let title: String
    let artwork: ExploreArtwork
    let layout: Layout

    init(title: String, artwork: ExploreArtwork, layout: Layout) {
        self.title = title
        self.artwork = artwork
        self.layout = layout
    }

    /// An entry for a name a source or the reader gave. A Legado source name often leads
    /// with an emoji (「📚书山聚合」); that emoji becomes the picture and the rest the name.
    /// Otherwise the name's first character is the picture.
    init(name: String, layout: Layout) {
        let parts = Self.splitLeadingEmoji(name)
        self.init(
            title: parts.title,
            artwork: .glyph(parts.emoji ?? String(parts.title.prefix(1))),
            layout: layout
        )
    }

    /// A source's entry.
    init(source: BookSource, layout: Layout) {
        self.init(name: source.bookSourceName, layout: layout)
    }

    var body: some View {
        switch layout {
        case .grid(let density):
            ExploreTile(title: title, artwork: artwork, density: density)
        case .list:
            ExploreRow(title: title, artwork: artwork)
        }
    }

    static func splitLeadingEmoji(_ name: String) -> (emoji: String?, title: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, isEmoji(first) else { return (nil, trimmed) }
        let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? (nil, trimmed) : (String(first), rest)
    }

    /// Emoji presentation by default, or text-default made emoji by its variation
    /// selector (「☀️」). A bare digit or `#` is an emoji only as a keycap.
    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation || scalars.contains("\u{FE0F}")
    }
}

private var exploreEntryShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
}

// MARK: - Grid tile

/// A tile in 探索's grid — 书悦's coloured story card, not 閱讀's white box: the
/// glyph floats on a stable brand gradient and the name reads white beneath it.
/// The gradient is assigned from the title, so the same entry always wears the same
/// colour while neighbours stay distinct.
private struct ExploreTile: View {
    let title: String
    let artwork: ExploreArtwork
    let density: ExploreGridDensity

    /// Each density's glyph size, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var artworkScale: CGFloat = 1

    private var gradient: [Color] { DSBrandGradient.tint(for: title) }

    var body: some View {
        Color.clear
            .aspectRatio(density.aspectRatio, contentMode: .fit)
            .overlay {
                VStack(spacing: density == .two ? DSSpacing.sm : DSSpacing.xs) {
                    Spacer(minLength: 0)
                    ExploreArtworkView(artwork: artwork, size: density.artworkSize * artworkScale)
                    Text(title)
                        .font(density.titleFont)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                        .padding(.horizontal, density.padding)
                    Spacer(minLength: 0)
                }
                .padding(density.padding)
            }
            .background {
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(exploreEntryShape)
            .contentShape(exploreEntryShape)
            .contentShape(.contextMenuPreview, exploreEntryShape)
    }
}

// MARK: - List card

/// An 探索 entry in the list layout: a long card of its own — glyph badge, name,
/// chevron — apart from its neighbours rather than a row of a grouped list. The
/// badge keeps the tile's gradient so grid and list read as one family.
private struct ExploreRow: View {
    let title: String
    let artwork: ExploreArtwork

    @ScaledMetric(relativeTo: .title2) private var artworkSide = DSLayout.exploreRowArtworkSide
    @ScaledMetric(relativeTo: .title2) private var artworkSize = DSLayout.exploreRowArtworkSize

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            ExploreArtworkBadge(artwork: artwork, size: artworkSize)
                .frame(width: artworkSide, height: artworkSide)
            Text(title)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(DSColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .interfaceCardSurface(in: exploreEntryShape)
        .contentShape(exploreEntryShape)
        .contentShape(.contextMenuPreview, exploreEntryShape)
    }
}

// MARK: - Artwork

/// The entry's picture on a coloured tile — white symbol / raw emoji, both legible
/// on the gradient. A source's emoji keeps its own colours; the first character
/// standing in for one is white on the tile, so the page's colour comes from the
/// gradient behind it.
private struct ExploreArtworkView: View {
    let artwork: ExploreArtwork
    let size: CGFloat

    var body: some View {
        switch artwork {
        case .symbol(let name):
            Image(systemName: name)
                .font(DSFont.fixed(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .accessibilityHidden(true)
        case .glyph(let glyph):
            Text(glyph)
                .font(DSFont.fixed(size: size, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .accessibilityHidden(true)
        }
    }
}

/// The list row's badge: the same coloured square the grid tile's gradient comes
/// from, glyph on top — grid and list feel like one page.
private struct ExploreArtworkBadge: View {
    let artwork: ExploreArtwork
    let size: CGFloat

    @ScaledMetric(relativeTo: .title2) private var badgeSide = DSLayout.exploreRowArtworkSide

    private var gradient: [Color] {
        switch artwork {
        case .symbol(let name): DSBrandGradient.tint(for: name)
        case .glyph(let glyph): DSBrandGradient.tint(for: glyph)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            .fill(
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: badgeSide, height: badgeSide)
            .overlay { ExploreArtworkView(artwork: artwork, size: size) }
            .accessibilityHidden(true)
    }
}

// MARK: - Press feedback

/// An entry answers the finger the moment it lands: it gives a little under it, or under
/// Reduce Motion dims instead of moving.
struct ExploreTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(reduceMotion ? nil : DSAnimation.press, value: configuration.isPressed)
    }
}

#Preview("探索 grid") {
    ScrollView {
        ForEach(ExploreGridDensity.allCases) { density in
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md), count: density.rawValue),
                spacing: DSSpacing.md
            ) {
                ExploreEntryLabel(title: "瀏覽器", artwork: .symbol("globe"), layout: .grid(density))
                ExploreEntryLabel(name: "男頻精選", layout: .grid(density))
                ExploreEntryLabel(title: "书山聚合", artwork: .glyph("📚"), layout: .grid(density))
                ExploreEntryLabel(title: "番茄小说", artwork: .glyph("番"), layout: .grid(density))
            }
            .padding()
        }
    }
    .background(DSColor.groupedBackground)
}

#Preview("探索 list") {
    ScrollView {
        LazyVStack(spacing: DSSpacing.md) {
            ExploreEntryLabel(title: "瀏覽器", artwork: .symbol("globe"), layout: .list)
            ExploreEntryLabel(name: "男頻精選", layout: .list)
            ExploreEntryLabel(title: "书山聚合", artwork: .glyph("📚"), layout: .list)
            ExploreEntryLabel(title: "番茄小说", artwork: .glyph("番"), layout: .list)
        }
        .padding()
    }
    .background(DSColor.groupedBackground)
}
