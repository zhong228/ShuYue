import Foundation
import Testing
import WebKit
@testable import yuedu_app

/// The verification page `java.startBrowserAwait` opens finishes itself the way Legado-E and
/// MD3 do: every finished page is asked `!!window._cf_chl_opt`, and the first page after a
/// challenge that no longer defines it completes the verification.
@Suite(.serialized)
@MainActor
struct SourceBrowserChallengeTests {
    private static let challengePage = """
        <html><head><script>window._cf_chl_opt = { cType: 'managed' };</script></head>
        <body>Just a moment...</body></html>
        """
    private static let contentPage = "<html><body><p>第一章</p></body></html>"

    @Test("a page that stops being a Cloudflare challenge finishes the verification")
    func clearedChallengeFinishesThePage() async throws {
        let (webView, coordinator, bridge) = makeBrowser(finishesWhenChallengeClears: true)

        webView.loadHTMLString(Self.challengePage, baseURL: URL(string: "https://source.example/"))
        #expect(await waitUntil { coordinator.sawChallenge }, "the challenge page should be recognised")
        #expect(!bridge.challengeCleared)

        webView.loadHTMLString(Self.contentPage, baseURL: URL(string: "https://source.example/"))
        #expect(await waitUntil { bridge.challengeCleared }, "clearing the challenge should finish the page")
    }

    @Test("an ordinary page never finishes by itself")
    func ordinaryPageStaysOpen() async throws {
        let (webView, coordinator, bridge) = makeBrowser(finishesWhenChallengeClears: true)

        webView.loadHTMLString(Self.contentPage, baseURL: URL(string: "https://source.example/"))
        #expect(await waitUntil { bridge.phase == .finished })
        webView.loadHTMLString(Self.contentPage, baseURL: URL(string: "https://source.example/2"))
        #expect(await waitUntil { bridge.phase == .finished })
        // Give the second page's check the same chance to (wrongly) fire.
        #expect(await !waitUntil(timeout: 1) { bridge.challengeCleared })
        #expect(!coordinator.sawChallenge)
    }

    @Test("a page opened without awaiting a result is not watched")
    func unwatchedPageIgnoresChallenges() async throws {
        let (webView, coordinator, bridge) = makeBrowser(finishesWhenChallengeClears: false)

        webView.loadHTMLString(Self.challengePage, baseURL: URL(string: "https://source.example/"))
        #expect(await waitUntil { bridge.phase == .finished })
        webView.loadHTMLString(Self.contentPage, baseURL: URL(string: "https://source.example/"))
        #expect(await waitUntil { bridge.phase == .finished })
        #expect(await !waitUntil(timeout: 1) { bridge.challengeCleared })
        #expect(!coordinator.sawChallenge)
    }

    private func makeBrowser(
        finishesWhenChallengeClears: Bool
    ) -> (WKWebView, JsBridgeBrowserRepresentable.Coordinator, JsBridgeBrowserBridge) {
        let bridge = JsBridgeBrowserBridge()
        let coordinator = JsBridgeBrowserRepresentable.Coordinator()
        coordinator.bridge = bridge
        coordinator.finishesWhenChallengeClears = finishesWhenChallengeClears
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        // `navigationDelegate` is weak: each test keeps `coordinator` alive itself.
        webView.navigationDelegate = coordinator
        coordinator.webView = webView
        return (webView, coordinator, bridge)
    }

    /// Polls `condition` on the main actor until it holds or `timeout` passes.
    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
