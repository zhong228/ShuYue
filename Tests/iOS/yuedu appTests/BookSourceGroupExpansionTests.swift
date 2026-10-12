import Foundation
import Testing
@testable import yuedu_app

@Suite("Book source group expansion persistence")
@MainActor
struct BookSourceGroupExpansionTests {
    @Test("collapsed and expanded choices survive reopening with a fresh defaults instance")
    func choicesSurviveReopening() throws {
        let suite = "BookSourceGroupExpansionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let original = BookSourceGroupExpansionStore(defaults: defaults)
        #expect(original.isExpanded("小說"))
        original.toggle("小說")
        original.toggle("漫畫")

        let reopened = BookSourceGroupExpansionStore(
            defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(!reopened.isExpanded("小說"))
        #expect(!reopened.isExpanded("漫畫"))
        #expect(reopened.isExpanded("新匯入分組"))
        reopened.toggle("小說")

        let relaunched = BookSourceGroupExpansionStore(
            defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(relaunched.isExpanded("小說"))
        #expect(!relaunched.isExpanded("漫畫"))
    }

    @Test("default and pin groups persist independently of display language")
    func builtInGroupsPersist() throws {
        let suite = "BookSourceGroupExpansionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let original = BookSourceGroupExpansionStore(defaults: defaults)
        original.toggle(BookSourceRowGroup.defaultGroupID)
        original.toggle(BookSourceRowGroup.topPinnedID)
        original.toggle(BookSourceRowGroup.bottomPinnedID)

        let reopened = BookSourceGroupExpansionStore(defaults: defaults)
        #expect(!reopened.isExpanded(BookSourceRowGroup.defaultGroupID))
        #expect(!reopened.isExpanded(BookSourceRowGroup.topPinnedID))
        #expect(!reopened.isExpanded(BookSourceRowGroup.bottomPinnedID))
        #expect(reopened.isExpanded("默認分組"))
        #expect(reopened.isExpanded("Default group"))
    }
}
