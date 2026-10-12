import Combine
import XCTest
@testable import yuedu_app

@MainActor
final class ReaderSettingsPublicationTests: XCTestCase {
    func testChangedThemeAppliesOnceAndIdenticalThemeDoesNotRepublish() throws {
        let original = ReaderPreferences.current()
        defer { original.apply() }
        original.apply()
        let theme = try XCTUnwrap(ReaderTheme.allCases.first { $0.rawValue != original.theme })
        var next = original
        next.theme = theme.rawValue
        var themes: [ReaderTheme] = []
        let token = ReaderConfig.shared.$theme.dropFirst().sink { themes.append($0) }
        next.apply()
        next.apply()
        XCTAssertEqual(ReaderTheme.loadPersisted(), theme)
        XCTAssertEqual(ReaderConfig.shared.theme, theme)
        XCTAssertEqual(themes, [theme])
        withExtendedLifetime(token) {}
    }

    func testIdenticalPreferencesAndConfigPublishNothing() {
        let settings = GlobalSettings.shared
        let preferences = ReaderPreferences.current()
        preferences.apply()
        var settingsPublications = 0, configPublications = 0
        let settingsToken = settings.objectWillChange.sink { settingsPublications += 1 }
        let configToken = ReaderConfig.shared.objectWillChange.sink { configPublications += 1 }
        preferences.apply()
        ReaderConfig.shared.syncFromGlobalSettings()
        XCTAssertEqual(settingsPublications, 0)
        XCTAssertEqual(configPublications, 0)
        withExtendedLifetime((settingsToken, configToken)) {}
    }

    func testRemoteChangeSupersedesPendingLocalWritebackWithoutEcho() {
        let settings = GlobalSettings.shared
        let original = ReaderPreferences.current()
        defer { original.apply() }
        original.apply()
        // This edit has already entered the existing slider debounce when sync arrives.
        ReaderConfig.shared.fontSize = CGFloat(original.readerFontSize + 1)
        var remote = original
        remote.readerFontSize += 2
        remote.readerHeaderTopPadding = (original.readerHeaderTopPadding ?? 0) + 5
        var fontValues: [Double] = []
        let token = settings.$readerFontSize.dropFirst().sink { fontValues.append($0) }
        remote.apply()
        XCTAssertEqual(fontValues, [remote.readerFontSize])
        XCTAssertEqual(ReaderConfig.shared.fontSize, CGFloat(remote.readerFontSize))
        XCTAssertEqual(settings.readerHeaderTopPadding, remote.readerHeaderTopPadding)
        let noEcho = expectation(description: "remote sync must not echo after the slider debounce")
        noEcho.isInverted = true
        let echoToken = settings.objectWillChange.sink { noEcho.fulfill() }
        // An inverted expectation observes a known 120 ms debounce, not app readiness.
        wait(for: [noEcho], timeout: 0.3)
        XCTAssertEqual(fontValues, [remote.readerFontSize])
        withExtendedLifetime((token, echoToken)) {}
    }

    func testUserEditStillWritesBackAfterRemoteSync() {
        let settings = GlobalSettings.shared
        let original = ReaderPreferences.current()
        defer { original.apply() }
        original.apply()
        let expected = original.readerFontSize + 1
        let written = expectation(description: "local font edit persists")
        let token = settings.$readerFontSize.dropFirst().filter { $0 == expected }
            .sink { _ in written.fulfill() }
        ReaderConfig.shared.fontSize = CGFloat(expected)
        wait(for: [written], timeout: 2)
        XCTAssertEqual(settings.readerFontSize, expected)
        withExtendedLifetime(token) {}
    }

    func testBubbleDeletionRepairsSelectionAndPreservesSyncClock() {
        let settings = GlobalSettings.shared
        let styles = settings.commentBubbleCustomStyles
        let selected = settings.commentBubbleSelectedCustomStyleID
        let mode = settings.commentBubblePresetMode
        let clock = settings.commentBubbleSelectionSyncClock
        defer {
            settings.applyCommentBubbleSync(styles: styles)
            settings.applyCommentBubbleSync(selection: selected)
            settings.commentBubblePresetMode = mode
        }
        let style = ReaderCommentBubbleCustomStyle(name: "Publication test", svg: "<svg/>")
        settings.applyCommentBubbleSync(styles: styles + [style])
        settings.applyCommentBubbleSync(selection: style.id)
        var publications = 0
        let token = settings.objectWillChange.sink { publications += 1 }
        settings.applyCommentBubbleSync(selection: style.id)
        XCTAssertEqual(publications, 0)
        settings.applyCommentBubbleSync(styles: styles)
        XCTAssertNil(settings.commentBubbleSelectedCustomStyleID)
        XCTAssertEqual(settings.commentBubblePresetMode, .builtin)
        XCTAssertEqual(settings.commentBubbleSelectionSyncClock, clock)
        withExtendedLifetime(token) {}
    }
}
