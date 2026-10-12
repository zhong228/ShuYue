import UIKit

// MARK: - Zoom container
//
// The single zoom layer of a paged spread (`FixedPageSpreadViewController`): a pinch
// between the fitted size and `FixedPageZoom.maximumScale`, a double tap to 2x at the
// tapped spot and back, and content kept in the middle while it is smaller than the
// screen. Paging stays with the page view controller around it — a zoomed page panned
// to its edge hands the rest of the drag over to a page turn.

final class FixedPageZoomableScrollView: UIScrollView, UIScrollViewDelegate {

    /// The view that scales.
    var zoomView: UIView? {
        didSet { replaceZoomView(oldValue) }
    }

    /// Off: no pinch, no double tap and nothing to pan. A zoom range of one scale leaves
    /// the scroll view without a working pinch, which is the point — a pinch recognizer
    /// still live under a zoom that is "off" claims two-finger gestures and drops them.
    var zoomEnabled = true {
        didSet { applyZoomEnabled() }
    }

    /// A pinch or double-tap zoom came to rest at this scale. Rasterized pages (PDF,
    /// fixed-layout EPUB) re-render at it so text stays sharp.
    var onZoomSettled: ((CGFloat) -> Void)?

    /// The scale changed — every frame of a pinch or animation, and a zoom set in code.
    var onZoomScaleChanged: ((CGFloat) -> Void)?

    private lazy var doubleTap = FixedPageDoubleTapZoomGestureRecognizer(
        target: self,
        action: #selector(handleDoubleTap(_:))
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        insetsLayoutMarginsFromSafeArea = false
        addGestureRecognizer(doubleTap)
        applyZoomEnabled()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        centerContent()
    }

    func resetZoom() {
        setZoomScale(minimumZoomScale, animated: false)
    }

    /// Where a double tap zooms, as a rect of the zoom view: from the fitted size, 2x
    /// with the tapped point in the middle; from any zoom at all, back to fitted.
    static func doubleTapTarget(
        tappedAt point: CGPoint,
        currentScale: CGFloat,
        minimumScale: CGFloat,
        viewportSize: CGSize
    ) -> CGRect {
        let scale = currentScale > minimumScale + 0.01 ? minimumScale : FixedPageZoom.doubleTapScale
        let size = CGSize(width: viewportSize.width / scale, height: viewportSize.height / scale)
        return CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func applyZoomEnabled() {
        if !zoomEnabled { resetZoom() }
        maximumZoomScale = zoomEnabled ? FixedPageZoom.maximumScale : minimumZoomScale
        isScrollEnabled = zoomEnabled
        doubleTap.isEnabled = zoomEnabled
    }

    private func replaceZoomView(_ previous: UIView?) {
        guard previous !== zoomView else { return }
        if previous?.superview === self {
            previous?.removeFromSuperview()
        }
        if let zoomView, zoomView.superview !== self {
            addSubview(zoomView)
        }
    }

    /// Content smaller than the screen (a pinch below the fitted size, before it springs
    /// back) sits in the middle rather than in the top-left corner.
    private func centerContent() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != inset {
            contentInset = inset
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard let zoomView else { return }
        let target = Self.doubleTapTarget(
            tappedAt: recognizer.location(in: zoomView),
            currentScale: zoomScale,
            minimumScale: minimumZoomScale,
            viewportSize: bounds.size
        )
        zoom(to: target, animated: true)
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        onZoomScaleChanged?(zoomScale)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        onZoomSettled?(scale)
    }
}
