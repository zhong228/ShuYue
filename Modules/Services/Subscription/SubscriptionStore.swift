import Combine
import FirebaseCore
import FirebaseFirestore
import Foundation
import StoreKit
import SwiftUI
import UIKit
import os

enum SubscriptionProductReloadPolicy {
    static func shouldReload(
        loadedProductCount: Int,
        expectedProductCount: Int,
        loadedStorefrontID: String?,
        currentStorefrontID: String?
    ) -> Bool {
        guard loadedProductCount >= expectedProductCount else { return true }
        guard let currentStorefrontID else { return false }
        return loadedStorefrontID != currentStorefrontID
    }
}

/// Single source of truth for the `MoYue Pro` subscription.
///
/// Wraps StoreKit 2: loads the monthly/lifetime products, drives purchase and
/// restore, listens for transaction updates in the background, and combines
/// Apple Account entitlements with the iCloud mirror.
@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    private static let subscriptionLog = Logger(
        subsystem: "com.zhong228.shuyue",
        category: "Subscription"
    )

    /// Compile-time build kind; DEBUG (Xcode-launched) builds accept sandbox
    /// transactions so development testing keeps working, Release builds
    /// (TestFlight/App Store) filter them unless explicitly enabled.
    private static let isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Resolves the running environment from `AppTransaction` and persists it.
    ///
    /// This used to skip the read entirely once a value was stored, on the
    /// assumption that "the value cannot change for an installed build". It can:
    /// a TestFlight install replaced by the App Store build keeps the same bundle
    /// identifier and therefore the same UserDefaults, so `.sandbox` stayed
    /// remembered and the App Store build believed it was running in TestFlight
    /// forever. That single stale value disabled all three entitlement paths at
    /// once for a paying customer — the account path read `sandboxIsProActive`
    /// (false), the keychain/CloudKit slots resolved to the `.sandbox` suffix
    /// (empty), and `SubscriptionEntitlementFilter` rejected her Production
    /// transaction, which also made "Restore Purchases" find nothing.
    ///
    /// So the stored value is an OFFLINE FALLBACK, never a reason to skip the
    /// read. Apple is asked on every launch and its answer wins.
    private func resolveRunningEnvironment() async {
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let appTransaction) = result else { return }
            let resolved = appTransaction.environment
            if let previous = SubscriptionRuntimeEnvironment.current, previous != resolved {
                Self.subscriptionLog.notice(
                    "Running environment CHANGED \(previous.rawValue, privacy: .public) -> \(resolved.rawValue, privacy: .public); entitlement slots move with it"
                )
            }
            SubscriptionRuntimeEnvironment.remember(resolved)
            Self.subscriptionLog.notice(
                "Running environment resolved: \(resolved.rawValue, privacy: .public)"
            )
        } catch {
            // Left unresolved rather than guessed. Unresolved means StoreKit's own
            // separation stays in charge, which is safe; guessing wrong would file
            // a TestFlight entitlement under the App Store slot and re-create the
            // exact leak this is meant to close.
            Self.subscriptionLog.error(
                "AppTransaction unavailable: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func acceptsTransaction(_ environment: AppStore.Environment) -> Bool {
        SubscriptionEntitlementFilter.shouldAccept(
            environment: environment,
            runningEnvironment: SubscriptionRuntimeEnvironment.current,
            isDebugBuild: Self.isDebugBuild
        )
    }

    /// The product identifiers configured in App Store Connect and the local
    /// `.storekit` file. Order here is the display order on the paywall.
    enum ProProduct: String, CaseIterable {
        case lifetime = "com.zhong228.shuyue.pro.lifetime"
        case monthly = "com.zhong228.shuyue.pro.monthly"
    }

    // MARK: - Published state

    /// Loaded `Product` values, ordered to match `ProProduct.allCases`.
    @Published private(set) var products: [Product] = []
    /// Product IDs the user currently owns an active entitlement for.
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var storeKitIsProActive: Bool = false
    /// Mirrored into the iCloud account, which survives an App Store account
    /// switch. See `SubscriptionICloudMirror`.
    @Published private(set) var iCloudIsProActive: Bool = false
    /// `true` while any Pro entitlement is active. Everything gates on this.
    ///
    /// MoYue v1.0.10+: all features are free and open, so this is always `true`.
    /// The entitlement machinery below (StoreKit reads, the iCloud mirror) still
    /// runs for telemetry and to keep the code path alive, but it can never lock
    /// a feature — `recomputeEntitlement()` resolves through
    /// `SubscriptionAccessPolicy.isProActive`, which always grants.
    @Published private(set) var isProActive: Bool = true
    /// `true` once launch has read every source of Pro (StoreKit, the account, the
    /// iCloud mirror): from then on a false `isProActive` means no Pro, not "not read
    /// yet". `ContentView` shows the Pro look optimistically only before this — it
    /// used to do so whenever `isProActive` was false, which kept a user without Pro
    /// in their Pro theme for good.
    @Published private(set) var hasResolvedEntitlements: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var isRestoring: Bool = false
    @Published private(set) var isRedeemingOfferCode: Bool = false
    /// Human-readable last error for surfacing in the paywall; nil when clear.
    @Published var lastErrorMessage: String?

    /// Debug-only entitlement override so gating can be exercised in the
    /// simulator without a StoreKit transaction. No effect in Release builds.
    @Published var debugForceProActive: Bool = false {
        didSet { recomputeEntitlement() }
    }

    // MARK: - Private

    private var updatesListenerTask: Task<Void, Never>?
    private var loadedStorefrontID: String?
    private var productLoadGeneration = 0
    private let iCloudMirror = SubscriptionICloudMirror.shared
    /// Throttle for the fire-and-forget drop diagnostic: one report per
    /// process per 5 minutes, so a repeatedly-failing device cannot flood
    /// the diagnostics collection.
    private var lastDropReportDate: Date?
    /// Persisted across launches: `true` once this device ever held a Pro
    /// entitlement. Cold-start drops (app relaunched while the entitlement is
    /// already false — the common "退出重進就掉了" report pattern) only report
    /// when this flag is set, so devices that never had Pro stay silent.
    private var hadProEver: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hadProEverKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hadProEverKey) }
    }
    private static let hadProEverKey = "subscription_had_pro_ever"
    /// Revoked transaction count from the last `currentEntitlements` read, so
    /// the drop diagnostic can distinguish "no transactions at all" from
    /// "transactions were revoked".
    private var lastRevokedCount = 0

    /// Tests can exercise publication without starting StoreKit/network observers.
    init(observeTransactions: Bool = true) {
        #if DEBUG
        // `-debug-force-pro`: a simulator launch has no StoreKit configuration, so this is
        // the only way to look at Pro-only screens there (e.g. Apple Books' action row with
        // AI 翻譯 in it). Debug builds only.
        if ProcessInfo.processInfo.arguments.contains("-debug-force-pro") {
            debugForceProActive = true
            // An initializer's own assignment skips `didSet`.
            recomputeEntitlement()
        }
        #endif
        guard observeTransactions else {
            // Nothing is read later, so what is known now is all there is.
            hasResolvedEntitlements = true
            return
        }
        // Start listening for transactions BEFORE any purchase so we never miss
        // an update delivered while the app was backgrounded or during a
        // purchase interrupted by an Ask-to-Buy / SCA prompt.
        updatesListenerTask = listenForTransactions()
        Task {
            // Before anything reads an environment-scoped store: the suffix that
            // separates TestFlight from App Store state depends on it.
            await resolveRunningEnvironment()
            await refreshEntitlements()
            await refreshICloudEntitlement()
            hasResolvedEntitlements = true
        }
    }

    deinit {
        updatesListenerTask?.cancel()
    }

    // MARK: - Feature gating

    /// The single entitlement gate. Coarse in v1: all features map to Pro.
    ///
    /// MoYue v1.0.10+: every feature is free and unlocked — this always returns
    /// `true`, so no UI ever shows a Pro lock or opens the paywall, while the
    /// `isProActive` published state (also always true) keeps theme/Appearance
    /// lookups on the unlocked branch.
    func hasAccess(_ feature: PremiumFeature) -> Bool {
        true
    }

    /// What the paywall shows right now: the offer, or its member page and whether
    /// that page still sells the lifetime upgrade. The paywall is the only Pro page —
    /// Settings' 「閱讀Pro」 row always opens it — so there is nothing to disagree with.
    var paywallPresentationState: PaywallPresentationState {
        PaywallPresentationPolicy.state(
            purchasedProductIDs: purchasedProductIDs,
            lifetimeProductID: ProProduct.lifetime.rawValue,
            monthlyProductID: ProProduct.monthly.rawValue,
            isProActive: isProActive
        )
    }

    /// The plan the member page names, lifetime first; nil for Pro granted by the
    /// MoYue account or the iCloud mirror.
    var ownedPlan: ProProduct? {
        PaywallPresentationPolicy.ownedPlanID(
            purchasedProductIDs: purchasedProductIDs,
            lifetimeProductID: ProProduct.lifetime.rawValue,
            monthlyProductID: ProProduct.monthly.rawValue
        ).flatMap(ProProduct.init(rawValue:))
    }

    /// Whether the member page links to Apple's subscription management.
    var subscriptionManagement: ProSubscriptionManagement {
        ProStatusPagePolicy.subscriptionManagement(
            purchasedProductIDs: purchasedProductIDs,
            lifetimeProductID: ProProduct.lifetime.rawValue,
            monthlyProductID: ProProduct.monthly.rawValue
        )
    }

    // MARK: - Product loading

    func loadProducts() async {
        let storefront = await Storefront.current
        await loadProducts(forStorefrontID: storefront?.id, forceReload: false)
    }

    /// Prices the loaded products for the App Store storefront again when it changed
    /// while the app was away — it changes only in Settings, so this runs when the app
    /// becomes active.
    ///
    /// In place of iterating `Storefront.updates`. Under StoreKit Testing, Xcode's test
    /// server announces a storefront change every time the storefront is read, and the
    /// sequence reads it again for every announcement: on the iOS 17.5 simulator that
    /// fed itself about 5,000 times a second until the system killed the app some 90
    /// seconds after launch, on every launch from Xcode.
    func reloadProductsIfStorefrontChanged() async {
        // Never loaded: the paywall loads them, for the storefront current then.
        guard let loadedStorefrontID else { return }
        guard let currentID = await Storefront.current?.id,
              currentID != loadedStorefrontID else { return }
        await loadProducts(forStorefrontID: currentID, forceReload: true)
    }

    private func loadProducts(forStorefrontID storefrontID: String?, forceReload: Bool) async {
        guard forceReload || SubscriptionProductReloadPolicy.shouldReload(
            loadedProductCount: products.count,
            expectedProductCount: ProProduct.allCases.count,
            loadedStorefrontID: loadedStorefrontID,
            currentStorefrontID: storefrontID
        ) else { return }

        productLoadGeneration += 1
        let generation = productLoadGeneration
        if let storefrontID, loadedStorefrontID != storefrontID {
            // A cached Product keeps its original localized price. Hide stale
            // prices while StoreKit fetches products for the new storefront.
            products = []
        }
        isLoadingProducts = true
        lastErrorMessage = nil
        defer {
            if generation == productLoadGeneration {
                isLoadingProducts = false
            }
        }
        do {
            let ids = ProProduct.allCases.map(\.rawValue)
            let loaded = try await Product.products(for: ids)
            guard generation == productLoadGeneration else { return }
            // Preserve the ProProduct.allCases display order.
            products = ProProduct.allCases.compactMap { pp in
                loaded.first { $0.id == pp.rawValue }
            }
            loadedStorefrontID = storefrontID
            if products.count != ProProduct.allCases.count {
                lastErrorMessage = localized("無法載入訂閱項目，請稍後再試")
            }
        } catch {
            guard generation == productLoadGeneration else { return }
            lastErrorMessage = localized("無法載入訂閱項目，請稍後再試")
        }
    }

    func product(for pro: ProProduct) -> Product? {
        products.first { $0.id == pro.rawValue }
    }

    // MARK: - Purchase / restore

    /// Returns `true` on a completed, verified purchase.
    @discardableResult
    func purchaseAsGuest(_ product: Product) async -> Bool {
        await purchase(product)
    }

    @discardableResult
    private func purchase(_ product: Product) async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        lastErrorMessage = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isProActive
            case .userCancelled:
                return false
            case .pending:
                // Ask-to-Buy / SCA: entitlement arrives later via the listener.
                lastErrorMessage = localized("購買待確認，完成後將自動解鎖")
                return false
            @unknown default:
                return false
            }
        } catch {
            lastErrorMessage = localized("購買失敗，請稍後再試")
            return false
        }
    }

    /// Presents Apple's offer-code sheet, then synchronizes any entitlement
    /// created by the redemption with StoreKit.
    func redeemOfferCode(in scene: UIWindowScene?) async {
        switch SubscriptionOfferCodeRedemptionPolicy.action(
            isRedeeming: isRedeemingOfferCode,
            hasWindowScene: scene != nil
        ) {
        case .ignore:
            return
        case .reportUnavailable:
            lastErrorMessage = localized("目前無法開啟優惠碼兌換，請稍後再試")
            return
        case .present:
            break
        }

        guard let scene else { return }
        isRedeemingOfferCode = true
        lastErrorMessage = nil
        defer { isRedeemingOfferCode = false }

        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: scene)
            await refreshEntitlements()
        } catch {
            lastErrorMessage = localized("目前無法開啟優惠碼兌換，請稍後再試")
        }
    }

    /// Restores by syncing with the App Store, then re-reading entitlements.
    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        lastErrorMessage = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            // A failed sync is non-fatal — currentEntitlements may still resolve.
        }
        await refreshEntitlements()
        // The iCloud mirror is a restorable grant too: a guest purchase made on
        // the previous App Store account lives only there. Reading it before the
        // verdict below keeps restore from reporting nothing to restore.
        await refreshICloudEntitlement()
        if !isProActive {
            lastErrorMessage = localized("沒有找到可恢復的訂閱")
        }
    }

    // MARK: - Entitlement resolution

    /// Recomputes the entitlement from `Transaction.currentEntitlements`.
    func refreshEntitlements() async {
        // Every entitlement path funnels through here, including purchase and the
        // `Transaction.updates` listener. The environment must be resolved before
        // `mirrorToICloud` writes, or an unresolved suffix would file a TestFlight
        // entitlement in the App Store slot.
        await resolveRunningEnvironment()
        var owned: Set<String> = []
        var revokedCount = 0
        var signedTransaction: String?
        var latestExpiry: Date?
        var hasUnexpiringProduct = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard acceptsTransaction(transaction.environment) else { continue }
            if transaction.revocationDate == nil {
                owned.insert(transaction.productID)
                if ProProduct(rawValue: transaction.productID) != nil {
                    signedTransaction = result.jwsRepresentation
                    if let expiration = transaction.expirationDate {
                        latestExpiry = max(latestExpiry ?? expiration, expiration)
                    } else {
                        // Lifetime: outlives any dated entitlement, so the mirror
                        // must not carry an expiry at all.
                        hasUnexpiringProduct = true
                    }
                }
            } else {
                revokedCount += 1
            }
        }
        purchasedProductIDs = owned
        lastRevokedCount = revokedCount
        Self.subscriptionLog.notice(
            "StoreKit currentEntitlements: owned \(owned.sorted().joined(separator: ","), privacy: .public) revoked \(revokedCount)"
        )
        recomputeEntitlement()
        await mirrorToICloud(
            owned: owned,
            revokedCount: revokedCount,
            expiresAt: hasUnexpiringProduct ? nil : latestExpiry,
            signedTransaction: signedTransaction
        )
    }

    /// Call only after Firebase has been configured (app active/auth callbacks).
    /// Foreground entry point: re-reads StoreKit entitlements and the iCloud
    /// mirror. (The Firebase account refresh was removed with the account system.)
    func refreshAllEntitlements() async {
        await resolveRunningEnvironment()
        await refreshEntitlements()
        await refreshICloudEntitlement()
        recomputeEntitlement()
    }

    /// Reads the iCloud mirror. Like the keychain seed, a missing or unreadable
    /// mirror means "nothing to say" and leaves access alone; only a mirror the
    /// app itself cleared after an Apple revocation reports `false`.
    private func refreshICloudEntitlement() async {
        guard let entitlement = await iCloudMirror.load() else { return }
        let isActive = entitlement.isActive()
        guard isActive != iCloudIsProActive else { return }
        iCloudIsProActive = isActive
        recomputeEntitlement()
    }

    /// Writes the StoreKit entitlement into the iCloud mirror so it outlives an
    /// App Store account switch. An empty entitlement set deliberately writes
    /// nothing — see `SubscriptionICloudMirrorPolicy`, that state is exactly what
    /// a switched account looks like.
    ///
    /// A backend `false` never reaches here: a guest purchase is real in iCloud
    /// while `entitlements/{uid}` legitimately has nothing, so only Apple's own
    /// revocation may clear the mirror.
    private func mirrorToICloud(
        owned: Set<String>,
        revokedCount: Int,
        expiresAt: Date?,
        signedTransaction: String?
    ) async {
        switch SubscriptionICloudMirrorPolicy.action(
            ownedCount: owned.count,
            revokedCount: revokedCount
        ) {
        case .store:
            await iCloudMirror.store(
                CachedSubscriptionEntitlement(isProActive: true, expiresAt: expiresAt),
                productIDs: owned,
                signedTransaction: signedTransaction
            )
            if !iCloudIsProActive {
                iCloudIsProActive = true
                recomputeEntitlement()
            }
        case .revoke:
            await iCloudMirror.clear()
            if iCloudIsProActive {
                iCloudIsProActive = false
                recomputeEntitlement()
            }
        case .leaveAlone:
            break
        }
    }

    private func recomputeEntitlement() {
        let hasPurchase = ProProduct.allCases.contains { purchasedProductIDs.contains($0.rawValue) }
        if storeKitIsProActive != hasPurchase { storeKitIsProActive = hasPurchase }
        let nextIsProActive = SubscriptionAccessPolicy.isProActive(
            storeKit: hasPurchase || debugForceProActive,
            account: false,
            iCloud: iCloudIsProActive
        )
        if isProActive != nextIsProActive { isProActive = nextIsProActive }
        if isProActive {
            hadProEver = true
        }
        Self.subscriptionLog.notice(
            "Entitlement recompute: storeKit \(hasPurchase, privacy: .public) iCloud \(self.iCloudIsProActive, privacy: .public) → pro \(self.isProActive, privacy: .public)"
        )
        // Report when Pro is (now) off on a device that ever had it — covers
        // both in-process drops and cold-start drops (relaunch with the
        // entitlement already false, where `previous` is always false).
        if !isProActive && hadProEver {
            reportEntitlementDrop(
                storeKit: hasPurchase,
                account: false,
                iCloud: iCloudIsProActive
            )
        }
    }

    /// Fire-and-forget telemetry: when the Pro entitlement drops, write the
    /// exact state (StoreKit flag, owned product IDs, app version, storefront)
    /// to Firestore `entitlementDiagnostics` so the developer can diagnose a
    /// device they cannot reach (e.g. a user reporting from behind a VPN).
    /// Deliberately best-effort: failure must never affect the reader, and
    /// Firebase may not be configured yet at early launch — guarded. (The
    /// account flag and uid were removed with the account system.)
    private func reportEntitlementDrop(storeKit: Bool, account: Bool, iCloud: Bool) {
        let now = Date()
        if let last = lastDropReportDate, now.timeIntervalSince(last) < 300 { return }
        lastDropReportDate = now
        guard FirebaseApp.app() != nil else { return }
        let info = Bundle.main.infoDictionary
        var data: [String: Any] = [
            "storeKit": storeKit,
            "account": account,
            "iCloud": iCloud,
            "ownedProducts": purchasedProductIDs.sorted().joined(separator: ","),
            "revokedCount": lastRevokedCount,
            "appVersion": info?["CFBundleShortVersionString"] as? String ?? "",
            "build": info?["CFBundleVersion"] as? String ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ]
        // Storefront (App Store region) is async; fold it in after the read so
        // the report shows whether Apple resolved the entitlement against the
        // user's home region or the VPN exit region.
        Task {
            let storefrontID = await Storefront.current?.id ?? ""
            data["storefront"] = storefrontID
            // Distinguishes "iCloud signed out, mirror could never help" from
            // "iCloud available and the mirror still had nothing" — the evidence
            // for whether users switch only the App Store account or the whole
            // Apple ID.
            data["iCloudAccountStatus"] = await self.iCloudMirror.accountStatusDescription()
            Self.subscriptionLog.notice("Reporting entitlement drop diagnostic to Firestore")
            do {
                _ = try await Firestore.firestore()
                    .collection("entitlementDiagnostics")
                    .addDocument(data: data)
            } catch {
                // Still best-effort (the reader must not care), but a silent failure
                // means the diagnostic the developer is waiting on never arrives —
                // and "no documents" would read as "no entitlement drops".
                Self.subscriptionLog.error(
                    "Entitlement drop diagnostic write failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.checkVerified(result) else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum SubscriptionError: Error {
        case failedVerification
    }
}
