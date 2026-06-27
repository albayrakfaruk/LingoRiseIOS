import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @AppStorage("onboarding_completed") var onboardingCompleted = false
    @AppStorage("dark_theme") var isDarkTheme = false
    @AppStorage("dark_theme_configured") var isDarkThemeConfigured = false
    @AppStorage(AppLocalization.storageKey) var appLanguage = AppLocalization.systemTag
    @Published var route: Route = .boot
    @Published var selectedTab: MainTab = .home
    @Published var selectedContent: Content?
    @Published var storyPackage: Content?
    @Published var isPremium = false
    let contentService = ContentService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        LexendFont.register()
        AppServices.configure()
        AppSubscriptionService.shared.$isPremium
            .removeDuplicates()
            .sink { [weak self] value in
                self?.isPremium = value
            }
            .store(in: &cancellables)
        route = .boot
    }

    func resolveStartRoute() async {
        try? await Task.sleep(nanoseconds: 450_000_000)
        route = onboardingCompleted ? .main : .onboarding
    }

    func finishOnboarding() {
        AppAnalytics.logOnboardingComplete()
        route = .personalization
    }

    func finishPersonalization() {
        route = .paywall(source: .personalizedOnboarding)
    }

    func completePaywall(source: PaywallSource) {
        if source == .personalizedOnboarding {
            AppPreferences.shared.setOnboardingCompleted()
            onboardingCompleted = true
            route = .main
        } else {
            route = .main
        }
    }

    func dismissPaywall(source: PaywallSource) {
        AppAnalytics.logPaywallDismiss(source: source)
        if source == .personalizedOnboarding {
            AppPreferences.shared.setOnboardingCompleted()
            onboardingCompleted = true
            route = .main
        } else {
            route = .main
        }
    }

    var preferredColorScheme: ColorScheme? {
        guard isDarkThemeConfigured else { return nil }
        return isDarkTheme ? .dark : .light
    }

    func effectiveDarkTheme(systemColorScheme: ColorScheme) -> Bool {
        isDarkThemeConfigured ? isDarkTheme : systemColorScheme == .dark
    }

    func setDarkTheme(_ enabled: Bool) {
        AppPreferences.shared.setDarkTheme(enabled)
        isDarkTheme = enabled
        isDarkThemeConfigured = true
    }

    func setAppLanguage(_ tag: String) {
        let normalized = AppLocalization.normalizedLanguageTag(tag)
        AppLocalization.setLanguageTag(normalized)
        appLanguage = normalized
    }

    func show(_ content: Content, dailyPick: Bool = false) {
        AppAnalytics.logStoryView(
            storyId: content.id,
            storyTitle: content.title,
            level: content.level,
            categoryName: content.category.title
        )
        selectedContent = content
        storyPackage = nil
        route = .storyDetail(content.id, dailyPick)
    }

    func updateCurrentRating(storyId: String, averageRating: Double, ratingCount: Int) {
        contentService.updateCurrentRating(storyId: storyId, averageRating: averageRating, ratingCount: ratingCount)
        if selectedContent?.id == storyId {
            selectedContent = selectedContent?.withRating(averageRating: averageRating, ratingCount: ratingCount)
        }
        if storyPackage?.id == storyId {
            storyPackage = storyPackage?.withRating(averageRating: averageRating, ratingCount: ratingCount)
        }
    }
}
