import Foundation
import Testing
@testable import yuedu_app

/// 書架檔讀不到時，不可以被空書架蓋掉。
///
/// `loadMeta` 讀失敗後 `records` 是空的、`lastPersistedMetadataData` 也是 nil，所以下一次存檔
/// （匯入一本書、套用同步、甚至只是記閱讀進度）就會覆蓋原檔，整份書架索引就沒了。
@Suite("BookStore shelf recovery", .serialized)
struct BookStoreShelfRecoveryTests {

    @Test("an unreadable shelf file is kept aside before anything overwrites it")
    @MainActor
    func unreadableShelfIsKeptAside() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadataURL = directory.appendingPathComponent("books_meta.json")
        let unreadable = Data("{ not json".utf8)
        try unreadable.write(to: metadataURL)

        let store = BookStore(metadataFileURL: metadataURL)
        store.replaceBooksFromSync([ReadingBook(title: "新書", author: "Author", contentFilename: "")])

        let backups = try corruptBackups(in: directory)
        #expect(backups.count == 1)
        #expect(try backups.first.map { try Data(contentsOf: $0) } == unreadable)
        // Once the bytes are safe, the shelf is writable again.
        let saved = try JSONDecoder().decode([ReadingBook].self, from: Data(contentsOf: metadataURL))
        #expect(saved.map(\.title) == ["新書"])
    }

    @Test("a shelf that could not be kept aside is never overwritten")
    @MainActor
    func shelfThatCannotBeKeptAsideIsNotOverwritten() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadataURL = directory.appendingPathComponent("books_meta.json")
        let unreadable = Data("{ not json".utf8)
        try unreadable.write(to: metadataURL)
        // Something else already holds the name this file's copy would take.
        let occupied = Data("an older copy".utf8)
        try occupied.write(to: try backupURL(for: metadataURL))

        let store = BookStore(metadataFileURL: metadataURL)
        store.replaceBooksFromSync([ReadingBook(title: "新書", author: "Author", contentFilename: "")])

        #expect(try Data(contentsOf: metadataURL) == unreadable)
        #expect(try Data(contentsOf: backupURL(for: metadataURL)) == occupied)
    }

    @Test("a relaunch recognises the copy it already made")
    @MainActor
    func relaunchReusesTheExistingCopy() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadataURL = directory.appendingPathComponent("books_meta.json")
        let unreadable = Data("{ not json".utf8)
        try unreadable.write(to: metadataURL)

        _ = BookStore(metadataFileURL: metadataURL)
        let relaunched = BookStore(metadataFileURL: metadataURL)
        relaunched.replaceBooksFromSync([ReadingBook(title: "新書", author: "Author", contentFilename: "")])

        #expect(try corruptBackups(in: directory).count == 1)
        let saved = try JSONDecoder().decode([ReadingBook].self, from: Data(contentsOf: metadataURL))
        #expect(saved.map(\.title) == ["新書"])
    }

    // MARK: - Helpers

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookStoreShelfRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func corruptBackups(in directory: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("corrupt") }
    }

    /// Mirrors the store's own naming: the shelf file's modification time, so a relaunch
    /// recognises the copy it made rather than filling the folder with duplicates.
    private func backupURL(for metadataURL: URL) throws -> URL {
        let modified = try metadataURL
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date()
        return metadataURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(modified.timeIntervalSince1970)).json")
    }
}
