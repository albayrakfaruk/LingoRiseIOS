import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

@MainActor
enum AppServices {
    static func configure() {
        configureFirebase()
        AppAnalytics.configure()
        AppNotificationService.shared.configure()
        AppRemoteConfig.shared.initialize()
        AppSubscriptionService.shared.initialize()
    }

    private static func configureFirebase() {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() == nil,
              let options = FirebaseOptions.defaultOptions(),
              isValidFirebaseOptions(options) else {
            return
        }

        FirebaseApp.configure(options: options)
        #endif
    }

    #if canImport(FirebaseCore)
    private static func isValidFirebaseOptions(_ options: FirebaseOptions) -> Bool {
        guard let apiKey = options.apiKey,
              let projectID = options.projectID else {
            return false
        }

        return !options.googleAppID.isEmpty &&
        !options.googleAppID.contains("$(") &&
        !options.gcmSenderID.isEmpty &&
        !apiKey.isEmpty &&
        !projectID.isEmpty
    }
    #endif
}
