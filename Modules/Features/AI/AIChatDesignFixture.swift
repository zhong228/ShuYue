#if DEBUG
import SwiftUI

/// Opt-in design fixture for the reading assistant (`-ai-chat-design-fixture`).
///
/// Seeds a service profile and a canned conversation into this device's stores, then
/// presents the production panel over an empty page, so the chat layout can be captured
/// without an AI key or an open book. Never selected in a normal launch.
struct AIChatDesignFixture: View {
    static let launchArgument = "-ai-chat-design-fixture"
    /// Together with `launchArgument`: shows the relationship map with a sample cast instead.
    static let relationshipMapArgument = "-ai-relationship-map"
    /// Together with `launchArgument`: shows the AI 查詞 card, answered by the preview
    /// provider, so its bottom bar can be captured.
    static let wordLookupArgument = "-ai-word-lookup"
    private static let bookID = UUID(uuidString: "5A1F1C7E-0000-4000-8000-00000000A1C4")!
    private static let profileID = UUID(uuidString: "5A1F1C7E-0000-4000-8000-00000000A1C5")!

    @State private var presented = false

    var body: some View {
        DSColor.background
            .ignoresSafeArea()
            .onAppear {
                // The lookup card brings its own provider; nothing to seed for it.
                if !ProcessInfo.processInfo.arguments.contains(Self.wordLookupArgument) {
                    Self.seed()
                }
                presented = true
            }
            .sheet(isPresented: $presented) {
                if ProcessInfo.processInfo.arguments.contains(Self.relationshipMapArgument) {
                    NavigationStack { AIRelationshipMapView(adapter: Self.adapter, graph: .sample) }
                } else if ProcessInfo.processInfo.arguments.contains(Self.wordLookupArgument) {
                    AIWordLookupView(
                        term: "聖者",
                        context: "他終於突破到聖者境界，氣息鋪天蓋地。",
                        bookTitle: "萬古神帝",
                        bookID: Self.bookID,
                        onAskAI: {},
                        provider: AIWordLookupPreviewProvider()
                    )
                } else {
                    AIAssistantPanelView(
                        bookID: Self.bookID,
                        bookTitle: "万古神帝",
                        adapter: Self.adapter,
                        progress: 0.5,
                        onOpenCitation: { _, _ in }
                    )
                }
            }
    }

    /// Two volumes, read into the second, so the summary page has volumes to list.
    private static var adapter: AIBookContentAdapter {
        let titles = ["第一卷 風起", "第1章 煉器戰士", "第2章 界子", "第二卷 雲湧", "第3章 青霄聖者", "第4章 無字劍譜"]
        let texts = ["", "張若塵接到大師兄所贈的黑色鐵球。", "青霄聖者與璇璣老人談到界子。", "", "青霄聖者對此並不看好。", "璇璣老人取出一本書冊。"]
        let chapters = titles.indices.map { BookChapter(index: $0, title: titles[$0], content: "") }
        return AIBookContentAdapter(bookID: bookID, chapters: chapters, readingPosition: (spine: 4, utf16Offset: texts[4].utf16.count),
                                    renderedText: texts[4]) { texts[$0] }
    }

    private static func seed() {
        let profile = AIServiceProfile(
            id: profileID,
            name: "DeepSeek",
            configuration: AIProviderConfiguration(endpoint: "https://api.deepseek.com/v1", defaultModel: "deepseek-flash"),
            models: ["deepseek-flash", "deepseek-pro"]
        )
        do { try AIProviderStore.shared.upsert(profile, apiKey: "fixture") }
        catch { AppLogger.error("AI chat fixture could not seed its service profile: \(error)") }
        AIChatStore.shared.save(session, forBook: bookID)
    }

    private static var session: AIChatSession {
        var summaryQuestion = AIChatMessage(role: .user, text: localized("本章已讀摘要"))
        summaryQuestion.action = .chapterSummary

        var summary = AIChatMessage(
            role: .assistant,
            text: """
            以下是目前能確認的已讀片段前情整理，只涵蓋這批片段。

            ## 一、青禾殿：煉器戰士與師門相聚
            張若塵接到大師兄所贈的**黑色鐵球**，鐵球重達數千斤，實為一具煉器戰士；他注入真氣激活銘紋，鐵球展開成三米高的鋼鐵巨人。

            - 煉器戰士由第一中央帝國神工部煉製，一般只有兵部能動用
            - 胸前凹槽存放靈晶供能，兵部多用聖石供能

            ## 二、青霄聖者與璇璣老人的密談
            兩人離開青禾殿後，落到一塊三十多里長的隕石上，談到玄武墟界出世的邪器。
            """,
            citations: [
                LLMCitation(chunkID: "fixture-1", quote: "鐵球重達數千斤……", spineIndex: 0, charOffset: 0, sectionTitle: "第561章 炼器战士"),
                LLMCitation(chunkID: "fixture-2", quote: "兩人離開青禾殿……", spineIndex: 0, charOffset: 120, sectionTitle: "第562章 界子"),
            ]
        )
        summary.notices = [
            localized("目前章節位置尚無法驗證，本次只使用此前可確認的內容。"),
            localized("本次只搜尋可確認的已讀範圍。"),
        ]

        var selectionQuestion = AIChatMessage(role: .user, text: localized("AI 解釋"))
        selectionQuestion.action = .explain
        selectionQuestion.selection = AIReadingSelection(
            bookID: bookID, spineIndex: 0, range: NSRange(location: 0, length: 24),
            text: "他注入真氣激活銘紋，鐵球展開成三米高的鋼鐵巨人。"
        )

        var unsupported = AIChatMessage(role: .assistant, text: "目前可用、已讀範圍內的檢索結果不足以確認。", hasEvidence: false)
        unsupported.notices = [
            localized("目前章節位置尚無法驗證，本次只使用此前可確認的內容。"),
            localized("部分章節沒有可用的本機正文，本次回答可能不完整。"),
            localized("本次只搜尋可確認的已讀範圍。"),
        ]

        var session = AIChatSession(
            id: UUID(uuidString: "5A1F1C7E-0000-4000-8000-00000000A1C6")!,
            messages: [summaryQuestion, summary, selectionQuestion, unsupported]
        )
        // Pinned to the fixture's own service, whatever else this device has configured.
        session.serviceID = profileID
        session.model = "deepseek-flash"
        return session
    }
}
#endif
