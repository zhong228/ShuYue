import Foundation
import NaturalLanguage
import YueduCoreTextTypography

/// A language the AI writes in: the language of every answer the reader reads, or the target
/// of a translation. No prompt names a fixed language — answers follow the reader.
///
/// The display name comes from the system, so it follows the interface language without a
/// string table; the prompt name is what the model is told, and is never shown.
enum AIAnswerLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"

    var id: String { rawValue }

    /// The interface language, which is also the default answer and translation language.
    ///
    /// Reads the device language preference directly. `Bundle.main.preferredLocalizations`
    /// is unreliable here: the app ships without per-language resource bundles, so it falls
    /// back to the development region and reports `en` on a Chinese device, which made every
    /// preset answer (前情回顾, 本章已读摘要…) come back in English — or, depending on the
    /// model, in traditional characters. `Locale.preferredLanguages` always reflects what the
    /// reader actually set, so a 简体中文 device answers in 简体中文.
    static var current: AIAnswerLanguage {
        matching(Locale.preferredLanguages.first ?? Locale.current.identifier)
    }

    static func matching(_ identifier: String?) -> AIAnswerLanguage {
        guard let identifier, !identifier.isEmpty else { return .simplifiedChinese }
        if let exact = AIAnswerLanguage(rawValue: identifier) { return exact }
        let lowered = identifier.lowercased()
        if lowered.hasPrefix("zh") {
            // zh-TW, zh-HK and zh-MO are written in traditional characters.
            let traditional = ["hant", "tw", "hk", "mo"].contains { lowered.contains($0) }
            return traditional ? .traditionalChinese : .simplifiedChinese
        }
        let base = String(lowered.prefix { $0 != "-" && $0 != "_" })
        return AIAnswerLanguage.allCases.first { $0.rawValue == base } ?? .english
    }

    /// How sure the recognizer must be before text the reader wrote overrides `fallback`. A
    /// bare name (林黛玉 scores 0.78 Chinese against 0.21 Japanese) or 「ok」 stays below it.
    static let minimumConfidence = 0.8

    /// The language the reader wrote `text` in — a question typed to the assistant, a custom
    /// prompt — or `fallback`, the interface language, when the text does not say.
    ///
    /// Chinese is settled in two steps. The recognizer is trusted to say *Chinese*, but its
    /// split between the scripts is a guess on text both write alike, such as 他去哪了. The
    /// script comes from the characters: text that simplifying changes has traditional
    /// characters, text that the reverse changes has simplified ones. Text with neither keeps
    /// the interface's script.
    static func of(readerText text: String, otherwise fallback: AIAnswerLanguage) -> AIAnswerLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = allCases.map(\.naturalLanguage)
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: allCases.count)
        let simplified = hypotheses[.simplifiedChinese] ?? 0
        let traditional = hypotheses[.traditionalChinese] ?? 0
        var scores: [(language: AIAnswerLanguage, probability: Double)] = allCases.filter { !$0.isChinese }.map {
            ($0, hypotheses[$0.naturalLanguage] ?? 0)
        }
        scores.append((simplified >= traditional ? .simplifiedChinese : .traditionalChinese, simplified + traditional))
        guard let best = scores.max(by: { $0.probability < $1.probability }),
              best.probability >= minimumConfidence else { return fallback }
        guard best.language.isChinese else { return best.language }
        switch ChineseScript.of(text) {
        case .traditional: return .traditionalChinese
        case .simplified: return .simplifiedChinese
        case nil: return fallback.isChinese ? fallback : best.language
        }
    }

    var isChinese: Bool { self == .traditionalChinese || self == .simplifiedChinese }

    private var naturalLanguage: NLLanguage {
        switch self {
        case .traditionalChinese: return .traditionalChinese
        case .simplifiedChinese: return .simplifiedChinese
        case .english: return .english
        case .japanese: return .japanese
        case .korean: return .korean
        case .french: return .french
        case .german: return .german
        case .spanish: return .spanish
        case .russian: return .russian
        }
    }

    var displayName: String {
        Locale.current.localizedString(forIdentifier: rawValue) ?? rawValue
    }

    /// The line an answer prompt carries in place of a fixed language. A reader who asks for
    /// another one in their own words still gets it.
    var answerRule: String { "用\(promptName)回答；读者明确要求其他语言时，照读者的要求。" }

    var promptName: String {
        switch self {
        case .traditionalChinese: return "繁体中文"
        case .simplifiedChinese: return "简体中文"
        case .english: return "英文"
        case .japanese: return "日文"
        case .korean: return "韩文"
        case .french: return "法文"
        case .german: return "德文"
        case .spanish: return "西班牙文"
        case .russian: return "俄文"
        }
    }
}
