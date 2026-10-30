import SwiftUI

/// 「設置自動閱讀 ∧」 — the running state, and the way to its controls.
///
/// Its own layer at the bottom of the screen, deliberately *not* a field in the
/// footer bar. It was one at first, which was wrong twice over: migration fills
/// unknown field kinds with `.hidden`, so it never appeared on any device that
/// already had a stored layout, and being a field meant someone could hide the
/// only way out of the mode. The bottom of the screen is just a position — it
/// shows whether or not the footer is on, and overlaps whatever is under it.
///
/// Tapping it opens `AutoReadControlPanel`; a tap on the page collapses that back
/// to this. Neither pauses the mode — see `ReaderView.autoReadIsCoveredBySurface`.
///
/// It wears the shared 界面效果 surface, like every other floating control in the
/// reader: on iOS 26 that is the same Liquid Glass the bottom bar under it is made
/// of, and it follows 毛玻璃／透明度／光暈 rather than a material of its own. It used
/// to hand-paint a dark `.ultraThinMaterial` — a second surface implementation
/// that on iOS 26 rendered as the legacy blur, so the pill read as a dark slab
/// floating over a glass toolbar.
struct AutoReadPill: View {
    let secondsPerPage: Double
    let fill: Color
    let tint: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DSSpacing.xs) {
                Text(localized("设置自动阅读"))
                Image(systemName: "chevron.up")
                    .font(DSFont.caption)
                    .accessibilityHidden(true)
            }
            .font(DSFont.footnote)
            .foregroundStyle(tint)
            .padding(.horizontal, DSSpacing.lg)
            .frame(minHeight: DSLayout.minimumTapTarget)
            // The hairline that used to sit here defined the edge of a flat fill;
            // glass draws its own, and 光暈 comes with the surface.
            .floatingSurface(in: Capsule(), fill: fill)
            // Kept: `floatingSurface` layers on top of the caller's shadow rather
            // than replacing it, so the pill still has depth at 光暈 0.
            .shadow(color: DSColor.coverHeroShadow, radius: 10, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("设置自动阅读"))
        .accessibilityValue(AutoReadController.secondsText(secondsPerPage))
    }
}

/// The auto-read controls, drawn over the reading page rather than in a sheet.
///
/// The reader has already collapsed all the chrome to get here — a modal would
/// put a system surface straight back over the page they are watching turn. This
/// sits above the footer instead, on the same 界面效果 surface as the bottom bar it
/// replaces — same shape, same radius, same glass — so entering the mode swaps one
/// bottom surface for another instead of introducing a third material.
///
/// No play/pause: auto-read is a mode. It collapses back to the pill on a tap
/// anywhere on the page — legado's `AutoReadDialog` dismisses on an outside tap
/// the same way — and 退出自動閱讀 is what ends the mode itself.
struct AutoReadControlPanel: View {
    @ObservedObject var autoReader: AutoReadController
    let fill: Color
    let tint: Color
    let accent: Color
    let onOpenTOC: () -> Void
    let onOpenReadingMenu: () -> Void
    let onOpenSettings: () -> Void
    let onCollapse: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            collapseHandle
            speedRow
            Divider()
                .overlay(tint.opacity(0.18))
            actionRow
        }
        .padding(DSSpacing.md)
        // The 現代 bottom bar's own shape and radius (`ReaderModernBottomControlBar`),
        // because this stands in that bar's place while the mode runs.
        .floatingSurface(
            in: RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous),
            fill: fill
        )
        .shadow(color: DSColor.coverHeroShadow, radius: 18, y: 8)
        .padding(.horizontal, DSSpa