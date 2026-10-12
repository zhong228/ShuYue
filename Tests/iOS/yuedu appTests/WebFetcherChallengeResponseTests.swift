import Foundation
import Testing
@testable import yuedu_app

/// A Cloudflare response is just a response, as in Legado: the fetcher neither opens a
/// verification page nor retries. It used to take every 403/503 — Cloudflare or not — for a
/// challenge and open a full-screen page from background work such as 書源驗證.
@Suite("WebFetcher challenge responses", .serialized)
struct WebFetcherChallengeResponseTests {
    private static let challengeHTML = """
        <html><head><title>Just a moment...</title>
        <script>window._cf_chl_opt = { cType: 'managed' };</script></head>
        <body><div id="cf-challenge-running"></div></body></html>
        """

    @Test("a 403 challenge is an HTTP error, answered once")
    func challengeStatusIsAnHTTPError() async throws {
        ChallengeURLProtocol.respond(status: 403, body: Self.challengeHTML)
        let fetcher = WebFetcher(session: ChallengeURLProtocol.session())
        let url = try #require(URL(string: "https://challenge-\(UUID().uuidString.prefix(8).lowercased()).example.com/book"))

        do {
            _ = try await fetcher.fetchHTML(
                url: url, method: "GET", body: nil, headers: [:], baseURL: url.absoluteString)
            Issue.record("a 403 must not come back as a page")
        } catch let error as FetchError {
            guard case .httpError(let status) = error else {
                Issue.record("expected httpError(403), got \(error)")
                return
            }
            #expect(status == 403)
        }
        #expect(ChallengeURLProtocol.requestCount == 1, "no retry behind the caller's back")
    }

    @Test("a 200 page carrying challenge markers comes back as the site sent it")
    func challengeBodyIsReturned() async throws {
        ChallengeURLProtocol.respond(status: 200, body: Self.challengeHTML)
        let fetcher = WebFetcher(session: ChallengeURLProtocol.session())
        let url = try #require(URL(string: "https://challenge-\(UUID().uuidString.prefix(8).lowercased()).example.com/toc"))

        let html = try await fetcher.fetchHTML(
            url: url, method: "GET", body: nil, headers: [:], baseURL: url.absoluteString)

        #expect(html.contains("_cf_chl_opt"))
        #expect(ChallengeURLProtocol.requestCount == 1)
    }
}

private final class ChallengeURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = ""
    nonisolated(unsafe) private static var requests = 0

    static func respond(status: Int, body: String) {
        lock.lock()
        self.status = status
        self.body = body
        requests = 0
        lock.unlock()
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChallengeURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        let status = Self.status
        let body = Self.body
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
