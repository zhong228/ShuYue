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
                        term: "圣者",
                        context: "他终于突破到圣者境界，气息铺天盖地。",
                        bookTitle: "万古神帝",
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
        let titles = ["第一卷 风起", "第1章 炼器战士", "第2章 界子", "第二卷 云涌", "第3章 青霄圣者", "第4章 无字剑谱"]
        let texts = ["", "张若尘接到大师兄所赠的黑色铁球。", "青霄圣者与璇玑老人谈到界子。", "", "青霄圣者对此并不看好。", "璇玑老人取出一本书册。"]
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
        var summaryQuestion = AIChatMessage(role: .user, text: localized("本章已读摘要"))
        summaryQuestion.action = .chapterSummary

        var summary = AIChatMessage(
            role: .assistant,
            text: """
            以下是目前能确认的已读片段前情整理，只涵盖这批片段。

            ## 一、青禾殿：炼器战士与师门相聚
            张若尘接到大师兄所赠的**黑色铁球**，铁球重达数千斤，实为一具炼器战士；他注入真气激活铭纹，铁球展开成三米高的钢铁巨人。

            - 炼器战士由第一中央帝国神工部炼制，一般只有兵部能动用
            - 胸前凹槽存放灵晶供能，兵部多用圣石供能

            ## 二、青霄圣者与璇玑老人的密谈
            两人离开青禾殿后，落到一块三十多里长的陨石上，谈到玄武墟界出世的邪器。
            """,
            citations: [
                LLMCitation(chunkID: "fixture-1", quote: "铁球重达数千斤……", spineIndex: 0, charOffset: 0, sectionTitle: "第561章 炼器战士"),
                LLMCitation(chunkID: "fixture-2", quote: "两人离开青禾殿……", spineIndex: 0, charOffset: 120, sectionTitle: "第562章 界子"),
            ]
        )
        summary.notices = [
            localized("目前章节位置尚无法验证，本次只使用此前可确认的内容。"),
            localized("本次只搜寻可确认的已读范围。"),
        ]

        var selectionQuestion = AIChatMessage(role: .user, text: localized("AI 解释"))
        selectionQuestion.action = .explain
        selectionQuestion.selection = AIReadingSelection(
            bookID: bookID, spineIndex: 0, range: NSRange(location: 0, length: 24),
            text: "他注入真气激活铭纹，铁球展开成三米高的钢铁巨人。"
        )

        var unsupported = AIChatMessage(role: .assistant, text: "目前可用、已读范围内的检索结果不足以确认。", hasEvidence: false)
        unsupported.notices = [
            localized("目前章节位置尚无法验证，本次只使用此前可确认的内容。"),
            localized("部分章节没有可用的本机正文，本次回答可能不完整。"),
            localized("本次只搜寻可确认的已读范围。"),
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
