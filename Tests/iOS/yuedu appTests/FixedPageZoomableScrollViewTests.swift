import Foundation
import Testing
import UIKit
@testable import yuedu_app

@Suite("Fixed page zoomable scroll view")
@MainActor
struct FixedPageZoomableScrollViewTests {

    @Test("setting zoomView inserts it into the scroll view")
    func settingZoomViewInsertsSubview() {
        let scrollView = FixedPageZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let imageView = UIImageView()

        scrollView.zoomView = imageView

        #expect(imageView.superview === scrollView)
        #expect(scrollView.subviews.contains(imageView))
    }

    @Test("replacing zoomView removes the previous view")
    func replacingZoomViewRemovesPreviousView() {
        let scrollView = FixedPageZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let firstView = UIImageView()
        let secondView = UIImageView()

        scrollView.zoomView = firstView
        scrollView.zoomView = secondView

        #expect(firstView.superview == nil)
        #expect(secondView.superview === scrollView)
        #expect(!scrollView.subviews.contains(firstView))
        #expect(scrollView.subviews.contains(secondView))
    }

    @Test("a double tap on a fitted page zooms to 2x with the tapped point in the middle")
    func doubleTapFromFittedZoomsIn() {
        let target = FixedPageZoomableScrollView.doubleTapTarget(
            tappedAt: CGPoint(x: 100, y: 300),
            currentScale: 1,
            minimumScale: 1,
            viewportSize: CGSize(width: 400, height: 800)
        )
        #expect(target == CGRect(x: 0, y: 100, width: 200, height: 400))
    }

    @Test("a double tap at any zoom goes back to the fitted size")
    func doubleTapWhileZoomedZoomsOut() {
        for scale: CGFloat in [1.5, 2, 4.8] {
            let target = FixedPageZoomableScrollView.doubleTapTarget(
                tappedAt: CGPoint(x: 100, y: 300),
                currentScale: scale,
                minimumScale: 1,
                viewportSize: CGSize(width: 400, height: 800)
            )
            #expect(target.size == CGSize(width: 400, height: 800))
        }
    }

    @Test("with zoom off there is no zoom range left for a pinch to claim")
    func zoomOffLeavesNoZoomRange() {
        let scrollView = FixedPageZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        #expect(scrollView.maximumZoomScale == FixedPageZoom.maximumScale)

        scrollView.zoomEnabled = false
        #expect(scrollView.maximumZoomScale == scrollView.minimumZoomScale)
        #expect(!scrollView.isScrollEnabled)

        scrollView.zoomEnabled = true
        #expect(scrollView.maximumZoomScale == FixedPageZoom.maximumScale)
        #expect(scrollView.isScrollEnabled)
    }
}
