import Foundation

/// Resolves presentation from the active mode's position owner. Scroll commits
/// deliberately leave the paged engine's current page unchanged.
@MainActor
enum ReaderDisplayedPosition {
    static func resolve(
        engine: any PagedReaderEngine,
        currentPage: Int,
        isScrolling: Bool,
        sessionLocation: ReaderLocation?
    ) -> CoreTextReadingPosition {
        if isScrolling, let sessionLocation {
            return sessionLocation.coreTextPosition
        }
        let page = max(0, min(currentPage, engine.totalPages - 1))
        let position = engine.charOffset(forPage: page)
        return CoreTextReadingPosition(spineIndex: position.spineIndex, charOffset: position.charOffset)
    }

    /// Reader positions use UTF-16 offsets; snippets must preserve complete
    /// graphemes even when a stored offset lands inside a composed character.
    static func excerpt(in text: String, charOffset: Int, maxLength: Int = 30) -> String {
        let source = text as NSString
        guard charOffset >= 0, charOffset < source.length else { return "" }
        let start = source.rangeOfComposedCharacterSequence(at: charOffset).location
        return String(source.substring(from: start).prefix(maxLength))
    }
}
