import Foundation

// MARK: - ImportedTTSSource: ImportableSource

extension ImportedTTSSource: ImportableSource {
    var importDisplayName: String {
        name.isEmpty ? urlTemplate : name
    }

    /// The URL template, matching how `TTSSourceJSONParser` already dedupes a pack. The `id`
    /// is derived from name+URL when a pack declares none, so it is not a stable identity.
    var importIdentityKey: String { urlTemplate }

    var importUpdateClock: Int64 { lastUpdateTime }

    /// Legado's `HttpTTS` has no comment field, so the row shows no note.
    var importComment: String? { nil }

    /// The Legado `HttpTTS` shape, which is what the user pasted and what they expect to
    /// edit — not our internal `Codable` spelling (`urlTemplate`, `headers`).
    var importEditableJSON: String {
        var object: [String: Any] = [
            "id": id,
            "name": name,
            "url": urlTemplate,
        ]
        if !headers.isEmpty { object["header"] = headers }
        if let contentType { object["contentType"] = contentType }
        if let concurrentRate { object["concurrentRate"] = concurrentRate }
        if let loginUrl { object["loginUrl"] = loginUrl }
        if let loginUi { object["loginUi"] = loginUi }
        if let loginCheckJs { object["loginCheckJs"] = loginCheckJs }
        if let jsLib { object["jsLib"] = jsLib }
        if lastUpdateTime != 0 { object["lastUpdateTime"] = lastUpdateTime }
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    static func importParse(editedJSON: String) -> ImportedTTSSource? {
        // Same parser as every import route, so the editor can't accept a shape the real
        // import would reject.
        guard let data = editedJSON.data(using: .utf8),
              let parsed = try? TTSSourceJSONParser.parse(data: data) else {
            return nil
        }
        return parsed.first
    }
}

// MARK: - TTSSourceImportMerge

/// The merge behind importing narration engines, kept out of the settings view so the view
/// calls one function instead of owning the rule.
enum TTSSourceImportMerge {

    /// `lastUpdateTime` per URL template, for building the confirmation list's states.
    static func existingUpdateClocks(in sources: [ImportedTTSSource]) -> [String: Int64] {
        var clocks: [String: Int64] = .init(minimumCapacity: sources.count)
        for source in sources {
            if let existing = clocks[source.urlTemplate] {
                clocks[source.urlTemplate] = max(existing, source.lastUpdateTime)
            } else {
                clocks[source.urlTemplate] = source.lastUpdateTime
            }
        }
        return clocks
    }

    /// Folds the selected sources into the library: a URL template the library already holds
    /// is **replaced**, anything else is appended, and the result is sorted by name as the
    /// list has always been.
    ///
    /// Replacing is the fix for a real defect. The previous merge was
    /// `for source in imported where !existingURLs.contains(source.urlTemplate)`, which
    /// skipped every source already present — so re-importing a corrected voice source did
    /// nothing at all, and the only way to take an update was to delete the old entry first.
    /// Upstream `ImportHttpTtsViewModel` inserts by primary key, which overwrites.
    static func merged(
        existing: [ImportedTTSSource],
        importing: [ImportedTTSSource]
    ) -> [ImportedTTSSource] {
        var merged = existing
        var indexByURL: [String: Int] = .init(minimumCapacity: merged.count)
        for (index, source) in merged.enumerated() where indexByURL[source.urlTemplate] == nil {
            indexByURL[source.urlTemplate] = index
        }
        for source in importing {
            if let index = indexByURL[source.urlTemplate] {
                merged[index] = source
            } else {
                indexByURL[source.urlTemplate] = merged.count
                merged.append(source)
            }
        }
        return merged.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
