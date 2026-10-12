import Foundation

/// Each book's 整章翻譯 setting. Kept per book: a reader translating one English novel does
/// not want every Chinese web novel on the shelf translated too.
enum ReaderTranslationSettingsStore {
    private static func key(_ book: UUID) -> String { "yd_reader_translation_\(book.uuidString)" }

    static func presentation(for book: UUID, defaults: UserDefaults = .standard) -> ReaderTranslationPresentation {
        guard let data = defaults.data(forKey: key(book)) else {
            #if DEBUG
            if ReaderTranslationFixture.isActive { return ReaderTranslationPresentation(mode: .bilingual, language: .english) }
            #endif
            return .off
        }
        do {
            return try JSONDecoder().decode(ReaderTranslationPresentation.self, from: data)
        } catch {
            AppLogger.error("Reader translation setting could not be read", error: error, context: ["book": book.uuidString])
            return .off
        }
    }

    static func setPresentation(_ presentation: ReaderTranslationPresentation, for book: UUID, defaults: UserDefaults = .standard) {
        do {
            defaults.set(try JSONEncoder().encode(presentation), forKey: key(book))
        } catch {
            AppLogger.error("Reader translation setting could not be saved", error: error, context: ["book": book.uuidString])
        }
    }
}
