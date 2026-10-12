import Combine
import Foundation

/// The one entry point the AI screens call.
///
/// Views ask for an answer, a recap or a character card; this owns the index, the spoiler
/// ceiling, the provider, and the degradation when any of them is missing. Nothing above this
/// line builds a prompt or touches retrieval — the project rule is that a view calls one
/// service-level use case and the service owns the rest.
@MainActor
final class AIAssistantService: ObservableObject {
    static let shared = AIAssistantService()

    /// What went wrong, in terms a reader can act on.
    enum Failure: LocalizedError, Equatable {
        case unavailable(AIProviderAssembly.Unavailable)
        case bookNotIndexed
        case emptyBook

        var errorDescription: String? {
            switch self {
            case let .unavailable(reason): return reason.message
            case .bookNotIndexed: return localized("這本書還沒建立索引")
            case .emptyBook: return localized("這本書沒有可以分析的內容")
            }
        }
    }

    /// Progress of a book's index build, so a long one is visible rather than a frozen screen.
    enum IndexState: Equatable {
        case idle
        case building
        case ready(chunkCount: Int)
        case failed(String)
    }

    @Published private(set) var indexedChapterCounts: [UUID: Int] = [:]
    @Published private(set) var indexState: [UUID: IndexState] = [:]

    private let store: AIBookIndexStore
    private let injectedProvider: (any LLMProviding)?
    private let cards: AICharacterCardStore
    private let diagnosticOrigin: AIDiagnostics.Origin
    private var latestSnapshots: [UUID: String] = [:]

    func activate(_ adapter: AIBookContentAdapter) {
        if latestSnapshots[adapter.chunkBookID] != adapter.contentFingerprint {
            indexedChapterCounts[adapter.chunkBookID] = 0
            indexState[adapter.chunkBookID] = .idle
        }
        latestSnapshots[adapter.chunkBookID] = adapter.contentFingerprint
    }

    init(store: AIBookIndexStore = .shared, provider: (any LLMProviding)? = nil, cards: AICharacterCardStore? = nil, diagnosticOrigin: AIDiagnostics.Origin = .observed) {
        self.store = store
        self.injectedProvider = provider
        self.cards = cards ?? .shared
        self.diagnosticOrigin = diagnosticOrigin
    }

    // MARK: - Index

    /// The identity an index for this book should have right now.
    private func expectedIdentifier(for adapter: AIBookContentAdapter) -> String {
        AIBookRetrievalIndex.identifier(contentFingerprint: adapter.contentFingerprint)
    }

    /// Builds — or reuses — the index for an open book.
    func index(
        forBook bookID: UUID,
        adapter: AIBookContentAdapter
    ) async throws -> AIBookRetrievalIndex {
        try Task.checkCancellation()
        let indexStarted = Date()
        if AIDiagnostics.current == nil { activate(adapter) }
        guard latestSnapshots[bookID] == adapter.contentFingerprint else { throw CancellationError() }
        let expected = expectedIdentifier(for: adapter)
        indexState[bookID] = .building
        do {
            let index = try await store.index(for: bookID, expectedIdentifier: expected) {
                let chunks = AIPublicationChunker(
                    maximumCharacters: 800,
                    overlapCharacters: 120,
                    minimumCharacters: 200
                ).chunks(from: adapter)
                guard !chunks.isEmpty else { throw Failure.emptyBook }
                return AIBookRetrievalIndex(
                    bookID: bookID,
                    chunks: chunks,
                    sectionTitleByID: adapter.sectionTitleByID,
                    contentFingerprint: adapter.contentFingerprint,
                    manifest: adapter.manifest
                )
            }
            if latestSnapshots[bookID] == adapter.contentFingerprint {
                indexedChapterCounts[bookID] = Set(index.chunks.map { $0.start.spineIndex }).count
                indexState[bookID] = .ready(chunkCount: index.chunks.count)
            }
            AIDiagnostics.current?.event("indexReady", ["indexedChapters": "\(Set(index.chunks.map { $0.start.spineIndex }).count)",
                "elapsedMs": "\(Date().timeIntervalSince(indexStarted) * 1000)"])
            return index
        } catch {
            if latestSnapshots[bookID] == adapter.contentFingerprint { indexState[bookID] = .failed(error.localizedDescription) }
            throw error
        }
    }

    // MARK: - Use cases

    /// Answer a question about the book, limited to what the reader has already read.
    func answer(
        question: String,
        bookID: UUID,
        adapter: AIBookContentAdapter,
        progress: Double,
        boundary: AIReadingBoundary? = nil
    ) async throws -> LLMGenerationResult {
        let boundary = boundary ?? adapter.boundary()
        return try await answer(context: .init(bookID: bookID, question: question, source: adapter, boundary: boundary))
    }

    /// Resolves configuration and credentials before an asynchronous request starts.
    func freezeProvider(in context: AIQuestionContext) throws -> AIQuestionContext {
        var frozen = context
        if context.provider != nil { return context }
        if let injectedProvider { frozen.provider = injectedProvider; return frozen }
        let profiles = try AIProviderStore.shared.profiles()
        let profile: AIServiceProfile?
        if let id = context.serviceID { profile = profiles.first { $0.id == id } }
        else { profile = profiles.first { $0.id == AIProviderStore.shared.activeID } ?? profiles.first }
        guard let profile else { throw Failure.unavailable(.notConfigured) }
        frozen.serviceID = profile.id
        frozen.model = context.model ?? profile.configuration.defaultModel
        switch AIProviderAssembly.makeProvider(profile: profile, model: frozen.model) {
        case .success(let provider): frozen.provider = provider
        case .failure(let reason): throw Failure.unavailable(reason)
        }
        return frozen
    }

