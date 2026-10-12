import Testing
import SwiftUI
import UIKit
@testable import yuedu_app

@Suite("Appearance theme presets", .serialized)
struct AppearanceThemePresetTests {
    @Test("image reader backgrounds keep the white chrome")
    @MainActor
    func imageReaderBackgroundKeepsWhiteChrome() {
        let settings = GlobalSettings.shared
        let picture = ReaderCustomBackground(
            name: "Picture",
            colorHex: 0x8A7B6C,
            imageFileName: "reader-background-test.jpg",
            isDark: false
        )
        #expect(settings.readerBackgroundPreset(for: picture).bar.rgbHex == UIColor.white.rgbHex)

        var night = picture
        night.isDark = true
        #expect(settings.readerBackgroundPreset(for: night).bar.rgbHex == 0x1A1A1A)
        #expect(settings.readerBackgroundPreset(for: night).isDarkAppearancePalette)
    }

    @Test("free users get classic plus six built-in appearance themes")
    func freeThemeCount() {
        #expect(AppearanceThemePreset.freeSolidPresets.count == 6)
        #expect(AppearanceThemePreset.freeSolidPresets.allSatisfy { !$0.requiresPro })
        #expect(AppearanceThemePreset.classic.isClassic)
        #expect(!AppearanceThemePreset.classic.requiresPro)
        #expect(AppearanceThemePreset.allDefaultPresets.first?.id == AppearanceThemePreset.classicID)
    }

    @Test("classic is the default and the fallback when Pro lapses")
    func classicIsDefault() {
        #expect(GlobalSettings.defaultAppearanceThemeID == AppearanceThemePreset.classicID)
        #expect(AppearanceThemePreset.preset(id: AppearanceThemePreset.classicID)?.isClassic == true)
    }

    @Test("app appearance can pin the current color scheme independently of the system")
    @MainActor
    func appAppearanceCanPinColorScheme() {
        let settings = GlobalSettings.shared
        let savedFollowsSystem = settings.appearanceFollowsSystem
        let savedPinnedScheme = settings.appearancePinnedColorScheme
        defer {
            settings.appearanceFollowsSystem = savedFollowsSystem
            settings.appearancePinnedColorScheme = savedPinnedScheme
        }

        #expect(GlobalSettings.defaultAppearanceFollowsSystem)

        settings.setAppearanceFollowsSystem(false, currentColorScheme: .dark)
        #expect(!settings.appearanceFollowsSystem)
        #expect(settings.appearancePinnedColorScheme == .dark)
        #expect(settings.effectiveAppearanceColorScheme(systemColorScheme: .light) == .dark)

        settings.setAppearanceFollowsSystem(true, currentColorScheme: .light)
        #expect(settings.effectiveAppearanceColorScheme(systemColorScheme: .light) == .light)
        #expect(settings.effectiveAppearanceColorScheme(systemColorScheme: .dark) == .dark)
    }

    @Test("invalid stored appearance schemes fall back to light")
    func invalidStoredAppearanceSchemeFallsBackToLight() {
        #expect(AppearanceColorScheme(storageValue: "unknown") == .light)
        #expect(AppearanceColorScheme(storageValue: nil) == .light)
    }

    @Test("bundled theme packs accept common background image formats")
    func acceptsCommonBackgroundImageFormats() {
        #expect(AppearanceThemePreset.shouldIncludeBundledThemeImage(relativePath: "宮/宮·日.jpg"))
        #expect(AppearanceThemePreset.shouldIncludeBundledThemeImage(relativePath: "主題/example.jpeg"))
        #expect(AppearanceThemePreset.shouldIncludeBundledThemeImage(relativePath: "主題/example.webp"))
        #expect(AppearanceThemePreset.shouldIncludeBundledThemeImage(relativePath: "主題/example.png"))
    }

    @Test("theme scanner skips icon folders and the loose background library")
    func skipsIconFolders() {
        #expect(!AppearanceThemePreset.shouldIncludeBundledThemeImage(relativePath: "芝士就是力量/图标/主页.png"))
        #expect(!AppearanceThemePreset.shouldIncludeBundledThemeImage(relativePath: "Theme/icons/home.png"))
        #expect(!AppearanceThemePreset.shouldIncludeBundledThemeImage(relativePath: "界面背景/example.jpeg"))
    }

    @Test("deleting a selected custom theme falls back to classic")
    @MainActor
    func deleteSelectedCustomThemeFallsBack() {
        let gs = GlobalSettings.shared
        let savedThemes = gs.customAppearanceThemes
        let savedLight = gs.appearanceThemeID
        let savedDark = gs.appearanceDarkThemeID
        defer {
            gs.customAppearanceThemes = savedThemes
            gs.appearanceThemeID = savedLight
            gs.appearanceDarkThemeID = savedDark
        }

        let custom = gs.saveCurrentAppearanceAsTheme(named: "Deleted", basedOn: AppearanceThemePreset.classic)
        gs.appearanceDarkThemeID = custom.id
        #expect(gs.appearanceThemeID == custom.id)

        gs.deleteCustomAppearanceTheme(id: custom.id)
        #expect(!gs.customAppearanceThemes.contains { $0.id == custom.id })
        #expect(gs.appearanceThemeID == GlobalSettings.defaultAppearanceThemeID)
        #expect(gs.appearanceDarkThemeID == GlobalSettings.defaultAppearanceThemeID)
    }

