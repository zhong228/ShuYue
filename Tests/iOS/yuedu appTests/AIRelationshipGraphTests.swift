import Foundation
import Testing
@testable import yuedu_app

@Suite("AI character relationship map")
struct AIRelationshipGraphTests {

    private func evidence(_ spine: Int) -> AIMemoryEvidence {
        AIMemoryEvidence(id: "e\(spine)", segmentID: "s0", unitID: "u0",
            span: AIMemorySpan(sectionID: "c\(spine)", chapterDigest: "d", transformation: "t", spine: spine, start: 0, end: 2),
            quote: "原文")
    }

    private func fact(_ id: String, _ kind: AIMemoryFact.Kind, _ entities: [String], _ text: String, chapter: Int) -> AIMemoryFact {
        AIMemoryFact(id: id, entities: entities, kind: kind, text: text, evidence: [evidence(chapter)],
                     safeAfter: AIMemoryPosition(spine: chapter, utf16: 2))
    }

    private func card(_ id: String, _ names: [String], entities: Set<String>, facts: [AIMemoryFact]) -> AIMemoryCard {
        AIMemoryCard(id: id, entityIDs: entities, names: names, mentions: [], facts: facts, aliases: [])
    }

    /// 張若塵 is related to 池瑤 twice and to 雲武郡王 once; 閒人 only has a narration fact.
    private var view: AIMemoryView {
        let marriage = fact("f1", .relationship, ["m1", "m2"], "張若塵與池瑤曾有婚約", chapter: 3)
        let rivals = fact("f2", .relationship, ["m2", "m1"], "池瑤與張若塵成為對手", chapter: 9)
        let father = fact("f3", .relationship, ["m1", "m3"], "雲武郡王是張若塵的父親", chapter: 1)
        let narration = fact("f4", .narration, ["m1", "m4"], "張若塵路過閒人身邊", chapter: 2)
        return AIMemoryView(cards: [
            card("A", ["張若塵", "若塵"], entities: ["m1", "m1b"], facts: [marriage, rivals, father, narration]),
            card("B", ["池瑤"], entities: ["m2"], facts: [marriage, rivals]),
            card("C", ["雲武郡王"], entities: ["m3"], facts: [father]),
            card("D", ["閒人"], entities: ["m4"], facts: [narration]),
        ], aliases: [], approvedAliasIDs: [])
    }

    @Test("only relationship facts become edges, once each, between different characters")
    func relationshipFactsBecomeEdges() {
        let graph = AIRelationshipGraph(view: view)
        #expect(graph.edges.count == 3)
        #expect(Set(graph.nodes.map(\.id)) == ["A", "B", "C"])
        #expect(graph.node("A")?.entityID == "m1")
    }

    @Test("the map opens on the best-connected character, with neighbours ordered by how related they are")
    func hubAndNeighbours() {
        let graph = AIRelationshipGraph(view: view)
        #expect(graph.hub?.id == "A")
        let neighbours = graph.neighbors(of: "A")
        #expect(neighbours.map(\.node.name) == ["池瑤", "雲武郡王"])
        #expect(neighbours[0].relations.map(\.chapter) == [3, 9])
        #expect(graph.neighbors(of: "C").map(\.node.name) == ["張若塵"])
    }

    @Test("a view without relationship facts draws nothing")
    func noRelationsNoMap() {
        let graph = AIRelationshipGraph(view: AIMemoryView(cards: [
            card("D", ["閒人"], entities: ["m4"], facts: [fact("f4", .narration, ["m4"], "閒人走過", chapter: 0)]),
        ], aliases: [], approvedAliasIDs: []))
        #expect(graph.nodes.isEmpty)
        #expect(graph.hub == nil)
    }
}
