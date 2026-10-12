import Foundation

// MARK: - Media Content Session
//
// iOS hard-caps `URLSession.shared` at 6 connections per host. Book sources
// (WebFetcher / LegadoJSBridge.requestSession) already run at 16/host, which is
// why source HTML loads fine while every media path that still used
// `URLSession.shared` — book covers, chapter illustrations, audiobook streams,
// TTS audio, manga pages, offline downloads, favicons — stalled and timed out
// once a shelf or a chapter had more than six in-flight requests to one site.
//
// This is the shared session every media/asset load should go through. It keeps
// the same 16-connections-per-host budget the crawler uses and sane default
// timeouts. Call sites that must fail fast (inline illustrations inside a
// sequentially-rendered chapter) still set `URLRequest.timeoutInterval`, which
// overrides the session-level request timeout.

enum MediaSession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 16
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024
        )
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()

    /// One request with transient-network retry (timeout, connection lost,
    /// DNS failure, …) on top of the shared media session. Use for loads where
    /// a transient failure is visible to the user (covers, search, downloads).
    static func dataWithRetry(
        for request: URLRequest,
        policy: FetchRetryPolicy = FetchRetryPolicy(
            maxAttempts: 3, baseDelay: 0.8, maxDelay: 12
        )
    ) async throws -> (Data, URLResponse) {
        try await policy.execute {
            try await shared.data(for: request)
        }
    }
}