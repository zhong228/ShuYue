import Combine
import Foundation
import Testing
@testable import yuedu_app

@Suite(.serialized)
@MainActor
struct SubscriptionPublicationTests {
    @Test func repeatedFreeStatusDoesNotInvalidateSubscribers() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "subscription_had_pro_ever")
        defaults.set(false, forKey: "subscription_had_pro_ever")
        defer { defaults.set(saved, forKey: "subscription_had_pro_ever") }
        let store = SubscriptionStore(observeTransactions: false)
        var updates = 0
        let token = store.$isProActive.dropFirst().sink { _ in updates += 1 }
        store.debugForceProActive = false
        store.debugForceProActive = false
        #expect(!store.isProActive)
        #expect(updates == 0)
        withExtendedLifetime(token) {}
    }

    @Test func recomputingTheSameEntitlementDoesNotRepublishIt() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "subscription_had_pro_ever")
        defer { defaults.set(saved, forKey: "subscription_had_pro_ever") }
        let store = SubscriptionStore(observeTransactions: false)
        var effective: [Bool] = [], purchased: [Bool] = []
        let effectiveToken = store.$isProActive.dropFirst().sink { effective.append($0) }
        let purchasedToken = store.$storeKitIsProActive.dropFirst().sink { purchased.append($0) }
        store.debugForceProActive = true
        store.debugForceProActive = true
        #expect(effective == [true])
        #expect(purchased.isEmpty)
        #expect(store.isProActive)
        withExtendedLifetime((effectiveToken, purchasedToken)) {}
    }
}
