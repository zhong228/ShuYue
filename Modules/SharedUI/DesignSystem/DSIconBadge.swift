import SwiftUI

// MARK: - 书悦 Brand Icon Badge

/// The tinted rounded square an SF Symbol or glyph sits in on 书悦's brand rows —
/// the iOS 18 settings look of a filled icon tile instead of a bare symbol. Every
/// 設定 / 探索 / RSS row shares this one component, so the whole app reads as one
/// family and nothing echoes 閱讀's flat grey icons.
struct DSIconBadge: View {
    let systemImage: String
    let gradient: [Color]
    var side: CGFloat = 30
    var iconSize: CGFloat = 16

    @ScaledMetric(relativeTo: .body) private var iconScale: CGFloat = 1

    var body: some View {
        Image(systemName: systemImage)
            .font(DSFont.fixed(size: iconSize * iconScale, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side * iconScale, height: side * iconScale)
            .background {
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Stable gradient assignment

/// Gives a stable 书悦 gradient for a given identifier (a row's symbol name, a
/// source's name, a folder's name…) so the same row always wears the same colour
/// without callers having to pick one. The palette is the book-cover gradient set,
/// so the chrome shares its colour story with the shelf.
enum DSBrandGradient {
    /// The palette rows draw from. Indexed by a name's stable hash — the first
    /// characters of SF Symbol names differ, so `hash` alone would cluster rows.
    private static let palette = DSColor.coverGradients

    static func tint(for identifier: String) -> [Color] {
        guard !palette.isEmpty else { return [DSColor.accent] }
        // Sum the scalars: stable across launches and OS versions, unlike `hashValue`.
        let sum = identifier.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let index = sum % palette.count
        return palette[index]
    }
}

#Preview("Badges") {
    HStack(spacing: 12) {
        DSIconBadge(systemImage: "books.vertical.fill",
                    gradient: DSBrandGradient.tint(for: "books.vertical.fill"))
        DSIconBadge(systemImage: "waveform",
                    gradient: DSBrandGradient.tint(for: "waveform"))
        DSIconBadge(systemImage: "sparkles",
                    gradient: DSBrandGradient.tint(for: "sparkles"))
    }
    .padding()
    .background(DSColor.groupedBackground)
}