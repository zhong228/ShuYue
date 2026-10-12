import SwiftUI

/// The app's own home-screen icon shown inside the app: the light or dark variant with the
/// appearance (`MoYueAppIcon` carries both), clipped to the icon mask. Decorative —
/// whatever it heads names the app in words.
struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        let mask = RoundedRectangle(cornerRadius: size * DSLayout.appIconCornerRatio, style: .continuous)
        Image("MoYueAppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(mask)
            // Holds the edge where the icon's own background meets a page of the same tone.
            .overlay(mask.strokeBorder(DSColor.separator, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

#Preview("App icon") {
    HStack(spacing: DSSpacing.xl) {
        AppIconImage(size: DSLayout.settingsRowIconSize)
        AppIconImage(size: DSLayout.paywallAppIconSize)
    }
    .padding()
}
