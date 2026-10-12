import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

/// The root cause behind 「開始驗證」 not responding the first time 書源驗證 opened.
///
/// 書源管理 set `pendingCheckSources` and `showCheckOptions = true` in one action, and the
/// `.sheet(isPresented:)` content read `pendingCheckSources.count` — state that `body`
/// never read. The probe below is that exact shape, next to the `.sheet(item:)` shape the
/// screen uses now.
@Suite(.serialized)
@MainActor
struct SheetStateSnapshotTests {
    @Test("sheet content that reads state body never reads sees the stale value first")
    func isPresentedSheetReadsStaleState() throws {
        let recorder = SheetProbeRecorder()
        let host = try WindowHost(IsPresentedSheetProbe(recorder: recorder))
        defer { host.tearDown() }

        try presentAndRecord(host: host, recorder: recorder)
        // The first presentation is built from the previous render: an empty payload —
        // 「將對 0 個書源」, and `.disabled(sourceCount == 0)` on 開始驗證.
        #expect(recorder.seenCounts.first == 0)
    }

    @Test("an item sheet receives the payload it was presented with")
    func itemSheetReadsItsPayload() throws {
        let recorder = SheetProbeRecorder()
        let host = try WindowHost(ItemSheetProbe(recorder: recorder))
        defer { host.tearDown() }

        try presentAndRecord(host: host, recorder: recorder)
        #expect(recorder.seenCounts.first == 3)
    }

    private func presentAndRecord(host: WindowHost, recorder: SheetProbeRecorder) throws {
        host.pump(seconds: 0.2)
        let trigger = try #require(recorder.trigger)
        // What the menu button's action did: set the payload and present, in one action.
        trigger()
        let deadline = Date(timeIntervalSinceNow: 5)
        while recorder.seenCounts.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }
}

@MainActor
final class SheetProbeRecorder {
    var trigger: (() -> Void)?
    var seenCounts: [Int] = []
}

/// 書源管理's old shape.
private struct IsPresentedSheetProbe: View {
    let recorder: SheetProbeRecorder
    @State private var showSheet = false
    @State private var pendingSources: [Int] = []

    var body: some View {
        Color.clear
            .onAppear {
                recorder.trigger = {
                    pendingSources = [1, 2, 3]
                    showSheet = true
                }
            }
            .sheet(isPresented: $showSheet) {
                SheetProbeContent(count: pendingSources.count, recorder: recorder)
            }
    }
}

/// The shape 書源管理 uses now.
private struct ItemSheetProbe: View {
    private struct Payload: Identifiable {
        let id = UUID()
        let sources: [Int]
    }

    let recorder: SheetProbeRecorder
    @State private var pending: Payload?

    var body: some View {
        Color.clear
            .onAppear {
                recorder.trigger = {
                    pending = Payload(sources: [1, 2, 3])
                }
            }
            .sheet(item: $pending) { payload in
                SheetProbeContent(count: payload.sources.count, recorder: recorder)
            }
    }
}

private struct SheetProbeContent: View {
    let count: Int
    let recorder: SheetProbeRecorder

    var body: some View {
        Text("\(count)")
            .onAppear { recorder.seenCounts.append(count) }
    }
}
