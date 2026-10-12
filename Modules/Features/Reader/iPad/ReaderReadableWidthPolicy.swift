import CoreGraphics

/// Apply readable width to each laid-out page, also in scroll mode and resized windows.
/// User margins remain additional space and are never overwritten in preferences.
enum ReaderReadableWidthPolicy {
    static func extraInset(pageWidth: CGFloat, usesReadableWidth: Bool) -> CGFloat {
        guard usesReadableWidth else { return 0 }
        let regularInset = min(DSLayout.readerRegularExtraHorizontalInset,
                               max(0, (pageWidth - DSLayout.readableNarrowWidth) / 2))
        return max(regularInset, (pageWidth - DSLayout.readableCompactWidth) / 2)
    }
}
