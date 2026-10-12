import Foundation
import SwiftUI
import Testing
@testable import yuedu_app

struct ExploreHomeLogicTests {
    @Test("探索's search keeps the sources whose name or group holds the text, within the chosen group")
    func searchNarrowsSources() {
        func source(_ name: String, group: String) -> BookSource {
            var source = BookSource(bookSourceUrl: "https://\(UUID().uuidString).example", bookSourceName: name)
            source.bookSourceGroup = group
            return source
        }
        let fanqie = source("🍅番茄小说", group: "男频, 精品")
        let qidian = source("起点中文网", group: "男频")
        let jjwxc = source("JJWXC 晋江", group: "女频")
        let all = [fanqie, qidian, jjwxc]
        func names(_ group: String?, _ query: String) -> [String] {
            ExploreHomeView.sources(all, inGroup: group, matching: query).map(\.bookSourceName)
        }

        #expect(names(nil, "") == ["🍅番茄小说", "起点中文网", "JJWXC 晋江"])
        #expect(names(nil, "番茄") == ["🍅番茄小说"])
        // A group's name finds its sources, as Legado's `flowExplore(key)` does.
        #expect(names(nil, "精品") == ["🍅番茄小说"])
        #expect(names(nil, "jjwxc") == ["JJWXC 晋江"])
        #expect(names("男频", "") == ["🍅番茄小说", "起点中文网"])
        #expect(names("男频", "晋江").isEmpty)
    }

    @Test("a source name's leading emoji becomes its tile's picture, the rest its name")
    func splitsLeadingEmoji() {
        #expect(ExploreEntryLabel.splitLeadingEmoji("📚书山聚合") == ("📚", "书山聚合"))
        #expect(ExploreEntryLabel.splitLeadingEmoji("☀️ 光遇聚合(26.9.29)") == ("☀️", "光遇聚合(26.9.29)"))
        #expect(ExploreEntryLabel.splitLeadingEmoji("番茄小说") == (nil, "番茄小说"))
        // A digit is an emoji only as a keycap, and a name that is only an emoji keeps it.
        #expect(ExploreEntryLabel.splitLeadingEmoji("1号书源") == (nil, "1号书源"))
        #expect(ExploreEntryLabel.splitLeadingEmoji("📚") == (nil, "📚"))
    }

    @Test("the grid keeps the chosen tiles to a row until the text grows too large for them")
    func gridDensityFollowsTextSize() {
        #expect(ExploreGridDensity.fitting(4, dynamicTypeSize: .large) == .four)
        #expect(ExploreGridDensity.fitting(3, dynamicTypeSize: .xSmall) == .three)
        #expect(ExploreGridDensity.fitting(4, dynamicTypeSize: .xLarge) == .three)
        #expect(ExploreGridDensity.fitting(2, dynamicTypeSize: .xLarge) == .two)
        #expect(ExploreGridDensity.fitting(4, dynamicTypeSize: .xxxLarge) == .two)
        // A value no menu offers, from an older or hand-edited preference.
        #expect(ExploreGridDensity.fitting(7, dynamicTypeSize: .large) == .default)
    }
}
