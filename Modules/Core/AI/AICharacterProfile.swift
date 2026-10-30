//
// Derived from ChatBook (https://github.com/bsnmldb/ChatBook),
// Sources/ChatBookCore/Assistant/CharacterProfile.swift and
// Sources/ChatBookCore/Assistant/AssistantJSONFencing.swift — Apache License 2.0.
// See NOTICE at the repository root.
//
import Foundation

/// Strips the ``` fences a model puts around JSON when it was asked not to.
enum AIJSONFencing {
    static func stripFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        if let newline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: newline)...])
        }
        if trimmed.hasSuffix("```") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A character card: who someone is, who they know, and — the part multi-role narration needs
/// — what else the book calls them.
///
/// **`aliasCandidates` is the only place the AI and the TTS work meet.** The dialogue
/// attribution heuristic cannot know that 張若塵, 若塵 and 塵哥 are one person, so without
/// this it casts three voices for one character. Everything else here is for the reader.
///
/// Source scope is persisted; only verified cards within the reading boundary supply safe aliases.
struct AICharacterProfile: Sendable, Equatable, Codable {
    let name: String
    /// First appearance, as the model summarised it from passages; `nil` when unsupported.
    let firstAppearance: String?
    let role: String?
    let relationships: [String]
    /// Other names the book uses for this character — fed back to 多角色朗讀 so they share
    /// one voice. Never includes `name` itself.
    let aliasCandidates: [String]
    let summary: String
    /// Chunks the card was built from, so every claim can be jumped back to.
    let citationChunkIDs: [String]
    let provider: String
    let model: String
    /// Prompt version this particular card was made with, so a later recipe change can tell
    /// old cards apart instead of silently mixing them.
    let promptVersion: String

    var sourceBoundary: AIReadingBoundary? = nil
    var maximumEvidencePosition: AIChunkLocation? = nil
    var retrievedEvidenceIDs: [String]? = nil

    func isSafe(at boundary: AIReadingBoundary) -> Bool {
        guard let sourceBoundary, let maximumEvidencePosition,
              !sourceBoundary.wholeBook, boundary.contains(sourceBoundary),
              retrievedEvidenceIDs?.isEmpty == false else { return false }
        return boundary.allows(maximumEvidencePosition)
    }

    static let currentPromptVersion = "yuedu.character.v3"

    /// The task, with the character's name kept **out** of it.
    ///
    /// The name arrives as a separate user message. Splicing user- or book-supplied text into
    /// the system role would let a novel containing something shaped like an instruction
    /// rewrite the rules it is being read under.
    ///
    /// The card is written in `language`, except the aliases: 多角色朗讀 matches them against
    /// the prose, so they stay exactly as the book writes them.
    static func task(language: AIAnswerLanguage) -> String {
        """
        整理指定人物在本书中的档案。可用工具 retrieve(query) 检索本书片段（进度范围 [0, 1.0]＝全书）。
        规则：不要透露该人物的最终结局或生死；可以说明身分、人物关系、首次登场。只依据检索到的片段，不要编造；没有依据的栏位留空。
        资讯足够后 action=finish，并把**纯 JSON**（不要加程式码区块标记）放进 answer：
        {"firstAppearance":string,"role":string,"relationships":[string],"aliasCandidates":[string],"summary":string}
        - firstAppearance、role、relationships、summary 用\(language.promptName)写；summary 是人物档案（不含结局）。
        - aliasCandidates：本书中可能指同一人的别称（不含人物名本身），逐字照书中原文的写法。
        """
    }

    private struct Fields: Decodable {
        let firstAppearance: String?
        let role: String?
        let relationships: [String]
        let aliasCandidates: [String]
        let summary: String
    }

    /// Invalid schemas fail before persistence; previous valid cards remain available.
    static func parse(
        fromAnswer answer: String,
        name: String,
        gatheredChunkIDs: [String],
        provider: String,
        model: String,
        citedChunkIDs: [String] = []
    ) throws -> AICharacterProfile {
        let started = Date()
        defer { AIDiagnostics.current?.event("characterParseDuration", ["elapsedMs": "\(Date().timeIntervalSince(started) * 1000)"]) }
        let cleaned = AIJSONFencing.stripFences(answer)
        if let data = cleaned.data(using: .utf8),
           let fields = try? JSONDecoder().decode(Fields.self, from: data),
           !fields.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AICharacterProfile(
                name: name,
                firstAppearance: fields.firstAppearance?.nilIfBlank,
                role: fields.role?.nilIfBlank,
                relationships: fields.relationships.compactMap(\.nilIfBlank),
                aliasCandidates: Self.normalizedAliases(fields.aliasCandidates, excluding: name),
                summary: fields.summary,
                citationChunkIDs: Array(Set(citedChunkIDs).intersection(gatheredChunkIDs)).sorted(),
                provider: provider,
                model: model,
                promptVersion: currentPromptVersion
            )
        }
        AIDiagnostics.current?.event("characterParsing", ["result": "invalidSchema"])
        throw LLMError.invalidSchema
    }

    /// Trims, de-duplicates, and drops the character's own name — models return it often, and
    /// keeping it would make the name an alias of itself.
    static func normalizedAliases(_ raw: [String], excluding name: String) -> [String] {
        let own = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen: Set<String> = [own]
        var out: [String] = []
        for candidate in raw {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    /// Every name this character answers to, the canonical one first.
    var allNames: [String] { [name] + aliasCandidates }
}

/// Folds a book's character cards into the alias table 多角色朗讀 casts voices against.
///
/// The map is alias → canonical name, so `TTSSpeakerAnnotator` can resolve whatever the
/// prose calls someone back to the character the user cast.
enum AICharacterAliasTable {
    /// - Note: when two characters claim the same alias it is dropped from both. Guessing
    ///   would put two people on one voice, which is worse than leaving the ambiguous name
    ///   attributed to nobody and read by the narrator.
    static func aliasMap(for profiles: [AICharacterProfile]) -> [String: String] {
        var owners: [String: Set<String>] = [:]
        for profile in profiles {
            for alias in profile.allNames {
                owners[alias, default: []].insert(profile.name)
            }
        }
        var map: [String: String] = [:]
        for (alias, claimants) in owners where claimants.count == 1 {
            guard let owner = claimants.first else { continue }
            map[alias] = owner
        }
        return map
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
