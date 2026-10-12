import SwiftUI

// MARK: - TTSSourceImportReviewHost

/// The import confirmation list for online narration engines — Legado's
/// `ImportHttpTtsDialog`, which is the book-source dialog minus the options that only make
/// sense for a book source: `HttpTTS` has no group, no comment field, and upstream overwrites
/// the whole record rather than keeping parts of the local copy.
///
/// The list itself, the 新增/更新/已有 states and the per-row JSON editor are the shared
/// `SourceImportConfirmList`.
struct TTSSourceImportReviewHost: View {
    /// What the pack parsed to.
    let sources: [ImportedTTSSource]
    /// The library as it stands, for the state badges and the merge.
    let existing: [ImportedTTSSource]
    /// Hands back the merged library and how many rows were taken.
    let onFinish: (_ merged: [ImportedTTSSource], _ importedCount: Int) -> Void
    let onCancel: () -> Void

    @StateObject private var plan: SourceImportPlan<ImportedTTSSource>
    private let clocks: [String: Int64]
    /// `HttpTTS` carries no comment, so the switch has nothing to show and stays off.
    @State private var showsComments = false

    init(
        sources: [ImportedTTSSource],
        existing: [ImportedTTSSource],
        onFinish: @escaping (_ merged: [ImportedTTSSource], _ importedCount: Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sources = sources
        self.existing = existing
        self.onFinish = onFinish
        self.onCancel = onCancel
        let clocks = TTSSourceImportMerge.existingUpdateClocks(in: existing)
        self.clocks = clocks
        _plan = StateObject(
            wrappedValue: SourceImportPlan(incoming: sources) { clocks[$0] }
        )
    }

    var body: some View {
        SourceImportConfirmList(
            title: localized("匯入語音源"),
            plan: plan,
            existingClock: { clocks[$0] },
            showsComments: $showsComments,
            confirmTitle: localized("匯入"),
            extraOptions: { EmptyView() },
            onConfirm: {
                let selected = plan.selectedSources
                onFinish(
                    TTSSourceImportMerge.merged(existing: existing, importing: selected),
                    selected.count
                )
            },
            onCancel: onCancel
        )
    }
}

// MARK: - PendingTTSSourceReview

/// `sheet(item:)` identity for a parsed pack awaiting review.
struct PendingTTSSourceReview: Identifiable {
    let id = UUID()
    let sources: [ImportedTTSSource]
}
