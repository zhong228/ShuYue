#if DEBUG
import Foundation

/// `-reader-translation-fixture`: a book with no stored 整章翻譯 setting opens side by side
/// with a canned English translation, so the translated layout can be looked at without an
/// AI service. Debug builds only.
enum ReaderTranslationFixture {
    static let launchArgument = "-reader-translation-fixture"
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }
    static var provider: (any LLMProviding)? { isActive ? Provider() : nil }

    /// Answers every paragraph with English prose about as long as it.
    private struct Provider: LLMProviding {
        let identifier = "Translation fixture"
        let defaultModel = "fixture"
        private static let sentences = [
            "Klein looked up at the crimson moon hanging over Tingen and felt a chill he could not name.",
            "The gaslights along the street flickered, and somewhere a church bell rang the hour.",
            "He opened the old notebook again, though he already knew every word written in it.",
        ]

        func generate(_ request: LLMGenerationRequest, model: String?) async throws -> LLMRawResponse {
            let payload = try JSONSerialization.jsonObject(with: Data((request.messages.last?.content ?? "").utf8)) as? [String: Any]
            let items = (payload?["paragraphs"] as? [[String: String]]) ?? []
            let translations = items.enumerated().map { index, item -> [String: String] in
                let length = (item["text"] ?? "").count
                let count = max(1, min(3, length / 40 + 1))
                let text = (0..<count).map { Self.sentences[(index + $0) % Self.sentences.count] }.joined(separator: " ")
                return ["id": item["id"] ?? "", "text": text]
            }
            let json = try JSONSerialization.data(withJSONObject: ["translations": translations])
            return LLMRawResponse(content: String(decoding: json, as: UTF8.self), provider: identifier, model: defaultModel, finishReason: "stop")
        }
    }
}
#endif
