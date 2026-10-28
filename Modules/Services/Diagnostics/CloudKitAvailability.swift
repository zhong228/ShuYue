import Foundation

/// Whether this build may touch CloudKit at all.
///
/// CloudKit is entitlement-gated: creating a `CKContainer(identifier:)` in a
/// process whose signatures lack the matching iCloud container entitlement calls
/// `os_crash` (EXC_BREAKPOINT / SIGTRAP) **inside the CloudKit framework** and
/// kills the app on the spot — that is the startup crash self-signed / sideloaded
/// installs hit. A sideload tool signs the app with a *free* provisioning profile
/// that does **not** authorize iCloud, and the user is typically still signed
/// into iCloud on the device, so `ubiquityIdentityToken` is non-`nil` there —
/// yet constructing the named container still `os_crash`es because the process
/// is not entitled for `iCloud.com.zhong228.shuyue`.
///
/// LiveContainer is the older instance of the same trap: it runs the app as a
/// *copy* under its own host process (`LiveProcess.appex`), whose entitlement
/// list never contains this app's container, so the container construction
/// `os_crash`es there too.
///
/// Every CloudKit entry point (`ICloudSyncManager`, `SubscriptionICloudMirror`)
/// must check `isAvailable` first and degrade (iCloud sync off, mirror read
/// returns nil) instead of constructing a container. Signed builds installed via
/// Xcode / TestFlight / App Store keep the real entitlement and CloudKit works
/// unchanged.
enum CloudKitAvailability {
    /// True when this process may touch CloudKit safely.
    ///
    /// Three gates, all required:
    ///
    /// 1. **Not running under a LiveContainer host.** The host process carries
    ///    its own iCloud identity (token non-`nil` when the user is signed in)
    ///    while lacking this app's container entitlement — the one case where
    ///    the token alone would let a guaranteed `os_crash` through. The host is
    ///    recognised by where the app is loaded from (`Documents/Applications/`
    ///    under the sandbox data container) and by the `TweakLoader.dylib`
    ///    it injects into every process.
    /// 2. **The device iCloud identity is available.** Non-`nil` only when the
    ///    user is signed into iCloud at the OS level. Note this is the *device*
    ///    sign-in state, not the app's capability — a free-profile sideload is
    ///    signed into iCloud as far as this token is concerned, which is exactly
    ///    why gate 2 alone is not enough.
    /// 3. **This process is actually entitled for the container.** A self-signed /
    ///    sideloaded build (free provisioning) is signed into iCloud at the OS
    ///    level — so it passes gate 2 — yet is *not* entitled for this app's
    ///    CloudKit container, and constructing the named `CKContainer` there is
    ///    exactly the `os_crash` that crashes the app on launch. Gate 3 reads the
    ///    entitlement actually attached to the running binary and refuses the
    ///    container when the entitlement is absent.
    static var isAvailable: Bool {
        guard !isRunningInsideLiveContainer else { return false }
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        guard processCarriesICloudContainerEntitlement else { return false }
        return true
    }

    /// True when the running binary's provisioning profile grants the iCloud
    /// container entitlement for `ICloudSyncManager.containerIdentifier`.
    ///
    /// CloudKit's launch crash is about the *process* entitlement, not the OS
    /// iCloud sign-in state. `ubiquityIdentityToken` is non-`nil` whenever the
    /// device is signed into iCloud — including on an app that a sideload tool
    /// signed with a free profile lacking any iCloud container. The only reliable
    /// way to know whether `CKContainer(identifier:)` is safe is to inspect the
    /// entitlement actually attached to the running binary.
    ///
    /// `SecCode` (the macOS API for reading code-signing entitlements) is not
    /// available on iOS, so instead we read the embedded `embedded.mobileprovision`
    /// and look for the container identifier among its entitlements:
    ///   • A sideload signed with a free profile has a profile, but one that does
    ///     NOT list this app's iCloud container → the identifier is absent → false.
    ///   • Dev / TestFlight / Ad-Hoc / Enterprise builds have a profile that DOES
    ///     list it → present → true.
    ///   • App Store installs ship without an embedded provisioning profile and
    ///     are always properly signed and entitled → absence is treated as true.
    /// Any failure to read the profile degrades to `false` (CloudKit off): a
    /// process that cannot prove it is entitled for the container must not be
    /// allowed to construct one.
    private static var processCarriesICloudContainerEntitlement: Bool {
        guard let provURL = Bundle.main.url(
            forResource: "embedded.mobileprovision", withExtension: nil
        ) else {
            // No embedded profile: this is an App Store install, which is always
            // properly signed and entitled for its own iCloud container.
            return true
        }
        guard let data = try? Data(contentsOf: provURL) else { return false }
        // The container identifier is embedded verbatim (UTF-8) inside the
        // profile's Entitlements plist, so a byte-range search is sufficient and
        // avoids CMS decoding of the signed blob.
        return data.range(of: Data(ICloudSyncManager.containerIdentifier.utf8)) != nil
    }

    /// True when this process is the LiveContainer host running a copied `.app`
    /// from the sandbox data container, i.e. the build carries no target-valid
    /// iCloud container entitlement and CloudKit *will* `os_crash` on container
    /// creation no matter what the iCloud token says.
    private static var isRunningInsideLiveContainer: Bool {
        // LiveContainer installs the app as a copy under the *data* container:
        //   <DataContainer>/Documents/Applications/<bundleID>_<hash>.app
        // (direct evidence from the user's crash report:
        //  .../Documents/Applications/com.zhong228.shuyue_813124420.app).
        // A signed install always lives under /var/containers/Bundle/Application/
        // (or the simulator's data dir), never under a data container's
        // Documents/Applications — so this path alone identifies the host.
        let mainBundlePath = Bundle.main.bundlePath
        if mainBundlePath.contains("/Documents/Applications/") { return true }

        // Older LiveContainer versions that do not swap `Bundle.main`: the main
        // bundle still points into the host's own container, whose path always
        // contains the LiveContainer app name (crash-report evidence:
        // .../LiveContainer.app/PlugIns/LiveProcess.appex). A plain install can
        // never have "LiveContainer.app" in its main bundle path.
        if mainBundlePath.contains("/LiveContainer.app/") { return true }

        // LiveContainer injects its loader dylib via DYLD_INSERT_LIBRARIES
        // (TweakLoader.dylib). Exposed on iOS; a silent no-op elsewhere.
        if let injected = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"],
           injected.contains("TweakLoader") {
            return true
        }
        return false
    }
}