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
    /// Why CloudKit is off in this process; `nil` when `isAvailable` is true.
    enum UnavailabilityReason {
        /// Running inside a LiveContainer host process.
        case liveContainer
        /// The device is not signed into iCloud.
        case iCloudNotSignedIn
        /// The running binary's signature carries no iCloud container entitlement
        /// for this app (free-profile / stripped self-sign installs).
        case entitlementMissing
    }

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

    /// Why `isAvailable` is false right now, for user-facing status text.
    /// Same order as the gates in `isAvailable`.
    static var unavailabilityReason: UnavailabilityReason? {
        if isAvailable { return nil }
        if isRunningInsideLiveContainer { return .liveContainer }
        if FileManager.default.ubiquityIdentityToken == nil { return .iCloudNotSignedIn }
        return .entitlementMissing
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
    /// available on iOS, so the entitlement is read from two places:
    ///
    ///   1. **The executable's own embedded code signature.** The entitlements
    ///      live in the `CSSLOT_ENTITLEMENTS` slot of the CMS superblob inside
    ///      the binary's `LC_CODE_SIGNATURE` — XML or DER, in both of which the
    ///      container identifier appears verbatim. An install can only run when
    ///      its signature was accepted, so what the signature carries is exactly
    ///      what the process is entitled for: TrollStore installs keep the
    ///      `ldid`-injected entitlements here, and self-sign tools that grant
    ///      iCloud (paid certs, user-added permissions) write it into the
    ///      re-signed binary. This is the primary, authoritative source.
    ///   2. **The embedded provisioning profile** as the fallback: a profile
    ///      that lists the container authorizes it even when the slot parse
    ///      fails for an unexpected format.
    ///
    ///   • A sideload signed with a free profile has a profile, but one that does
    ///     NOT list this app's iCloud container, and a signature without the
    ///     entitlement either → false.
    ///   • Dev / TestFlight / Ad-Hoc / Enterprise builds have both → true.
    ///   • App Store installs are always properly signed and entitled → true.
    /// Any failure to read either source degrades to the other; both failing
    /// means `false` (CloudKit off): a process that cannot prove it is entitled
    /// for the container must not be allowed to construct one.
    private static var processCarriesICloudContainerEntitlement: Bool {
        let containerID = Data(ICloudSyncManager.containerIdentifier.utf8)

        // Primary: the entitlements blob inside the running executable's own
        // code signature. What the signature carries is what the process runs with.
        if let entitlements = signatureEntitlementsData(),
           entitlements.range(of: containerID) != nil {
            return true
        }

        // Fallback: the embedded provisioning profile. The container identifier is
        // embedded verbatim (UTF-8) inside the profile's Entitlements plist, so a
        // byte-range search is sufficient and avoids CMS decoding of the signed
        // blob. Absent profile = App Store install, always properly entitled.
        guard let provURL = Bundle.main.url(
            forResource: "embedded.mobileprovision", withExtension: nil
        ) else {
            // No embedded profile and no matching signature entitlement: treat a
            // profile-less install as App Store distribution, which is entitled.
            // (The signature parse above already had its chance.)
            return true
        }
        guard let data = try? Data(contentsOf: provURL) else { return false }
        return data.range(of: containerID) != nil
    }

    /// The entitlements payload from the running executable's embedded code
    /// signature, or `nil` when it cannot be parsed (unexpected format, no
    /// signature slot). XML and DER entitlement blobs both work — the container
    /// identifier is a verbatim UTF-8 byte run in either.
    ///
    /// Pure Mach-O/blob parsing of the on-disk binary (no private API): header →
    /// load commands → `LC_CODE_SIGNATURE` offset → CMS superblob → the
    /// `CSSLOT_ENTITLEMENTS` (type 5) blob.
    private static func signatureEntitlementsData() -> Data? {
        guard let execURL = Bundle.main.executableURL,
              let file = try? FileHandle(forReadingFrom: execURL)
        else { return nil }
        defer { try? file.close() }

        func read(_ offset: UInt64, _ count: Int) -> Data? {
            file.seek(toFileOffset: offset)
            return try? file.read(upToCount: count)
        }
        func u32LE(_ data: Data, _ offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= data.count else { return nil }
            func byte(_ i: Int) -> UInt32 { UInt32(data[data.startIndex + offset + i]) }
            return byte(0) | byte(1) << 8 | byte(2) << 16 | byte(3) << 24
        }
        func u32BE(_ data: Data, _ offset: Int) -> UInt32? {
            guard let v = u32LE(data, offset) else { return nil }
            return UInt32(bigEndian: v)
        }

        guard let head = read(0, 4096), head.count >= 32 else { return nil }

        // Fat (universal) binaries: pick the arm64 slice, else the first one.
        // FAT_MAGIC (CA FE BA BE) and FAT_MAGIC_64 (CA FE BA BF) read little-endian.
        let magic = u32LE(head, 0) ?? 0
        if magic == 0xBEBA_FECA || magic == 0xBFBA_FECA {
            guard let nfat = u32BE(head, 4) else { return nil }
            var found: UInt64?
            for i in 0..<min(Int(nfat), 16) {
                let entry = 8 + i * 20
                let cpuType = u32BE(head, entry) ?? 0
                let archOffset = UInt64(u32BE(head, entry + 8) ?? 0)
                // CPU_TYPE_ARM64 = 0x0100000C
                if cpuType == 0x0100_000C { found = archOffset; break }
                if found == nil { found = archOffset }
            }
            guard let slice = found else { return nil }
            guard let sliceHead = read(slice, 32), sliceHead.count == 32 else { return nil }
            return parseLoadCommands(sliceHead, base: slice, read: read, u32LE: u32LE, u32BE: u32BE)
        }

        // Thin Mach-O: MH_MAGIC_64 (CF FA ED FE) or MH_MAGIC (CE FA ED FE), read LE.
        guard magic == 0xFEED_FACF || magic == 0xFEED_FACE else { return nil }
        let headerSize = magic == 0xFEED_FACF ? 32 : 28
        guard let header = read(0, headerSize), header.count == headerSize else { return nil }
        return parseLoadCommands(header, base: 0, read: read, u32LE: u32LE, u32BE: u32BE)
    }

    /// Walks the Mach-O load commands of the slice at `base` hunting for
    /// `LC_CODE_SIGNATURE`, then extracts the entitlements blob from the
    /// embedded signature superblob.
    private static func parseLoadCommands(
        _ header: Data,
        base: UInt64,
        read: (UInt64, Int) -> Data?,
        u32LE: (Data, Int) -> UInt32?,
        u32BE: (Data, Int) -> UInt32?
    ) -> Data? {
        guard let ncmds = u32LE(header, 16), let sizeofcmds = u32LE(header, 20) else { return nil }
        let commandsStart = header.count == 32 ? 32 : 28 // 64-bit vs 32-bit Mach-O header
        let commandsSize = min(Int(sizeofcmds), 1 << 20)
        guard let commands = read(base + UInt64(commandsStart), commandsSize), commands.count == commandsSize else { return nil }

        var signatureOffset: UInt64?
        var cursor = 0
        for _ in 0..<min(Int(ncmds), 4096) {
            guard cursor + 8 <= commands.count else { break }
            let cmd = u32LE(commands, cursor) ?? 0
            let cmdSize = Int(u32LE(commands, cursor + 4) ?? 0)
            guard cmdSize >= 8, cursor + cmdSize <= commands.count else { break }
            // LC_CODE_SIGNATURE = 0x1d; LinkeditDataCommand.dataoff at +8.
            if cmd == 0x1d, cmdSize >= 16 {
                signatureOffset = UInt64(u32LE(commands, cursor + 8) ?? 0)
                break
            }
            cursor += cmdSize
        }
        guard let sigOff = signatureOffset else { return nil }

        // Embedded signature superblob: magic 0xFADE0CC0, length, count, then
        // 8-byte blob indexes (type, offset) — all big-endian.
        guard let superHead = read(sigOff, 12), superHead.count == 12,
              u32BE(superHead, 0) == 0xFADE0CC0,
              let blobCount = u32BE(superHead, 8)
        else { return nil }

        guard let indexData = read(sigOff + 12, Int(blobCount) * 8), indexData.count == Int(blobCount) * 8 else { return nil }
        for i in 0..<Int(blobCount) {
            let type = u32BE(indexData, i * 8) ?? 0
            let offset = u32BE(indexData, i * 8 + 4) ?? 0
            guard type == 5 else { continue } // CSSLOT_ENTITLEMENTS
            let blobBase = sigOff + UInt64(offset)
            guard let blobHead = read(blobBase, 8), blobHead.count == 8,
                  u32BE(blobHead, 0) == 0xFADE7171, // CSMAGIC_EMBEDDED_ENTITLEMENTS
                  let blobLength = Int(exactly: u32BE(blobHead, 4) ?? 0),
                  blobLength > 8, blobLength <= 1 << 20
            else { return nil }
            return read(blobBase + 8, blobLength - 8)
        }
        return nil
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
