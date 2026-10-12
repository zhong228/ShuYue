import Combine
import Foundation

/// One AI 查詞 request and its streamed answer. Owned by the card: closing the card cancels
/// the request.
@MainActor
final class AIWordLookupModel: ObservableObject {
    enum State: Equatable {
        case idle
        case streaming(String)
        case finished(String)
        case failed(String)
        /// No usable AI service. The card offers the settings instead of a retry.
        case unavailable(String)
    }

    let term: String
    let context: String
    let bookTitle: String?
    let bookID: UUID
    let language: AIAnswerLanguage
    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?
    private let injectedProvider: (any LLMProviding)?
    private let origin: AIDiagnostics.Origin

    init(term: String, context: String, bookTitle: String?, bookID: UUID, language: AIAnswerLanguage = .current,
         provider: (any LLMProviding)? = nil, origin: AIDiagnostics.Origin = .observed) {
        self.term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        self.context = context
        self.bookTitle = bookTitle
        self.bookID = bookID
        self.language = language
        injectedProvider = provider
        self.origin = origin
    }

    var answer: String? {
        switch state {
        case let .streaming(text), let .finished(text): return text.isEmpty ? nil : text
        default: return nil
        }
    }

    func start() {
        task?.cancel()
        let base: any LLMProviding
        if let injectedProvider {
            base = injectedProvider
        } else {
            switch AIProviderAssembly.makeProvider() {
            case let .success(provider): base = provider
            case let .failure(reason):
                state = .unavailable(reason.message)
                return
            }
        }
        let request = AIWordLookup.request(term: term, context: context, bookTitle: bookTitle, language: language)
        let provider = AITracedProvider(base: base)
        let trace = AIDiagnosticStore.shared.begin(feature: "wordLookup", bookID: bookID, origin: origin)
        trace.event("wordLookup", ["promptVersion": AIWordLookup.promptVersion, "termCharacters": "\(term.count)",
                                   "contextCharacters": "\(context.count)", "language": language.rawValue])
        state = .streaming("")
        task = Task { [weak self] in
            defer { AIDiagnosticStore.shared.finish(trace) }
            var text = ""
            do {
                let stream = AIDiagnostics.$current.withValue(trace) { provider.stream(request) }
                for try await delta in stream {
                    text += delta
                    self?.state = .streaming(text)
                }
                try Task.checkCancellation()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LLMError.emptyOutput }
                self?.state = .finished(text)
            } catch is CancellationError {
                return
            } catch {
                AppLogger.error("AI word lookup failed", error: error, context: ["characters": text.count])
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Lets tests wait for the answer instead of polling.
    func wait() async { await task?.value }
}
