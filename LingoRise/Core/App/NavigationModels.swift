import Foundation

enum Route: Equatable {
    case boot
    case onboarding
    case personalization
    case main
    case storyDetail(String, Bool)
    case reading(String, Bool)
    case practice(String, Bool)
    case paywall(source: PaywallSource)

    var screenName: String? {
        switch self {
        case .boot:
            return nil
        case .onboarding:
            return "onboarding"
        case .personalization:
            return "personalization"
        case .main:
            return "main"
        case .storyDetail:
            return "story_detail"
        case .reading:
            return "reading"
        case .practice:
            return "practice_recording"
        case .paywall:
            return "paywall"
        }
    }
}

enum MainTab: String, CaseIterable {
    case home = "Home"
    case explore = "Explore"
    case profile = "Profile"

    var symbol: String {
        switch self {
        case .home: return "house"
        case .explore: return "safari"
        case .profile: return "person"
        }
    }

    var titleKey: String {
        switch self {
        case .home: return "nav_home"
        case .explore: return "nav_explore"
        case .profile: return "nav_profile"
        }
    }
}

enum PaywallSource: String, Equatable {
    case onboarding
    case personalizedOnboarding
    case home
    case explore
    case profile
    case profileYearlyUpgrade
    case storyDetail
    case reading
    case practice
}
