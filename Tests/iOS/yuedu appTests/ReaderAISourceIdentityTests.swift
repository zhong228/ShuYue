import Foundation
import Testing
@testable import yuedu_app

struct ReaderAISourceIdentityTests {
    @Test func metadataIdentityPreservesSerializedContextAndDetectsSourceChanges() {
        let id = UUID()
        let chapters = [BookChapter(index: 0, title: "First", content: "body", href: "0.xhtml"),
                        BookChapter(index: 1, title: "Second", content: "text", href: "1.xhtml")]
        let original = ReaderAISourceIdentity(bookID: id, sourceID: nil, source: "book", chapters: chapters)
        let expected = "\(id):local:book0:0.xhtml:First\n1:1.xhtml:Second"
        #expect(original.context == expected)
        #expect(original == ReaderAISourceIdentity(bookID: id, sourceID: nil, source: "book", chapters: chapters))
        var loaded = chapters
        loaded[1].content = "newly loaded text"
        let sameMetadata = ReaderAISourceIdentity(bookID: id, sourceID: nil, source: "book", chapters: loaded)
        #expect(original == sameMetadata && original.context == sameMetadata.context)
        for change in 0..<4 {
            var modified = chapters
            if change == 0 { modified[1].title = "Renamed" }
            if change == 1 { modified[1].href = "replacement.xhtml" }
            if change == 2 { modified[1].index = 4 }
            if change == 3 { modified.reverse() }
            let identity = ReaderAISourceIdentity(bookID: id, sourceID: nil, source: "book", chapters: modified)
            #expect(original != identity && original.context != identity.context)
        }
        #expect(original != ReaderAISourceIdentity(bookID: UUID(), sourceID: nil, source: "book", chapters: chapters))
        #expect(original != ReaderAISourceIdentity(bookID: id, sourceID: UUID(), source: "book", chapters: chapters))
        #expect(original != ReaderAISourceIdentity(bookID: id, sourceID: nil, source: "other", chapters: chapters))
        // An older acquisition still compares against the exact context string;
        // changing source cannot make a stale async result appear current.
        #expect(original.context == expected)
    }
}
