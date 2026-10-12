import FirebaseCore

/// Whether this build has a real Firebase configuration.
///
/// CI builds ship a placeholder `GoogleService-Info.plist` and skip
/// `FirebaseApp.configure()` (see `configureFirebaseIfAvailable()` in
/// `RSSNotificationManager`), so no default FirebaseApp exists. Every Firebase
/// SDK entry point — `Auth.auth()`, `Firestore.firestore()`,
/// `Storage.storage()`, `Functions.functions()`, `Crashlytics.crashlytics()` —
/// throws (crashes the app) when the default app is missing. All of them must
/// check `isConfigured` first and degrade gracefully (account/Firestore
/// features off) instead of crashing at launch.
enum FirebaseAvailability {
    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }
}