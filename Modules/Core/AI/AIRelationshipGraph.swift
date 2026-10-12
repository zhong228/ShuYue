import Foundation

/// Who is related to whom, from the relationship facts in the reader's character records.
///
/// Only facts of kind `.relationship` that name two or more characters become edges; each keeps
/// its source fact so the reader can check it. Built from an `AIMemoryView` that is already
/// limited to the reading boundary, so the graph never shows more than has been read.
struct AIRelationshipGraph: Equatable, Sendable {
    struct Node: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        /// What `AIMemoryCardView` looks the character up by.
        let entityID: String
    }

    struct Edge: Identifiable, Equatable, Sendable {
        let id: String
        let first: String
        let second: String
        let text: String
        /// Chapter of the fact's first evidence, for ordering and display.
        let chapter: Int?

        func other(than node: String) -> String? {
            first == node ? second : second == node ? first : nil
        }
    }

    struct Neighbor: Identifiable, Equatable, Sendable {
        let node: Node
        let relations: [Edge]
        var id: String { node.id }
    }

    let nodes: [Node]
    let edges: [Edge]

    init(view: AIMemoryView) {
        var owner: [String: String] = [:]
        for card in view.cards {
            for entity in card.entityIDs { owner[entity] = card.id }
        }
        var edges: [Edge] = []
        var seen = Set<String>()
        for card in view.cards {
            for fact in card.facts where fact.kind == .relationship && seen.insert(fact.id).inserted {
                var cards: [String] = []
                for entity in fact.entities {
                    if let id = owner[entity], !cards.contains(id) { cards.append(id) }
                }
                guard let first = cards.first else { continue }
                for second in cards.dropFirst() {
                    edges.append(Edge(id: "\(fact.id):\(second)", first: first, second: second,
                                      text: fact.text, chapter: fact.evidence.first?.span.spine))
                }
            }
        }
        let connected = Set(edges.flatMap { [$0.first, $0.second] })
        nodes = view.cards.filter { connected.contains($0.id) }
            .map { Node(id: $0.id, name: $0.names.first ?? $0.id, entityID: $0.entityIDs.sorted().first ?? $0.id) }
        self.edges = edges
    }

    init(nodes: [Node], edges: [Edge]) {
        self.nodes = nodes
        self.edges = edges
    }

    func node(_ id: String) -> Node? { nodes.first { $0.id == id } }

    /// The best-connected character: where the map opens.
    var hub: Node? {
        var best: (node: Node, degree: Int)?
        for node in nodes {
            let count = degree(of: node.id)
            if let current = best, current.degree > count || (current.degree == count && current.node.name <= node.name) { continue }
            best = (node, count)
        }
        return best?.node
    }

    func degree(of id: String) -> Int { edges.filter { $0.first == id || $0.second == id }.count }

    /// Characters related to `id`, most relations first, each with its relations in reading order.
    func neighbors(of id: String) -> [Neighbor] {
        var grouped: [String: [Edge]] = [:]
        for edge in edges {
            guard let other = edge.other(than: id) else { continue }
            grouped[other, default: []].append(edge)
        }
        return grouped.compactMap { otherID, relations in
            node(otherID).map { Neighbor(node: $0, relations: relations.sorted { ($0.chapter ?? .max) < ($1.chapter ?? .max) }) }
        }
        .sorted { $0.relations.count == $1.relations.count ? $0.node.name < $1.node.name : $0.relations.count > $1.relations.count }
    }
}
