import SwiftUI
import XCTest
@testable import yuedu_app

/// `java.getVerificationCode`'s sheet, drawn for review. A few real sources draw their code as
/// an SVG data URI, which only reaches the screen through the WebView rasterizer.
@MainActor
final class SourceCaptchaViewSnapshotTests: XCTestCase {
    private static let svgCaptcha: String = {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="120" height="40">\
            <rect width="120" height="40" fill="#eeeeee"/>\
            <text x="18" y="28" font-size="24" font-family="Menlo" fill="#333333">7K3Q</text></svg>
            """
        return "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
    }()

    func testSVGCaptchaLoadsAndTheSheetDraws() async throws {
        let image = await OnlineImageLoader.load(
            src: Self.svgCaptcha, renderWidth: 320, cachePolicy: .reloadIgnoringLocalCacheData)
        XCTAssertNotNil(image, "an SVG captcha must decode to an image")

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let host = UIHostingController(rootView: SourceCaptchaView(
                request: SourceCaptchaRequest(
                    imageURL: Self.svgCaptcha, headers: [:], sourceName: "示例書源", sourceURL: ""),
                onFinish: { _ in }
            ))
            window.overrideUserInterfaceStyle = appearance
            window.rootViewController = host
            window.makeKeyAndVisible()
            // The sheet loads its own copy of the image; the screenshot is for review, so it
            // simply waits long enough for the rasterizer to have drawn it.
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(100))
                window.layoutIfNeeded()
            }
            let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "captcha-\(appearance == .dark ? "dark" : "light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
