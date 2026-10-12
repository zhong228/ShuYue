import UIKit

/// Updated at geometry boundaries, never per glyph. Also read by the opt-in
/// gesture harness; a geometrically correct offset can still kill momentum.
struct ViewportCommitDiagnostics {
    var commits = 0
    var decelerationCorrections = 0
    var interruptedDecelerations = 0
    var continuedDecelerations = 0
    var countChanges = 0
    var insertions = 0
    var decelerationInsertions = 0
    var progressDuringGeometry = 0
    var maximumScreenError: CGFloat = 0

    mutating func record(correction: CGFloat, screenError: CGFloat,
                         wasDecelerating: Bool, isDecelerating: Bool,
                         countChanged: Bool, cause: String) {
        commits += 1
        maximumScreenError = max(maximumScreenError, abs(screenError))
        if countChanged { countChanges += 1 }
        if cause == "chapterInsertion" {
            insertions += 1
            if wasDecelerating { decelerationInsertions += 1 }
        }
        if wasDecelerating && abs(correction) > 0.01 {
            decelerationCorrections += 1
            if !isDecelerating { interruptedDecelerations += 1 }
        }
    }
}
