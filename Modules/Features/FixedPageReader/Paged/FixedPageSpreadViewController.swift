import UIKit

// MARK: - Spread
//
// What the paged reader shows at once: one page, or two side by side. The spread is the
// only zoom layer — its pages are plain content with no zoom of their own — so a pinch
// or a double tap scales the whole spread, and once a zoom settles the pages re-render
// for it. Pages used to keep a zoom view of their own inside this one: switched off, it
// still claimed every pinch and did nothing with it, leaving double tap as the only zoom.

final class FixedPageSpreadViewController: UIViewController {

    /// How a spread was left zoomed, to show it the same way when it comes back.
    struct Zoom: Equatable {
        let scale: CGFloat
        let contentOffset: CGPoint
        /// A zoom only means something at the size it was made at.
        let viewportSize: CGSize
    }

    let spreadIndex: Int
    let pages: [FixedPage]
    let fixedPageReaderConfiguration: FixedPageReaderConfiguration
    let targetWidth: CGFloat

    /// A zoom to come back to. Applied when the spread first shows an image, so the page
    /// is never seen at its fitted size first.
    var restoredZoom: Zoom?
    /// The spread left the screen; the reader keeps its zoom for when it returns.
    var onDisappear: ((FixedPageSpreadViewController) -> Void)?
    /// The reader's controls are up, so Live Text's button may show.
    var controlsShown = false {
        didSet { updateLiveTextButtons() }
    }

    /// The zoom to keep for this spread, nil at the fitted size.
    var currentZoom: Zoom? {
        // Not applied yet (the page has not shown an image): still the one to keep.
        if let restoredZoom { return restoredZoom }
        guard FixedPageZoom.isZoomedIn(zoomView.zoomScale), laidOutSize != .zero else { return nil }
        return Zoom(scale: zoomView.zoomScale, contentOffset: zoomView.contentOffset, viewportSize: laidOutSize)
    }

    private let zoomView = FixedPageZoomableScrollView()
    private let stackView = UIStackView()
    private(set) var pageControllers: [FixedPagePageViewController] = []
    /// Size of the last layout. Zoom resets only when it changes (rotation, Split View):
    /// other layout passes — the controls coming and going move the safe areas — must
    /// leave a zoomed spread where it is.
    private var laidOutSize: CGSize = .zero

    init(
        spreadIndex: Int,
        pages: [FixedPage],
        fixedPageReaderConfiguration: FixedPageReaderConfiguration,
        targetWidth: CGFloat
    ) {
        self.spreadIndex = spreadIndex
        self.pages = pages
        self.fixedPageReaderConfiguration = fixedPageReaderConfiguration
        self.targetWidth = targetWidth
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        zoomView.frame = view.bounds
        zoomView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Nothing to zoom until a page shows its image: a spinner or a retry button stays put.
        zoomView.zoomEnabled = false
        zoomView.onZoomSettled = { [weak self] scale in self?.zoomDidSettle(atScale: scale) }
        zoomView.onZoomScaleChanged = { [weak self] _ in self?.updateLiveTextButtons() }
        view.addSubview(zoomView)

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.alignment = .fill
        stackView.spacing = 0
        zoomView.zoomView = stackView

        installPages()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = zoomView.bounds.size
        guard size.width > 0, size.height > 0, size != laidOutSize else { return }
        laidOutSize = size
        zoomView.resetZoom()
        stackView.frame = CGRect(origin: .zero, size: size)
        zoomView.contentSize = size
        zoomDidSettle(atScale: 1)
        restoreZoomIfReady()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDisappear?(self)
    }

    /// Pages re-render for the zoom they are shown at: sharper above the fitted size,
    /// back to their 1x render at it.
    func zoomDidSettle(atScale scale: CGFloat) {
        for page in pageControllers {
            page.refineImage(forZoomScale: scale)
        }
    }

    private func installPages() {
        let isRTL = fixedPageReaderConfiguration.progression == .rightToLeft
        let pageTargetWidth = pages.count > 1 ? targetWidth / 2 : targetWidth

        var controllers = pages.map { page in
            let controller = FixedPagePageViewController(
                page: page,
                index: page.id,
                fixedPageReaderConfiguration: fixedPageReaderConfiguration,
                targetWidth: pageTargetWidth
            )
            controller.onImageLoaded = { [weak self] _ in self?.pageDidShowImage() }
            return controller
        }

        // Right to left, the lower-index page of a pair sits on the right.
        if isRTL && controllers.count == 2 {
            controllers.reverse()
        }
        // A pair meets at the spine between them.
        if controllers.count == 2 {
            controllers[0].spineSide = .right
            controllers[1].spineSide = .left
        }

        pageControllers = controllers
        for controller in pageControllers {
            addChild(controller)
            stackView.addArrangedSubview(controller.view)
            controller.didMove(toParent: self)
        }
        updateLiveTextButtons()
    }

    private func pageDidShowImage() {
        zoomView.zoomEnabled = fixedPageReaderConfiguration.isZoomEnabled
        restoreZoomIfReady()
        // A page that arrives while the spread is zoomed re-renders for that zoom.
        zoomDidSettle(atScale: zoomView.zoomScale)
    }

    /// Puts the remembered zoom back once the spread can take it: showing an image, and
    /// laid out at the size the zoom was made at. Either can come first — a page turned
    /// back to finds its image in the memory cache, often before its first layout.
    private func restoreZoomIfReady() {
        guard let zoom = restoredZoom,
              zoomView.zoomEnabled,
              zoom.viewportSize == laidOutSize
        else { return }
        restoredZoom = nil
        zoomView.setZoomScale(zoom.scale, animated: false)
        zoomView.contentOffset = zoom.contentOffset
        zoomDidSettle(atScale: zoom.scale)
    }

    private func updateLiveTextButtons() {
        let shows = FixedPageZoom.showsLiveTextButton(controlsShown: controlsShown, zoomScale: zoomView.zoomScale)
        for page in pageControllers {
            page.setShowsLiveTextButton(shows)
        }
    }
}
