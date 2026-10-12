import SwiftUI

// MARK: - Design System: Shared Components

/// Common search bar shared by HomeView and BookSourceListView.
struct DSSearchBar: View {
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DSColor.textSecondary)
            TextField(placeholder, text: $text)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DSColor.textSecondary)
                }
            }
        }
        .padding(10)
        .background(DSColor.textSecondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.md))
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
    }
}

/// Settings navigation row with icon, title, optional detail, and chevron.
/// The icon wears 书悦's coloured badge (`DSIconBadge`) so 設定 and everything it
/// opens read as one brand instead of 閱讀's flat grey symbols.
struct DSSettingsRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    /// Needs Pro the user does not have: the chevron becomes a lock, as on 外觀's 啟動圖
    /// row, and `action` is expected to open the paywall.
    var isLocked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.md) {
                DSIconBadge(systemImage: icon,
                            gradient: DSBrandGradient.tint(for: icon))
                Text(title)
                    .font(DSFont.body)
                    .foregroundColor(DSColor.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: DSSpacing.sm)
                if let detail {
                    Text(detail)
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                        .lineLimit(1)
                }
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(DSFont.caption)
                        .foregroundColor(DSColor.textSecondary)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(DSFont.caption.weight(.semibold))
                        .foregroundColor(DSColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


struct IconConsistentLabelStyle: LabelStyle {
    /// Off for a row whose title carries its own colour — an action or a destructive
    /// row — so its symbol matches the title instead of turning accent-coloured.
    var themesIcon = true

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            themedIcon(configuration.icon)
            configuration.title
        }
    }

    /// A row's symbol wears the tint — 強調色 — in every theme, 默認 included, as the
    /// symbol leading a list row does on iOS (user's call, 2026-09-29). `.tint` resolves
    /// from the environment when the symbol draws, so a theme switch or a 強調色 edit
    /// reaches rows SwiftUI does not rebuild. Deciding here from
    /// `AppearanceThemePreset.activeAppThemes`, a global SwiftUI cannot observe, left
    /// those rows in the colour they were first drawn in — black beside red ones.
    @ViewBuilder
    private func themedIcon(_ icon: Configuration.Icon) -> some View {
        let sized = icon
            .font(DSFont.fixed(size: 17, weight: .medium))
            .frame(width: 28, height: 28)
        if themesIcon {
            sized.foregroundStyle(.tint)
        } else {
            sized
        }
    }
}

/// Reusable page background: the themed grouped background plus, when the user
/// configured a page background (Pro), the gradient/image layer for the given
/// scope. Use inside `ZStack` or `.background { }` on any surface that should
/// show the page background — tabs, sheets, and standalone views alike.
struct PageBackgroundView: View {
    let scope: AppearancePageBackgroundScope
    @ObservedObject private var gs = GlobalSettings.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            DSColor.groupedBackground
            if subscriptionStore.hasAccess(.readerThemePacks),
               let slice = gs.resolvedPageBackgroundSlice(for: scope, colorScheme: colorScheme) {
                AppearancePageBackgroundLayerView(slice: slice)
            }
        }
    }
}

private struct ThemedAppSurfaceModifier: ViewModifier {
    let scope: AppearancePageBackgroundScope
    @ObservedObject private var gs = GlobalSettings.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @Environment(\.colorScheme) private var colorScheme

    private var slice: AppearancePageBackgroundSlice? {
        guard subscriptionStore.hasAccess(.readerThemePacks) else { return nil }
        return gs.resolvedPageBackgroundSlice(for: scope, colorScheme: colorScheme)
    }

    /// Single structure for every state — branching over `content` would change
    /// the modified view's identity when a page background appears or vanishes,
    /// and SwiftUI rebuilds what changed identity, dropping its `@State` and any
    /// screen it had pushed. Branch inside `.background` instead.
    /// (The two theme-less branches this replaced were already byte-identical.)
    func body(content: Content) -> some View {
        let slice = self.slice
        return content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    DSColor.groupedBackground
                    if let slice {
                        AppearancePageBackgroundLayerView(slice: slice)
                    }
                }
                .ignoresSafeArea()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// Hides the navigation bar's default material background when a page
/// background or app theme is active, so the background shows through the
/// nav-bar region (behind the title and toolbar buttons).
private struct PageBackgroundToolbarModifier: ViewModifier {
    let scope: AppearancePageBackgroundScope
    @ObservedObject private var gs = GlobalSettings.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @Environment(\.colorScheme) private var colorScheme

    private var hasBackground: Bool {
        if subscriptionStore.hasAccess(.readerThemePacks),
           gs.resolvedPageBackgroundSlice(for: scope, colorScheme: colorScheme) != nil {
            return true
        }
        // 默認 with its 背景 as shipped keeps the system's page, and the bar that goes with it.
        guard let theme = AppearanceThemePreset.activeAppThemes.theme(for: colorScheme) else { return false }
        return !theme.keepsSystemBackgrounds
    }

    /// Always the same modifier, only its visibility changes (`.automatic` is
    /// the default bar background, i.e. what "not applied" looked like). An
    /// `if/else` here re-identified the whole screen whenever the theme moved
    /// between 默認 and a real theme: 外觀主題 uses this modifier, so switching
    /// themes from it reset its own `@State` and popped it back to 設定.
    func body(content: Content) -> some View {
        content.toolbarBackground(hasBackground ? .hidden : .automatic, for: .navigationBar)
    }
}

extension View {
    /// Retints a scrollable `Form`/`List` to the active app theme and paints
    /// the page background layer for `scope`. The background is painted
    /// directly behind the `Form`/`List` (with `ignoresSafeArea` so it extends
    /// behind the navigation bar), and the navigation bar's default material is
    /// hidden so the background shows through the nav-bar region. A no-op when
    /// no theme is active and no page background is configured. Apply directly
    /// on the `Form`/`List`.
    func themedAppSurface(for scope: AppearancePageBackgroundScope = .global) -> some View {
        modifier(ThemedAppSurfaceModifier(scope: scope))
    }

