import Foundation
import Testing
@testable import yuedu_app

/// 每本書自己的閱讀設定只存在一個地方。
///
/// 固定頁閱讀器原本只把閱讀方向存在 UserDefaults（`fixedPage.readingMode.<書ID>`），自動裁邊、
/// 雙頁、切分大圖等開關都沒存，每次重開書都回到預設。
@Suite("Book reader settings store", .serialized)
struct BookReaderSettingsStoreTests {

    @Test("a book's fixed-page settings survive reopening the store")
    func fixedPageSettingsSurviveReopening() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("settings.json")
        let bookID = UUID()
        let configuration = FixedPageReaderConfiguration.everyToggleChanged()

        BookReaderSettingsStore(fileURL: fileURL).setFixedPageConfiguration(configuration, for: bookID)

        #expect(BookReaderSettingsStore(fileURL: fileURL).fixedPageConfiguration(for: bookID) == configuration)
    }

    @Test("a book with nothing saved reads the right-to-left defaults")
    func unsavedBookReadsDefaults() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = BookReaderSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))

        #expect(store.fixedPageConfiguration(for: UUID()) == FixedPageReadingMode.rtl.recommendedConfiguration)
    }

    @Test("removing one book's settings is saved and leaves other books alone")
    func removingSettingsIsSaved() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("settings.json")
        let removed = UUID()
        let kept = UUID()
        let configuration = FixedPageReaderConfiguration.everyToggleChanged()
        let store = BookReaderSettingsStore(fileURL: fileURL)
        store.setFixedPageConfiguration(configuration, for: removed)
        store.setFixedPageConfiguration(configuration, for: kept)

        store.removeSettings(for: removed)

        let reopened = BookReaderSettingsStore(fileURL: fileURL)
        #expect(reopened.fixedPageConfiguration(for: removed) == FixedPageReadingMode.rtl.recommendedConfiguration)
        #expect(reopened.fixedPageConfiguration(for: kept) == configuration)
    }

    @Test("settings of books that no longer exist are dropped")
    func settingsOfMissingBooksAreDropped() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("settings.json")
        let missing = UUID()
        let kept = UUID()
        let configuration = FixedPageReaderConfiguration.everyToggleChanged()
        let store = BookReaderSettingsStore(fileURL: fileURL)
        store.setFixedPageConfiguration(configuration, for: missing)
        store.setFixedPageConfiguration(configuration, for: kept)

        store.removeSettings(notIn: [kept])

        let reopened = BookReaderSettingsStore(fileURL: fileURL)
        #expect(reopened.fixedPageConfiguration(for: missing) == FixedPageReadingMode.rtl.recommendedConfiguration)
        #expect(reopened.fixedPageConfiguration(for: kept) == configuration)
    }

    @Test("an unreadable settings file is kept aside instead of being overwritten")
    func unreadableFileIsKeptAside() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("settings.json")
        let original = Data("{ not json".utf8)
        try original.write(to: fileURL)

        BookReaderSettingsStore(fileURL: fileURL)
            .setFixedPageConfiguration(.everyToggleChanged(), for: UUID())

        let backups = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("corrupt") }
        #expect(backups.count == 1)
        #expect(try backups.first.map { try Data(contentsOf: $0) } == original)
    }

    @Test("legacy reading modes move into the store and their keys are removed")
    func legacyReadingModesMoveIntoStore() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("settings.json")
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bothKeys = UUID()
        let legacyOnly = UUID()
        let unknown = UUID()
        defaults.set(FixedPageReadingMode.ltr.rawValue, forKey: currentKey(bothKeys))
        defaults.set(FixedPageReadingMode.webtoon.rawValue, forKey: legacyKey(bothKeys))
        defaults.set(FixedPageReadingMode.webtoon.rawValue, forKey: legacyKey(legacyOnly))
        defaults.set(FixedPageReadingMode.vertical.rawValue, forKey: currentKey(unknown))

        let migrated = BookReaderSettingsStore(fileURL: fileURL).migrateLegacyFixedPageReadingModes(
            from: defaults,
            knownBookIDs: [bothKeys, legacyOnly],
            removesUnknownKeys: false
        )

        #expect(migrated == 2)
        let reopened = BookReaderSettingsStore(fileURL: fileURL)
        // The newer key wins, as it did when the reader read it directly.
        #expect(reopened.fixedPageConfiguration(for: bothKeys) == FixedPageReadingMode.ltr.recommendedConfiguration)
        #expect(reopened.fixedPageConfiguration(for: legacyOnly) == FixedPageReadingMode.webtoon.recommendedConfiguration)
        #expect(defaults.object(forKey: currentKey(bothKeys)) == nil)
        #expect(defaults.object(forKey: legacyKey(bothKeys)) == nil)
        #expect(defaults.object(forKey: legacyKey(legacyOnly)) == nil)
        // A book the shelf does not list may only have failed to load, so its key stays.
        #expect(defaults.object(forKey: currentKey(unknown)) as? Int == FixedPageReadingMode.vertical.rawValue)
        #expect(reopened.fixedPageConfiguration(for: unknown) == FixedPageReadingMode.rtl.recommendedConfiguration)

        let second = reopened.migrateLegacyFixedPageReadingModes(
            from: defaults,
            knownBookIDs: [bothKeys, legacyOnly],
            removesUnknownKeys: false
        )
        #expect(second == 0)
    }

    @Test("legacy keys of books missing from a complete shelf are removed")
    func unknownLegacyKeysRemovedForCompleteShelf() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("settings.json")
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let deletedBook = UUID()
        defaults.set(FixedPageReadingMode.vertical.rawValue, forKey: currentKey(deletedBook))
        defaults.set(FixedPageReadingMode.webtoon.rawValue, forKey: legacyKey(deletedBook))

        let migrated = BookReaderSettingsStore(fileURL: fileURL).migrateLegacyFixedPageReadingModes(
            from: defaults,
            knownBookIDs: [],
            removesUnknownKeys: true
        )

        #expect(migrated == 0)
        #expect(defaults.object(forKey: currentKey(deletedBook)) == nil)
        #expect(defaults.object(forKey: legacyKey(deletedBook)) == nil)
        #expect(
            BookReaderSettingsStore(fileURL: fileURL).fixedPageConfiguration(for: deletedBook)
                == FixedPageReadingMode.rtl.recommendedConfiguration
        )
    }

    @Test("legacy keys stay when the store cannot be written")
    func legacyKeysStayWhenWriteFails() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unwritable = directory
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("settings.json")
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let book = UUID()
        defaults.set(FixedPageReadingMode.ltr.rawValue, forKey: currentKey(book))

        BookReaderSettingsStore(fileURL: unwritable).migrateLegacyFixedPageReadingModes(
            from: defaults,
            knownBookIDs: [book],
            removesUnknownKeys: true
        )

        #expect(defaults.object(forKey: currentKey(book)) as? Int == FixedPageReadingMode.ltr.rawValue)
    }

    @Test("a stored configuration wins over a leftover legacy key")
    func storedConfigurationWinsOverLegacyKey() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("settings.json")
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let book = UUID()
        let configuration = FixedPageReaderConfiguration.everyToggleChanged()
        let store = BookReaderSettingsStore(fileURL: fileURL)
        store.setFixedPageConfiguration(configuration, for: book)
        defaults.set(FixedPageReadingMode.webtoon.rawValue, forKey: currentKey(book))

        let migrated = store.migrateLegacyFixedPageReadingModes(
            from: defaults,
            knownBookIDs: [book],
            removesUnknownKeys: false
        )

        #expect(migrated == 0)
        #expect(BookReaderSettingsStore(fileURL: fileURL).fixedPageConfiguration(for: book) == configuration)
        #expect(defaults.object(forKey: currentKey(book)) == nil)
    }

    // MARK: - Helpers

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookReaderSettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "test.book-reader-settings.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func currentKey(_ bookID: UUID) -> String {
        "fixedPage.readingMode.\(bookID.uuidString)"
    }

    private func legacyKey(_ bookID: UUID) -> String {
        "manga.readingMode.\(bookID.uuidString)"
    }
}

extension FixedPageReaderConfiguration {
    /// Every toggle moved off its default, so a store that drops any one of them fails.
    static func everyToggleChanged() -> FixedPageReaderConfiguration {
        var configuration = FixedPageReadingMode.ltr.recommendedConfiguration
        configuration.pageSpreadLayout = .double
        configuration.pageOffset = true
        configuration.splitWideImages = true
        configuration.cropBorders = true
        configuration.pillarbox = true
        configuration.pillarboxAmount = 0.5
        configuration.autoScrollSpeed = 5
        configuration.isLiveTextEnabled = false
        return configuration
    }
}
