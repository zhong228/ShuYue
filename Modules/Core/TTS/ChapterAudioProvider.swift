import Foundation

struct ChapterAudio {
    let url: URL
    let headers: [String: String]
    let chapterStartSeconds: Double?
    let chapterDurationSeconds: Double?

    init(
        url: URL,
        headers: [String: String] = [:],
        chapterStartSeconds: Double? = nil,
        chapterDurationSeconds: Double? = nil
    ) {
        self.url = url
        self.headers = headers
        self.chapterStartSeconds = chapterStartSeconds
        self.chapterDurationSeconds = chapterDurationSeconds
    }
}

enum ChapterAudioProviderError: LocalizedError {
    case missingAudio(contentLength: Int, preview: String)
    case missingLocalAudio

    var errorDescription: String? {
        switch self {
        case .missingAudio:
            return localized("未找到音訊")
        case .missingLocalAudio:
            return localized("音訊檔案不在此裝置上，請重新匯入")
        }
    }
}

@MainActor
protocol ChapterAudioProvider: AnyObject {
    /// The chapter's playable link. `priority` is `.immediate` for the chapter the listener
    /// is waiting on and `.prefetch` for a look-ahead (`AudiobookResourcePreloader`).
    func audio(
        for book: ReadingBook,
        chapterIndex: Int,
        priority: ChapterFetchPriority,
        store: BookStore
    ) async throws -> ChapterAudio

    /// Forgets the chapter's resolved link so the next `audio` call resolves it again —
    /// legado's `AudioPlayManager.refreshChapter` (`chapter.resourceUrl = null`), which its
    /// player runs once, silently, when a link fails to play: most links are time-signed,
    /// so a failure usually means the link expired while it sat resolved.
    func discardResolvedAudio(for book: ReadingBook, chapterIndex: Int, store: BookStore)
}

@MainActor
final class OnlineChapterAudioProvider: ChapterAudioProvider {
    /// Direct TOC links that failed to play once are remembered by "bookId#chapterIndex",
    /// so the fast path does not hand the same expired link to the player again; the
    /// chapter falls back to the page-fetch path, which can produce a fresh link.
    private var failedDirectChapters: Set<String> = []

    func audio(
        for book: ReadingBook,
        chapterIndex: Int,
        priority: ChapterFetchPriority,
        store: BookStore
    ) async throws -> ChapterAudio {
        // Fast path: when the TOC entry itself already points at a playable audio file,
        // there is no chapter page to fetch and parse — the per-chapter fetch is the slow
        // part of loading an online audiobook. Play the link straight away.
        if let refs = book.onlineChapters, refs.indices.contains(chapterIndex) {
            let ref = refs[chapterIndex]
            if Self.isDirectAudioURL(ref.url),
               !failedDirectChapters.contains(Self.failureKey(book: book, chapter: chapterIndex)) {
                let sanitized = RuleEngine.sanitizeExtractedURL(ref.url)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: sanitized) {
                    return ChapterAudio(url: url, headers: sourceHeaders(for: book))
                }
            }
        }

        // Cache first, like every online chapter: the cached content is this chapter's
        // resolved link (legado keeps it in `BookChapter.resourceUrl`).
        let package = try await ChapterFetchManager.shared.fetchChapter(
            book: book,
            chapterIndex: chapterIndex,
            priority: priority,
            store: store
        )

        guard let request = DirectChapterAudioResolver.request(from: package.content),
              let url = request.url else {
            throw ChapterAudioProviderError.missingAudio(
                contentLength: package.content.count,
                preview: String(package.content.prefix(160))
            )
        }

        let mergedHeaders = sourceHeaders(for: book)
            .merging(request.allHTTPHeaderFields ?? [:]) { _, requestValue in requestValue }

        return ChapterAudio(
            url: url,
            headers: mergedHeaders
        )
    }

    /// The same two steps the reader's refetch takes: the cached chapter file, and the
    /// shelf record's pointer to it. A direct TOC link is also marked failed here — both
    /// the retry path and the look-ahead path call this when a resolved link does not
    /// play, and retrying an expired time-signed URL would only fail again.
    func discardResolvedAudio(for book: ReadingBook, chapterIndex: Int, store: BookStore) {
        if let refs = book.onlineChapters, refs.indices.contains(chapterIndex),
           Self.isDirectAudioURL(refs[chapterIndex].url) {
            failedDirectChapters.insert(Self.failureKey(book: book, chapter: chapterIndex))
        }
        BookSourceFetcher.shared.clearChapterCache(bookId: book.id, chapterIndex: chapterIndex)
        store.clearCachedChapter(bookId: book.id, chapterIndex: chapterIndex)
    }

    /// Whether a TOC link is already a playable audio stream — stricter than the page
    /// content heuristic (`DirectChapterAudioResolver`), because here we judge the raw
    /// link before any page is fetched: it has to be http(s) with a real audio file
    /// extension, or carry an audio MIME in its query (e.g. 番茄 `mime_type=audio_mpeg`).
    /// Page URLs are otherwise never mistaken for streams.
    static func isDirectAudioURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return false
        }

        if Self.audioExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        let lowered = trimmed.lowercased()
        return lowered.contains("mime=audio")
            || lowered.contains("mime_type=audio")
            || lowered.contains("content-type=audio")
    }

    private static let audioExtensions: Set<String> = [
        "aac", "aiff", "aif", "flac", "m4a", "m4b", "mp3", "oga", "ogg", "opus", "wav"
    ]

    private static func failureKey(book: ReadingBook, chapter: Int) -> String {
        "\(book.id.uuidString)#\(chapter)"
    }

    private func sourceHeaders(for book: ReadingBook) -> [String: String] {
        let source = book.bookSourceId.flatMap { id in
            BookSourceStore.shared.sources.first { $0.id == id }
        }
        return BookCoverLoader.headers(
            sourceBaseURL: source?.bookSourceUrl,
            sourceHeaders: source?.parsedHeaders ?? [:]
        )
    }
}

@MainActor
final class LocalChapterAudioProvider: ChapterAudioProvider {
    func audio(
        for book: ReadingBook,
        chapterIndex: Int,
        priority: ChapterFetchPriority,
        store: BookStore
    ) async throws -> ChapterAudio {
        guard let refs = book.onlineChapters, refs.indices.contains(chapterIndex) else {
            throw ChapterAudioProviderError.missingAudio(contentLength: 0, preview: "")
        }
        let ref = refs[chapterIndex]

        let url = Self.documentsURL(for: ref.url)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ChapterAudioProviderError.missingLocalAudio
        }

        return ChapterAudio(
            url: url,
            chapterStartSeconds: ref.audioStartSeconds,
            chapterDurationSeconds: ref.audioDurationSeconds
        )
    }

    /// A local chapter's link is a file path; there is nothing resolved to forget.
    func discardResolvedAudio(for book: ReadingBook, chapterIndex: Int, store: BookStore) {}

    /// Audio extracted from a user-supplied archive (`local_audio/<id>/…`) or the
    /// audiobook file itself — user content, so it stays in Documents.
    private static func documentsURL(for relativePath: String) -> URL {
        StorageLocations.bookFile(relativePath)
    }
}
