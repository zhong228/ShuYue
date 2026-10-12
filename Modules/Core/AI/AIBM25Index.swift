//
// Derived from ChatBook (https://github.com/bsnmldb/ChatBook),
// Sources/ChatBookCore/Retrieval/BM25Index.swift — Apache License 2.0.
// See NOTICE at the repository root.
//
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
import Foundation

/// In-memory keyword retrieval over a book's chunks.
///
/// Not persisted: it is rebuilt from the stored chunks when a book's index loads, which costs
/// far less than keeping a second on-disk structure in sync with the first.
///
/// Tokenisation combines system word segmentation with overlapping Han character pairs,
/// so names remain searchable when their surrounding sentences change segmentation.
/// There is no jieba or SQLite FTS dependency. This tier works with **no model
/// downloaded at all**: exact hits on names, places and terms are what Chinese readers
/// actually ask about, which is why keyword weight is set above vector weight when both run.
struct AIBM25Index: Sendable {
    private struct Posting: Sendable {
        let documentIndex: Int
        let frequency: Int
    }

    private let chunks: [AIContentChunk]
    /// Only the inverted lists and per-document lengths are kept. Holding the tokenised text
    /// as well would mean millions of small `String`s on a long web novel.
    private let postingsByTerm: [String: [Posting]]
    private let documentLengths: [Int]
    private let averageDocumentLength: Double
    private let documentCount: Int
    private let k1: Double
    private let b: Double

    init(chunks: [AIContentChunk], k1: Double = 1.5, b: Double = 0.75) {
        self.chunks = chunks
        self.k1 = k1
        self.b = b
        self.documentCount = chunks.count
        var postings: [String: [Posting]] = [:]
        var lengths: [Int] = []
        lengths.reserveCapacity(chunks.count)
        for (documentIndex, chunk) in chunks.enumerated() {
            let tokens = Self.tokenize(chunk.text)
            lengths.append(tokens.count)
            var frequencies: [String: Int] = [:]
            for token in tokens { frequencies[token, default: 0] += 1 }
            for (term, frequency) in frequencies {
                postings[term, default: []].append(
                    Posting(documentIndex: documentIndex, frequency: frequency)
                )
            }
        }
        self.postingsByTerm = postings
        self.documentLengths = lengths
        let total = lengths.reduce(0, +)
        self.averageDocumentLength = documentCount > 0 ? Double(total) / Double(documentCount) : 0
    }

    /// Scores `query`, returning hits with a positive score, best first.
    func search(query: String, limit: Int, eligibleIDs: Set<String>? = nil) -> [AIRetrievalHit] {
        let terms = Set(Self.tokenize(query))
        guard !terms.isEmpty, documentCount > 0, limit > 0 else { return [] }
        var scoresByDocument: [Int: Double] = [:]
        for term in terms {
            guard let postings = postingsByTerm[term] else { continue }
            let documentFrequency = Double(postings.count)
            let idf = log(
                1 + (Double(documentCount) - documentFrequency + 0.5) / (documentFrequency + 0.5)
            )
            for posting in postings {
                if let eligibleIDs, !eligibleIDs.contains(chunks[posting.documentIndex].id) { continue }
                let length = Double(documentLengths[posting.documentIndex])
                let frequency = Double(posting.frequency)
                let denominator = frequency
                    + k1 * (1 - b + b * length / max(averageDocumentLength, 1))
                scoresByDocument[posting.documentIndex, default: 0] +=
                    idf * (frequency * (k1 + 1)) / denominator
            }
        }
        return AIRetrievalRanking.topK(
            scoresByDocument.lazy.map { documentIndex, score in
                AIRetrievalHit(chunk: chunks[documentIndex], score: score)
            },
            limit: min(limit, documentCount)
        )
    }

    /// Retrieval-only normalization; evidence and UTF-16 coordinates retain the original text.
    static func searchText(_ text: String) -> String {
        let normalized = text.precomposedStringWithCompatibilityMapping
        return (normalized.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? normalized).lowercased()
    }

    static func tokenize(_ input: String) -> [String] {
        let text = searchText(input)
        var tokens: [String] = []
        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(String(text[range]).lowercased())
            return true
        }
        #else
        tokens = text
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
        #endif
        // A two-character word is already represented by its pair. Keep longer words
        // and single-character words without doubling the same occurrence's frequency.
        tokens.removeAll { $0.count == 2 && $0.allSatisfy(isHan) }
        var previous: Character?
        for character in text {
            guard isHan(character) else { previous = nil; continue }
            if let previous { tokens.append(String(previous) + String(character)) }
            previous = character
        }
        return tokens
    }

    private static func isHan(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x20000...0x2FA1F, 0x30000...0x323AF: return true
        default: return false
        }
    }
}
