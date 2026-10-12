import Foundation
import Testing
@testable import yuedu_app

@Suite("Reading assistant redesign", .serialized)
@MainActor
struct AIReadingAssistantRedesignTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "AIReadingRedesignTests.\(UUID())")!
    }

    @Test func migrationVerifiesCopiedKeyAndPreservesLegacy() throws {
        let preferences = defaults()
        let store = AIProviderStore(defaults: preferences)
        let legacy = AIProviderConfiguration(endpoint: "https://example.com/v1", defaultModel: "reader")
        store.save(legacy)
        var secrets: [String: String] = ["legacy": "test-key"]
        let migrated = try store.profiles(readKey: { secrets[$0?.uuidString ?? "legacy"] }, writeKey: { value, id in
            secrets[id.uuidString] = value; return true
        })
        #expect(migrated.count == 1)
        #expect(migrated[0].configuration == legacy)
        #expect(secrets[migrated[0].id.uuidString] == "test-key")
        #expect(secrets["legacy"] == "test-key")
        #expect(try store.load() == legacy)
        #expect(try store.profiles() == migrated)
        #expect(store.activeID == migrated[0].id)
    }

    @Test func failedKeyMigrationDoesNotPublishNewConfiguration() throws {
        let preferences = defaults()
        let store = AIProviderStore(defaults: preferences)
        store.save(.default)
        #expect(throws: (any Error).self) {
            try store.profiles(readKey: { _ in "test-key" }, writeKey: { _, _ in false })
        }
        #expect(preferences.data(forKey: "yd_ai_provider_configuration.profiles") == nil)
        #expect(try store.load() == .default)
        #expect(AIAPIKeyStore.account(for: UUID()) != AIAPIKeyStore.account(for: UUID()))
        #expect(AIAPIKeyStore.account(for: UUID()) != AIAPIKeyStore.account(for: nil))
    }

    @Test func migrationPreservesLegacyDefaultWhenOnlyKeyWasSaved() throws {
        let store = AIProviderStore(defaults: defaults())
        var copied: String?
        let migrated = try store.profiles(readKey: { $0 == nil ? "legacy-default-key" : copied }, writeKey: { value, _ in copied = value; return true })
        #expect(migrated.count == 1)
        #expect(migrated.first?.configuration == .default)
        #expect(copied == "legacy-default-key")
        #expect(try store.load() == nil)
    }

    @Test func customPromptsKeepOrderContextAndDisabledState() throws {
        let preferences = defaults()
        let store = AICustomPromptStore(defaults: preferences)
        let first = AICustomPrompt(title: "Explain", instruction: "Explain the argument", context: .selection, isEnabled: false)
        let second = AICustomPrompt(title: "Summary", instruction: "Summarize", context: .chapter)
        try store.save([second, first])
        #expect(AICustomPromptStore(defaults: preferences).prompts == [second, first])
    }

    @Test func citationAuthorizesSourceAndBoundaryBeforeLoading() async throws {
        let source = source(book: UUID(), texts: ["已讀", "未讀😀原文"], spine: 0, offset: 2)
        var citation = LLMCitation(chunkID: "future", quote: "未讀😀", spineIndex: 1, charOffset: 0)
        citation.sourceVersion = source.contentFingerprint
        citation.coordinateUnit = "sourceUTF16"
        var loads: [Int] = []
        do {
            _ = try await AIReadingContentService.citationOffset(citation, source: source, boundary: source.boundary()) {
                loads.append($0); return "未讀😀原文"
            }
            Issue.record("Unread citation must be rejected before acquisition")
        } catch { }
        #expect(loads.isEmpty)
        var stale = citation
        stale.sourceVersion = "previous source"
        do {
            _ = try await AIReadingContentService.citationOffset(stale, source: source, boundary: source.boundary(wholeBook: true)) {
                loads.append($0); return "未讀😀原文"
            }
            Issue.record("Stale citation must be rejected before acquisition")
        } catch { }
        #expect(loads.isEmpty)
        let offset = try await AIReadingContentService.citationOffset(citation, source: source, boundary: source.boundary(wholeBook: true)) {
            loads.append($0); return "標題\n未讀😀原文"
        }
        #expect(offset == 3)
        #expect(loads == [1])
        let cancelled = Task { @MainActor in
            try await AIReadingContentService.citationOffset(citation, source: source, boundary: source.boundary(wholeBook: true)) {
                loads.append($0); return "未讀😀原文"
            }
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; Issue.record("Cancelled citation must not load") }
        catch is CancellationError { }
        #expect(loads == [1])
    }

    @Test func selectionRejectsUnreadTextAndBrokenUnicodeRanges() {
        let book = UUID()
        let text = "甲😀乙\n丙丁"
        let source = AIBookContentAdapter(bookID: book,
            chapters: [.init(index: 0, title: "One", content: text, href: "one")],
            readingPosition: (0, 4), renderedText: text, textForChapter: { _ in text })
        let valid = AIReadingSelection(bookID: book, spineIndex: 0, range: NSRange(location: 1, length: 3), text: "😀乙")
        #expect(valid.validated(in: source, boundary: source.boundary()))
        let split = AIReadingSelection(bookID: book, spineIndex: 0, range: NSRange(location: 2, length: 2), text: "😀乙")
        #expect(!split.validated(in: source, boundary: source.boundary()))
        let future = AIReadingSelection(bookID: book, spineIndex: 0, range: NSRange(location: 3, length: 3), text: "乙\n丙")
        #expect(!future.validated(in: source, boundary: source.boundary()))
        #expect(future.validated(in: source, boundary: source.boundary(wholeBook: true)))
    }

    @Test func renderedTitleAndWhitespaceKeepExactRepeatedSelectionAndCitation() throws {
        let text = "甲😀乙。\n甲😀乙。\n後文"
        let rendered = "章節標題\n甲😀乙。\n\n甲😀乙。\n\n後文\n"
        let selected = "甲😀乙。"
        let renderedRange = NSRange(try #require(rendered.range(of: selected, options: .backwards)), in: rendered)
        let sourceRange = NSRange(try #require(text.range(of: selected, options: .backwards)), in: text)
        #expect(AITextCoordinates.mappedRange(renderedRange, from: rendered, to: text) == sourceRange)
        #expect(AITextCoordinates.sourceBoundaryOffset(source: text, rendered: rendered, renderedOffset: NSMaxRange(renderedRange)) == NSMaxRange(sourceRange))
        let book = UUID()
        let source = source(book: book, texts: [text], spine: 0, offset: text.utf16.count)
        let launch = AIReadingLaunch(action: .explain, selection: .init(bookID: book, spineIndex: 0, range: renderedRange, text: selected), renderedChapterText: rendered)
        let resolved = launch.resolvingSelection(in: source)
        #expect(resolved.id == launch.id)
        #expect(resolved.selection?.range == sourceRange)
        #expect(resolved.selection?.originalText == selected)
        #expect(resolved.selection?.validated(in: source, boundary: source.boundary()) == true)
        var citation = LLMCitation(chunkID: "selected", quote: selected, spineIndex: 0, charOffset: sourceRange.location)
        citation.sourceVersion = source.contentFingerprint; citation.coordinateUnit = "sourceUTF16"
        #expect(AITextCoordinates.citationOffset(citation, sourceVersion: source.contentFingerprint, sourceText: text, renderedText: rendered) == renderedRange.location)
        #expect(AITextCoordinates.mappedRange(renderedRange, from: rendered, to: "甲😀乙。\nChanged story") == nil)
    }

    @Test func canonicallyEqualUnicodeDoesNotPretendToShareUTF16Coordinates() {
        let composed = "é正文"
        let decomposed = "e\u{301}正文"
        #expect(AITextCoordinates.mappedRange(NSRange(location: 1, length: 1), from: composed, to: decomposed) == nil)
        #expect(AITextCoordinates.sourceBoundaryOffset(source: decomposed, rendered: composed, renderedOffset: 2) == 0)
        let book = UUID()
        let old = source(book: book, texts: [composed], spine: 0, offset: composed.utf16.count)
        let updated = source(book: book, texts: [decomposed], spine: 0, offset: decomposed.utf16.count)
        var message = AIChatMessage(role: .assistant, text: "Prior evidence")
        message.provenance = .init(requestID: UUID(), bookID: book, conversationID: UUID(), boundary: old.boundary(), status: .completed)
        let context = AIQuestionContext(bookID: book, question: "Follow up", source: old, boundary: old.boundary(), history: [message])
        #expect(context.replacingSource(updated).history[0].provenance?.boundary.sourceVersion == old.contentFingerprint)
    }

    @Test func crossParagraphSelectionPreservesOriginalTextAndVerifiedSourceRange() throws {
        let text = "甲😀乙。\n丙丁。\n後文"
        let rendered = "第一章\n甲😀乙。\n\n丙丁。\n\n後文"
        let selectionText = "😀乙。\n\n丙丁"
        let range = NSRange(try #require(rendered.range(of: selectionText)), in: rendered)
        let source = source(book: UUID(), texts: [text], spine: 0, offset: text.utf16.count)
        let launch = AIReadingLaunch(action: .translate,
            selection: .init(bookID: source.chunkBookID, spineIndex: 0, range: range, text: selectionText), renderedChapterText: rendered)
        let resolved = try #require(launch.resolvingSelection(in: source).selection)
        #expect(resolved.text == "😀乙。\n丙丁")
        #expect(resolved.displayText == selectionText)
        #expect(resolved.validated(in: source, boundary: source.boundary()))
    }

    @Test func partialStreamNeverShowsProtocolAndKeepsMarkdownLinks() {
        var parser = AIAnswerStreamDisplay(nonce: "test")
        var output = parser.consume("Answer [S")
        output += parser.consume("1] with [Swift](https://example.com).[[SELF")
        output += parser.consume("ASSESS:test]]{\"sufficient\":\"full\"}[[/SELFASSESS:test]]")
        #expect(output == "Answer  with [Swift](https://example.com).")
    }

    private func source(book: UUID, texts: [String], spine: Int, offset: Int) -> AIBookContentAdapter {
        AIBookContentAdapter(bookID: book, chapters: texts.indices.map { .init(index: $0, title: "Chapter \($0)", content: "") },
            readingPosition: (spine, offset), renderedText: texts[spine], textForChapter: { texts[$0].isEmpty ? nil : texts[$0] })
    }

    @Test func missingChapterRequestsNeverCrossReadingBoundary() {
        let book = UUID()
        let source = source(book: book, texts: ["", "current passage", ""], spine: 1, offset: 8)
        var context = AIQuestionContext(bookID: book, question: "Chapter 2", source: source, boundary: source.boundary())
        #expect(!AIReadingContentService.chapterRequests(context).contains(2))
        context = AIQuestionContext(bookID: book, question: "Chapter 2", source: source, boundary: source.boundary(wholeBook: true))
        #expect(AIReadingContentService.chapterRequests(context).contains(2))
    }

    @Test func chapterSummaryIncludesReadPrefixAndNoOtherChapters() throws {
        let book = UUID()
        let source = source(book: book, texts: ["Old chapter", "甲😀乙，未讀結局"], spine: 1, offset: 4)
        var context = AIQuestionContext(bookID: book, question: "Summary", source: source, boundary: source.boundary())
        context.action = .chapterSummary
        let index = AIBookRetrievalIndex(bookID: book, chunks: AIPublicationChunker().chunks(from: source), contentFingerprint: source.contentFingerprint)
        let evidence = try AIReadingEvidence.collect(context: context, index: index)
        #expect(evidence.map { $0.chunk.text }.joined() == "甲😀乙")
        #expect(evidence.allSatisfy { $0.chunk.start.spineIndex == 1 })
    }

    @Test func fillingMissingChapterPreservesSafeHistoryButNotChangedSource() {
        let book = UUID()
        let old = source(book: book, texts: ["", "read text"], spine: 1, offset: 9)
        let fresh = source(book: book, texts: ["downloaded", "read text"], spine: 1, offset: 9)
        let changed = source(book: book, texts: ["downloaded", "changed text"], spine: 1, offset: 9)
        let conversation = UUID()
        var message = AIChatMessage(role: .assistant, text: "Earlier answer")
        var citation = LLMCitation(chunkID: "old", quote: "read text", spineIndex: 1, charOffset: 0)
        citation.sourceVersion = old.contentFingerprint
        citation.coordinateUnit = "sourceUTF16"
        message.citations = [citation]
        message.provenance = .init(requestID: UUID(), bookID: book, conversationID: conversation, boundary: old.boundary(), status: .completed)
        let context = AIQuestionContext(bookID: book, conversationID: conversation, question: "Why?", source: old, boundary: old.boundary(), history: [message])
        #expect(context.replacingSource(fresh).safeHistory().count == 1)
        #expect(context.replacingSource(fresh).history.first?.citations.first?.sourceVersion == fresh.contentFingerprint)
        #expect(context.replacingSource(changed).history.first?.citations.first?.sourceVersion == old.contentFingerprint)
        #expect(context.replacingSource(changed).safeHistory().isEmpty)
        message.provenance = .init(requestID: UUID(), bookID: book, conversationID: conversation, boundary: old.boundary(wholeBook: true), status: .completed)
        let full = AIQuestionContext(bookID: book, conversationID: conversation, question: "Why?", source: old, boundary: old.boundary(), history: [message])
        #expect(full.replacingSource(fresh).safeHistory().isEmpty)
    }

    @Test func interruptedTranscriptRestoresPartialTextWithoutRestarting() {
        let preferences = defaults()
        let store = AIChatStore(defaults: preferences)
        let book = UUID()
        var session = AIChatSession(messages: [.init(role: .user, text: "Question"), .init(role: .assistant, text: "Partial answer", isPending: true)])
        session.wholeBook = true
        store.save(session, forBook: book)
        let restored = store.sessions(forBook: book)[0]
        #expect(restored.messages.last?.text == "Partial answer")
        #expect(restored.messages.last?.isPending == false)
        #expect(restored.messages.last?.errorMessage != nil)
        #expect(restored.wholeBook == true)
        let model = AIReadingConversation(store: store)
        model.open(source: source(book: book, texts: ["Some text"], spine: 0, offset: 9))
        #expect(model.session.id == session.id)
        #expect(!model.isBusy)
        model.startNew()
        #expect(!model.wholeBook)
    }

    @Test func selectionActionStreamsFinalAnswerAndOnlySafeEvidence() async throws {
        let fixture = AIPhase2ConversationTests()
        let source = fixture.source(["甲😀乙。未讀身分"], offset: 4)
        var context = fixture.context(source, "Explain")
        context.action = .explain
        context.allowsBackgroundKnowledge = true
        context.selection = .init(bookID: fixture.book, spineIndex: 0, range: NSRange(location: 1, length: 3), text: "😀乙")
        let provider = AIPhase2ConversationTests.Provider([.answer()])
        let sink = TextSink()
        let result = try await AIAgenticAssistant.answerQuestion(context: context, index: fixture.index(source), provider: provider,
            onText: { sink.text += $0 })
        #expect(!sink.text.isEmpty)
        #expect(!sink.text.contains("SELFASSESS"))
        #expect(!sink.text.contains("[S1]"))
        #expect(result.citations.contains { $0.quote == "😀乙" })
        let requests = await provider.requests
        #expect(requests.count == 1)
        #expect(!requests[0].messages.last!.content.contains("未讀身分"))
    }

    @Test func separateServicesKeepIndependentKeychainSecrets() throws {
        let first = UUID(), second = UUID()
        defer { _ = AIAPIKeyStore.clear(providerID: first); _ = AIAPIKeyStore.clear(providerID: second) }
        #expect(AIAPIKeyStore.save("first-test-secret", providerID: first))
        #expect(AIAPIKeyStore.save("second-test-secret", providerID: second))
        #expect(AIAPIKeyStore.load(providerID: first) == "first-test-secret")
        #expect(AIAPIKeyStore.load(providerID: second) == "second-test-secret")
        _ = AIAPIKeyStore.clear(providerID: first)
        #expect(AIAPIKeyStore.load(providerID: first) == nil)
        #expect(AIAPIKeyStore.load(providerID: second) == "second-test-secret")
    }

    @Test func sameQuestionReallyStartsAnotherRequest() async throws {
        let provider = AIPhase2ConversationTests.Provider([.answer(), .answer()])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let assistant = AIAssistantService(store: AIBookIndexStore(directory: directory), provider: provider, diagnosticOrigin: .testFixture)
        let conversation = AIReadingConversation(store: AIChatStore(defaults: defaults()), assistant: assistant)
        conversation.open(source: source(book: UUID(), texts: ["The reader found the key."], spine: 0, offset: 25))
        await conversation.send("Summary", action: .chapterSummary)?.value
        await conversation.send("Summary", action: .chapterSummary)?.value
        #expect(await provider.requests.count == 2)
        #expect(conversation.session.messages.count == 4)
        #expect(conversation.session.messages.last?.errorMessage == nil)
    }

    @Test(arguments: ["cancel", "book", "source", "sameTextDifferentSource", "conversation"])
    func latePreparationCannotPublishIntoAnotherRequest(change: String) async throws {
        let provider = AIPhase2ConversationTests.Provider([.answer()])
        let assistant = AIAssistantService(provider: provider, diagnosticOrigin: .testFixture)
        let store = AIChatStore(defaults: defaults())
        let conversation = AIReadingConversation(store: store, assistant: assistant)
        let book = UUID()
        let original = source(book: book, texts: ["The original text."], spine: 0, offset: 18)
        conversation.open(source: original)
        let gate = PreparationGate()
        let request = conversation.send("Summary", action: .chapterSummary) { context in
            await gate.pause()
            return context
        }
        await gate.waitUntilEntered()
        switch change {
        case "book": conversation.open(source: source(book: UUID(), texts: ["Other book"], spine: 0, offset: 10))
        case "source": conversation.open(source: source(book: book, texts: ["Changed source"], spine: 0, offset: 14))
        case "sameTextDifferentSource": conversation.open(source: original, sourceIdentity: "other-book-source")
        case "conversation": conversation.startNew()
        default: conversation.cancel()
        }
        gate.release()
        await request?.value
        #expect(!conversation.isBusy)
        #expect(await provider.requests.isEmpty)
        #expect(!conversation.session.messages.contains { $0.text.contains("Fixture answer") })
        #expect(store.sessions(forBook: book).first?.messages.last?.errorMessage != nil)
    }

    @Test func onlineAcquisitionLoadsOnlyRequestedChaptersAndPreservesMissingState() async throws {
        let book = UUID()
        let texts = ["", "", "Read chapter", ""]
        let source = source(book: book, texts: texts, spine: 2, offset: 12)
        let chapters = texts.indices.map { BookChapter(index: $0, title: "Chapter \($0)", content: "") }
        let context = AIQuestionContext(bookID: book, question: "Chapter 0", source: source, boundary: source.boundary())
        var loaded: [Int] = []
        let prepared = try await AIReadingContentService.acquire(context, chapters: chapters) { index in
            loaded.append(index); return "The missing chapter"
        }
        #expect(loaded == [0])
        #expect(prepared.source.manifest.chapters[0].status == .available)
        #expect(prepared.source.manifest.chapters[1].status == .notDownloaded)
        #expect(prepared.source.manifest.chapters[3].status == .notDownloaded)
    }

    @Test func onlineFailureIsReportedAndCancellationStopsTheNextChapter() async throws {
        let book = UUID()
        let texts = ["", "", "Read chapter", ""]
        let source = source(book: book, texts: texts, spine: 2, offset: 12)
        let chapters = texts.indices.map { BookChapter(index: $0, title: "Chapter \($0)", content: "") }
        var context = AIQuestionContext(bookID: book, question: "Recap", source: source, boundary: source.boundary())
        context.action = .recap
        var failures: [Int] = []
        do {
            _ = try await AIReadingContentService.acquire(context, chapters: chapters) { index in
                failures.append(index); throw URLError(.notConnectedToInternet)
            }
            Issue.record("An offline source must not become a successful empty answer")
        } catch { #expect((error as? URLError)?.code == .notConnectedToInternet) }
        #expect(failures == [0])
        let gate = PreparationGate()
        var loaded: [Int] = []
        let frozen = context
        let request = Task { @MainActor in
            try await AIReadingContentService.acquire(frozen, chapters: chapters) { index in
                loaded.append(index); await gate.pause(); return "Downloaded"
            }
        }
        await gate.waitUntilEntered()
        request.cancel(); gate.release()
        do { _ = try await request.value; Issue.record("Cancelled acquisition must stop") }
        catch { #expect(error is CancellationError) }
        #expect(loaded == [0])
    }

    @Test(arguments: [false, true])
    func streamingCancellationKeepsPartialTextAndIgnoresLateNetworkEvents(selectHistory: Bool) async throws {
        let provider = StreamingGateProvider()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let assistant = AIAssistantService(store: AIBookIndexStore(directory: directory), provider: provider, diagnosticOrigin: .testFixture)
        let store = AIChatStore(defaults: defaults())
        let conversation = AIReadingConversation(store: store, assistant: assistant)
        let book = UUID()
        conversation.open(source: source(book: book, texts: ["The reader found the key."], spine: 0, offset: 25))
        let request = conversation.send("Summary", action: .chapterSummary)
        await provider.waitUntilSubscribed()
        let staleHistory = try #require(conversation.history.first)
        await provider.emit("Partial answer")
        for _ in 0..<1000 {
            if conversation.session.messages.last?.text == "Partial answer" { break }
            await Task.yield()
        }
        #expect(conversation.session.messages.last?.text == "Partial answer")
        if selectHistory { conversation.select(staleHistory) } else { conversation.cancel() }
        await provider.finish("LATE RESPONSE")
        await request?.value
        #expect(conversation.session.messages.last?.text == "Partial answer")
        #expect(conversation.session.messages.last?.errorMessage != nil)
        let restored = AIReadingConversation(store: store, assistant: assistant)
        restored.open(source: source(book: book, texts: ["The reader found the key."], spine: 0, offset: 25))
        #expect(restored.session.messages.last?.text == "Partial answer")
        #expect(!restored.isBusy)
        #expect(await provider.subscriptions == 1)
    }

    @Test func markdownKeepsCodeLiteralAndSeparatesListsHeadingsAndQuotes() {
        let text = "# Title\n\n**Bold** and [link](https://example.com).\n- One\n- Two\n\n> Quote\n\n```swift\nlet text = \"**literal**\"\n```"
        let blocks = AIAnswerMarkdown.blocks(text)
        #expect(blocks.map(\.kind) == [.heading, .paragraph, .list, .list, .quote, .code])
        #expect(blocks.last?.text == "let text = \"**literal**\"")
    }

    @Test func markdownListItemsDrawBulletsAndKeepOrderedNumbersAndDepth() {
        #expect(AIAnswerMarkdown.listItem("- One") == .init(depth: 0, marker: "•", text: "One"))
        #expect(AIAnswerMarkdown.listItem("  * Nested **bold**") == .init(depth: 1, marker: "•", text: "Nested **bold**"))
        #expect(AIAnswerMarkdown.listItem("\t+ Tabbed") == .init(depth: 1, marker: "•", text: "Tabbed"))
        #expect(AIAnswerMarkdown.listItem("12) Twelve") == .init(depth: 0, marker: "12)", text: "Twelve"))
        #expect(AIAnswerMarkdown.listItem("3. 第三點") == .init(depth: 0, marker: "3.", text: "第三點"))
    }

    private actor StreamingGateProvider: LLMProviding {
        let identifier = "streaming-fixture"
        let defaultModel = "fixture"
        var subscriptions = 0
        private var continuation: AsyncThrowingStream<String, Error>.Continuation?
        private var observer: CheckedContinuation<Void, Never>?
        func generate(_ request: LLMGenerationRequest, model: String?) async throws -> LLMRawResponse {
            throw LLMError.providerError("Unexpected non-streaming call")
        }
        nonisolated func stream(_ request: LLMGenerationRequest, model: String?) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in Task { await self.attach(continuation) } }
        }
        private func attach(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
            self.continuation = continuation; subscriptions += 1
            observer?.resume(); observer = nil
        }
        func waitUntilSubscribed() async {
            if continuation != nil { return }
            await withCheckedContinuation { observer = $0 }
        }
        func emit(_ text: String) { continuation?.yield(text) }
        func finish(_ text: String) { continuation?.yield(text); continuation?.finish() }
    }

    private final class PreparationGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var observer: CheckedContinuation<Void, Never>?
        private var entered = false
        func pause() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation; entered = true
                observer?.resume(); observer = nil
            }
        }
        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { observer = $0 }
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    private final class TextSink { var text = "" }
}
