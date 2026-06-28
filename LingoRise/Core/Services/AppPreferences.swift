import Foundation

@MainActor
final class AppPreferences {
    static let shared = AppPreferences()

    private let defaults: UserDefaults
    private let notificationPromptInterval = 3
    private let retentionOfferLastShownDateKey = "retention_offer_last_shown_date"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var onboardingCompleted: Bool {
        defaults.bool(forKey: "onboarding_completed")
    }

    func setOnboardingCompleted() {
        defaults.set(true, forKey: "onboarding_completed")
    }

    var darkTheme: Bool? {
        guard defaults.object(forKey: "dark_theme") != nil else { return nil }
        return defaults.bool(forKey: "dark_theme")
    }

    func setDarkTheme(_ enabled: Bool) {
        defaults.set(enabled, forKey: "dark_theme")
        defaults.set(true, forKey: "dark_theme_configured")
    }

    func canShowRetentionOfferToday() -> Bool {
        defaults.string(forKey: retentionOfferLastShownDateKey) != Self.todayKey()
    }

    func markRetentionOfferShownToday() {
        defaults.set(Self.todayKey(), forKey: retentionOfferLastShownDateKey)
    }

    func recordHomeVisitAndShouldRequestNotificationPermission() -> Bool {
        if defaults.bool(forKey: "notification_permission_prompted") == false {
            defaults.set(true, forKey: "notification_permission_prompted")
            defaults.set(0, forKey: "home_visits_since_notification_prompt")
            return true
        }

        let visitCount = defaults.integer(forKey: "home_visits_since_notification_prompt") + 1
        if visitCount >= notificationPromptInterval {
            defaults.set(0, forKey: "home_visits_since_notification_prompt")
            return true
        }

        defaults.set(visitCount, forKey: "home_visits_since_notification_prompt")
        return false
    }

    func getOrCreateRatingDeviceId() -> String {
        if let existing = defaults.string(forKey: "rating_device_id") {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: "rating_device_id")
        return generated
    }

    func getStoryRating(storyId: String) -> Int {
        defaults.integer(forKey: storyRatingKey(storyId))
    }

    func setStoryRating(storyId: String, rating: Int) {
        defaults.set(min(max(rating, 1), 5), forKey: storyRatingKey(storyId))
    }

    private func storyRatingKey(_ storyId: String) -> String {
        "story_rating_\(storyId)"
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
