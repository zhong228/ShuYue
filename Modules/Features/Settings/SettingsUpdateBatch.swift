import Foundation

/// Compare before invoking a @Published setter: a didSet guard is too late to
/// prevent objectWillChange. This owns no state and never delays an update.
@MainActor
struct SettingsUpdateBatch<Root: AnyObject> {
    let root: Root
    let reason: String
    private let start = SourcePerfTrace.now
    private(set) var changedFields: [String] = []

    init(_ root: Root, reason: String) {
        self.root = root
        self.reason = reason
    }

    mutating func set<Value: Equatable>(_ path: ReferenceWritableKeyPath<Root, Value>,
                                       _ value: Value, field: String) {
        guard root[keyPath: path] != value else { return }
        root[keyPath: path] = value
        changedFields.append(field)
    }

    func finish() {
        SourcePerfTrace.record("settings.apply", "reason=\(reason) changed=\(changedFields.count) fields=\(changedFields.joined(separator: ","))",
                               since: start, thresholdMs: 0)
    }
}