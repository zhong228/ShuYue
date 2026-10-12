import Combine
import Foundation

@MainActor
final class AICustomPromptStore: ObservableObject {
    static let shared = AICustomPromptStore()
    @Published private(set) var prompts: [AICustomPrompt] = []
    @Published private(set) var failure: String?
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "yd_ai_custom_prompts") {
        self.defaults = defaults; self.key = key
        if let data = defaults.data(forKey: key) {
            do { prompts = try JSONDecoder().decode([AICustomPrompt].self, from: data) }
            catch { failure = error.localizedDescription }
        }
    }

    func save(_ values: [AICustomPrompt]) throws {
        // A corrupt store must be recoverable without overwriting it with an empty view.
        guard failure == nil else { throw AIProviderStore.LoadError.corruptedConfiguration }
        let data = try JSONEncoder().encode(values)
        defaults.set(data, forKey: key)
        prompts = values
    }
}
