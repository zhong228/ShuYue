@testable import YueduCoreText
import CoreText
import Foundation
import Testing
import UIKit
@testable import yuedu_app

/// Temporary diagnostic sweep: slices every spine of every corpus EPUB the way the legacy
/// scroll engine does and reports chunks that lay out nothing.
@Suite("Chunk slicer corpus sweep", .serialized)
@MainActor
struct CoreTextChunkSlicerCorpusSweepTests {
    @Test func sweepCorpus() async throws {
        let directory = CoreTextChunkSlicerImageLineTests.directory
        let books = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".epub") }.sorted()
        // `TEST_RUNNER_SWEEP_BOOKS=8-9` → books 8 and 9 of the sorted list.
        let window = ProcessInfo.processInfo.environment["SWEEP_BOOKS"]?.split(separator: "-").compactMap { Int($0) }
        let selected = window.map { w in Array(books[w[0]...min(w[1], books.count - 1)]) } ?? books
        let profiles: [(String, ReaderRenderSettings)] = [
            ("fidelity", CoreTextChunkSlicerImageLineTests.fidelity),
            ("defaults", CoreTextChunkSlicerImageLineTests.appDefaults),
        ]
        var total = 0, empty = 0
        for book in selected {
            let session: PublicationSession
            do { session = try await PublicationSession.open(sourceURL: URL(fileURLWithPath: directory + "/" + book)) }
            catch { print("SWEEP open-failed \(book): \(error)"); continue }
            let screen = CoreTextChunkSlicerImageLineTests.screen
            let builder = EPUBAttributedStringBuilder(session: session, renderSize: screen)
            for spine in session.chapters.indices {
                for vertical in [true, false] {
                    for (name, base) in profiles {
                        var settings = base
                        settings.writingMode = vertical ? .verticalRTL : .horizontal
                        let result: AttributedChapterBuildResult
                        do {
                            result = try await builder.buildChapter(
                                at: spine, settings: settings,
                                themeTextColor: settings.textColor, themeBackgroundColor: settings.backgroundColor)
                        } catch { print("SWEEP build-failed \(book) \(spine): \(error)"); continue }
                        if result.imagePage?.image != nil { continue }
                        // As `CoreTextScrollEngine` lays a chapter out (`prepareAttributedString`).
                        let contentWidth = vertical ? screen.height - 2 * settings.marginH
                                                    : screen.width - 2 * settings.marginH
                        var attr = result.attributedString
                        if vertical, attr.length > 0 {
                            attr = CoreTextPaginator.preparedAttributedString(
                                attr, writingMode: settings.writingMode, fontSize: settings.fontSize,
                                maxInlineAnnotationAdvance: max(settings.fontSize * 4, contentWidth - settings.fontSize * 2))
                        }
                        let output = CoreTextChunkSlicer.slice(
                            attributedString: attr, chapterIndex: spine, contentWidth: contentWidth,
                            writingMode: settings.writingMode,
                            pageBackgroundImage: result.pageBackgroundImage,
                            minimumBackdropExtent: vertical ? screen.width : screen.height)
                        for (index, chunk) in output.chunks.enumerated() where !chunk.isImageOnly {
                            total += 1
                            chunk.materializeFrameIfNeeded()
                            let lines = chunk.frame.map { (CTFrameGetLines($0) as! [CTLine]).count } ?? 0
                            guard lines == 0 else { continue }
                            empty += 1
                            let text = (attr.string as NSString).substring(with: NSRange(
                                location: chunk.charRange.location, length: min(chunk.charRange.length, 40)))
                            print("SWEEP empty \(vertical ? "V" : "H") \(name) \(book) spine=\(spine) chunk=\(index)/\(output.chunks.count) range=\(chunk.charRange.location)+\(chunk.charRange.length) of \(attr.length) size=\(chunk.width)x\(chunk.height) text=\(text.debugDescription) | \(CoreTextChunkSlicerImageLineTests.diagnose(chunk))")
                        }
                    }
                }
            }
            print("SWEEP book-done \(book) spines=\(session.chapters.count)")
        }
        print("SWEEP total chunks=\(total) empty=\(empty)")
    }
}
