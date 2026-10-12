import Foundation

/// A remote sync record: the value a device uploaded plus when and whether it
/// was deleted. `value` is nil for a tombstone.
///
/// Extracted from the retired Firestore account sync into the shared merge core:
/// the iCloud (CloudKit) sync reuses the same last-write-wins merge so the two
/// sync channels agree on what wins.
struct FirestoreSyncRecord<Value> {
    var id: String
    var value: Value?
    var updatedAt: Date
    var deleted: Bool
}

/// Per-id merge bookkeeping kept locally between syncs, so a device knows what it
/// already saw and when, without re-reading the whole cloud copy every time.
struct SyncShadowEntry: Codable, Equatable {
    var updatedAt: Date
    var hash: String
    var deleted: Bool
}

/// Last-write-wins merge that understands tombstones in both directions.
/// Returns the resolved values plus an updated shadow (per-id timestamp/hash/deleted).
enum FirestoreSyncMerge {
    static func merge<Value>(
        local: [Value],
        remote: [FirestoreSyncRecord<Value>],
        shadow: [String: SyncShadowEntry],
        id: (Value) -> String,
        hash: (Value) -> String,
        fallbackUpdatedAt: (Value) -> Date
    ) -> (values: [Value], shadow: [String: SyncShadowEntry]) {
        var orderedIDs: [String] = []
        let totalCount = max(local.count, shadow.count)
        var valuesByID: [String: Value] = .init(minimumCapacity: totalCount)
        var newShadow: [String: SyncShadowEntry] = .init(minimumCapacity: max(totalCount, remote.count))

        // Carry forward tombstones we already know about (local deletions, possibly not pushed yet).
        for (sid, entry) in shadow where entry.deleted {
            newShadow[sid] = entry
        }

        // Seed with local values.
        for value in local {
            let valueID = id(value)
            orderedIDs.append(valueID)
            valuesByID[valueID] = value
            let updatedAt = shadow[valueID]?.updatedAt ?? fallbackUpdatedAt(value)
            newShadow[valueID] = SyncShadowEntry(updatedAt: updatedAt, hash: hash(value), deleted: false)
        }

        for record in remote {
            let localEntry = newShadow[record.id]

            if record.deleted {
                // Remote deletion wins unless we have a strictly newer local edit.
                if let localEntry, !localEntry.deleted, localEntry.updatedAt > record.updatedAt {
                    continue
                }
                valuesByID[record.id] = nil
                newShadow[record.id] = SyncShadowEntry(updatedAt: record.updatedAt, hash: "", deleted: true)
                continue
            }

            guard let value = record.value else { continue }

            if let localEntry {
                // We already have (or previously tombstoned) this id locally.
                if record.updatedAt >= localEntry.updatedAt {
                    if localEntry.deleted {
                        orderedIDs.append(record.id)
                    }
                    valuesByID[record.id] = value
                    newShadow[record.id] = SyncShadowEntry(updatedAt: record.updatedAt, hash: hash(value), deleted: false)
                }
            } else {
                // Brand new remote item.
                orderedIDs.append(record.id)
                valuesByID[record.id] = value
                newShadow[record.id] = SyncShadowEntry(updatedAt: record.updatedAt, hash: hash(value), deleted: false)
            }
        }

        let values = orderedIDs.compactMap { valuesByID[$0] }
        return (values, newShadow)
    }
}

/// Persisted merge shadows (UserDefaults), keyed per sync collection.
enum SyncShadowStore {
    private static let prefix = "yd_firestore_shadow_"

    static func load(_ collection: String) -> [String: SyncShadowEntry] {
        guard let data = UserDefaults.standard.data(forKey: prefix + collection),
              let decoded = try? JSONDecoder().decode([String: SyncShadowEntry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func save(_ collection: String, _ entries: [String: SyncShadowEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: prefix + collection)
    }

    static func clearAll(collections: [String]) {
        for collection in collections {
            UserDefaults.standard.removeObject(forKey: prefix + collection)
        }
    }
}