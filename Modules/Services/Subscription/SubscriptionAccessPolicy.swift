import StoreKit

enum SubscriptionAccessPolicy {
    /// Two independent grants, unioned. They are keyed by two different
    /// identities on purpose: `storeKit` by the App Store account and `iCloud` by
    /// the iCloud account (via the mirror). A user who switches App Store
    /// accounts loses only the first; the iCloud mirror keeps the grant. The
    /// account (Firebase) grant was removed with the account system; the
    /// `account` parameter stays for API stability and is always `false`.
    ///
    /// MoYue v1.0.10+: all features are free and open. The entitlement machinery
    /// (StoreKit product loading, restore, the iCloud mirror) is kept intact so
    /// the codebase stays buildable and the UI keeps working, but the *verdict*
    /// is always granted — every feature is unlocked for every user. The
    /// parameters are kept for API stability and ignored.
    static func isProActive(storeKit: Bool, account: Bool, iCloud: Bool) -> Bool {
        true
    }
}

enum PaywallPresentationState: Equatable {
    /// Nothing owned yet: the normal offer.
    case offer
    /// An active monthly subscription. Lifetime is still sellable, framed as an
    /// upgrade, and monthly must not be offered again.
    case upgradeFromMonthly
    /// Lifetime owned, or Pro arriving from the iCloud mirror with no local
    /// transaction to identify the plan. Either way there is nothing left to
    /// sell, so the paywall shows its member page, not an offer.
    case alreadyPro
}

enum PaywallPresentationPolicy {
    /// What the paywall should show on open.
    ///
    /// Opening straight onto the purchase options for someone who already paid —
    /// especially a lifetime buyer — reads as being asked to pay twice, so
    /// ownership is resolved before anything is offered.
    static func state(
        purchasedProductIDs: Set<String>,
        lifetimeProductID: String,
        monthlyProductID: String,
        isProActive: Bool
    ) -> PaywallPresentationState {
        if purchasedProductIDs.contains(lifetimeProductID) { return .alreadyPro }
        if purchasedProductIDs.contains(monthlyProductID) { return .upgradeFromMonthly }
        return isProActive ? .alreadyPro : .offer
    }

    /// The plan the member page names as theirs: lifetime whenever it is owned — a
    /// monthly plan still held beside it is billing to cancel, not their plan — then
    /// monthly. Nil for Pro from the iCloud mirror, which has no transaction on
    /// this Apple Account to name a plan by.
    static func ownedPlanID(
        purchasedProductIDs: Set<String>,
        lifetimeProductID: String,
        monthlyProductID: String
    ) -> String? {
        if purchasedProductIDs.contains(lifetimeProductID) { return lifetimeProductID }
        if purchasedProductIDs.contains(monthlyProductID) { return monthlyProductID }
        return nil
    }
}

/// What the paywall's member page offers for Apple's subscription management.
enum ProSubscriptionManagement: Equatable {
    /// No monthly plan on this Apple Account: lifetime only, or Pro granted by the
    /// iCloud mirror. Apple's subscription list has nothing of ours to show, so
    /// the page offers no link.
    case unavailable
    /// A monthly subscription the user may want to cancel.
    case monthly
    /// Monthly still held next to lifetime. Buying a non-consumable never ends a
    /// subscription, so the link keeps the cancellation reminder that the
    /// thank-you page shows once, right after the upgrade.
    case monthlyAlongsideLifetime
}

enum ProStatusPagePolicy {
    static func subscriptionManagement(
        purchasedProductIDs: Set<String>,
        lifetimeProductID: String,
        monthlyProductID: String
    ) -> ProSubscriptionManagement {
        guard purchasedProductIDs.contains(monthlyProductID) else { return .unavailable }
        return purchasedProductIDs.contains(lifetimeProductID) ? .monthlyAlongsideLifetime : .monthly
    }
}

enum SubscriptionICloudMirrorPolicy {
    enum Action: Equatable {
        case store
        case revoke
        case leaveAlone
    }