    /// 配色 on a built-in theme (2026-09-29): its colours change and it stays itself —
    /// the same id, name and lock, not a custom copy. An edited 默認 is a palette.
    @Test("editing a built-in theme's colours keeps it built-in")
    @MainActor
    func editsBuiltInThemeColors() throws {
        let gs = GlobalSettings.shared
        let saved = gs.appearanceBuiltInThemeColors
        defer { gs.appearanceBuiltInThemeColors = saved }

        let ocean = try #require(AppearanceThemePreset.freeSolidPresets.first)
        var colors = ocean.customCopy(name: ocean.localizedName)
        colors.accentHex = 0xFF0000
        gs.appearanceBuiltInThemeColors = [ocean.id: colors]
        let edited = try #require(gs.appearancePreset(id: ocean.id, isProActive: true))
        #expect(edited.accent.rgbHex == 0xFF0000)
        #expect(edited.id == ocean.id)
        #expect(!edited.isCustom)
        #expect(edited.localizedName == ocean.localizedName)
        #expect(edited.palette(for: .dark).accent.rgbHex != ocean.palette(for: .dark).accent.rgbHex)

        var classicColors = AppearanceThemePreset.classic.customCopy(name: "默認")
        classicColors.accentHex = 0x00AA00
        gs.appearanceBuiltInThemeColors[AppearanceThemePreset.classicID] = classicColors
        let classic = try #require(gs.appearancePreset(id: AppearanceThemePreset.classicID, isProActive: true))
        #expect(!classic.isClassic)
        #expect(!classic.palette(for: .dark).isClassic)
        #expect(AppearanceThemePreset.classic.isClassic)
    }

    /// 配色 on a built-in theme is Pro, like a theme of the user's own: without Pro the
    /// theme wears the colours it ships with, and the edits come back with Pro.
    @Test("a built-in theme's edited colours need Pro")
    @MainActor
    func builtInColourEditsNeedPro() throws {
        let gs = GlobalSettings.shared
        let savedColors = gs.appearanceBuiltInThemeColors
        let savedLight = gs.appearanceThemeID
        defer {
            gs.appearanceBuiltInThemeColors = savedColors
            gs.appearanceThemeID = savedLight
        }

        let ocean = try #require(AppearanceThemePreset.freeSolidPresets.first)
        var colors = ocean.customCopy(name: ocean.localizedName)
        colors.accentHex = 0xFF0000
        gs.appearanceBuiltInThemeColors = [ocean.id: colors]
        gs.appearanceThemeID = ocean.id

        #expect(gs.appearanceBaseTheme(for: .light, isProActive: true).accent.rgbHex == 0xFF0000)
        let withoutPro = gs.appearanceBaseTheme(for: .light, isProActive: false)
        #expect(withoutPro.id == ocean.id)
        #expect(withoutPro.accent.rgbHex == ocean.accent.rgbHex)
        #expect(gs.builtInThemePreset(ocean, isProActive: false).accent.rgbHex == ocean.accent.rgbHex)
        #expect(gs.appearanceBuiltInThemeColors[ocean.id] != nil)
    }

    /// Until launch has read the entitlement, the Pro look is worn optimistically; after
    /// that, no Pro means no Pro — a theme of the user's own falls back to 默認.
    @Test("the Pro look is optimistic only until the entitlement is read")
    @MainActor
    func proLookIsOptimisticOnlyUntilResolved() throws {
        let gs = GlobalSettings.shared
        let savedThemes = gs.customAppearanceThemes
        let savedLight = gs.appearanceThemeID
        let savedDark = gs.appearanceDarkThemeID
        defer {
            gs.customAppearanceThemes = savedThemes
            gs.appearanceThemeID = savedLight
            gs.appearanceDarkThemeID = savedDark
        }

        let custom = gs.saveCurrentAppearanceAsTheme(named: "Optimistic", basedOn: AppearanceThemePreset.freeSolidPresets[0])
        #expect(gs.appThemeOnScreen(for: .light, isProActive: false, hasResolvedEntitlements: false)?.id == custom.id)
        #expect(gs.appThemeOnScreen(for: .light, isProActive: true, hasResolvedEntitlements: true)?.id == custom.id)
        #expect(gs.appThemeOnScreen(for: .light, isProActive: false, hasResolvedEntitlements: true) == nil)
        gs.deleteCustomAppearanceTheme(id: custom.id)
    }

    /// 重新命名 from a tile's long press.
    @Test("renaming a custom theme trims the name and ignores a blank one")
    @MainActor
    func renamesCustomTheme() {
        let gs = GlobalSettings.shared
        let savedThemes = gs.customAppearanceThemes
        let savedLight = gs.appearanceThemeID
        let savedDark = gs.appearanceDarkThemeID
        defer {
            gs.customAppearanceThemes = savedThemes
            gs.appearanceThemeID = savedLight
            gs.appearanceDarkThemeID = savedDark
        }

        let custom = gs.saveCurrentAppearanceAsTheme(named: "Before", basedOn: AppearanceThemePreset.classic)
        gs.renameCustomAppearanceTheme(id: custom.id, to: "  After  ")
        #expect(gs.customAppearanceThemes.first { $0.id == custom.id }?.name == "After")

        gs.renameCustomAppearanceTheme(id: custom.id, to: "   ")
        #expect(gs.customAppearanceThemes.first { $0.id == custom.id }?.name == "After")
        gs.deleteCustomAppearanceTheme(id: custom.id)
    }
}
