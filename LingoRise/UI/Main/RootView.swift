import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            switch appState.route {
            case .boot:
                SplashScreen()
            case .onboarding:
                OnboardingScreen()
            case .personalization:
                PersonalizationScreen()
            case .main:
                MainScreen()
            case let .storyDetail(storyId, dailyPick):
                StoryDetailScreen(storyId: storyId, isDailyPick: dailyPick)
            case let .reading(storyId, dailyPick):
                ReadingScreen(storyId: storyId, isDailyPick: dailyPick)
            case let .practice(storyId, dailyPick):
                PracticeScreen(
                    storyId: storyId,
                    isDailyPick: dailyPick,
                    hasPracticeAccess: appState.isPremium || !AppRemoteConfig.shared.isPracticePaywallEnabled
                )
            case let .paywall(source):
                PaywallScreen(source: source)
            }
        }
        .task {
            if appState.route == .boot {
                await appState.resolveStartRoute()
            }
        }
    }

    private var appBackground: Color {
        appState.effectiveDarkTheme(systemColorScheme: colorScheme) ? LingoRiseColors.backgroundDark : LingoRiseColors.backgroundLight
    }
}
