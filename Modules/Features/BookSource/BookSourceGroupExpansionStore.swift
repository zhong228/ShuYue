import Combine
import Foundation

/// Local presentation preferences. Only collapsed groups are stored so new groups
/// start expanded; filtering or temporarily emptying a group never erases its choice.
@MainActor
final class BookSourceGroupExpansionStore: ObservableObject {
    private static let storageKey = "bookSourceList.collapsedGroups"
    private let defaults: UserDefaults
    @Published private var collapsedGroups: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        collapsedGroups = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    func isExpanded(_ id: String) -> Bool {
        !collapsedGroups.contains(id)
    }

    func toggle(_ id: String) {
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
        defaults.set(collapsedGroups.sorted(), forKey: Self.storageKey)
    }
}
