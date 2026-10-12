import Combine
import Foundation

/// Owns the complete conversation lifetime. Views never write transcripts or assemble prompts.
@MainActor
final class AIReadingConversation: ObservableObject {
    typealias Prepare = @MainActor (AIQuestionContext) async throws -> AIQuestionContext
    @Published private(set) var session = AIChatSession()
    @Published private(set) var history: [AIChatSession] = []
    @Published private(set) var stage: AIQuestionStage = .searching
    @Published private(set) var source: AIBookContentAdapter?
    @Published var selection: AIReadingSelection?
    /// This book's highlights and notes, read at send time so a mark just made counts.
    var bookAnnotations: @MainActor () -> [AIReaderAnnotation] = { [] }
    /// Other books' marks, read only for a question that reaches across the shelf.
    var libraryAnnotations: @MainActor () -> [AIReaderAnnotation] = { [] }
    private let store: AIChatStore
    private let assistant: AIAssistantService
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var openedBook: UUID?
    private var sourceIdentity: String?

    init(store: AIChatStore = .shared, assistant: AIAssistantService? = nil) {
        self.store = store; self.assistant = assistant ?? .shared
    }
    var isBusy: Bool { requestID != nil }
    var wholeBook: Bool { session.wholeBook ?? false }
    var boundary: AIReadingBoundary? { source?.boundary(wholeBook: wholeBook) }

    func open(source: AIBookContentAdapter, sourceIdentity: String? = nil) {
        if openedBook != source.chunkBookID {
            cancel()
            openedBook = source.chunkBookID
            selection = nil
            history = store.sessions(forBook: source.chunkBookID)
            session = history.first ?? AIChatSession()
        } else if self.sourceIdentity != sourceIdentity || self.source?.contentFingerprint != source.contentFingerprint {
            cancel()
        } else if let previous = self.source, !source.boundary(wholeBook: wholeBook).contains(previous.boundary(wholeBook: wholeBook)) {
            cancel()
        }
        self.sourceIdentity = sourceIdentity
        self.source = source
        assistant.activate(source)
    }

    func setWholeBook(_ value: Bool) {
        cancel()
        session.wholeBook = value
        persist()
    }
    func setModel(profile: AIServiceProfile, model: String) {
        session.serviceID = profile.id; session.model = model
        persist()
    }
    func startNew() {
        cancel(); persist()
        session = AIChatSession()
        selection = nil
    }
    func select(_ value: AIChatSession) {
        cancel()
        // The list may have captured this conversation before its latest streamed text.
        // Cancellation saves that text; restore the fresh record instead of overwriting it.
        session = openedBook.flatMap { book in store.sessions(forBook: book).first { $0.id == value.id } } ?? value
        selection = nil
        persist()
    }
    func delete(_ id: UUID) {
        guard let book = openedBook else { return }
        if session.id == id { cancel(); session = AIChatSession() }
        store.delete(sessionID: id, forBook: book)
        history = store.sessions(forBook: book)
    }

    @discardableResult
    func send(_ question: String, action: AIReadingAction = .question, custom: AICustomPrompt? = nil,
              prepare: @escaping Prepare = { $0 }, retrying userID: UUID? = nil) -> Task<Void, Never>? {
        guard !isBusy, let source, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var context = AIQuestionContext(bookID: source.chunkBookID, conversationID: session.id, question: question,
            source: source, boundary: source.boundary(wholeBook: wholeBook), history: session.messages.filter { $0.id != userID })
        context.action = action; context.selection = selection; context.customPrompt = custom
        context.serviceID = session.serviceID; context.model = session.model
        context.allowsBackgroundKnowledge = true
        context.annotations = AIReaderAnnotationSet(book: bookAnnotations(),
            library: AIReaderAnnotations.asksAcrossBooks(question) ? libraryAnnotations() : [])
        do { context = try assistant.freezeProvider(in: context) }
        catch { appendFailure(context: context, error: error); return nil }
        let metadata = AIChatProvenance(requestID: context.requestID, bookID: context.bookID,
            conversationID: session.id, boundary: context.boundary, status: .pending)
        guard let turn = session.prepareQuestion(question, metadata: metadata, retrying: userID) else { return nil }
        if let index = session.messages.firstIndex(where: { $0.id == turn.user }) {
            session.messages[index].action = action
            session.messages[index].selection = selection
            session.messages[index].customPrompt = custom
        }
        requestID = context.requestID; stage = .searching; persist()
        let frozen = context
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await prepare(frozen)
                try Task.checkCancellation()
                guard owns(frozen) else { return }
                for old in prepared.history {
                    if let index = session.messages.firstIndex(where: { $0.id == old.id }) {
                        session.messages[index].provenance = old.provenance
                        session.messages[index].citations = old.citations
                    }
                }
                self.source = prepared.source
                assistant.activate(prepared.source)
                let result = try await assistant.answer(context: prepared, onStage: { [weak self] stage in
                    guard let self, self.owns(frozen) else { return }
                    self.stage = stage
                }, onText: { [weak self] delta in
                    guard let self, self.owns(frozen), let index = self.session.messages.firstIndex(where: { $0.id == turn.assistant }) else { return }
                    self.session.messages[index].text += delta
                })
                try Task.checkCancellation()
                guard owns(frozen), let index = session.messages.firstIndex(where: { $0.id == turn.assistant }) else { return }
                session.messages[index].text = result.content
                session.messages[index].citations = result.citations
                session.messages[index].hasEvidence = result.hasEvidence
                session.messages[index].notices = result.notices
                session.messages[index].provenance = result.provenance
                session.messages[index].isPending = false
                if let user = session.messages.firstIndex(where: { $0.id == turn.user }) { session.messages[user].provenance = result.provenance }
                requestID = nil; task = nil; persist()
            } catch {
                guard owns(frozen), let index = session.messages.firstIndex(where: { $0.id == turn.assistant }) else { return }
                session.messages[index].isPending = false
                session.messages[index].errorMessage = error is CancellationError ? localized("回覆已中止") : error.localizedDescription
                session.messages[index].provenance?.status = error is CancellationError ? .cancelled : .failed
                requestID = nil; task = nil; persist()
            }
        }
        return task
    }

    func retry(prepare: @escaping Prepare) {
        guard session.messages.count >= 2, let answer = session.messages.last, answer.errorMessage != nil else { return }
        let user = session.messages[session.messages.count - 2]
        selection = user.selection
        send(user.text, action: user.action ?? .question, custom: user.customPrompt, prepare: prepare, retrying: user.id)
    }

    func cancel() {
        task?.cancel(); task = nil; requestID = nil
        for index in session.messages.indices where session.messages[index].isPending {
            session.messages[index].isPending = false
            session.messages[index].errorMessage = localized("回覆已中止")
            session.messages[index].provenance?.status = .cancelled
        }
        persist()
    }
    private func owns(_ context: AIQuestionContext) -> Bool {
        requestID == context.requestID && session.id == context.conversationID && openedBook == context.bookID
    }
    private func persist() {
        guard let book = openedBook else { return }
        store.save(session, forBook: book)
        history = store.sessions(forBook: book)
    }
    private func appendFailure(context: AIQuestionContext, error: Error) {
        var question = AIChatMessage(role: .user, text: context.question)
        question.action = context.action; question.selection = context.selection; question.customPrompt = context.customPrompt
        session.messages.append(question)
        session.messages.append(.init(role: .assistant, text: "", errorMessage: error.localizedDescription))
        persist()
    }
}