    func answer(context: AIQuestionContext,
                onStage: (@MainActor @Sendable (AIQuestionStage) -> Void)? = nil,
                onText: (@MainActor @Sendable (String) -> Void)? = nil) async throws -> LLMGenerationResult {
        try await traced("answer", adapter: context.source, boundary: context.boundary, requestID: context.requestID) {
            let frozen = try freezeProvider(in: context)
            guard let resolved = frozen.provider else { throw Failure.unavailable(.notConfigured) }
            let provider = AITracedProvider(base: resolved)
            let index = try await index(forBook: context.bookID, adapter: context.source)
            return try await AIAgenticAssistant.answerQuestion(context: frozen, index: index, provider: provider,
                onStage: onStage, onText: onText)
        }
    }

    /// A character card with an explicit, versioned scope selected by the reader.
    func characterCard(
        name: String,
        bookID: UUID,
        adapter: AIBookContentAdapter,
        boundary: AIReadingBoundary,
        onStep: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> AICharacterProfile {
        return try await traced("characterCard", adapter: adapter, boundary: boundary) {
            let provider = try resolveProvider()
            let index = try await index(forBook: bookID, adapter: adapter)
            let result = try await AIAgenticAssistant.run(
                task: AICharacterProfile.task(language: .current),
                userInput: name,
                index: index,
                provider: provider,
                scope: boundary.wholeBook ? 1 : adapter.progress(forSpine: boundary.spineIndex, charOffset: boundary.utf16Offset),
                boundary: boundary,
                maxSteps: 3,
                onStep: onStep
            )
            var profile = try AICharacterProfile.parse(
                fromAnswer: result.answer,
                name: name,
                gatheredChunkIDs: result.retrievedChunks.map(\.id),
                provider: result.provider,
                model: result.model,
                citedChunkIDs: result.citationChunkIDs
            )
            profile.sourceBoundary = boundary
            profile.retrievedEvidenceIDs = result.retrievedChunks.map(\.id)
            profile.maximumEvidencePosition = result.retrievedChunks.map(\.end).max {
                $0.spineIndex == $1.spineIndex ? $0.charOffset < $1.charOffset : $0.spineIndex < $1.spineIndex
            }
            try Task.checkCancellation()
            guard latestSnapshots[bookID] == adapter.contentFingerprint else { throw CancellationError() }
            AIDiagnostics.current?.event("characterParsing", ["result": "valid", "retrieved": "\(result.retrievedChunks.count)", "cited": "\(profile.citationChunkIDs.count)"])
            cards.upsert(profile, forBook: bookID)
            return profile
        }
    }

    // MARK: - Availability

    var isConfigured: Bool {
        injectedProvider != nil || AIProviderStore.shared.hasConfiguredProfile
    }

    private func traced<T>(_ feature: String, adapter: AIBookContentAdapter, boundary: AIReadingBoundary, requestID: UUID = UUID(), operation: () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        activate(adapter)
        let trace = AIDiagnosticStore.shared.begin(feature: feature, bookID: adapter.chunkBookID, adapter: adapter, boundary: boundary, origin: diagnosticOrigin, requestID: requestID)
        defer { AIDiagnosticStore.shared.finish(trace) }
        return try await AIDiagnostics.$current.withValue(trace) {
            do {
                guard boundary.sourceVersion == adapter.contentFingerprint else { throw CancellationError() }
                let result = try await operation()
                try Task.checkCancellation()
                guard latestSnapshots[adapter.chunkBookID] == adapter.contentFingerprint else { throw CancellationError() }
                trace.event("complete", ["result": "success"])
                return result
            } catch {
                trace.event("complete", ["result": error is CancellationError ? "cancelled" : "failed", "kind": String(describing: type(of: error))])
                throw error
            }
        }
    }

    private func resolveProvider() throws -> any LLMProviding {
        if let injectedProvider { return AITracedProvider(base: injectedProvider) }
        switch AIProviderAssembly.makeProvider() {
        case let .success(provider): return AITracedProvider(base: provider)
        case let .failure(reason): throw Failure.unavailable(reason)
        }
    }
}


struct AIBookCharactersSnapshot {
    var memory = AIMemoryView(cards: [], aliases: [], approvedAliasIDs: [])
    var profiles: [AICharacterProfile] = []
}

extension AIAssistantService {
    func characters(source: AIBookContentAdapter) async throws -> AIBookCharactersSnapshot {
        cards.loadIfNeeded(forBook: source.chunkBookID)
        try await AICharacterMemoryService.shared.load(source: source)
        let memory = try await AICharacterMemoryService.shared.view(source: source, boundary: source.boundary())
        return .init(memory: memory, profiles: cards.profiles(forBook: source.chunkBookID).filter { $0.isSafe(at: source.boundary()) })
    }
}
