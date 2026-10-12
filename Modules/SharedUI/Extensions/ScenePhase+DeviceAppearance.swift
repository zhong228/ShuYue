import SwiftUI

extension ScenePhase {
    /// Whether the light／dark in the environment is the device's appearance. In the
    /// background it is not: UIKit draws the app-switcher snapshots there in both
    /// appearances, turning the trait collection to the opposite one and back within a
    /// third of a second of leaving the app (iOS 27 simulator log, 2026-10-05). Whatever
    /// follows the device's appearance acts on it only outside the background, and takes
    /// it up again as the scene comes back.
    ///
    /// Reported 2026-10-04: with 主題切換 › 跟隨系統 on, every trip out of the app put a
    /// reader set to 白天 on a dark device back in 深色. The snapshots read as the device
    /// turning light — so the reader followed it again — and then dark; they also laid the
    /// open book out twice and wore the other appearance's theme setup in between.
    var showsDeviceAppearance: Bool { self != .background }
}
