import Foundation
import Testing
@testable import yuedu_app

@Suite("AI book index")
struct AIBookRetrievalIndexTests {

    private let bookID = UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!

    /// Keyword indexes saved before the vector tier was removed carried this exact prefix;
    /// keeping it means they are reused instead of every book rebuilding once after update.
    @Test("the identity keeps the keyword prefix older saved indexes were written with")
    func identityKeepsTheSavedKeywordPrefix() {
        let identifier = AIBookRetrievalIndex.identifier(contentFingerprint: "fp")
        #expect(identifier == "keyword@none@\(AIPublicationChunker.version)@800/120/200@fp")
    }

    /// The failure this guards, seen on a real book: the panel opened while five chapters
    /// were laid out, indexed those, and cached the result. Every later question — and 前情提要
    /// at 51% — was answered out of five chapters of a whole novel, because the identity did
    /// not mention how much text went in.
    @Test("gathering more of the book changes the index identity")
    func contentFingerprintIsPartOfIndexIdentity() {
        let partial = AIBookRetrievalIndex.identifier(contentFingerprint: "300/5/12000")
        let whole = AIBookRetrievalIndex.identifier(contentFingerprint: "300/300/4200000")
        #expect(partial != whole)
    }

    @Test("the adapter's fingerprint moves when chapters gain text")
    func adapterFingerprintTracksAvailableText() {
        let bookID = UUID()
        let chapters = (0..<3).map { BookChapter(index: $0, title: "第\($0)章", content: "") }
        let laidOutOnly = AIBookContentAdapter(bookID: bookID, chapters: chapters) { index in
            index == 0 ? "第一章的內容" : nil
        }
        let gathered = AIBookContentAdapter(bookID: bookID, chapters: chapters) { index in
            "第\(index)章的內容，長度不一樣"
        }
        #expect(laidOutOnly.contentFingerprint != gathered.contentFingerprint)
    }

    @Test("the index answers on keywords")
    func keywordRetrievalFindsTheName() async throws {
        let index = makeIndex()
        let hits = try await index.retrieve(query: "張若塵", maximumProgress: 1.0, limit: 5)
        #expect(!hits.isEmpty)
        #expect(hits.first?.chunk.text.contains("張若塵") == true)
    }

    /// Filtering after the cut would let unread passages occupy the slots and hand back
    /// fewer — sometimes none — making an answerable question look unanswerable.
    @Test("the spoiler boundary is applied before results are trimmed to the limit")
    func filtersBeforeTrimming() async throws {
        // Ten chunks all matching the query; only the earliest two are within progress.
        let chunks = (0..<10).map { ordinal in
            makeChunk(
                ordinal: ordinal,
                text: "張若塵在第\(ordinal)段出現。",
                progressStart: Double(ordinal) / 10,
                progressEnd: Double(ordinal + 1) / 10
            )
        }
        let index = AIBookRetrievalIndex(bookID: bookID, chunks: chunks)
        let hits = try await index.retrieve(query: "張若塵", maximumProgress: 0.2, limit: 5)
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.chunk.progressEnd <= 0.2 + 0.000_001 })
        #expect(hits.count <= 2)
    }

    @Test("a section restriction narrows retrieval to those chapters")
    func restrictsToSections() async throws {
        let chunks = [
            makeChunk(ordinal: 0, sectionID: "c0", text: "張若塵在第一章。"),
            makeChunk(ordinal: 1, sectionID: "c1", text: "張若塵在第二章。"),
        ]
        let index = AIBookRetrievalIndex(bookID: bookID, chunks: chunks)
        let hits = try await index.retrieve(
            query: "張若塵",
            maximumProgress: 1.0,
            limit: 5,
            restrictToSectionIDs: ["c1"]
        )
        #expect(hits.map(\.chunk.sectionID) == ["c1"])
    }

    /// A device that had downloaded the retired semantic-search model gets its space back,
    /// and the leftover download address goes with it.
    @Test("the retired embedding model and its download address are removed")
    func retiredEmbeddingModelIsRemoved() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let installed = support.appendingPathComponent(AIRetiredEmbeddingCleanup.directoryName, isDirectory: true)
        let model = installed.appendingPathComponent("distiluse-base-multilingual-cased-v2@1.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: model.appendingPathComponent("weights.bin"))
        let suite = "AIRetiredEmbeddingCleanupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://example.invalid/model.zip", forKey: AIRetiredEmbeddingCleanup.sourceURLKey)

        AIRetiredEmbeddingCleanup.run(applicationSupport: support, defaults: defaults)

        #expect(!FileManager.default.fileExists(atPath: installed.path))
        #expect(defaults.string(forKey: AIRetiredEmbeddingCleanup.sourceURLKey) == nil)
        // A second launch finds nothing and changes nothing.
        AIRetiredEmbeddingCleanup.run(applicationSupport: support, defaults: defaults)
        #expect(!FileManager.default.fileExists(atPath: installed.path))
    }

    // MARK: - Fixtures

    private func makeIndex() -> AIBookRetrievalIndex {
        AIBookRetrievalIndex(
            bookID: bookID,
            chunks: [
                makeChunk(ordinal: 0, text: "池瑤走出房門，天色已暗。"),
                makeChunk(ordinal: 1, text: "張若塵盤膝而坐，運轉神石。"),
            ]
        )
    }

    private func makeChunk(
        ordinal: Int,
        sectionID: String = "c0",
        text: String = "內容",
        progressStart: Double = 0,
        progressEnd: Double = 0.1
    ) -> AIContentChunk {
        AIContentChunk(
            id: "\(bookID.uuidString):\(sectionID):\(ordinal)",
            bookID: bookID,
            sectionID: sectionID,
            ordinal: ordinal,
            text: text,
            start: AIChunkLocation(spineIndex: 0, charOffset: ordinal * 10, progress: progressStart),
            end: AIChunkLocation(spineIndex: 0, charOffset: ordinal * 10 + 5, progress: progressEnd)
        )
    }
}
