import SwiftUI

/// 书坊批量刮削 — one tap finds covers for every coverless shelf book.
struct BookshelfScrapeView: View {
    @EnvironmentObject var store: BookStore

    private enum Phase: Equatable {
        case idle
        case scraping(progress: String)
        case finished(success: Int, failed: Int)
    }

    private struct Outcome: Identifiable {
        let id = UUID()
        let bookTitle: String
        let found: Bool
        let providerName: String?
    }

    @State private var phase: Phase = .idle
    @State private var outcomes: [Outcome] = []
    @State private var scrapeTask: Task<Void, Never>?

    private var coverlessBooks: [ReadingBook] {
        store.books.filter { $0.coverImagePath == nil }
    }

    var body: some View {
        List {
            Section {
                switch phase {
                case .idle:
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        Text(localized("掃描無封面書籍並自動搜尋封面"))
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textPrimary)
                        Text(
                            String(format: localized("書坊中共有 %d 本無封面書籍。"), coverlessBooks.count)
                        )
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                        Button {
                            startScrape()
                        } label: {
                            Label(localized("開始刮削"), systemImage: "sparkle.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(coverlessBooks.isEmpty)
                    }
                    .padding(.vertical, DSSpacing.sm)
                case .scraping(let progress):
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        Text(progress)
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textPrimary)
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    .padding(.vertical, DSSpacing.sm)
                case .finished(let success, let failed):
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        Text(localized("刮削完成"))
                            .font(DSFont.headline)
                            .foregroundStyle(DSColor.textPrimary)
                        Text(
                            String(format: localized("成功 %d 本，失敗 %d 本。"), success, failed)
                        )
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                    }
                    .padding(.vertical, DSSpacing.sm)
                }
            }
            .interfaceSectionSurface()

            if !outcomes.isEmpty {
                Section(localized("刮削結果")) {
                    ForEach(outcomes) { outcome in
                        HStack {
                            Text(outcome.bookTitle)
                                .font(DSFont.body)
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            if outcome.found {
                                Text(outcome.providerName ?? localized("找到封面"))
                                    .font(DSFont.caption)
                                    .foregroundStyle(DSColor.success)
                            } else {
                                Text(localized("未找到封面"))
                                    .font(DSFont.caption)
                                    .foregroundStyle(DSColor.warning)
                            }
                        }
                    }
                }
                .interfaceSectionSurface()
            }
        }
        .listStyle(.insetGrouped)
        .themedAppSurface()
        .softScrollEdges()
        .navigationTitle(localized("刮削書坊封面"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localized("取消")) {
                    scrapeTask?.cancel()
                }
                .disabled(phase == .idle)
            }
        }
        .onDisappear {
            scrapeTask?.cancel()
        }
    }

    private func startScrape() {
        let candidates = coverlessBooks
        outcomes = []
        phase = .scraping(progress: String(format: localized("刮削中 %d/%d"), 0, candidates.count))

        scrapeTask = Task { @MainActor in
            var success = 0
            for (index, book) in candidates.enumerated() {
                if Task.isCancelled { break }
                phase = .scraping(
                    progress: String(format: localized("刮削中 %d/%d"), index + 1, candidates.count)
                )
                let found = await scrapeCover(for: book)
                if found { success += 1 }
            }
            let failed = candidates.count - success
            phase = .finished(success: success, failed: failed)
        }
    }

    @MainActor
    private func scrapeCover(for book: ReadingBook) async -> Bool {
        let results = await OnlineCoverSearchService.searchCovers(
            name: book.title,
            author: book.author
        )
        guard let first = results.first else {
            outcomes.append(
                Outcome(bookTitle: book.title, found: false, providerName: nil)
            )
            return false
        }
        let applied = await store.applyCustomCover(
            bookId: book.id,
            coverUrl: first.coverUrl,
            sourceId: nil
        )
        outcomes.append(
            Outcome(bookTitle: book.title, found: applied, providerName: applied ? first.providerName : nil)
        )
        return applied
    }
}

#Preview {
    NavigationStack {
        BookshelfScrapeView()
            .environmentObject(BookStore())
    }
}
