import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

@Suite(.serialized)
@MainActor
struct HostedCollectionListTests {
    @Test("50,000 items build only the rows on screen, and a refresh rebuilds only those")
    func buildsOnlyVisibleRows() throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let row: (Int) -> Text = { Text("Row \($0)") }
        let controller = HostedCollectionListController<Int, Text>(
            row: row, showsSeparator: { _ in true })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let items = Array(0..<50_000)
        let startedAt = ProcessInfo.processInfo.systemUptime
        controller.update(
            items: items, contentVersion: 0, animated: false, row: row,
            showsSeparator: { _ in true }, usesSystemMargins: { _ in false },
            drawsCellSurface: { _ in false })
        controller.view.layoutIfNeeded()
        controller.collectionView.layoutIfNeeded()
        let firstLayoutMs = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)

        let visible = controller.collectionView.indexPathsForVisibleItems.count
        #expect(visible > 0)
        // Prefetching may configure a screenful ahead; nothing near 50,000.
        #expect(controller.rowBuildCount <= visible * 3)

        let builtBeforeRefresh = controller.rowBuildCount
        controller.update(
            items: items, contentVersion: 1, animated: false, row: row,
            showsSeparator: { _ in true }, usesSystemMargins: { _ in false },
            drawsCellSurface: { _ in false })
        #expect(controller.rowBuildCount - builtBeforeRefresh
            == controller.collectionView.indexPathsForVisibleItems.count)

        controller.scroll(
            to: HostedCollectionListScrollRequest(item: 49_999, serial: 1), animated: false)
        controller.collectionView.layoutIfNeeded()
        #expect(controller.collectionView.indexPathsForVisibleItems
            .contains(IndexPath(item: 49_999, section: 0)))
        print("SCALE hostedList items=50000 firstLayoutMs=\(firstLayoutMs) rowsBuilt=\(builtBeforeRefresh)")
    }

    @Test("scrolling reuses cells across rows with and without a surface")
    func reuseAcrossSurfaceKinds() throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let row: (Int) -> Text = { Text("Row \($0)") }
        // 書源管理's mix: a clear header, then surfaced group and source rows.
        let surface: (Int) -> Bool = { $0 % 7 != 0 }
        let controller = HostedCollectionListController<Int, Text>(
            row: row, showsSeparator: { _ in true }, drawsCellSurface: surface)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.update(
            items: Array(0..<3_000), contentVersion: 0, animated: false, row: row,
            showsSeparator: { _ in true }, usesSystemMargins: { $0 % 7 == 0 },
            drawsCellSurface: surface)
        controller.view.layoutIfNeeded()
        let collection = controller.collectionView!
        // Fast scrolling, down and back: every step recycles cells into rows of the
        // other kind. UIKit threw from `_UISystemBackgroundView` here when a recycled
        // cell's background configuration changed under a hosting background.
        for step in 0..<120 {
            let offset = CGFloat(step < 60 ? step : 120 - step) * 700
            collection.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            collection.layoutIfNeeded()
            controller.update(
                items: Array(0..<3_000), contentVersion: step + 1, animated: false, row: row,
                showsSeparator: { _ in true }, usesSystemMargins: { $0 % 7 == 0 },
                drawsCellSurface: surface)
        }
        #expect(!collection.indexPathsForVisibleItems.isEmpty)
    }

    @Test("a row drawn on the surface paints the whole cell, not just its content")
    func surfaceFillsTheCell() throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let row: (Int) -> Text = { Text("R\($0)") }
        let controller = HostedCollectionListController<Int, Text>(
            row: row, showsSeparator: { _ in false }, drawsCellSurface: { $0 == 0 })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        // Anything the cells leave transparent shows up red.
        window.backgroundColor = .red
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.update(
            items: [0, 1], contentVersion: 0, animated: false, row: row,
            showsSeparator: { _ in false }, usesSystemMargins: { _ in false },
            drawsCellSurface: { $0 == 0 })
        controller.view.layoutIfNeeded()
        controller.collectionView.layoutIfNeeded()

        let surfaceCell = try #require(controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        let clearCell = try #require(controller.collectionView.cellForItem(at: IndexPath(item: 1, section: 0)))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        func isRed(_ cell: UICollectionViewCell) -> Bool {
            // Far right of the row, clear of the text; near the bottom edge, where content
            // shorter than the cell used to leave a strip.
            let frame = cell.convert(cell.bounds, to: window)
            return image.redDominates(at: CGPoint(x: frame.maxX - 8, y: frame.maxY - 2))
        }
        #expect(!isRed(surfaceCell), "the surface must reach the cell's edges")
        #expect(isRed(clearCell), "a row without a surface stays transparent")
    }
}

private extension UIImage {
    func redDominates(at point: CGPoint) -> Bool {
        guard let cgImage else { return false }
        let x = Int(point.x * scale), y = Int(point.y * scale)
        guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(cgImage, in: CGRect(x: -x, y: y - cgImage.height + 1, width: cgImage.width, height: cgImage.height))
        return pixel[0] > 200 && pixel[1] < 80 && pixel[2] < 80
    }
}

