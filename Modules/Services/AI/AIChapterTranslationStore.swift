import Foundation

/// 整章翻譯's translations: one file per book and target language, mapping a paragraph's
/// digest (`ReaderTranslationText.storageKey`) to its translation.
///
/// Application Support, not Caches: every translation in here was paid for with a model call.
actor AIChapterTranslationStore {
    static let shared = AIChapterTranslationStore()
    let directory: URL

    private struct Record: Codable {
        var promptVersion: String
        var entries: [String: String]
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AITranslations", isDirectory: true)
    }

    private nonisolated func folder(_ book: UUID) -> URL { directory.appendingPathComponent(book.uuidString, isDirectory: true) }
    private nonisolated func url(_ book: UUID, _ language: AIAnswerLanguage) -> URL {
        folder(book).appendingPathComponent("\(language.rawValue).json")
    }

    /// The stored translations, or none for a book never translated into `language`.
    ///
    /// Synchronous because the chapter layout asks for them while it builds; writes are
    /// atomic, so a read never sees half a file.
    nonisolated func loadSync(book: UUID, language: AIAnswerLanguage) throws -> [String: String] {
        let path = url(book, language)
        guard FileManager.default.fileExists(atPath: path.path) else { return [:] }
        return try JSONDecoder().decode(Record.self, from: Data(contentsOf: path)).entries
    }

    func save(_ entries: [String: String], book: UUID, language: AIAnswerLanguage) throws {
        try FileManager.default.createDirectory(at: folder(book), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Record(promptVersion: AIChapterTranslation.promptVersion, entries: entries))
            .write(to: url(book, language), options: [.atomic, .completeFileProtection])
    }

    /// Every language's translations of `book`.
    func clear(book: UUID) throws {
        let path = folder(book)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
    }
}
