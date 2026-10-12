import Testing
@testable import yuedu_app

struct BookCoverLoaderHeaderTests {
    @Test("a source named instead of addressed sends no Referer")
    func nonURLBaseSendsNoReferer() {
        // 📚书山聚合's bookSourceUrl is `书山聚合`; byteimg answers that Referer with 403.
        let headers = BookCoverLoader.headers(sourceBaseURL: "书山聚合", sourceHeaders: [:])
        #expect(headers["Referer"] == nil)
        #expect(headers["User-Agent"] != nil)
    }

    @Test("an http(s) source URL is still sent as the Referer")
    func httpBaseIsReferer() {
        let headers = BookCoverLoader.headers(sourceBaseURL: "https://www.example.com", sourceHeaders: [:])
        #expect(headers["Referer"] == "https://www.example.com")
    }

    @Test("the source's own header rule wins over the defaults")
    func sourceHeadersOverride() {
        let headers = BookCoverLoader.headers(
            sourceBaseURL: "https://www.example.com",
            sourceHeaders: ["Referer": "https://cdn.example.com/", "User-Agent": "Custom"]
        )
        #expect(headers["Referer"] == "https://cdn.example.com/")
        #expect(headers["User-Agent"] == "Custom")
    }
}
