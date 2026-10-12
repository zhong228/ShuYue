import Combine
import Testing
import UIKit
import SwiftUI
@testable import yuedu_app

/// The stack is real UIKit; completion delivery is controlled so cancellation
/// and intermediate states can be asserted without timers or screen animations.
@MainActor
private final class DetailTestNavigationController: UINavigationController {
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        setViewControllers(viewControllers + [viewController], animated: false)
    }

    override func popViewController(animated: Bool) -> UIViewController? {
        guard viewControllers.count > 1 else { return nil }
        let removed = viewControllers.last
        setViewControllers(Array(viewControllers.dropLast()), animated: false)
        return removed
    }

    func settle() {
        guard let topViewController else { return }
        delegate?.navigationController?(self, didShow: topViewController, animated: false)
    }
}

@Suite("Reader detail navigation", .serialized)
@MainActor
struct ReaderDetailNavigationTests {
    private func openedReader(
        owner: UUID? = nil,
        onClosed: @escaping () -> Void = {}
    ) -> (ReaderNavigationCoordinator, DetailTestNavigationController, UIViewController, UUID) {
        let root = UIViewController()
        let nav = DetailTestNavigationController(rootViewController: root)
        let reader = UIViewController()
        let id = UUID()
        let coordinator = ReaderNavigationCoordinator()
        coordinator.attach(to: nav, owner: owner)
        coordinator.open(bookID: id, destination: { reader }, onReaderClosed: onClosed)
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        return (coordinator, nav, reader, id)
    }

    @Test("details push above the same reader and Continue Reading pops only details")
    func detailRoundTripRetainsReader() {
        var closedCount = 0
        var returnedCount = 0
        let (coordinator, nav, reader, id) = openedReader { closedCount += 1 }
        defer { coordinator.detachNavigationController() }
        let detail = UIViewController()
        #expect(coordinator.showDetail(detail, onReturn: { returnedCount += 1 }))
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(nav.viewControllers.count == 3)
        #expect(nav.viewControllers[1] === reader)
        #expect(coordinator.activeBookID == id)
        #expect(closedCount == 0)

        #expect(coordinator.returnFromDetail())
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(nav.viewControllers.count == 2)
        #expect(nav.topViewController === reader)
        #expect(coordinator.activeBookID == id)
        #expect(coordinator.isReaderPresented)
        #expect(!coordinator.isShowingDetail)
        #expect(returnedCount == 1)
        #expect(closedCount == 0)
    }

    @Test("detail cancellation keeps the reader and its temporary-book ownership")
    func cancelledDetailPopDoesNotCleanUpReader() {
        var cleanedUp = false
        let (coordinator, nav, reader, id) = openedReader { cleanedUp = true }
        defer { coordinator.detachNavigationController() }
        let detail = UIViewController()
        #expect(coordinator.showDetail(detail))
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        // UIKit begins revealing the reader, then restores the detail on cancel.
        nav.delegate?.navigationController?(nav, willShow: reader, animated: true)
        #expect(!coordinator.returnFromDetail())
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(coordinator.isShowingDetail)
        #expect(coordinator.activeBookID == id)
        #expect(nav.viewControllers[1] === reader)
        #expect(!cleanedUp)
        #expect(!coordinator.showDetail(UIViewController()))
    }

    @Test("chapter selection is applied only after returning to the retained reader")
    func chapterSelectionWaitsForDetailReturn() {
        let (coordinator, nav, reader, _) = openedReader()
        defer { coordinator.detachNavigationController() }
        #expect(coordinator.showDetail(UIViewController()))
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        var appliedChapter: Int?
        let accepted = coordinator.returnFromDetail {
            #expect(nav.topViewController === reader)
            appliedChapter = 7
        }
        #expect(accepted)
        #expect(appliedChapter == nil)
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(appliedChapter == 7)
    }

    @Test("the native back button detaches details without closing the reader")
    func nativeDetailBackRetainsReader() {
        let (coordinator, nav, reader, id) = openedReader()
        defer { coordinator.detachNavigationController() }
        #expect(coordinator.showDetail(UIViewController()))
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        _ = nav.popViewController(animated: false)
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(!coordinator.isShowingDetail)
        #expect(coordinator.activeBookID == id)
        #expect(nav.topViewController === reader)
        #expect(coordinator.showDetail(UIViewController()))
    }

    @Test("reader cleanup runs once on the real reader pop, never on detail return")
    func readerClosureOwnsCleanup() {
        var closedCount = 0
        let (coordinator, nav, _, _) = openedReader { closedCount += 1 }
        let detail = UIViewController()
        #expect(coordinator.showDetail(detail))
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(coordinator.returnFromDetail())
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(closedCount == 0)
        coordinator.close()
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(nav.viewControllers.count == 1)
        #expect(closedCount == 1)
        #expect(coordinator.activeBookID == nil)
        coordinator.detachNavigationController()
        #expect(closedCount == 1)
    }

