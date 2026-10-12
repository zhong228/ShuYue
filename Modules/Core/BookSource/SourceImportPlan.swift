import Foundation
import Combine
// MARK: - SourceImportItemState

/// Where one incoming item stands against what the library already holds —
/// Legado's 「新增 / 更新 / 已有」 badge on each row of its import dialog.
enum SourceImportItemState: Equatable {
    /// Nothing local shares this item's identity key.
    case new
    /// A local item shares the key and declares an older `lastUpdateTime`.
    case update
    /// A local item shares the key and is not older, so importing changes nothing
    /// the author has dated as newer. Left unchecked by default.
    case existing
}

// MARK: - ImportableSource

/// A type that can appear in an import confirmation list. Book sources and online
/// narration engines both conform; the list UI and the selection logic are written
/// once against this protocol instead of twice per type.
protocol ImportableSource {
    /// The name shown on the row's checkbox.
    var importDisplayName: String { get }
    /// Decides "does the library already have this one" — `bookSourceUrl` for a book
    /// source, the URL template for a narration engine. Never the random local UUID:
    /// source JSON carries no stable id, so every device decodes a fresh one.
    var importIdentityKey: String { get }
    /// The author-declared `lastUpdateTime` from the JSON, which is what separates
    /// 「更新」 from 「已有」. Not a local modification time.
    var importUpdateClock: Int64 { get }
    /// The author's note about the source (a book source's `bookSourceComment`).
    /// `nil` when the type has no such field.
    var importComment: String? { get }
    /// What the per-row editor shows: this item as the Legado-shaped JSON the user
    /// recognises from the pack they pasted, not our internal `Codable` spelling.
    var importEditableJSON: String { get }
    /// Parses the editor's text back into one item. `nil` when the text does not
    /// decode, in which case the edit is rejected and the original row is kept.
    static func importParse(editedJSON: String) -> Self?
}

// MARK: - SourceImportPlan

/// The state behind an import confirmation list: what arrived, what the library
/// already has, and which rows the user has ticked.
///
/// Selection is index-based, exactly as upstream's parallel `selectStatus` array is,
/// because a single pack can legitimately carry two entries with the same name *and*
/// the same identity key — the row position is the only stable identity here.
///
/// Counts and the new/update index sets are computed once in `init` and maintained
/// incrementally. A 1912-source pack (yckceo's collection) re-scanning every entry on
/// each tap is the same quadratic shape that made the source list take 670s, so
/// nothing here walks the whole array per toggle.
@MainActor
final class SourceImportPlan<Source: ImportableSource>: ObservableObject {

    /// One row: the incoming item plus how it compares to the library.
    struct Entry: Identifiable {
        /// Position in the incoming pack. Stable for the lifetime of the plan and the
        /// key the selection set stores.
        let id: Int
        var source: Source
        var state: SourceImportItemState
    }

    @Published private(set) var entries: [Entry]
    /// Ticked row ids. One `Set` write per tap, so a tap republishes once.
    @Published private(set) var selectedIDs: Set<Int>

    /// Row ids by state, so 「全選新增」/「全選更新」 and the toolbar's enablement don't
    /// re-derive the states on every body pass.
    private(set) var newIDs: Set<Int>
    private(set) var updateIDs: Set<Int>

    /// Builds the plan by comparing each incoming item against the library.
    ///
    /// - Parameters:
    ///   - incoming: the parsed pack, in file order.
    ///   - existingClock: the library's `lastUpdateTime` for an identity key, or `nil`
    ///     when the library has no item under that key.
    init(incoming: [Source], existingClock: (String) -> Int64?) {
        var entries: [Entry] = []
        entries.reserveCapacity(incoming.count)
        var selected: Set<Int> = []
        var newIDs: Set<Int> = []
        var updateIDs: Set<Int> = []

        for (index, source) in incoming.enumerated() {
            let state: SourceImportItemState
            if let localClock = existingClock(source.importIdentityKey) {
                state = localClock < source.importUpdateClock ? .update : .existing
            } else {
                state = .new
            }
            entries.append(Entry(id: index, source: source, state: state))
            switch state {
            case .new:
                newIDs.insert(index)
                selected.insert(index)
            case .update:
                updateIDs.insert(index)
                selected.insert(index)
            case .existing:
                // Upstream leaves these unticked: re-importing a copy the author has not
                // dated as newer would overwrite local edits for no gain. The user can
                // still tick them by hand.
                break
            }
        }

        self.entries = entries
        self.selectedIDs = selected
        self.newIDs = newIDs
        self.updateIDs = updateIDs
    }

    // MARK: Derived counts

    var totalCount: Int { entries.count }
    var selectedCount: Int { selectedIDs.count }
    var newCount: Int { newIDs.count }
    var updateCount: Int { updateIDs.count }
    var existingCount: Int { entries.count - newIDs.count - updateIDs.count }

    var isEmpty: Bool { entries.isEmpty }

    /// Whether every row is ticked — drives the footer's 全選 ⇄ 取消全選 flip.
    var isSelectingAll: Bool {
        !entries.isEmpty && selectedIDs.count == entries.count
    }

    var isSelectingAllNew: Bool {
        !newIDs.isEmpty && newIDs.isSubset(of: selectedIDs)
    }

    var isSelectingAllUpdate: Bool {
        !updateIDs.isEmpty && updateIDs.isSubset(of: selectedIDs)
    }

    func isSelected(_ id: Int) -> Bool {
        selectedIDs.contains(id)
    }

    /// The ticked items, in file order — what the importer actually writes.
    var selectedSources: [Source] {
        entries.filter { selectedIDs.contains($0.id) }.map(\.source)
    }

    // MARK: Mutation

    func toggle(_ id: Int) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func setSelected(_ isSelected: Bool, for id: Int) {
        if isSelected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    /// Footer 全選: ticks everything, or clears everything when all are already ticked.
    func toggleSelectAll() {
        if isSelectingAll {
            selectedIDs = []
        } else {
            selectedIDs = Set(entries.map(\.id))
        }
    }

    /// Menu 全選新增: ticks every 「新增」 row, or unticks them when all are already ticked.
    /// Rows in other states are untouched, matching upstream.
    func toggleSelectAllNew() {
        if isSelectingAllNew {
            selectedIDs.subtract(newIDs)
        } else {
            selectedIDs.formUnion(newIDs)
        }
    }

    /// Menu 全選更新, the 「更新」 counterpart of `toggleSelectAllNew()`.
    func toggleSelectAllUpdate() {
        if isSelectingAllUpdate {
            selectedIDs.subtract(updateIDs)
        } else {
            selectedIDs.formUnion(updateIDs)
        }
    }

    /// Applies a per-row JSON edit. The row keeps its position and its ticked state; its
    /// state badge is recomputed because the edit can change the identity key or the
    /// declared `lastUpdateTime`.
    ///
    /// Returns `false` when the text does not parse, so the caller can keep the editor open.
    @discardableResult
    func applyEdit(json: String, to id: Int, existingClock: (String) -> Int64?) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              let parsed = Source.importParse(editedJSON: json) else {
            return false
        }
        let state: SourceImportItemState
        if let localClock = existingClock(parsed.importIdentityKey) {
            state = localClock < parsed.importUpdateClock ? .update : .existing
        } else {
            state = .new
        }
        newIDs.remove(id)
        updateIDs.remove(id)
        switch state {
        case .new: newIDs.insert(id)
        case .update: updateIDs.insert(id)
        case .existing: break
        }
        entries[index].source = parsed
        entries[index].state = state
        return true
    }
}
