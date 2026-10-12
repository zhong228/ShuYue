import Foundation
import SwiftSoup
import Testing
@testable import yuedu_app

/// `displayText(fromHTMLFragment:)` skips its markup and entity passes for text that
/// contains neither — the bookshelf calls it once per row per body evaluation, and a
/// library publish behind the open reader re-evaluates every row.
///
/// The skip is only sound if it changes nothing, so the suite keeps the
/// pre-optimization algorithm verbatim as `reference` and requires the two to agree
/// on every case. Extend `corpus`, not the reference, when a new shape turns up.
@Suite("displayText fast path")
struct ReaderHTMLDisplayTextFastPathTests {

    @Test("clean text is returned unchanged", arguments: [
        "第一章 驚蟄",
        "Chapter 1",
        "第 1 章　風起",
        "序章",
    ])
    func cleanTextIsUnchanged(_ input: String) {
        #expect(ReaderHTMLUtilities.displayText(fromHTMLFragment: input) == input)
    }

    @Test("markup and entities are still handled")
    func markupAndEntitiesStillHandled() {
        #expect(
            ReaderHTMLUtilities.displayText(fromHTMLFragment: "<b>第一章</b> 驚蟄") == "第一章 驚蟄"
        )
        // Doubly encoded: unescaping turns `&lt;br&gt;` into a real tag, which only the
        // second markup pass can strip — the reason the `<` test is taken again after
        // unescaping rather than reused from the `&` test.
        #expect(ReaderHTMLUtilities.displayText(fromHTMLFragment: "A&lt;br&gt;B") == "A B")
        #expect(ReaderHTMLUtilities.displayText(fromHTMLFragment: "A<br>B") == "A B")
        #expect(ReaderHTMLUtilities.displayText(fromHTMLFragment: "A&amp;B") == "A&B")
    }

    @Test("bidi controls are dropped from otherwise clean text")
    func bidiControlsAreDropped() {
        // No `&` and no `<`, so every markup pass is skipped — but the bidi filter is
        // not tied to either marker and must still run.
        #expect(
            ReaderHTMLUtilities.displayText(fromHTMLFragment: "第一章\u{200E} 驚蟄") == "第一章 驚蟄"
        )
        #expect(
            ReaderHTMLUtilities.displayText(fromHTMLFragment: "\u{FEFF}序章") == "序章"
        )
    }

    @Test("every corpus entry matches the pre-optimization algorithm")
    func matchesReferenceImplementation() {
        for input in Self.corpus {
            for preservingLineBreaks in [false, true] {
                let optimized = ReaderHTMLUtilities.displayText(
                    fromHTMLFragment: input,
                    preservingLineBreaks: preservingLineBreaks
                )
                let expected = Self.reference(
                    input,
                    preservingLineBreaks: preservingLineBreaks
                )
                #expect(
                    optimized == expected,
                    "input \(String(reflecting: input)) preservingLineBreaks=\(preservingLineBreaks)"
                )
            }
        }
    }

    /// The before/after number for the bookshelf re-render this change targets.
    ///
    /// A device trace caught one library publish behind the open reader spending
    /// ~24 ms re-evaluating the shelf, with `displayText` under
    /// `ReadingBook.latestChapterDisplayTitle` as the hot leaf. Chapter titles are
    /// sanitized on write, so every row was paying for markup handling on clean text.
    /// This runs both implementations over a shelf-sized batch and prints each — read
    /// the printed line for the ratio on the machine under test; the assertion is a
    /// loose floor, not the measurement.
    @Test("clean titles cost materially less than the pre-optimization algorithm")
    func fastPathIsMeasurablyCheaper() {
        // 40 rows, each cleaning one already-sanitized newest-chapter title.
        let titles = (0..<40).map { "第 \($0) 章　風起於青萍之末" }
        let iterations = 50

        func time(_ body: () -> Void) -> Duration {
            let clock = ContinuousClock()
            // One untimed pass so neither side pays for first-use setup.
            body()
            return clock.measure {
                for _ in 0..<iterations { body() }
            }
        }

        let optimized = time {
            for title in titles {
                _ = ReaderHTMLUtilities.displayText(fromHTMLFragment: title)
            }
        }
        let original = time {
            for title in titles {
                _ = Self.reference(title, preservingLineBreaks: false)
            }
        }

        func milliseconds(_ duration: Duration) -> Double {
            let parts = duration.components
            return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
        }
        let optimizedMs = milliseconds(optimized)
        let originalMs = milliseconds(original)
        print(
            "displayText over \(titles.count) clean titles × \(iterations): "
                + "before \(String(format: "%.1f", originalMs)) ms, "
                + "after \(String(format: "%.1f", optimizedMs)) ms"
        )
        #expect(optimized < original)
    }

    private static let corpus: [String] = [
        "",
        "   ",
        "第一章 驚蟄",
        "  第一章 驚蟄  ",
        "第一章\n\n驚蟄",
        "第一章\t\t驚蟄",
        "第一章\u{000B}驚蟄",
        "第一章\u{000C}驚蟄",
        "第一章\r\n驚蟄",
        "第一章　驚蟄",
        "第一章\u{00A0}驚蟄",
        "<b>第一章</b> 驚蟄",
        "<p>第一段</p><p>第二段</p>",
        "<div>一</div><li>二</li><h3>三</h3><blockquote>四</blockquote>",
        "A<br>B",
        "A<br/>B",
        "A<BR />B",
        "A&lt;br&gt;B",
        "A&LT;BR/&GT;B",
        "A&amp;B",
        "A&nbsp;B",
        "A&#160;B",
        "A&ensp;B&emsp;C&thinsp;D",
        "A&quot;B&#34;C&apos;D&#39;E",
        "A&lt;tag&gt;B",
        "A&lrm;B",
        "第一章\u{200E} 驚蟄",
        "\u{FEFF}序章",
        "\u{202A}左\u{202C}右\u{2066}中\u{2069}",
        "&amp;\u{200F}<i>斜體</i>\n\n尾",
        "<span style=\"color: red\">紅</span>",
        "未閉合 <b 標籤",
        "A > B < C",
        "100% &amp; 50&#37;",
        "<p>一\n二</p>\n\n<p>三</p>",
        "多行\n\n\n\n段落",
        "trailing tag<br>",
        "&",
        "<",
    ]

    /// `ReaderHTMLUtilities.displayText` exactly as it stood before the markup and
    /// entity passes were made conditional. Kept verbatim on purpose: it is the
    /// specification the optimization must not drift from.
    private static func reference(_ text: String, preservingLineBreaks: Bool) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        if let decoded = try? Entities.unescape(result) {
            result = decoded
        }

        result = result.replacingOccurrences(
            of: #"(?i)&lt;\s*br\s*/?\s*&gt;"#,
            with: "\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)<\s*br\s*/?\s*>"#,
            with: "\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)</(?:p|div|li|h[1-6]|section|article|blockquote|dt|dd|tr)>"#,
            with: "\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&#160;", " "),
            ("&ensp;", " "),
            ("&emsp;", " "),
            ("&thinsp;", ""),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        let bidiControls: Set<UInt32> = [
            0x061C, 0x200E, 0x200F,
            0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
            0x2066, 0x2067, 0x2068, 0x2069,
            0xFEFF,
        ]
        result = String(result.unicodeScalars.filter { !bidiControls.contains($0.value) })

        if preservingLineBreaks {
            return result
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\u{000B}", with: " ")
                .replacingOccurrences(of: "\u{000C}", with: " ")
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
                .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
            .replacingOccurrences(of: #"[ \t\f\v\r\n]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
