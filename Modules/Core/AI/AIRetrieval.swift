//
// Derived from ChatBook (https://github.com/bsnmldb/ChatBook),
// Sources/ChatBookCore/Retrieval/Retrieval.swift — Apache License 2.0.
// See NOTICE at the repository root.
//
import Foundation

/// A chunk that matched, with the score that ranked it.
struct AIRetrievalHit: Identifiable, Hashable, Sendable {
    var id: String { chunk.id }
    var chunk: AIContentChunk
    var score: Double

    init(chunk: AIContentChunk, score: Double) {
        self.chunk = chunk
        self.score = score
    }
}

/// Bounded ranking shared by every retrieval path.
///
/// Queries ask for 16–24 candidates out of a whole book, so keeping only K avoids sorting
/// tens of thousands of chunks on every question.
enum AIRetrievalRanking {
    static func topK<S: Sequence>(_ candidates: S, limit: Int) -> [AIRetrievalHit]
    where S.Element == AIRetrievalHit {
        guard limit > 0 else { return [] }
        var best: [AIRetrievalHit] = []
        best.reserveCapacity(limit)
        for candidate in candidates {
            consider(candidate, in: &best, limit: limit)
        }
        return best
    }

    static func consider(_ candidate: AIRetrievalHit, in best: inout [AIRetrievalHit], limit: Int) {
        guard limit > 0 else { return }
        if best.count == limit, let last = best.last, !ranksBefore(candidate, last) { return }

        var lower = 0
        var upper = best.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if ranksBefore(candidate, best[middle]) {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        best.insert(candidate, at: lower)
        if best.count > limit { best.removeLast() }
    }

    /// Ties break on reading order, so the same question asked twice ranks identically.
    private static func ranksBefore(_ lhs: AIRetrievalHit, _ rhs: AIRetrievalHit) -> Bool {
        if lhs.score == rhs.score { return lhs.chunk.ordinal < rhs.chunk.ordinal }
        return lhs.score > rhs.score
    }
}

/// Keeps unread pages out of an answer.
///
/// This is a **retrieval** boundary, not a prompt instruction, and that is the whole point:
/// asking a model nicely not to spoil the ending is not a control. Text that never reaches
/// the model cannot be leaked by it.
enum AISpoilerSafeFilter {
    /// A chunk is safe only when it **ends** at or before the reader's progress. A chunk that
    /// merely starts before it still carries an unread tail.
    static func apply(
        to hits: [AIRetrievalHit],
        maximumProgress: Double,
        tolerance: Double = 0.000_001
    ) -> [AIRetrievalHit] {
        let ceiling = min(max(maximumProgress, 0), 1) + max(0, tolerance)
        return hits.filter { $0.chunk.progressEnd <= ceiling }
    }

    /// The same boundary applied to chunks directly, so the recap path and the question path
    /// cannot drift apart.
    static func chunks(
        _ chunks: [AIContentChunk],
        maximumProgress: Double,
        tolerance: Double = 0.000_001
    ) -> [AIContentChunk] {
        let ceiling = min(max(maximumProgress, 0), 1) + max(0, tolerance)
        return chunks.filter { $0.progressEnd <= ceiling }
    }
}