    /// What the iCloud mirror should do after a `Transaction.currentEntitlements`
    /// read.
    ///
    /// `leaveAlone` is the entire reason the mirror exists: an App Store account
    /// holding no transactions at all for this app is indistinguishable from
    /// "the user just switched storefront accounts", which is precisely the state
    /// the mirror is there to survive. Only a transaction Apple actually revoked
    /// may clear it.
    static func action(ownedCount: Int, revokedCount: Int) -> Action {
        if ownedCount > 0 { return .store }
        if revokedCount > 0 { return .revoke }
        return .leaveAlone
    }
}

/// The environment this build itself runs in, as reported by Apple's
/// `AppTransaction` (the app's own receipt, not any purchase): a TestFlight build
/// reports `.sandbox`, an App Store build `.production`.
///
/// Not actor-isolated, because the keychain cache and the CloudKit mirror both
/// need the storage suffix from outside the main actor.
enum SubscriptionRuntimeEnvironment {
    private static let storageKey = "subscription_running_environment"

    /// `nil` until `AppTransaction` has been read once; persisted after that so
    /// later launches have an answer synchronously and offline.
    ///
    /// This is a CACHE, not the truth. It does change for what iOS treats as one
    /// installed app: a TestFlight build replaced by the App Store build keeps
    /// this container, so a remembered `.sandbox` outlived the build that wrote
    /// it and locked paying customers out of every entitlement path. Callers must
    /// keep asking `AppTransaction` and overwrite this — see
    /// `SubscriptionStore.resolveRunningEnvironment()`.
    static var current: AppStore.Environment? {
        UserDefaults.standard.string(forKey: storageKey)
            .map(AppStore.Environment.init(rawValue:))
    }

    static func remember(_ environment: AppStore.Environment) {
        UserDefaults.standard.set(environment.rawValue, forKey: storageKey)
    }

    /// Gate for every environment-scoped store. Until the environment is known
    /// there is no correct slot to use, and defaulting to the Production one
    /// would let a TestFlight build file its free entitlement where the App Store
    /// build reads it — the exact leak the suffix exists to close. Skipping the
    /// cache entirely is safe: StoreKit still reports the live entitlement.
    static var isResolved: Bool { current != nil }

    /// Suffix that keeps each environment's entitlement state in its own storage
    /// slot, for the two stores that outlive the app: the keychain cache and the
    /// CloudKit mirror. Both survive one install replacing another, so a single
    /// slot let a TestFlight install's Pro state be read straight back by an App
    /// Store build put on top of it. Production keeps the bare key so entitlement
    /// state already cached by paying users survives this change.
    static var storageSuffix: String {
        guard let current, current != .production else { return "" }
        return ".\(current.rawValue.lowercased())"
    }
}

enum SubscriptionEntitlementFilter {
    /// Whether a transaction counts as an entitlement for *this* build.
    ///
    /// StoreKit already separates the two: a TestFlight build's
    /// `Transaction.currentEntitlements` yields Sandbox transactions, an App
    /// Store build's yields Production ones. So this is defence in depth, not the
    /// primary boundary.
    ///
    /// Critically this compares against the *running* environment rather than
    /// rejecting Sandbox outright. Rejecting it meant a TestFlight build threw
    /// away the purchase it had just made, so neither the lifetime nor the
    /// monthly product ever unlocked there.
    static func shouldAccept(
        environment: AppStore.Environment,
        runningEnvironment: AppStore.Environment?,
        isDebugBuild: Bool
    ) -> Bool {
        // A local Xcode run buys either through a StoreKit configuration file
        // (.xcode) or a sandbox Apple Account (.sandbox); accept both so testing
        // is not blocked by which one the developer picked.
        if isDebugBuild { return true }
        // Environment not resolved yet (first launch, `AppTransaction` still in
        // flight): trust StoreKit's own separation rather than discarding a real
        // purchase.
        guard let runningEnvironment else { return true }
        return environment == runningEnvironment
    }
}