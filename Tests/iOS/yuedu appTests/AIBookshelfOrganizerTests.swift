import Foundation
import Testing
@testable import yuedu_app

@Suite("AI bookshelf organizer")
struct AIBookshelfOrganizerTests {

    private func book(_ title: String, group: String = "", intro: String? = nil) -> AIBookshelfOrganizer.Book {
        AIBookshelfOrganizer.Book(id: UUID(), title: title, author: "作者", group: group, intro: intro)
    }

    private func raw(_ json: String) -> LLMRawResponse {
        .init(content: json, provider: "fake", model: "fake", finishReason: "stop")
    }

    @Test("the ungrouped scope skips books that already have a group; batches cap the request size")
    func scopeAndBatches() {
        let shelf = [book("甲"), book("乙", group: "玄幻"), book("丙", group: "  ")]
        #expect(AIBookshelfOrganizer.books(shelf, in: .ungrouped).map(\.title) == ["甲", "丙"])
        #expect(AIBookshelfOrganizer.books(shelf, in: .all).count == 3)
        let many = (0..<130).map { book("書\($0)") }
        #expect(AIBookshelfOrganizer.batches(many).map(\.count) == [60, 60, 10])
    }

    @Test("the request names books by position, never by library identifier, and trims long blurbs")
    func requestPayload() throws {
        let long = String(repeating: "簡", count: 400)
        let books = [book("萬古神帝", intro: long), book("三體", group: "科幻")]
        let request = try AIBookshelfOrganizer.request(books: books, existingGroups: ["科幻"], language: .traditionalChinese)
        let payload = request.messages[1].content
        #expect(payload.contains("\"id\":\"b1\"") && payload.contains("\"id\":\"b2\""))
        #expect(!payload.contains(books[0].id.uuidString))
        #expect(payload.contains("\"existingGroups\":[\"科幻\"]"))
        #expect(payload.contains("\"currentGroup\":\"科幻\""))
        #expect(!payload.contains(String(repeating: "簡", count: AIBookshelfOrganizer.introCharacters + 1)))
        #expect(request.messages[0].content.contains("用繁體中文"))
    }

    @Test("an answer maps books to groups; unsure and omitted books stay where they are")
    func parseAssignments() throws {
        let books = [book("甲"), book("乙"), book("丙")]
        let parsed = try AIBookshelfOrganizer.parse(raw("```json\n{\"assignments\":[{\"id\":\"b1\",\"group\":\"「玄幻」\"}],\"unsure\":[\"b2\"]}\n```"), books: books)
        #expect(parsed == [books[0].id: "玄幻"])
    }

    @Test("unknown or repeated books and unusable group names make the answer malformed")
    func parseRejectsMalformedAnswers() {
        let books = [book("甲"), book("乙")]
        let malformed = [
            "{\"assignments\":[{\"id\":\"b9\",\"group\":\"玄幻\"}]}",
            "{\"assignments\":[{\"id\":\"b1\",\"group\":\"玄幻\"},{\"id\":\"b1\",\"group\":\"都市\"}]}",
            "{\"assignments\":[{\"id\":\"b1\",\"group\":\"玄幻\"}],\"unsure\":[\"b1\"]}",
            "{\"assignments\":[{\"id\":\"b1\",\"group\":\"  \"}]}",
            "{\"assignments\":[{\"id\":\"b1\",\"group\":\"\(String(repeating: "長", count: 21))\"}]}",
            "分組如下：玄幻",
        ]
        for answer in malformed {
            #expect(throws: AIBookshelfOrganizer.Failure.invalidSchema) { try AIBookshelfOrganizer.parse(raw(answer), books: books) }
        }
    }

    @Test("a name matching an existing group apart from case or width keeps the shelf's spelling")
    func canonicalNames() {
        #expect(AIBookshelfOrganizer.canonical("sci-fi", existing: ["Sci-Fi"]) == "Sci-Fi")
        #expect(AIBookshelfOrganizer.canonical("ＳＦ", existing: ["SF"]) == "SF")
        #expect(AIBookshelfOrganizer.canonical("都市", existing: ["SF"]) == "都市")
    }

    @Test("the proposal lists only books that would move, biggest groups first, and applies only what is on")
    func proposalReview() {
        let a = book("甲"), b = book("乙", group: "玄幻"), c = book("丙"), d = book("丁"), e = book("戊")
        var proposal = AIBookshelfProposal(books: [a, b, c, d, e],
            assignments: [a.id: "都市", b.id: "玄幻", c.id: "科幻", d.id: "科幻"], existingGroups: ["玄幻"])
        #expect(proposal.groups.map(\.name) == ["科幻", "都市"])
        #expect(proposal.unchangedCount == 1)
        #expect(proposal.unassignedCount == 1)
        #expect(proposal.includedCount == 3)

        proposal.groups[0].moves[1].isIncluded = false
        proposal.groups[1].name = " 科幻 "
        #expect(proposal.assignments == [c.id: "科幻", a.id: "科幻"])

        proposal.groups[1].name = ""
        #expect(!proposal.canApply)
    }

    @Test @MainActor func laterBatchesReuseTheGroupsEarlierOnesChose() async throws {
        let books = (0..<(AIBookshelfOrganizer.batchSize + 1)).map { book("書\($0)") }
        let provider = ShelfProvider()
        let model = AIBookshelfOrganizerModel(provider: provider, origin: .testFixture, language: .traditionalChinese)
        model.start(books: books, existingGroups: ["科幻"])
        await model.wait()
        #expect(model.phase == .review)
        let requests = await provider.requests
        #expect(requests.count == 2)
        #expect(requests[1].contains("\"existingGroups\":[\"科幻\",\"玄幻\"]"))
        let proposal = try #require(model.proposal)
        #expect(proposal.groups.map(\.name) == ["玄幻"])
        #expect(proposal.includedCount == books.count)
    }

    /// Puts every book in 玄幻, spelled differently in the second batch.
    private actor ShelfProvider: LLMProviding {
        let identifier = "shelf-fixture"
        let defaultModel = "fixture"
        private(set) var requests: [String] = []

        func generate(_ request: LLMGenerationRequest, model: String?) async throws -> LLMRawResponse {
            let payload = request.messages.last?.content ?? ""
            requests.append(payload)
            let data = try #require(payload.data(using: .utf8))
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let items = (object?["books"] as? [[String: Any]]) ?? []
            let name = requests.count == 1 ? "玄幻" : "「玄幻」"
            let assignments = items.compactMap { $0["id"] as? String }.map { ["id": $0, "group": name] }
            let json = try JSONSerialization.data(withJSONObject: ["assignments": assignments])
            return .init(content: String(decoding: json, as: UTF8.self), provider: identifier, model: defaultModel, finishReason: "stop")
        }

        nonisolated func stream(_ request: LLMGenerationRequest, model: String?) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }
}
