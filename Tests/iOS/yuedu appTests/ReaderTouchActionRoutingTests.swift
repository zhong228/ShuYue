import Testing
@testable import yuedu_app

@Suite("Reader Touch Action Routing")
struct ReaderTouchActionRoutingTests {
    @Test("every touch action maps to one explicit reader command")
    func mapsAction() {
        let mappings: [(TouchAction, ReaderTouchCommand)] = [
            (.none, .none),
            (.toggleMenu, .toggleMenu),
            (.prevPage, .previousPage),
            (.nextPage, .nextPage),
            (.previousChapter, .previousChapter),
            (.nextChapter, .nextChapter),
            (.toggleBookmark, .toggleBookmark),
            (.tableOfContents, .tableOfContents),
        ]

        for (action, command) in mappings {
            #expect(action.readerCommand == command)
        }
    }

    @Test("only page and chapter turns put the reading menu away")
    func turnsPage() {
        let turns: Set<TouchAction> = [.prevPage, .nextPage, .previousChapter, .nextChapter]
        for action in TouchAction.allCases {
            #expect(action.readerCommand.turnsPage == turns.contains(action))
        }
    }
}
