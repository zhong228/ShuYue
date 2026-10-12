import Foundation

/// A cheap value to observe during view updates. Building the serialized source
/// context belongs to AI acquisition, not to every scroll/chapter/UI update.
struct ReaderAISourceIdentity: Equatable {
    let bookID: UUID
    let sourceID: UUID?
    let source: String
    let chapters: [BookChapter]

    var context: String {
        "\(bookID):\(sourceID?.uuidString ?? "local"):\(source)"
            + chapters.map { "\($0.index):\($0.href):\($0.title)" }.joined(separator: "\n")
    }

    func presentationAdapter(prepared: AIBookContentAdapter?, identity: Self?) -> AIBookContentAdapter {
        guard let prepared, prepared.chunkBookID == bookID, identity == self else {
            return .pending(bookID: bookID)
        }
        return prepared
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.bookID == rhs.bookID, lhs.sourceID == rhs.sourceID,
              lhs.source == rhs.source, lhs.chapters.count == rhs.chapters.count else { return false }
        // Array is copy-on-write. Progress updates keep the same storage; compare
        // its identity only while both buffers are borrowed, never cache pointers.
        let sameStorage = lhs.chapters.withUnsafeBufferPointer { left in
            rhs.chapters.withUnsafeBufferPointer { right in left.baseAddress == right.baseAddress }
        }
        if sameStorage { return true }
        return zip(lhs.chapters, rhs.chapters).allSatisfy {
            $0.index == $1.index && $0.href == $1.href && $0.title == $1.title
        }
    }
}
