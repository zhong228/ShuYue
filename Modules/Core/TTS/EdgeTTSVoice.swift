import Foundation

struct EdgeTTSVoice: Identifiable, Equatable, Sendable {
    let id: String
    let nameKey: String

    var displayName: String { localized(nameKey) }
    var sourceIdentifier: String { Self.sourcePrefix + id }

    // An internal identifier, never an HTTP template or an imported/deletable source.
    static let sourcePrefix = "yuedu-edge-tts:"
    static let voices: [EdgeTTSVoice] = [
        .init(id: "zh-TW-HsiaoChenNeural", nameKey: "晓臻・台湾华语・女声"),
        .init(id: "zh-TW-HsiaoYuNeural", nameKey: "晓雨・台湾华语・女声"),
        .init(id: "zh-TW-YunJheNeural", nameKey: "云哲・台湾华语・男声"),
        .init(id: "zh-CN-XiaoxiaoNeural", nameKey: "晓晓・普通话・女声"),
        .init(id: "zh-CN-YunxiNeural", nameKey: "云希・普通话・男声"),
        .init(id: "zh-CN-YunjianNeural", nameKey: "云健・普通话・男声"),
        .init(id: "zh-HK-HiuGaaiNeural", nameKey: "晓佳・粤语・女声"),
        .init(id: "zh-HK-WanLungNeural", nameKey: "云龙・粤语・男声"),
        .init(id: "en-US-AriaNeural", nameKey: "Aria・美式英语・女声"),
        .init(id: "en-US-GuyNeural", nameKey: "Guy・美式英语・男声"),
    ]
    static let defaultVoice = voices[0]

    static func voice(id: String) -> EdgeTTSVoice? {
        voices.first { $0.id == id }
    }

    static func isEdgeSource(_ identifier: String) -> Bool {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(sourcePrefix)
    }

    static func voice(sourceIdentifier: String) -> EdgeTTSVoice? {
        let identifier = sourceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEdgeSource(identifier) else { return nil }
        return voice(id: String(identifier.dropFirst(sourcePrefix.count)))
    }
}
