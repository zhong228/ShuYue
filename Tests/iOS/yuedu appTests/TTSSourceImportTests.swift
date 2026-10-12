import Foundation
import Testing
@testable import yuedu_app

@Suite("TTS source import")
struct TTSSourceImportTests {

    private func source(
        _ name: String,
        url: String,
        clock: Int64,
        contentType: String? = nil
    ) -> ImportedTTSSource {
        ImportedTTSSource(
            name: name,
            urlTemplate: url,
            contentType: contentType,
            lastUpdateTime: clock
        )
    }

    // MARK: Merge

    /// The defect this covers: the old merge was
    /// `for source in imported where !existingURLs.contains(source.urlTemplate)`, so a voice
    /// source the library already held was skipped entirely and re-importing a corrected
    /// version did nothing at all.
    @Test("re-importing an existing voice source replaces it")
    func reimportReplacesExistingSource() {
        let existing = [source("語音", url: "https://tts.example/{{speakText}}", clock: 100)]
        let corrected = [
            source(
                "語音（已修）",
                url: "https://tts.example/{{speakText}}",
                clock: 500,
                contentType: "audio/mpeg"
            )
        ]

        let merged = TTSSourceImportMerge.merged(existing: existing, importing: corrected)

        #expect(merged.count == 1)
        #expect(merged[0].name == "語音（已修）")
        #expect(merged[0].contentType == "audio/mpeg")
    }

    @Test("a new voice source is appended and the list stays sorted by name")
    func newSourceAppendedAndSorted() {
        let existing = [source("丙", url: "https://c.example", clock: 1)]
        let importing = [
            source("甲", url: "https://a.example", clock: 1),
            source("乙", url: "https://b.example", clock: 1),
        ]

        let merged = TTSSourceImportMerge.merged(existing: existing, importing: importing)

        #expect(merged.count == 3)
        #expect(merged.map(\.name) == ["丙", "乙", "甲"].sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        })
    }

    @Test("existing clocks report the newest per URL template")
    func existingClocksReportNewest() {
        let sources = [
            source("舊", url: "https://dup.example", clock: 100),
            source("新", url: "https://dup.example", clock: 900),
        ]

        #expect(
            TTSSourceImportMerge.existingUpdateClocks(in: sources)["https://dup.example"] == 900
        )
    }

    // MARK: Plan states

    @MainActor
    @Test("a pack without update stamps is offered as an update, not silently skipped")
    func stamplessPackIsOfferedAsUpdate() throws {
        // Legado defaults a missing `lastUpdateTime` to now for exactly this reason: otherwise
        // a stampless pack compares equal forever and every row reads 「已有」, leaving a
        // re-imported fix unticked.
        let json = #"[{"name":"語音","url":"https://tts.example/{{speakText}}"}]"#
        let parsed = try TTSSourceJSONParser.parse(data: Data(json.utf8))
        let existing = [source("語音", url: "https://tts.example/{{speakText}}", clock: 100)]
        let clocks = TTSSourceImportMerge.existingUpdateClocks(in: existing)

        let plan = SourceImportPlan(incoming: parsed) { clocks[$0] }

        #expect(plan.entries[0].state == .update)
        #expect(plan.isSelected(0))
    }

    @MainActor
    @Test("a declared stamp not newer than the local copy reads as existing")
    func declaredOlderStampReadsExisting() throws {
        let json = """
        [{"name":"語音","url":"https://tts.example/{{speakText}}","lastUpdateTime":100}]
        """
        let parsed = try TTSSourceJSONParser.parse(data: Data(json.utf8))
        let clocks = ["https://tts.example/{{speakText}}": Int64(100)]

        let plan = SourceImportPlan(incoming: parsed) { clocks[$0] }

        #expect(plan.entries[0].state == .existing)
        #expect(plan.isSelected(0) == false)
    }

    // MARK: Parsing

    @Test("lastUpdateTime is read whether the pack writes it as a number or a string")
    func lastUpdateTimeParsesBothShapes() throws {
        let json = """
        [
          {"name":"甲","url":"https://a.example","lastUpdateTime":1700000000000},
          {"name":"乙","url":"https://b.example","lastUpdateTime":"1700000000001"}
        ]
        """
        let parsed = try TTSSourceJSONParser.parse(data: Data(json.utf8))

        #expect(parsed[0].lastUpdateTime == 1_700_000_000_000)
        #expect(parsed[1].lastUpdateTime == 1_700_000_000_001)
    }

    /// The persisted form is one array decoded with `try?`, so a key that older builds never
    /// wrote must not throw — that would drop every imported voice source at once.
    @Test("voice sources stored before lastUpdateTime existed still decode")
    func legacyRecordsStillDecode() throws {
        let legacy = """
        [{
          "id" : "語音|https://tts.example",
          "name" : "語音",
          "urlTemplate" : "https://tts.example",
          "headers" : {"Referer":"https://tts.example"}
        }]
        """
        let decoded = try JSONDecoder().decode(
            [ImportedTTSSource].self,
            from: Data(legacy.utf8)
        )

        #expect(decoded.count == 1)
        #expect(decoded[0].name == "語音")
        #expect(decoded[0].headers["Referer"] == "https://tts.example")
        #expect(decoded[0].lastUpdateTime == 0, "no declared stamp")
        #expect(decoded[0].contentType == nil)
    }

    @Test("an encoded voice source round-trips through the persisted form")
    func roundTripsThroughPersistedForm() throws {
        let original = source("語音", url: "https://tts.example", clock: 4242)
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([ImportedTTSSource].self, from: data)

        #expect(decoded == [original])
    }

    // MARK: Per-row editing

    @Test("the row editor shows Legado field names and parses them back")
    func rowEditorUsesLegadoShape() throws {
        let original = ImportedTTSSource(
            name: "語音",
            urlTemplate: "https://tts.example/{{speakText}}",
            headers: ["Referer": "https://tts.example"],
            contentType: "audio/mpeg",
            lastUpdateTime: 4242
        )

        let json = original.importEditableJSON
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        // The user pasted a Legado pack, so the editor must speak `url`/`header`, not our
        // internal `urlTemplate`/`headers`.
        #expect(object["url"] as? String == "https://tts.example/{{speakText}}")
        #expect(object["urlTemplate"] == nil)
        #expect(object["header"] != nil)

        let reparsed = try #require(ImportedTTSSource.importParse(editedJSON: json))
        #expect(reparsed.urlTemplate == original.urlTemplate)
        #expect(reparsed.headers == original.headers)
        #expect(reparsed.contentType == "audio/mpeg")
        #expect(reparsed.lastUpdateTime == 4242)
    }

    @Test("an edit without a URL is rejected")
    func editWithoutURLRejected() {
        #expect(ImportedTTSSource.importParse(editedJSON: #"{"name":"沒有網址"}"#) == nil)
        #expect(ImportedTTSSource.importParse(editedJSON: "not json") == nil)
    }
}
