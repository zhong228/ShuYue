import SwiftUI
import UIKit

/// The app's appearance themes as a UIKit trait, bridged into SwiftUI's environment as
/// `EnvironmentValues.appThemes`. `DSColor`'s themed colours resolve from it when they
/// draw, so a theme switch repaints every view — including one SwiftUI does not rebuild.
///
/// They used to capture `AppearanceThemePreset.activeAppThemes` when a view's body ran,
/// and a view whose inputs had not changed (a settings row) kept the old theme's colours
/// after a switch (reproduced 2026-09-29, `ThemeColorReactivityTests`). A trait marked
/// `affectsColorAppearance` makes UIKit and SwiftUI re-resolve dynamic colours when it
/// changes, the way they do for light and dark.
struct AppThemesTrait: UITraitDefinition {
    static let defaultValue = ActiveAppThemes()
    static let affectsColorAppearance = true
    static let name = "AppThemes"

    /// Puts `themes` on every window of the app, for UIKit views outside SwiftUI's
    /// environment — the reader's card transition, the inline video player. SwiftUI's
    /// own views read the environment value `ContentView` sets, which is the same.
    @MainActor
    static func apply(_ themes: ActiveAppThemes) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.traitOverrides[AppThemesTrait.self] = themes
            }
        }
    }
}

private struct AppThemesKey: UITraitBridgedEnvironmentKey {
    static let defaultValue = ActiveAppThemes()

    static func read(from traitCollection: UITraitCollection) -> ActiveAppThemes {
        traitCollection[AppThemesTrait.self]
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: ActiveAppThemes) {
        mutableTraits[AppThemesTrait.self] = value
    }
}

extension EnvironmentValues {
    /// The appearance themes on screen — see `AppThemesTrait`.
    var appThemes: ActiveAppThemes {
        get { self[AppThemesKey.self] }
        set { self[AppThemesKey.self] = newValue }
    }
}
