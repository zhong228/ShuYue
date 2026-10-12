import SwiftUI

/// An icon and a title side by side on a toolbar button, at a fixed width.
///
/// Use this, not a `Label` with `.labelStyle(.titleAndIcon)`: in the iOS 26 bottom bar
/// such a label got a glass capsule sized for its icon alone, and the title either went
/// missing or spilled out of the capsule (seen on device); iOS 27 clipped a long title at
/// the capsule's edge. A fixed width gives the capsule one size in every language, and a
/// title too long for it ends in "…", as Apple Books' "Add to…" does.
///
/// The icon is hidden from VoiceOver: give the button the title as its label.
struct ToolbarTitleAndIconLabel: View {
    let title: String
    let systemImage: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: width)
    }
}

#if DEBUG
#Preview("底部工具列：圖示＋文字") {
    NavigationStack {
        DSColor.background
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {} label: { Image(systemName: "trash") }
                        .accessibilityLabel(localized("刪除"))
                    Spacer()
                    // Short enough to fit, then too long for the width.
                    Button {} label: {
                        ToolbarTitleAndIconLabel(
                            title: localized("加入分組"),
                            systemImage: "text.badge.plus",
                            width: DSLayout.bookshelfAddToGroupLabelWidth
                        )
                    }
                    .accessibilityLabel(localized("加入分組"))
                    Button {} label: {
                        ToolbarTitleAndIconLabel(
                            title: "グループに追加",
                            systemImage: "text.badge.plus",
                            width: DSLayout.bookshelfAddToGroupLabelWidth
                        )
                    }
                    .accessibilityLabel("グループに追加")
                }
            }
    }
}
#endif
