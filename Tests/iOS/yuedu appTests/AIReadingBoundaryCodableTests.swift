import Foundation
import Testing
@testable import yuedu_app

struct AIReadingBoundaryCodableTests {
    @Test func preservesEncodedCoordinateUnitAndBoundary() throws {
        let boundary = AIReadingBoundary(sourceVersion: "v1", sectionID: "chapter.xhtml",
                                         spineIndex: 3, utf16Offset: 42, wholeBook: true)
        let data = try JSONEncoder().encode(boundary)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["coordinateUnit"] as? String == "sourceUTF16")
        #expect(try JSONDecoder().decode(AIReadingBoundary.self, from: data) == boundary)
    }

    @Test func decodingKeepsTheFixedUnitRegardlessOfStoredUnit() throws {
        for unit in [nil, "sourceUTF16", "pageIndex"] as [String?] {
            var json: [String: Any] = ["sourceVersion": "v1", "sectionID": "0",
                                       "spineIndex": 0, "utf16Offset": 12, "wholeBook": false]
            json["coordinateUnit"] = unit
            let data = try JSONSerialization.data(withJSONObject: json)
            let boundary = try JSONDecoder().decode(AIReadingBoundary.self, from: data)
            #expect(boundary.coordinateUnit == "sourceUTF16")
            #expect(boundary.utf16Offset == 12)
            #expect(!boundary.wholeBook)
        }
    }
}