    @Test("removing a book from details closes details before the reader")
    func closeFromDetailClosesBothInOrder() {
        var closedCount = 0
        let (coordinator, nav, reader, _) = openedReader { closedCount += 1 }
        defer { coordinator.detachNavigationController() }
        #expect(coordinator.showDetail(UIViewController()))
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        coordinator.close()
        #expect(nav.topViewController === reader)
        #expect(closedCount == 0)
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(nav.viewControllers.count == 1)
        #expect(closedCount == 1)
    }

    @Test("native detail pushes are never assigned the book-cover animator")
    func detailDoesNotBorrowReaderAnimator() {
        let root = UIViewController()
        let reader = UIViewController()
        let detail = UIViewController()
        let nav = DetailTestNavigationController(rootViewController: root)
        nav.setViewControllers([root, reader], animated: false)
        let driver = ReaderNavigationTransitionDriver()
        driver.sourceProvider = { ReaderTransitionSource(bookID: UUID()) }
        driver.readerIsPresented = { true }
        driver.attach(to: nav)
        defer { driver.detach() }
        #expect(driver.pushDetail(detail, above: reader, animated: false))
        #expect(driver.navigationController(nav, animationControllerFor: .push, from: reader, to: detail) == nil)
        nav.settle()
        #expect(driver.popDetail(detail, returningTo: reader, animated: false))
        #expect(driver.navigationController(nav, animationControllerFor: .pop, from: detail, to: reader) == nil)
    }

    @Test("an externally removed reader releases its trial ownership once")
    func externalRemovalCleansUp() {
        var closedCount = 0
        let (coordinator, nav, _, _) = openedReader { closedCount += 1 }
        defer { coordinator.detachNavigationController() }
        nav.setViewControllers([nav.viewControllers[0]], animated: false)
        nav.settle()
        coordinator.navigationTransitionDidSettle()
        #expect(closedCount == 1)
        #expect(!coordinator.shouldIgnoreOpenRequest())
    }

    @Test("probe teardown never publishes or releases a reader during SwiftUI's graph update")
    func teardownPublishesOutsideDismantle() async throws {
        let owner = UUID()
        var closedCount = 0
        let (coordinator, nav, _, id) = openedReader(owner: owner) { closedCount += 1 }
        var changes = 0
        let subscription = coordinator.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel(); coordinator.detachNavigationController() }

        let cleanup = try #require(coordinator.detachNavigationController(afterDismantling: owner))
        // The caller has not yielded: it is still inside dismantleUIView.
        #expect(changes == 0)
        #expect(closedCount == 0)
        #expect(coordinator.readerBookID == id)
        await cleanup.value
        #expect(!coordinator.isReaderPresented)
        #expect(coordinator.readerBookID == nil)
        #expect(closedCount == 1)
        #expect(changes == 2)
        #expect(!(nav.delegate is ReaderNavigationTransitionDriver))
        coordinator.detachNavigationController()
        #expect(closedCount == 1)
        #expect(changes == 2, "Idle teardown must not invalidate SwiftUI again")
    }

    @Test("replacement attachment cancels cleanup queued by the previous probe")
    func replacementCancelsPendingTeardown() async throws {
        let owner = UUID()
        let replacement = UUID()
        var closedCount = 0
        let (coordinator, nav, _, id) = openedReader(owner: owner) { closedCount += 1 }
        defer { coordinator.detachNavigationController() }
        let cleanup = try #require(coordinator.detachNavigationController(afterDismantling: owner))
        coordinator.attach(to: nav, owner: replacement)
        await cleanup.value
        #expect(coordinator.isReaderPresented)
        #expect(coordinator.readerBookID == id)
        #expect(closedCount == 0)
        #expect(nav.delegate is ReaderNavigationTransitionDriver)
        #expect(coordinator.detachNavigationController(afterDismantling: owner) == nil)
        let replacementCleanup = try #require(coordinator.detachNavigationController(afterDismantling: replacement))
        await replacementCleanup.value
        #expect(closedCount == 1)
    }

    @Test("an idle shelf probe can disappear while another tab pushes a reader without publishing")
    func idleShelfTeardownDoesNotPublish() async throws {
        let nav = DetailTestNavigationController(rootViewController: UIViewController())
        let coordinator = ReaderNavigationCoordinator()
        let owner = UUID()
        coordinator.attach(to: nav, owner: owner)
        var changes = 0
        let subscription = coordinator.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel(); coordinator.detachNavigationController() }
        let cleanup = try #require(coordinator.detachNavigationController(afterDismantling: owner))
        #expect(changes == 0)
        await cleanup.value
        #expect(changes == 0)
        #expect(!(nav.delegate is ReaderNavigationTransitionDriver))
    }
}
