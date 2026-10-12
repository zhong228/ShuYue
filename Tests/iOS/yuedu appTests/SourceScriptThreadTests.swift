import Foundation
import Testing
@testable import yuedu_app

/// Source JS can stop for the reader (`java.startBrowserAwait`) for as long as the reader
/// takes. Scripts reached from async code run on `SourceScriptThread`, so while many of them
/// wait, Swift's concurrency pool — as wide as the CPU — stays free for everything else.
/// Before, each waiting source held one of those threads: a handful waiting at once froze
/// every other async task in the app.
@Suite("Source scripts waiting for the reader", .serialized)
struct SourceScriptThreadTests {
    @Test("two dozen sources waiting on a verification page leave the concurrency pool free")
    func waitingScriptsDoNotHoldConcurrencyThreads() async throws {
        let waiting = 24
        let pages = PendingPages()
        let previous = LegadoJSBridge.sharedBrowserPresenter
        LegadoJSBridge.sharedBrowserPresenter = { _, completion in pages.add(completion) }
        defer { LegadoJSBridge.sharedBrowserPresenter = previous }
        // Should the pool starve after all, release the pages from a GCD thread so the test
        // fails on its expectations instead of hanging.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { pages.releaseAll() }

        WaitingSourceProtocol.body = "<p>page</p>"
        let fetcher = BookSourceFetcher(webFetcher: WebFetcher(session: WaitingSourceProtocol.session()))
        let sources = (0..<waiting).map { index -> BookSource in
            var source = BookSource(
                bookSourceUrl: "https://waiting-\(index)-\(UUID().uuidString.prefix(6).lowercased()).example",
                bookSourceName: "waiting source \(index)"
            )
            // A Cloudflare-style check: the source opens a page and waits for the reader.
            source.loginCheckJs = "java.startBrowserAwait('https://verify.example/', '驗證', false); result"
            return source
        }
        let stages = sources.map { source in
            Task {
                try await fetcher.fetchStageHTML(
                    url: URL(string: source.bookSourceUrl + "/search")!,
                    method: "GET", body: nil, headers: [:],
                    baseURL: source.bookSourceUrl, source: source)
            }
        }

        let deadline = Date().addingTimeInterval(20)
        while pages.count < waiting, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(pages.count == waiting, "every source should be waiting on its page")

        let probeStarted = Date()
        let answer = await Task.detached { 6 * 7 }.value
        let probeSeconds = Date().timeIntervalSince(probeStarted)
        #expect(answer == 42)
        #expect(probeSeconds < 1, "other async work waited \(probeSeconds) s for a thread")

        pages.releaseAll()
        for stage in stages {
            #expect(try await stage.value == "<p>page</p>")
        }
    }
}

private final class PendingPages: @unchecked Sendable {
    private let lock = NSLock()
    private var completions: [(String?) -> Void] = []

    func add(_ completion: @escaping (String?) -> Void) {
        lock.lock()
        completions.append(completion)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return completions.count
    }

    func releaseAll() {
        lock.lock()
        let pending = completions
        completions = []
        lock.unlock()
        pending.forEach { $0("<html>verified</html>") }
    }
}

private final class WaitingSourceProtocol: URLProtocol {
    nonisolated(unsafe) static var body = ""

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WaitingSourceProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
