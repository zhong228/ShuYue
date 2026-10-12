import Foundation
import Testing
@testable import yuedu_app

/// What one downloaded sync blob holds. A blob that cannot be read is not an empty one:
/// merged as "the cloud has nothing", a sync uploaded this device's view over it, and what
/// only other devices had was gone from the cloud until they uploaded it again (2026-10-05).
@Suite("iCloud sync blob decoding")
struct ICloudSyncBlobDecodingTests {
    private struct Item: Codable, Equatable {
        var id: String
        var text: String
    }

    private let stamped = Date(timeIntervalSince1970: 1_700_000_000)

    private func decode(_ data: Data) throws -> (records: [FirestoreSyncRecord<Item>], payloadHash: String?) {
        try ICloudSyncManager.decodeCloudSyncBlob(
            data, recordName: "items_v2",
            id: { $0.id }, fallbackUpdatedAt: { _ in .distantPast }
        )
    }

    @Test("a blob in neither format throws instead of reading as empty")
    func anUnreadableBlobThrows() {
        #expect(throws: ICloudSyncError.self) { try decode(Data("<html>503 Service Unavailable</html>".utf8)) }
        #expect(throws: ICloudSyncError.self) { try decode(Data(#"{"records":[]}"#.utf8)) }
    }

    @Test("the merge format, with its payload hash")
    func theMergeFormat() throws {
        let records = [
            CloudSyncRecord(id: "a", value: Item(id: "a", text: "A"), updatedAt: stamped, deleted: false),
            CloudSyncRecord<Item>(id: "b", value: nil, updatedAt: stamped, deleted: true),
        ]
        let blob = try decode(ICloudSyncManager.encodeCloudSyncRecords(records))
        #expect(blob.records.map(\.id) == ["a", "b"])
        #expect(blob.records.map(\.deleted) == [false, true])
        #expect(blob.payloadHash == (try ICloudSyncManager.cloudSyncPayloadHash(records)))
    }

    @Test("a plain array from before the merge sync: every item live")
    func aPlainArray() throws {
        let blob = try decode(JSONEncoder().encode([Item(id: "a", text: "A")]))
        #expect(blob.records.map(\.id) == ["a"])
        #expect(blob.records.first?.deleted == false)
        #expect(blob.payloadHash == nil)
    }

    @Test("an empty blob is empty")
    func anEmptyBlobIsEmpty() throws {
        #expect(try decode(Data("[]".utf8)).records.isEmpty)
    }
}
