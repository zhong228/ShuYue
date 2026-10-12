//
// Derived from ChatBook (https://github.com/bsnmldb/ChatBook),
// Sources/ChatBookCore/Retrieval/BookRetrievalIndex.swift — Apache License 2.0.
// See NOTICE at the repository root.
//
import Foundation

/// One book's searchable index: BM25 over the book's chunks.
///
/// Keyword retrieval is the only tier. Readers ask about names, places and terms, where an
/// exact hit is what matters, and the assistant's follow-up searches cover rephrasing. The
/// optional on-device vector model this once supported was removed on 2026-09-24.
struct AIBookRetrievalIndex: Sendable {
    let bookID: UUID
    /// Everything needed to decide whether a stored index is still the right one. A change to
    /// any component forces a rebuild rather than a silent mismatch.
    let identifier: String
    let contentFingerprint: String
    let manifest: AISourceManifest?
    let chunkerConfiguration: String
    let chunks: [AIContentChunk]
    let sectionTitleByID: [String: String]
    private let keyword: AIBM25Index

    init(
        bookID: UUID,
        chunks: [AIContentChunk],
        sectionTitleByID: [String: String] = [:],
        contentFingerprint: String = "",
        manifest: AISourceManifest? = nil,
        chunkerConfiguration: String = "800/120/200"
    ) {
        self.contentFingerprint = contentFingerprint
        self.manifest = manifest
        self.chunkerConfiguration = chunkerConfiguration
        self.bookID = bookID
        self.chunks = chunks
        self.sectionTitleByID = sectionTitleByID
        self.identifier = Self.identifier(
            contentFingerprint: contentFingerprint,
            chunkerConfiguration: chunkerConfiguration
        )
        self.keyword = AIBM25Index(chunks: chunks)
    }

    /// `keyword@none@chunker@content` — a stored index whose identifier differs from what
    /// the app would build today is rebuilt, not queried.
    ///
    /// `contentFingerprint` is the load-bearing one for a book being read: the text available
    /// to index grows as chapters are gathered, and without it the first index — built from
    /// whatever happened to be laid out — would be reused forever.
    ///
    /// `keyword@none` is the retired tier/embedding pair, kept verbatim so keyword indexes
    /// saved before the vector tier was removed still match and are not rebuilt; indexes saved
    /// with vectors no longer match and are rebuilt as keyword ones.
    static func identifier(
        contentFingerprint: String = "",
        chunkerConfiguration: String = "800/120/200"
    ) -> String {
        "keyword@none@\(AIPublicationChunker.version)@\(chunkerConfiguration)@\(contentFingerprint)"
    }

    /// Retrieval, with the spoiler boundary applied **before** the results are trimmed to
    /// `limit`.
    ///
    /// Order matters: filtering after the cut would let unread passages take up slots and
    /// hand back fewer usable ones than asked for — sometimes none, making a well-evidenced
    /// question look unanswerable.
    func retrieve(
        query: String,
        maximumProgress: Double,
        limit: Int = 8,
        restrictToSectionIDs: Set<String>? = nil,
        boundary: AIReadingBoundary? = nil
    ) async throws -> [AIRetrievalHit] {
        guard limit > 0 else { return [] }
        let started = Date()
        AIDiagnostics.current?.event("query", ["characters": "\(query.count)"])
        let eligible = chunks.filter { chunk in
            let within = boundary.map { $0.contains(chunk) } ?? (chunk.progressEnd <= maximumProgress)
            return within && (restrictToSectionIDs?.contains(chunk.sectionID) ?? true)
        }
        let eligibleIDs = Set(eligible.map(\.id))
        let candidates = keyword.search(query: query, limit: max(limit * 4, 32), eligibleIDs: eligibleIDs)
        let result = Array(candidates.prefix(limit))
        AIDiagnostics.current?.retrieval(total: chunks.count, eligible: eligible.count,
            candidates: [candidates.count], hits: result, scoreType: "BM25",
            elapsed: Date().timeIntervalSince(started))
        return result
    }
}
