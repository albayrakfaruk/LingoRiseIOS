import Foundation

#if canImport(FirebaseRemoteConfig)
import FirebaseCore
import FirebaseRemoteConfig
#endif

@MainActor
final class AppRemoteConfig {
    static let shared = AppRemoteConfig()

    private enum Key {
        static let termsOfUse = "TERMS_OF_USE"
        static let privacyPolicy = "PRIVACY_POLICY"
        static let companyEmail = "COMPANY_EMAIL"
        static let onboardingMonthly = "ONBOARDING_MONTHLY"
        static let practicePaywallEnabled = "PRACTICE_PAYWALL_ENABLED"
    }

    private init() {}

    func initialize() {
        #if canImport(FirebaseRemoteConfig)
        guard FirebaseApp.app() != nil else { return }

        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = isDebugBuild ? 0 : 3600
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([
            Key.termsOfUse: "" as NSObject,
            Key.privacyPolicy: "" as NSObject,
            Key.companyEmail: "" as NSObject,
            Key.onboardingMonthly: false as NSObject,
            Key.practicePaywallEnabled: true as NSObject
        ])
        remoteConfig.fetchAndActivate { _, error in
            #if DEBUG
            if let error {
                print("remote_config_fetch_failed", error.localizedDescription)
            }
            #endif
        }
        #endif
    }

    var isOnboardingMonthly: Bool {
        #if canImport(FirebaseRemoteConfig)
        guard FirebaseApp.app() != nil else { return false }
        return RemoteConfig.remoteConfig().configValue(forKey: Key.onboardingMonthly).boolValue
        #else
        false
        #endif
    }

    var isPracticePaywallEnabled: Bool {
        #if canImport(FirebaseRemoteConfig)
        guard FirebaseApp.app() != nil else { return true }
        return RemoteConfig.remoteConfig().configValue(forKey: Key.practicePaywallEnabled).boolValue
        #else
        true
        #endif
    }

    var termsOfUseUrl: String {
        remoteString(Key.termsOfUse)
    }

    var privacyPolicyUrl: String {
        remoteString(Key.privacyPolicy)
    }

    var companyEmail: String {
        remoteString(Key.companyEmail)
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private func remoteString(_ key: String) -> String {
        #if canImport(FirebaseRemoteConfig)
        guard FirebaseApp.app() != nil else { return "" }
        return RemoteConfig.remoteConfig().configValue(forKey: key).stringValue
        #else
        ""
        #endif
    }
}
