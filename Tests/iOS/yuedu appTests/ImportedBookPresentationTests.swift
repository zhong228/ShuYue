import Testing
import XCTest
import UIKit
@testable import yuedu_app

@Suite("Imported book presentation", .serialized)
@MainActor
struct ImportedBookPresentationTests {
    @Test("Cold launch retains its request until the scene has a visible window")
    func coldLaunch() async throws {
        let bridge = ImportedBookPresentationController()
        let destination = UIViewController()
        let requestID = UUID()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil }
        let completed: UUID = await withCheckedContinuation { continuation in
            bridge.receive(requestID: requestID, makeDestination: { destination }, didPresent: {
                continuation.resume(returning: $0)
            })
            #expect(bridge.presentedViewController == nil)
            window.rootViewController = bridge
            window.makeKeyAndVisible()
        }
        #expect(bridge.presentedViewController === destination)
        #expect(completed == requestID)
    }

    @Test("A document opens above an existing modal instead of being dropped by the root")
    func existingModal() async throws {
        let root = UIViewController()
        let bridge = ImportedBookPresentationController()
        root.addChild(bridge)
        root.view.addSubview(bridge.view)
        bridge.didMove(toParent: root)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let existing = UIViewController()
        await withCheckedContinuation { continuation in
            root.present(existing, animated: false) { continuation.resume() }
        }
        let destination = UIViewController()
        let requestID = UUID()
        let completed: UUID = await withCheckedContinuation { continuation in
            bridge.receive(requestID: requestID, makeDestination: { destination }, didPresent: {
                continuation.resume(returning: $0)
            })
        }
        #expect(root.presentedViewController === existing)
        #expect(existing.presentedViewController === destination)
        #expect(completed == requestID)
    }

    @Test("A theme arriving during a book transition keeps each request's acknowledgement")
    func overlappingRequests() async throws {
        let bridge = ImportedBookPresentationController()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = bridge
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let book = UIViewController()
        let theme = UIViewController()
        let bookID = UUID()
        let themeID = UUID()
        var bookAcknowledgements: [UUID] = []
        var themeAcknowledgements: [UUID] = []
        let completed = XCTestExpectation(description: "Theme presentation completed")
        bridge.receive(requestID: bookID, makeDestination: {
            // Queue the second handoff only after the first destination is being
            // built; UIWindow attachment itself is asynchronous on cold launch.
            Task { @MainActor in
                bridge.receive(requestID: themeID, makeDestination: { theme }, didPresent: {
                    themeAcknowledgements.append($0)
                    if $0 == themeID { completed.fulfill() }
                })
            }
            return book
        }, didPresent: {
            bookAcknowledgements.append($0)
        })
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 5)
        #expect(result == .completed)
        #expect(bookAcknowledgements == [bookID])
        #expect(themeAcknowledgements == [themeID])
        #expect(book.presentedViewController === theme)
    }

}
