import Foundation

/// One file per book holding its chapter digests, volume summaries and whole-book summary.
///
/// Application Support, not Caches: every digest in here was paid for with a model call, and
/// the system evicting it under disk pressure would make the reader pay again.
actor AIBookSummaryStore {
    static let shared = AIBookSummaryStore()
    let directory: URL
    private var cache: [UUID: AIBookSummaryRecord] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIBookSummaries", isDirectory: true)
    }

    private func url(_ book: UUID) -> URL { directory.appendingPathComponent("\(book.uuidString).json") }

    /// The stored record, or an empty one for a book never summarised.
    func load(book: UUID) throws -> AIBookSummaryRecord {
        if let cached = cache[book] { return cached }
        let path = url(book)
        guard FileManager.default.fileExists(atPath: path.path) else { return AIBookSummaryRecord() }
        let record = try JSONDecoder().decode(AIBookSummaryRecord.self, from: Data(contentsOf: path))
        cache[book] = record
        return record
    }

    func save(_ record: AIBookSummaryRecord, book: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: url(book), options: [.atomic, .completeFileProtection])
        cache[book] = record
    }

    func clear(book: UUID) throws {
        cache[book] = nil
        let path = url(book)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
    }
}
