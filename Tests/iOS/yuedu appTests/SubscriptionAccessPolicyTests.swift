import Foundation
import Testing
@testable import yuedu_app

@Suite("Subscription access policy")
struct SubscriptionAccessPolicyTests {
    @Test("StoreKit, account and iCloud entitlements coexist")
    func entitlementsCoexist() {
        #expect(!SubscriptionAccessPolicy.isProActive(storeKit: false, account: false, iCloud: false))
        #expect(SubscriptionAccessPolicy.isProActive(storeKit: true, account: false, iCloud: false))
        #expect(SubscriptionAccessPolicy.isProActive(storeKit: false, account: true, iCloud: false))
        #expect(SubscriptionAccessPolicy.isProActive(storeKit: false, account: false, iCloud: true))
        #expect(SubscriptionAccessPolicy.isProActive(storeKit: true, account: true, iCloud: true))
    }

    @Test("iCloud alone carries a guest purchase across an App Store account switch")
    func iCloudMirrorSurvivesStoreAccountSwitch() {
        // The reported failure: a guest purchase, so no MoYue account, and the new
        // App Store account holds no transactions. Only the mirror is left.
        #expect(SubscriptionAccessPolicy.isProActive(storeKit: false, account: false, iCloud: true))
    }

    @Test("an emptied App Store account leaves the iCloud mirror alone")
    func emptyStoreAccountDoesNotClearMirror() {
        // Zero owned and zero revoked is what a switched App Store account looks
        // like. Clearing here would erase the only surviving grant.
        #expect(SubscriptionICloudMirrorPolicy.action(ownedCount: 0, revokedCount: 0) == .leaveAlone)
    }

    @Test("an Apple revocation clears the iCloud mirror")
    func revocationClearsMirror() {
        #expect(SubscriptionICloudMirrorPolicy.action(ownedCount: 0, revokedCount: 1) == .revoke)
    }

    @Test("an active entitlement is mirrored even alongside a revoked one")
    func activeEntitlementIsMirrored() {
        #expect(SubscriptionICloudMirrorPolicy.action(ownedCount: 1, revokedCount: 0) == .store)
        #expect(SubscriptionICloudMirrorPolicy.action(ownedCount: 1, revokedCount: 1) == .store)
    }

    @Test("cached monthly entitlement expires offline")
    func cachedEntitlementExpiry() {
        let now = Date(timeIntervalSince1970: 1_000)
        let monthly = CachedSubscriptionEntitlement(
            isProActive: true,
            expiresAt: now.addingTimeInterval(60)
        )
        let lifetime = CachedSubscriptionEntitlement(isProActive: true, expiresAt: nil)

        #expect(monthly.isActive(at: now))
        #expect(!monthly.isActive(at: now.addingTimeInterval(60)))
        #expect(lifetime.isActive(at: now.addingTimeInterval(1_000_000)))
        #expect(!CachedSubscriptionEntitlement(isProActive: false, expiresAt: nil).isActive(at: now))
    }

    private static let lifetimeID = "com.zhong228.shuyue.pro.lifetime"
    private static let monthlyID = "com.zhong228.shuyue.pro.monthly"

    private func paywallState(
        purchased: Set<String>,
        isProActive: Bool
    ) -> PaywallPresentationState {
        PaywallPresentationPolicy.state(
            purchasedProductIDs: purchased,
            lifetimeProductID: Self.lifetimeID,
            monthlyProductID: Self.monthlyID,
            isProActive: isProActive
        )
    }