    /// Hides the navigation bar's default material when a page background or app
    /// theme is active. Use on views that paint their own background via
    /// `PageBackgroundView` (non-`Form`/`List` surfaces like `ScrollView`,
    /// `ZStack`, etc.) so the nav-bar region shows the page background.
    func pageBackgroundToolbar(for scope: AppearancePageBackgroundScope = .global) -> some View {
        modifier(PageBackgroundToolbarModifier(scope: scope))
    }
}

/// Card container with uniform padding, rounded corners, and shadow.
struct DSCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            content
        }
        .padding(DSSpacing.lg)
        .interfaceCardSurface()
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
        .shadow(color: DSColor.shadow, radius: 6, x: 0, y: 4)
    }
}

/// The capsule every chip, filter and quick action in a bar is drawn as. Unselected it
/// sits on the app's floating surface — glass with 外觀主題 › 界面效果 › 毛玻璃 on, its
/// fill without — so it matches the controls floating over the page; selected it is the
/// accent with white text. The label is subheadline at medium weight: a semantic text
/// style, so it scales with Dynamic Type and keeps the system's tracking, with the
/// weight rather than the size setting it apart from body text.
struct DSCapsuleLabel: View {
    let title: String
    /// A symbol before the title.
    var systemImage: String? = nil
    /// A symbol after it — `chevron.down` on a menu, `arrow.up.right` on a link out.
    var trailingSystemImage: String? = nil
    var isSelected = false
    /// Takes the width it is offered, its title centred — a chip in a grid of equal
    /// columns, which gives a long title as many columns as it needs; a title wider than
    /// the whole row takes a second line. Off, the capsule hugs its one line.
    var fillsWidth = false
    /// On a card that is glass itself: a plain gray fill when not selected, since glass
    /// on glass turns muddy.
    var onCard = false
    /// Off, a floating surface (Liquid Glass on iOS 26) paints the capsule. A page's
    /// filter band stacks several of these under one scrolling surface, and glass is
    /// re-sampled against the moving background every frame — enough to drop frames at
    /// the 發現 top band while the rows below it scroll smoothly. That band opts out
    /// (`false`) and paints the solid theme surface instead, the same look the shelf's
    /// `DSGroupSegment` already uses (v1.0.30).
    var usesGlassSurface = true
    /// A value after the title on the same line, in the secondary colour — what an input
    /// holds, or that it is empty. It is cut short before the title is.
    var detail: String? = nil
    /// The narrowest the capsule gets, its title centred: a one-character title would
    /// otherwise make a capsule narrower than it is tall.
    var minWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(fillsWidth ? 2 : 1)
                .multilineTextAlignment(.center)
                .layoutPriority(1)
            if let detail {
                Text(detail)
                    .fontWeight(.regular)
                    .foregroundStyle(isSelected ? DSColor.textOnAccent : DSColor.textSecondary)
                    .lineLimit(1)
            }
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(DSFont.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .font(DSFont.subheadline.weight(.medium))
        .foregroundStyle(isSelected ? DSColor.textOnAccent : DSColor.textPrimary)
        .padding(.horizontal, fillsWidth ? DSSpacing.sm : DSSpacing.md)
        .padding(.vertical, fillsWidth ? DSSpacing.xs : 0)
        .frame(minWidth: minWidth, maxWidth: fillsWidth ? .infinity : nil, minHeight: DSLayout.capsuleControlHeight)
        .background {
            if isSelected {
                Capsule().fill(DSColor.accent)
            } else if onCard {
                Capsule().fill(DSColor.neutralControlFill)
            } else if usesGlassSurface {
                Color.clear.floatingSurfaceBackground(in: Capsule())
            } else {
                Capsule().fill(DSColor.surface)
            }
        }
        .contentShape(Capsule())
    }
}

/// Selectable chip button for filter and sort bars.
struct DSChip: View {
    let title: String
    let isSelected: Bool
    /// See `DSCapsuleLabel.minWidth`.
    var minWidth: CGFloat? = nil
    /// See `DSCapsuleLabel.usesGlassSurface`.
    var usesGlassSurface = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DSCapsuleLabel(title: title, isSelected: isSelected, usesGlassSurface: usesGlassSurface, minWidth: minWidth)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A bookshelf group segment: the selectable navigation segment that switches which
/// shelf page is in view. Taller than `DSChip` and always carrying a glyph, it reads
/// as a segmented control rather than a filter chip — the shelf's top-level navigation,
/// not a toolbar. Selected segments fill with the accent; unselected ones sit on the
/// floating surface like the other controls over the page.
struct DSGroupSegment: View {
    let title: String
    var systemImage: String? = nil
    var isSelected = false
    /// See `DSCapsuleLabel.minWidth`.
    var minWidth: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(DSFont.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .layoutPriority(1)
            }
            .font(DSFont.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? DSColor.textOnAccent : DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.md)
            .frame(minWidth: minWidth, minHeight: DSLayout.capsuleControlHeight)
            .background {
                if isSelected {
                    Capsule().fill(DSColor.accent)
                } else {
                    Capsule().fill(DSColor.surface)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Empty state placeholder view.
struct DSEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    
    var body: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: icon)
                .font(DSFont.fixed(size: 48))
                .foregroundColor(DSColor.textSecondary.opacity(0.5))
            Text(title)
                .font(DSFont.headline)
                .foregroundColor(DSColor.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(DSFont.caption)
                    .foregroundColor(DSColor.textSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSSpacing.xl)
    }
}
