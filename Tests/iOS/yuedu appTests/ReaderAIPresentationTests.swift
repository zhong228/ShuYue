import XCTest
@testable import yuedu_app

@MainActor
final class ReaderAIPresentationTests: XCTestCase {
    func testLargeTOCUnpreparedPresentationCost() {
        let id = UUID()
        let chapters = (0..<13_209).map {
            BookChapter(index: $0, title: "第\($0)章 神奇的任務", content: "", href: "https://example.invalid/chapter/\($0)")
        }
        let identity = ReaderAISourceIdentity(bookID: id, sourceID: nil, source: "online", chapters: chapters)
        let start = SourcePerfTrace.now
        for _ in 0..<4 {
            let adapter = identity.presentationAdapter(prepared: nil, identity: nil)
            XCTAssertFalse(adapter.isPrepared)
            XCTAssertTrue(adapter.chunkSections.isEmpty)
            XCTAssertFalse(adapter.readingPositionVerified)
            XCTAssertEqual(adapter.chunkBookID, id)
            XCTAssertEqual(adapter.boundary().utf16Offset, 0)
        }
        let ms = (SourcePerfTrace.now - start) * 1000
        SourcePerfTrace.record("reader.ai.presentationBenchmark", "chapters=13209 reads=4", since: start, thresholdMs: 0)
        print("AI_PRESENTATION_MS=\(ms)")
    }
    func testPreparedSnapshotKeepsFingerprintEvidenceAndBoundary() async throws {
        let id = UUID()
        let chapters = [BookChapter(index: 0, title: "First", content: "", href: "first"),
                        BookChapter(index: 1, title: "Unread", content: "", href: "second")]
        let identity = ReaderAISourceIdentity(bookID: id, sourceID: nil, source: "book", chapters: chapters)
        let prepared = try await AIBookContentAdapter.prepare(bookID: id, chapters: chapters,
            transformationVersion: "test", missingStatus: [1: .notDownloaded], acquisitionMilliseconds: 0,
            texts: [0: "甲乙丙丁"])
        let expected = AIBookContentAdapter(bookID: id, chapters: chapters, transformationVersion: "test",
            missingStatus: [1: .notDownloaded], textForChapter: { $0 == 0 ? "甲乙丙丁" : nil })
        XCTAssertEqual(prepared.contentFingerprint, expected.contentFingerprint)
        XCTAssertEqual(prepared.manifest, expected.manifest)
        let visible = identity.presentationAdapter(prepared: prepared, identity: identity)
            .atReadingPosition(spine: 0, renderedOffset: 2, renderedText: "甲乙丙丁")
        XCTAssertTrue(visible.isPrepared)
        XCTAssertTrue(visible.readingPositionVerified)
        XCTAssertEqual(visible.sections(in: visible.boundary()).map(\.text), ["甲乙"])

        var changed = chapters
        changed[0].href = "replacement"
        let replacement = ReaderAISourceIdentity(bookID: id, sourceID: nil, source: "book", chapters: changed)
        XCTAssertFalse(replacement.presentationAdapter(prepared: prepared, identity: identity).isPrepared)
        let other = ReaderAISourceIdentity(bookID: UUID(), sourceID: nil, source: "book", chapters: chapters)
        XCTAssertFalse(other.presentationAdapter(prepared: prepared, identity: identity).isPrepared)
    }

    func testCancelledPreparationCannotReturnPublishableSnapshot() async {
        let task = Task {
            try await AIBookContentAdapter.prepare(bookID: UUID(), chapters: [], transformationVersion: "test",
                missingStatus: [:], acquisitionMilliseconds: 0, texts: [:])
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled acquisition must not publish")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

}
