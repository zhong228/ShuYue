import SwiftUI

// MARK: - Auto-scroll button (webtoon layout)
//
// Starts and pauses auto-scroll. Shown only when switched on in the reader's settings,
// in the bottom corner chosen there, and dimmed while the page scrolls under it — the
// way Aidoku offers its own.

enum FixedPageAutoScrollButtonPosition: String, CaseIterable {
    case left
    case right
}

struct FixedPageAutoScrollButton: View {
    let isAutoScrolling: Bool
    /// The page is moving under the button: a finger, a glide, or auto-scroll itself.
    let isContentScrolling: Bool
    let position: FixedPageAutoScrollButtonPosition
    let action: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                if position == .right { Spacer() }
                Button(action: action) {
                    Image(systemName: isAutoScrolling ? "pause.fill" : "play.fill")
                        .font(DSFont.bodyBold)
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                        .accessibilityHidden(true)
                }
                .buttonStyle(DimmedWhileScrollingButtonStyle(isDimmed: isContentScrolling))
                .accessibilityLabel(isAutoScrolling ? localized("暫停自動捲動") : localized("開始自動捲動"))
                if position == .left { Spacer() }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.lg)
        }
    }
}

/// On a material circle; dimmed while the page scrolls, back to full strength the
/// moment it is pressed.
private struct DimmedWhileScrollingButtonStyle: ButtonStyle {
    let isDimmed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial, in: Circle())
            .opacity(isDimmed && !configuration.isPressed ? DSLayout.readerFloatingControlScrollingOpacity : 1)
            .animation(DSAnimation.fast, value: isDimmed)
    }
}

#Preview("Auto-scroll button") {
    ZStack {
        Color.black.ignoresSafeArea()
        FixedPageAutoScrollButton(isAutoScrolling: false, isContentScrolling: false, position: .right) {}
        FixedPageAutoScrollButton(isAutoScrolling: true, isContentScrolling: true, position: .left) {}
    }
}
