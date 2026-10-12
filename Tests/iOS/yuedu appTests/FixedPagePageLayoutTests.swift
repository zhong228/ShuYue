import Foundation
import Testing
import UIKit
@testable import yuedu_app

/// 分頁模式的頁面要整頁放進版面（設定的 fitPage）。原本是寬度撐滿、超出的部分直接裁掉：
/// iPad 橫向單頁時，直式的漫畫頁只看得到上半截，放大也看不到下面。
@Suite("Fixed page page layout", .serialized)
@MainActor
struct FixedPagePageLayoutTests {

    @Test("a portrait page in a landscape slot shows whole, centred")
    func portraitPageFitsLandscapeSlot() async throws {
        let (page, url) = try Self.makeImagePage(id: 0, size: CGSize(width: 400, height: 600))
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = FixedPagePageViewController(
            page: page,
            index: 0,
            fixedPageReaderConfiguration: .recommendedDefault(for: .rtl),
            targetWidth: 1180
        )
        controller.view.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        controller.view.layoutIfNeeded()
        await controller.loadTask?.value

        let frame = controller.imageView.frame
        #expect(abs(frame.height - 820) < 0.5)
        #expect(abs(frame.width - 820 * 400 / 600) < 0.5)
        #expect(abs(frame.midX - 590) < 0.5)
        #expect(frame.minY >= 0 && frame.maxY <= 820)
    }

    @Test("the two pages of a spread meet at the spine")
    func spreadPagesMeetAtTheSpine() async throws {
        let (first, firstURL) = try Self.makeImagePage(id: 0, size: CGSize(width: 400, height: 600))
        let (second, secondURL) = try Self.makeImagePage(id: 1, size: CGSize(width: 400, height: 600))
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        var configuration = FixedPageReaderConfiguration.recommendedDefault(for: .ltr)
        configuration.pageSpreadLayout = .double
        let spread = FixedPageSpreadViewController(
            spreadIndex: 0,
            pages: [first, second],
            fixedPageReaderConfiguration: configuration,
            targetWidth: 1180
        )
        spread.view.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        spread.view.layoutIfNeeded()
        for page in spread.pageControllers {
            await page.loadTask?.value
        }
        spread.view.layoutIfNeeded()

        let frames = spread.pageControllers.map { $0.imageView.convert($0.imageView.bounds, to: spread.view) }
        try #require(frames.count == 2)
        #expect(abs(frames[0].maxX - 590) < 0.5)
        #expect(abs(frames[1].minX - 590) < 0.5)
        #expect(frames.allSatisfy { abs($0.height - 820) < 0.5 })
    }

    /// A solid grey PNG of `size` pixels in the temporary directory, as a local page.
    private static func makeImagePage(id: Int, size: CGSize) throws -> (FixedPage, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FixedPagePageLayoutTests-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        try data.write(to: url)
        return (FixedPage(id: id, imageURL: url.absoluteString, headers: [:], localURL: url), url)
    }
}
