import Foundation
import UIKit
import UserNotifications

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@MainActor
final class AppNotificationService: NSObject {
    static let shared = AppNotificationService()

    private let functionsRegion = "europe-west1"
    private var isConfigured = false

    private override init() {
        super.init()
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        UNUserNotificationCenter.current().delegate = self

        #if canImport(FirebaseMessaging)
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().delegate = self
        Messaging.messaging().token { [weak self] token, error in
            #if DEBUG
            if let error {
                print("fcm_token_fetch_failed", error.localizedDescription)
            }
            #endif
            guard let token, !token.isEmpty else { return }
            Task { @MainActor in
                self?.registerNotificationDevice(token: token)
            }
        }
        #endif
    }

    func requestAuthorizationFromHomeIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                Task { @MainActor [weak self] in
                    guard AppPreferences.shared.recordHomeVisitAndShouldRequestNotificationPermission() else { return }
                    self?.requestAuthorization()
                }
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    func setAPNSToken(_ deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { [weak self] token, error in
            #if DEBUG
            if let error {
                print("fcm_token_fetch_failed", error.localizedDescription)
            }
            #endif
            guard let token, !token.isEmpty else { return }
            Task { @MainActor in
                self?.registerNotificationDevice(token: token)
            }
        }
        #endif
    }

    @MainActor
    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            #if DEBUG
            if let error {
                print("notification_authorization_failed", error.localizedDescription)
            }
            #endif
            guard granted else { return }
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func registerNotificationDevice(token: String) {
        #if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
        guard FirebaseApp.app() != nil else { return }
        guard Auth.auth().currentUser != nil else { return }

        let offsetMinutes = TimeZone.current.secondsFromGMT() / 60
        let languageCode = Locale.current.language.languageCode?.identifier
            ?? Locale.current.identifier.prefix(2).lowercased()

        Functions.functions(region: functionsRegion)
            .httpsCallable("registerNotificationDevice")
            .call([
                "token": token,
                "timezoneOffsetMinutes": offsetMinutes,
                "locale": languageCode
            ]) { _, error in
                #if DEBUG
                if let error {
                    print("notification_device_register_failed", error.localizedDescription)
                }
                #endif
            }
        #endif
    }
}

extension AppNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
    }
}

#if canImport(FirebaseMessaging)
extension AppNotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task { @MainActor in
            AppNotificationService.shared.registerNotificationDevice(token: fcmToken)
        }
    }
}
#endif
