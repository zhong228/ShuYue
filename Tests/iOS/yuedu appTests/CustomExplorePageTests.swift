import Foundation
import Testing
@testable import yuedu_app

@MainActor
struct CustomExplorePageTests {
    private static func reference(_ title: String, source: String = "https://a.example") -> ExploreCategoryReference {
        ExploreCategoryReference(sourceURL: source, title: title, url: "/\(title)")
    }

    private static func component(_ kind: CustomExploreComponent.Kind, _ titles: String...) -> CustomExploreComponent {
        CustomExploreComponent(kind: kind, categories: titles.map { reference($0) })
    }

    private static func temporaryStore() -> (CustomExplorePageStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("custom-explore-\(UUID().uuidString).json")
        return (CustomExplorePageStore(fileURL: url), url)
    }

    @Test("a new page takes its name; a blank or taken name gets the default or a number")
    func pageNames() {
        let (store, url) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(store.createPage(named: "  男頻  ").name == "男頻")
        #expect(store.createPage(named: "男頻").name == "男頻 2")
        let blank = store.createPage(named: " ").name
        #expect(!blank.isEmpty)
        #expect(store.createPage(named: "").name == "\(blank) 2")

        let page = store.pages[0]
        store.renamePage(id: page.id, to: "   ")
        #expect(store.page(id: page.id)?.name == "男頻")
        store.renamePage(id: page.id, to: " 女頻 ")
        #expect(store.page(id: page.id)?.name == "女頻")

        store.deletePage(id: page.id)
        #expect(store.page(id: page.id) == nil)
        #expect(store.pages.count == 3)
    }

    @Test("blocks go in before the waterfall, which stays last and alone")
    func waterfallStaysLast() {
        let waterfall = Self.component(.waterfall, "瀑布")
        var components = CustomExplorePage.saving(Self.component(.featuredCards, "推薦"), into: [])
        components = CustomExplorePage.saving(waterfall, into: components)
        components = CustomExplorePage.saving(Self.component(.ranking, "排行"), into: components)
        #expect(components.map(\.kind) == [.featuredCards, .ranking, .waterfall])

        // A second waterfall is not added.
        components = CustomExplorePage.saving(Self.component(.waterfall, "又一個"), into: components)
        #expect(components.filter { $0.kind == .waterfall }.map(\.id) == [waterfall.id])

        // Saving a block again keeps its place.
        var changed = components[0]
        changed.title = "換個標題"
        components = CustomExplorePage.saving(changed, into: components)
        #expect(components.map(\.id) == [changed.id, components[1].id, waterfall.id])
        #expect(components[0].title == "換個標題")

        // Dragging a block below the waterfall leaves the waterfall last.
        let moved = CustomExplorePage.moving(components, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(moved.map(\.kind) == [.ranking, .featuredCards, .waterfall])
        // So does dragging the waterfall up.
        let raised = CustomExplorePage.moving(components, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(raised.map(\.kind) == [.featuredCards, .ranking, .waterfall])
    }

    @Test("多分類排行榜 needs two categories of one source; the others need one")
    func completeness() {
        #expect(!CustomExploreComponent(kind: .featuredCards, categories: []).isComplete)
        #expect(Self.component(.featuredCards, "推薦").isComplete)
        #expect(!Self.component(.multiCategoryRanking, "都市").isComplete)
        #expect(Self.component(.multiCategoryRanking, "都市", "玄幻").isComplete)
        let mixed = CustomExploreComponent(
            kind: .multiCategoryRanking,
            categories: [Self.reference("都市"), Self.reference("玄幻", source: "https://b.example")]
        )
        #expect(!mixed.isComplete)

        // A block without a title of its own reads its category's.
        #expect(Self.component(.ranking, "黑馬榜").displayTitle == "黑馬榜")
        var titled = Self.component(.ranking, "黑馬榜")
        titled.title = "  本週黑馬  "
        #expect(titled.displayTitle == "本週黑馬")
    }

    @Test("加入自訂頁 adds the category as a 推薦卡片 block before the waterfall")
    func addCategory() {
        let (store, url) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let page = store.createPage(named: "我的")
        store.saveComponent(Self.component(.waterfall, "瀑布"), inPage: page.id)

        let reference = Self.reference("巔峰榜")
        #expect(!store.page(page.id, contains: reference))
        store.addCategory(reference, toPage: page.id)
        #expect(store.page(page.id, contains: reference))
        let components = store.page(id: page.id)?.components ?? []
        #expect(components.map(\.kind) == [.featuredCards, .waterfall])
        #expect(components.first?.categories == [reference])
    }

    @Test("pages and their blocks are there in the next session")
    func persistence() {
        let (store, url) = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let page = store.createPage(named: "男頻")
        store.saveComponent(Self.component(.multiCategoryRanking, "都市", "玄幻"), inPage: page.id)
        store.saveComponent(Self.component(.grid, "黑馬榜"), inPage: page.id)
        store.removeComponents(atOffsets: IndexSet(integer: 0), inPage: page.id)

        let next = CustomExplorePageStore(fileURL: url)
        #expect(next.pages == store.pages)
        #expect(next.page(id: page.id)?.components.map(\.kind) == [.grid])
    }
}