    @Test("a lifetime owner is never shown the purchase options again")
    func lifetimeOwnerSeesNoPaywall() {
        // Opening straight onto the plan picker reads as being asked to pay twice.
        #expect(paywallState(purchased: [Self.lifetimeID], isProActive: true) == .alreadyPro)
        // Even holding both, lifetime wins: there is nothing left to sell.
        #expect(
            paywallState(purchased: [Self.lifetimeID, Self.monthlyID], isProActive: true)
                == .alreadyPro
        )
    }

    @Test("a monthly subscriber is offered the lifetime upgrade")
    func monthlySubscriberSeesUpgrade() {
        #expect(paywallState(purchased: [Self.monthlyID], isProActive: true) == .upgradeFromMonthly)
    }

    @Test("Pro without a local transaction gets the member page, not the offer")
    func accountGrantedProHidesPaywall() {
        // Pro arriving from the MoYue account or the iCloud mirror — bought on
        // another Apple Account — leaves no local transaction to name the plan,
        // but there is still nothing to sell.
        #expect(paywallState(purchased: [], isProActive: true) == .alreadyPro)
    }

    @Test("a free user sees the normal offer")
    func freeUserSeesOffer() {
        #expect(paywallState(purchased: [], isProActive: false) == .offer)
    }

    private func ownedPlanID(purchased: Set<String>) -> String? {
        PaywallPresentationPolicy.ownedPlanID(
            purchasedProductIDs: purchased,
            lifetimeProductID: Self.lifetimeID,
            monthlyProductID: Self.monthlyID
        )
    }

    @Test("the member page names lifetime whenever it is owned, then monthly")
    func memberPageNamesTheOwnedPlan() {
        #expect(ownedPlanID(purchased: [Self.lifetimeID]) == Self.lifetimeID)
        #expect(ownedPlanID(purchased: [Self.monthlyID]) == Self.monthlyID)
        // A monthly plan still held next to lifetime is billing to cancel, not their plan.
        #expect(ownedPlanID(purchased: [Self.monthlyID, Self.lifetimeID]) == Self.lifetimeID)
        // Pro from the MoYue account or the iCloud mirror names no plan on this Apple Account.
        #expect(ownedPlanID(purchased: []) == nil)
    }

    private func subscriptionManagement(purchased: Set<String>) -> ProSubscriptionManagement {
        ProStatusPagePolicy.subscriptionManagement(
            purchasedProductIDs: purchased,
            lifetimeProductID: Self.lifetimeID,
            monthlyProductID: Self.monthlyID
        )
    }

    @Test("the member page links to Apple's subscription management only for a monthly plan")
    func subscriptionManagementNeedsMonthly() {
        #expect(subscriptionManagement(purchased: [Self.monthlyID]) == .monthly)
        // Lifetime is not a subscription, and Pro granted by the account or the
        // iCloud mirror leaves nothing on this Apple Account to manage.
        #expect(subscriptionManagement(purchased: [Self.lifetimeID]) == .unavailable)
        #expect(subscriptionManagement(purchased: []) == .unavailable)
    }

    @Test("monthly held next to lifetime keeps the cancellation reminder")
    func monthlyAlongsideLifetimeRemindsToCancel() {
        // Buying lifetime never ends the monthly subscription. Without the reminder
        // it keeps billing once the one-time thank-you page is gone.
        #expect(
            subscriptionManagement(purchased: [Self.monthlyID, Self.lifetimeID])
                == .monthlyAlongsideLifetime
        )
    }

    @Test("complete product cache reloads after the App Store storefront changes")
    func productCacheReloadsForChangedStorefront() {
        #expect(SubscriptionProductReloadPolicy.shouldReload(
            loadedProductCount: 2,
            expectedProductCount: 2,
            loadedStorefrontID: "USA",
            currentStorefrontID: "TWN"
        ))
    }

    @Test("complete product cache remains valid for the same storefront")
    func productCacheRemainsValidForSameStorefront() {
        #expect(!SubscriptionProductReloadPolicy.shouldReload(
            loadedProductCount: 2,
            expectedProductCount: 2,
            loadedStorefrontID: "TWN",
            currentStorefrontID: "TWN"
        ))
    }

    @Test("incomplete product cache reloads without storefront information")
    func incompleteProductCacheReloadsWithoutStorefront() {
        #expect(SubscriptionProductReloadPolicy.shouldReload(
            loadedProductCount: 1,
            expectedProductCount: 2,
            loadedStorefrontID: nil,
            currentStorefrontID: nil
        ))
    }

    @Test("idle offer-code request presents when a window scene is available")
    func idleOfferCodeRequestPresents() {
        #expect(SubscriptionOfferCodeRedemptionPolicy.action(
            isRedeeming: false,
            hasWindowScene: true
        ) == .present)
    }

    @Test("offer-code request is ignored while another sheet is active")
    func duplicateOfferCodeRequestIsIgnored() {
        #expect(SubscriptionOfferCodeRedemptionPolicy.action(
            isRedeeming: true,
            hasWindowScene: true
        ) == .ignore)
    }

    @Test("offer-code request reports unavailable without a window scene")
    func offerCodeRequestWithoutSceneReportsUnavailable() {
        #expect(SubscriptionOfferCodeRedemptionPolicy.action(
            isRedeeming: false,
            hasWindowScene: false
        ) == .reportUnavailable)
    }
}
