import Foundation

/// Whether this build may touch CloudKit at all.
///
/// CloudKit is entitlement-gated: creating a `CKContainer(identifier:)` in a
/// process whose signatures lack the matching iCloud container entitlement calls
/// `os_crash` (EXC_BREAKPOINT / SIGTRAP) **inside the CloudKit framework** and
/// kills the app on the spot — that is the startup crash LiveContainer users hit
/// from the first build. LiveContainer runs the app as a *copy* under its own
/// host process (`LiveProcess.appex`): the host is signed and may itself be
/// entitled for iCloud, so a signed-in iPhone yields a non-`nil`
/// `ubiquityIdentityToken` in that process too — but the host's entitlement
/// list never contains this app's container (`iCloud.com.zhong228.shuyue`),
/// so constructing the container there still `os_crash`es.
///
/// Every CloudKit entry point (`ICloudSyncManager`, `SubscriptionICloudMirror`)
/// must check `isAvailable` first and degrade (iCloud sync off, mirror read
/// returns nil) instead of constructing a container. Signed builds installed via
/// Xcode / TestFlight / App Store keep the real entitlement and CloudKit works
/// unchanged.
enum CloudKitAvailability {
    /// True when this process may touch CloudKit safely.
    ///
    /// Two gates, both required:
    ///
    /// 1. **Not running under a LiveContainer host.** The host process carries
    ///    its own iCloud identity (token non-`nil` when the user is signed in)
    ///    while lacking this app's container entitlement — the one case where
    ///    the token alone would let a guaranteed `os_crash` through. The host is
    ///    recognised by where the app is loaded from (`Documents/Applications/`
    ///    under the sandbox data container) and by the `TweakLoader.dylib`
    ///    it injects into every process.
    /// 2. **The local iCloud identity is available.** Non-`nil` only in a
    ///    process that is entitled for iCloud **and** has the user signed in.
    ///    A signed build with the user signed out of iCloud → `nil` → CloudKit
    ///    work is skipped until sign-in, when it becomes available again; a
    ///    `CKContainer` would not have crashed there, it would just report
    ///    `.noAccount`, so skipping is functionally equivalent without the risk.
    static var isAvailable: Bool {
        guard !isRunningInsideLiveContainer else { return false }
        return FileManager.default.ubiquityIdentityToken != nil
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