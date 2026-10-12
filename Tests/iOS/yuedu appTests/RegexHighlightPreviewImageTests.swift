import Testing
import UIKit
@testable import yuedu_app

@Suite("Regex highlight preview images", .serialized)
@MainActor
struct RegexHighlightPreviewImageTests {
    @Test("changing either focus axis redraws the same preview view", arguments: [
        ReaderStyleImageContentMode.fill, .fit, .tile,
    ])
    func focusRedraws(mode: ReaderStyleImageContentMode) throws {
        for horizontal in [true, false] {
            let size: CGSize
            switch mode {
            case .fill:
                size = horizontal ? CGSize(width: 400, height: 20) : CGSize(width: 20, height: 400)
            case .fit:
                size = horizontal ? CGSize(width: 20, height: 400) : CGSize(width: 400, height: 20)
            default:
                size = CGSize(width: 19, height: 17)
            }
            let id = UUID()
            ReaderStyleAssetImageCache.shared.insert(sourceImage(size: size, horizontal: horizontal), for: id)
            defer { ReaderStyleAssetImageCache.shared.remove(id) }
            let model = makeModel(id: id, mode: mode)
            let view = RegexHighlightLivePreviewView(frame: CGRect(x: 0, y: 0, width: 240, height: 90))
            model.lightStyle.decoration.backgroundImage?.focalX = 0
            model.lightStyle.decoration.backgroundImage?.focalY = 0
            let before = try render(model, view: view)
            if horizontal {
                model.lightStyle.decoration.backgroundImage?.focalX = 1
            } else {
                model.lightStyle.decoration.backgroundImage?.focalY = 1
            }
            let after = try render(model, view: view)
            #expect(before != after, "Focus must change rendered pixels on the movable axis")
        }
    }

    @Test("image and decoration opacity match for an image alone and multiply together")
    func imageOpacityComposition() throws {
        let id = UUID()
        ReaderStyleAssetImageCache.shared.insert(sourceImage(size: CGSize(width: 20, height: 20), horizontal: true), for: id)
        defer { ReaderStyleAssetImageCache.shared.remove(id) }
        let model = makeModel(id: id, mode: .stretch)
        let view = RegexHighlightLivePreviewView(frame: CGRect(x: 0, y: 0, width: 240, height: 90))
        let opaque = try render(model, view: view)
        model.lightStyle.decoration.backgroundImage?.opacity = 0.5
        let imageHalf = try render(model, view: view)
        model.lightStyle.decoration.backgroundImage?.opacity = 1
        model.lightStyle.decoration.opacity = 0.5
        #expect(try render(model, view: view) == imageHalf)
        #expect(opaque != imageHalf)
        model.lightStyle.decoration.backgroundImage?.opacity = 0.5
        let bothHalf = try render(model, view: view)
        model.lightStyle.decoration.opacity = 1
        model.lightStyle.decoration.backgroundImage?.opacity = 0.25
        #expect(try render(model, view: view) == bothHalf)
        #expect(bothHalf != imageHalf)
    }

    @Test("decoration opacity also fades the border while image opacity does not")
    func opacityScopesDiffer() throws {
        let id = UUID()
        ReaderStyleAssetImageCache.shared.insert(sourceImage(size: CGSize(width: 20, height: 20), horizontal: true), for: id)
        defer { ReaderStyleAssetImageCache.shared.remove(id) }
        let model = makeModel(id: id, mode: .stretch)
        model.lightStyle.decoration.borders = [.bottom: .init(width: 4, colorHex: 0x00FF00)]
        let view = RegexHighlightLivePreviewView(frame: CGRect(x: 0, y: 0, width: 240, height: 90))
        model.lightStyle.decoration.backgroundImage?.opacity = 0.5
        let imageHalf = try render(model, view: view)
        model.lightStyle.decoration.backgroundImage?.opacity = 1
        model.lightStyle.decoration.opacity = 0.5
        #expect(try render(model, view: view) != imageHalf)
    }

    private func makeModel(id: UUID, mode: ReaderStyleImageContentMode) -> RegexHighlightRuleEditorModel {
        let model = RegexHighlightRuleEditorModel(
            rule: .custom(name: "Image", pattern: "AAAA"), testText: "AAAA"
        ) { _ in }
        model.lightStyle.text.fontSize = 24
        model.lightStyle.decoration.backgroundImage = .init(assetID: id, contentMode: mode)
        return model
    }

    private func sourceImage(size: CGSize, horizontal: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.blue.setFill()
            context.fill(CGRect(
                x: horizontal ? size.width / 2 : 0,
                y: horizontal ? 0 : size.height / 2,
                width: horizontal ? size.width / 2 : size.width,
                height: horizontal ? size.height : size.height / 2
            ))
        }
    }

    private func render(_ model: RegexHighlightRuleEditorModel, view: RegexHighlightLivePreviewView) throws -> Data {
        let attributed = NSMutableAttributedString(
            attributedString: try model.previewAttributedString(appearance: .light, baseTextColor: .clear)
        )
        // Inspect decoration pixels without glyphs obscuring the image.
        attributed.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: 0, length: attributed.length))
        view.attributed = attributed
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(view.bounds)
            view.layer.render(in: context.cgContext)
        }
        return try #require(image.pngData())
    }
}
