import AVFoundation
import SwiftUI

@main
struct LingoRiseApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.isDarkTheme ? .dark : .light)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @AppStorage("onboarding_completed") var onboardingCompleted = false
    @AppStorage("dark_theme") var isDarkTheme = false
    @Published var route: Route = .boot
    @Published var selectedTab: MainTab = .home
    @Published var selectedContent: Content?
    @Published var storyPackage: Content?
    @Published var isPremium = false
    let contentService = ContentService()

    init() {
        route = onboardingCompleted ? .main : .onboarding
    }

    func finishOnboarding() {
        route = .personalization
    }

    func finishPersonalization() {
        route = .paywall(source: .personalizedOnboarding)
    }

    func completePaywall(source: PaywallSource) {
        if source == .personalizedOnboarding {
            onboardingCompleted = true
            route = .main
        } else {
            route = .main
        }
    }

    func dismissPaywall(source: PaywallSource) {
        if source == .personalizedOnboarding {
            onboardingCompleted = true
            route = .main
        } else {
            route = .main
        }
    }

    func show(_ content: Content, dailyPick: Bool = false) {
        selectedContent = content
        storyPackage = nil
        route = .storyDetail(content.id, dailyPick)
    }
}

enum Route: Equatable {
    case boot
    case onboarding
    case personalization
    case main
    case storyDetail(String, Bool)
    case reading(String, Bool)
    case practice(String, Bool)
    case paywall(source: PaywallSource)
}

enum MainTab: String, CaseIterable {
    case home = "Home"
    case explore = "Explore"
    case profile = "Profile"

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "safari.fill"
        case .profile: return "person.fill"
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

enum ContentType: String, Codable {
    case story
    case fact
    case article
    case news

    var label: String {
        switch self {
        case .story: return "Story"
        case .fact: return "Quick fact"
        case .article: return "Article"
        case .news: return "News"
        }
    }
}

enum EnglishAccent: String, Codable {
    case us = "en-US"
    case uk = "en-GB"

    var label: String {
        switch self {
        case .us: return "US English"
        case .uk: return "British English"
        }
    }
}

enum ExploreSortOption: String, CaseIterable {
    case newest = "Newest"
    case shortestDuration = "Shortest Duration"
    case longestDuration = "Longest Duration"
}

struct Category: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
}

struct TargetWord: Identifiable, Hashable {
    var id: String { text }
    let text: String
    let pronunciation: String
    let audioUrl: String
}

struct SentenceAudio: Identifiable, Hashable {
    let id = UUID()
    let index: Int
    let text: String
    let audioUrl: String
    let durationMs: Int
    let pronunciation: String
}

struct SourceReference: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let publisher: String
    let url: String
    let publishedAt: String
    let countryCode: String
    let isLocal: Bool
}

struct Content: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let summary: String
    let category: Category
    let level: String
    let duration: String
    let imageUrl: String
    let durationMs: Int
    var sentences: [SentenceAudio]
    let isPremium: Bool
    let createdAt: Date?
    let wordCount: Int
    let targetWords: [TargetWord]
    let contentType: ContentType
    let rating: Double?
    let ratingCount: Int
    let accent: EnglishAccent
    let sourceReferences: [SourceReference]
    let practiceSentenceIndexes: [Int]
}

struct LingoRiseColors {
    static let primary = Color(hex: 0x1955CC)
    static let primaryLight = Color(hex: 0x3B76ED)
    static let backgroundLight = Color(hex: 0xF7F8FC)
    static let backgroundDark = Color(hex: 0x111621)
    static let surfaceDark = Color(hex: 0x1A2233)
    static let surfaceVariantLight = Color(hex: 0xE9EDF5)
}

extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            switch appState.route {
            case .boot:
                ProgressView()
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
                PracticeScreen(storyId: storyId, isDailyPick: dailyPick)
            case let .paywall(source):
                PaywallScreen(source: source)
            }
        }
    }

    private var appBackground: Color {
        appState.isDarkTheme ? LingoRiseColors.backgroundDark : LingoRiseColors.backgroundLight
    }
}

struct OnboardingScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0

    private let steps: [OnboardingStep] = [
        .init(title: "Learn through stories.", subtitle: "Read and listen to engaging content designed to improve your English naturally.", image: "onboarding_story_lost_city_z", badge: "NEW STORY"),
        .init(title: "Speak English with Stories", subtitle: "Listen, read, and improve your pronunciation naturally.", image: "onboarding_speak_stories_hero", badge: "AI NARRATOR ACTIVE"),
        .init(title: "Powered by AI", subtitle: "Experience dynamic voice narration that makes every story immersive.", image: "onboarding_follow_stories_hero", badge: "RECORDING"),
        .init(title: "Perfect your pronunciation.", subtitle: "Record yourself and get instant feedback on your spoken English.", image: "onboarding_story_coffee_culture", badge: "EXCELLENT"),
        .init(title: "Start your speaking journey", subtitle: "Open a story and begin in seconds. Your voice is ready to be heard.", image: "onboarding_start_journey_hero", badge: "9:41")
    ]

    var body: some View {
        let item = steps[step]
        VStack(spacing: 0) {
            TabView(selection: $step) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 22) {
                        OnboardingHero(step: item, index: index)
                            .padding(.horizontal, 22)
                            .padding(.top, 16)
                        VStack(spacing: 10) {
                            Text(item.title)
                                .font(.system(size: 34, weight: .bold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                            Text(item.subtitle)
                                .font(.system(size: 16, weight: .medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 24)
                        }
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? LingoRiseColors.primary : Color.secondary.opacity(0.22))
                        .frame(width: index == step ? 24 : 8, height: 8)
                }
            }
            .padding(.bottom, 18)

            Button {
                if step < steps.count - 1 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                        step += 1
                    }
                } else {
                    appState.finishOnboarding()
                }
            } label: {
                Text(step == steps.count - 1 ? "Start" : "Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(.white)
                    .background(LingoRiseColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            Text("Trusted by language learners worldwide")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .background(appState.isDarkTheme ? LingoRiseColors.backgroundDark : .white)
    }
}

struct OnboardingStep {
    let title: String
    let subtitle: String
    let image: String
    let badge: String
}

struct OnboardingHero: View {
    let step: OnboardingStep
    let index: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(step.image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 430)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color(hex: 0x111621, alpha: 0.92)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 14) {
                Text(step.badge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(index == 3 ? Color(hex: 0x5FD39A) : Color(hex: 0xFACC15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                if index == 0 {
                    StoryPreviewStack()
                } else if index == 3 {
                    PronunciationPreview()
                } else {
                    Text("The mist rolled in from the northern peaks, carrying whispers of a language long forgotten.")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineSpacing(6)
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 12)
    }
}

struct StoryPreviewStack: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Discover")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                MiniStoryCard(title: "The Lost City of Z", image: "onboarding_story_lost_city_z")
                MiniStoryCard(title: "Coffee Culture in Italy", image: "onboarding_story_coffee_culture")
            }
        }
    }
}

struct MiniStoryCard: View {
    let title: String
    let image: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(image)
                .resizable()
                .scaledToFill()
                .frame(width: 130, height: 86)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(10)
        .frame(width: 150)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PronunciationPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([("language", "/ˈlæŋɡwɪdʒ/", false), ("journey", "/ˈdʒɜːrni/", true), ("listen", "/ˈlɪsən/", false)], id: \.0) { word, ipa, selected in
                HStack {
                    Text(word)
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text(ipa)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(selected ? Color(hex: 0x5FD39A) : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(selected ? 0.55 : 0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

struct PersonalizationScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0
    @State private var goal = "Speak confidently"
    @State private var level = "Intermediate"
    @State private var commitment = "10 minutes"
    @State private var motivations: Set<String> = ["Short lessons"]
    @State private var generatedItems = 0
    private let goals = ["Speak confidently", "Travel", "Work & career", "Movies & content", "Daily English"]
    private let levels = ["Beginner", "Basic", "Intermediate", "Advanced"]
    private let commitments = ["5 minutes", "10 minutes", "15 minutes", "20 minutes", "30 minutes", "Flexible"]
    private let motivationItems = ["Daily reminders", "Fast progress", "Short lessons", "AI guidance", "Weekly goals", "Vocabulary growth"]

    var body: some View {
        VStack(spacing: 18) {
            PersonalizationProgress(step: min(step, 5))
                .padding(.top, 18)
            Spacer(minLength: 4)
            Group {
                switch step {
                case 0:
                    CenteredQuestion(title: "Now let’s build your learning plan", subtitle: "Answer 4 quick questions", symbol: "wand.and.stars")
                case 1:
                    SelectableQuestion(eyebrow: "Goal", title: "What brings you here?", subtitle: "Pick the path that feels closest.", items: goals, selected: $goal)
                case 2:
                    SelectableQuestion(eyebrow: "Level", title: "Where should we start?", subtitle: "Your plan adapts from here.", items: levels, selected: $level)
                case 3:
                    SelectableQuestion(eyebrow: "Daily effort", title: "How much time can you spend?", subtitle: "Consistency matters more than long sessions", items: commitments, selected: $commitment)
                case 4:
                    MotivationQuestion(items: motivationItems, selected: $motivations)
                case 5:
                    GeneratingStep(generatedItems: generatedItems)
                default:
                    ResultStep(goal: goal, commitment: commitment) {
                        step = 1
                    }
                }
            }
            Spacer()
            Button(action: continueFlow) {
                Text(step >= 6 ? "Continue" : "Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(.white)
                    .background(LingoRiseColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 18)
        .onChange(of: step) { _, newValue in
            if newValue == 5 {
                generatedItems = 0
                Task {
                    for index in 1...4 {
                        try? await Task.sleep(nanoseconds: 420_000_000)
                        await MainActor.run { generatedItems = index }
                    }
                    try? await Task.sleep(nanoseconds: 360_000_000)
                    await MainActor.run { step = 6 }
                }
            }
        }
    }

    private func continueFlow() {
        if step >= 6 {
            appState.finishPersonalization()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                step += 1
            }
        }
    }
}

struct PersonalizationProgress: View {
    let step: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? LingoRiseColors.primary : Color.secondary.opacity(0.18))
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, 8)
    }
}

struct CenteredQuestion: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(LingoRiseColors.primary)
                .frame(width: 96, height: 96)
                .background(LingoRiseColors.primary.opacity(0.12))
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct SelectableQuestion: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let items: [String]
    @Binding var selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuestionHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)
            ForEach(items, id: \.self) { item in
                SelectableRow(title: item, isSelected: item == selected) {
                    selected = item
                }
            }
        }
    }
}

struct MotivationQuestion: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuestionHeader(eyebrow: "Motivation", title: "What helps you stay consistent?", subtitle: "Choose all that fit.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(items, id: \.self) { item in
                    Button {
                        if selected.contains(item) {
                            selected.remove(item)
                        } else {
                            selected.insert(item)
                        }
                    } label: {
                        HStack {
                            Text(item)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            if selected.contains(item) {
                                Image(systemName: "checkmark")
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .foregroundStyle(selected.contains(item) ? LingoRiseColors.primary : .primary)
                        .background(selected.contains(item) ? LingoRiseColors.primary.opacity(0.12) : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }
}

struct QuestionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LingoRiseColors.primary)
            Text(title)
                .font(.system(size: 31, weight: .bold))
            Text(subtitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SelectableRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? LingoRiseColors.primary : Color.secondary.opacity(0.55))
            }
            .padding(18)
            .foregroundStyle(.primary)
            .background(isSelected ? LingoRiseColors.primary.opacity(0.1) : Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? LingoRiseColors.primary : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct GeneratingStep: View {
    let generatedItems: Int
    private let items = ["Analyzing answers", "Adjusting lesson pace", "Building learning path", "Preparing first milestone"]

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(LingoRiseColors.primary)
                .scaleEffect(1.35)
            Text("Building your plan")
                .font(.system(size: 32, weight: .bold))
            Text("Setting up a path that fits your goal.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                    HStack(spacing: 12) {
                        Image(systemName: index < generatedItems ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index < generatedItems ? Color(hex: 0x22C55E) : .secondary)
                        Text(text)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .padding(20)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct ResultStep: View {
    let goal: String
    let commitment: String
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            QuestionHeader(eyebrow: "Personal plan", title: "Your plan is ready", subtitle: "Built around the choices you just made.")
            HStack(spacing: 12) {
                ResultMetric(title: "Goal", value: goal)
                ResultMetric(title: "Daily effort", value: commitment)
            }
            ResultMetric(title: "First milestone", value: "Hold your first 2-minute conversation")
            ResultMetric(title: "Weekly target", value: "7 focused lessons")
            Button("Edit answers", action: onEdit)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LingoRiseColors.primary)
        }
    }
}

struct ResultMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct MainScreen: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var homeModel = HomeModel()
    @StateObject private var exploreModel = ExploreModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch appState.selectedTab {
                case .home:
                    HomeScreen(model: homeModel)
                case .explore:
                    ExploreScreen(model: exploreModel)
                case .profile:
                    ProfileScreen()
                }
            }
            FloatingTabBar(selectedTab: $appState.selectedTab)
                .padding(.bottom, 14)
        }
        .onAppear {
            homeModel.configure(service: appState.contentService)
            exploreModel.configure(service: appState.contentService)
            Task {
                await homeModel.load()
                await exploreModel.load()
            }
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .foregroundStyle(selectedTab == tab ? LingoRiseColors.primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.86)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
    }
}

@MainActor
final class HomeModel: ObservableObject {
    @Published var isLoading = false
    @Published var hasError = false
    @Published var dailyStory: Content?
    @Published var categories: [Category] = []
    @Published var storiesByCategory: [String: [Content]] = [:]
    private var service: ContentService?
    private var loaded = false

    func configure(service: ContentService) {
        self.service = service
    }

    func load() async {
        guard !loaded, let service else { return }
        isLoading = true
        hasError = false
        do {
            categories = try await service.getCategories()
            dailyStory = try await service.getDailyPick()
            var grouped: [String: [Content]] = [:]
            for category in categories {
                grouped[category.id] = try await service.getStories(categoryId: category.id, limit: 5)
            }
            storiesByCategory = grouped
            loaded = true
            isLoading = false
        } catch {
            hasError = true
            isLoading = false
        }
    }

    func retry() async {
        loaded = false
        await load()
    }
}

struct HomeScreen: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var model: HomeModel
    private let date = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(date)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Hi there 👋")
                            .font(.system(size: 35, weight: .bold))
                    }
                    Spacer()
                    PremiumBadge(isPremium: appState.isPremium) {
                        appState.route = .paywall(source: .home)
                    }
                }
                .padding(.top, 18)

                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                } else if model.hasError {
                    MessageState(title: "Couldn’t load your stories", message: "Check your connection and try again.", actionTitle: "Retry") {
                        Task { await model.retry() }
                    }
                } else if model.dailyStory == nil && model.storiesByCategory.values.allSatisfy({ $0.isEmpty }) {
                    MessageState(title: "New stories are on the way", message: "There is no published content yet. Please check back soon.")
                } else {
                    if let daily = model.dailyStory {
                        HomeHeroCard(story: daily) {
                            appState.show(daily, dailyPick: true)
                        }
                    }
                    ForEach(model.categories) { category in
                        let stories = model.storiesByCategory[category.id] ?? []
                        if !stories.isEmpty {
                            HomeCategorySection(category: category, stories: stories) {
                                appState.selectedTab = .explore
                            } onStory: { story in
                                appState.show(story)
                            }
                        }
                    }
                    Text("Small practice. Big progress.")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
        .background(Color(.systemBackground).opacity(0.02))
    }
}

struct PremiumBadge: View {
    let isPremium: Bool
    let action: () -> Void

    var body: some View {
        Button(action: isPremium ? {} : action) {
            HStack(spacing: 7) {
                Image(systemName: "crown.fill")
                Text("PRO")
                    .font(.system(size: 12, weight: .bold))
                if isPremium {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 40)
            .foregroundStyle(isPremium ? Color(hex: 0x5FD39A) : Color(hex: 0xF2C14E))
            .background(Color(hex: isPremium ? 0x15221D : 0x1D1A15))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct HomeHeroCard: View {
    let story: Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                AsyncStoryImage(url: story.imageUrl)
                    .frame(height: 348)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Color(hex: 0x111621, alpha: 0.25), Color(hex: 0x111621)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Free today")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: 0xFACC15))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.46))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Spacer()
                        Label(localizedDuration(story.duration), systemImage: "timer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text(story.title)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    Text(story.summary)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(3)
                    Text("Start reading · \(localizedDuration(story.duration))")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(LingoRiseColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct HomeCategorySection: View {
    let category: Category
    let stories: [Content]
    let onShowAll: () -> Void
    let onStory: (Content) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(category.title)
                    .font(.system(size: 30, weight: .semibold))
                Spacer()
                Button("Show All", action: onShowAll)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LingoRiseColors.primary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(stories) { story in
                        HomeStoryCard(story: story) {
                            onStory(story)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct HomeStoryCard: View {
    let story: Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .topLeading) {
                    AsyncStoryImage(url: story.imageUrl)
                        .frame(width: 172, height: 118)
                    Text(difficultyLabel(story.level))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(difficultyColor(story.level).opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(story.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(story.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Label(localizedDuration(story.duration), systemImage: "timer")
                    Spacer()
                    Text(story.level)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 196, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class ExploreModel: ObservableObject {
    @Published var categories: [Category] = []
    @Published var allStories: [Content] = []
    @Published var query = ""
    @Published var selectedLevels: Set<String> = []
    @Published var selectedCategories: Set<String> = []
    @Published var sort: ExploreSortOption = .newest
    @Published var isLoading = false
    @Published var hasError = false
    private var service: ContentService?

    var visibleStories: [Content] {
        var result = allStories
        if query.count >= 3 {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.summary.localizedCaseInsensitiveContains(query)
                    || $0.level.localizedCaseInsensitiveContains(query)
                    || $0.category.title.localizedCaseInsensitiveContains(query)
            }
        }
        if !selectedLevels.isEmpty {
            result = result.filter { selectedLevels.contains($0.level) }
        }
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category.id) }
        }
        switch sort {
        case .newest:
            return result.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .shortestDuration:
            return result.sorted { $0.durationMs < $1.durationMs }
        case .longestDuration:
            return result.sorted { $0.durationMs > $1.durationMs }
        }
    }

    func configure(service: ContentService) {
        self.service = service
    }

    func load() async {
        guard let service, allStories.isEmpty else { return }
        isLoading = true
        hasError = false
        do {
            categories = try await service.getCategories()
            allStories = try await service.getExploreStories()
            isLoading = false
        } catch {
            hasError = true
            isLoading = false
        }
    }

    func clearDiscovery() {
        query = ""
        selectedLevels = []
        selectedCategories = []
        sort = .newest
    }
}

struct ExploreScreen: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var model: ExploreModel
    @State private var showFilters = false
    @State private var showSort = false
    private let columns = [GridItem(.adaptive(minimum: 156), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Explore")
                    .font(.system(size: 34, weight: .bold))
                Spacer()
                CircleIcon(systemName: "slider.horizontal.3", active: !model.selectedLevels.isEmpty || !model.selectedCategories.isEmpty) {
                    showFilters = true
                }
                CircleIcon(systemName: "arrow.up.arrow.down") {
                    showSort = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search stories, genres, or levels…", text: $model.query)
                    .textInputAutocapitalization(.never)
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.hasError {
                MessageState(title: "Couldn’t load stories", message: "Check your connection and try again.", actionTitle: "Retry") {
                    Task { await model.load() }
                }
            } else if model.visibleStories.isEmpty {
                VStack(spacing: 8) {
                    Text(model.query.isEmpty && model.selectedLevels.isEmpty && model.selectedCategories.isEmpty ? "No stories found" : "No stories match your search or filters.")
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(model.query.isEmpty ? "There is no published content yet. Please check back soon." : "Try adjusting your filters or searching for something else to find your next story.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if !model.query.isEmpty || !model.selectedLevels.isEmpty || !model.selectedCategories.isEmpty {
                        Button("Clear all filters") {
                            model.clearDiscovery()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LingoRiseColors.primary)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.visibleStories) { story in
                            ExploreStoryCard(story: story) {
                                if story.isPremium && !appState.isPremium {
                                    appState.route = .paywall(source: .explore)
                                } else {
                                    appState.show(story)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                }
            }
        }
        .sheet(isPresented: $showSort) {
            SortSheet(selection: $model.sort)
                .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(categories: model.categories, selectedLevels: $model.selectedLevels, selectedCategories: $model.selectedCategories)
                .presentationDetents([.medium, .large])
        }
    }
}

struct CircleIcon: View {
    let systemName: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
                if active {
                    Circle()
                        .fill(LingoRiseColors.primary)
                        .frame(width: 8, height: 8)
                        .padding(7)
                }
            }
        }
    }
}

struct ExploreStoryCard: View {
    let story: Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    AsyncStoryImage(url: story.imageUrl)
                        .aspectRatio(1.22, contentMode: .fit)
                    Text(difficultyLabel(story.level))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(difficultyColor(story.level).opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(8)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(story.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack {
                        Text(story.level)
                        Text("•")
                        Text(localizedDuration(story.duration))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    Text(story.accent.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .background(Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: ExploreSortOption

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sort by")
                .font(.system(size: 24, weight: .bold))
                .padding(.bottom, 4)
            ForEach(ExploreSortOption.allCases, id: \.self) { option in
                Button {
                    selection = option
                    dismiss()
                } label: {
                    HStack {
                        Text(option.rawValue)
                        Spacer()
                        if selection == option {
                            Image(systemName: "checkmark")
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            Spacer()
        }
        .padding(22)
    }
}

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    @Binding var selectedLevels: Set<String>
    @Binding var selectedCategories: Set<String>
    private let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Level")
                        .font(.system(size: 18, weight: .bold))
                    FlowTags(items: levels, selected: $selectedLevels)
                    Text("Category")
                        .font(.system(size: 18, weight: .bold))
                    FlowTags(items: categories.map(\.id), titles: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.title) }), selected: $selectedCategories)
                }
                .padding(20)
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        selectedLevels = []
                        selectedCategories = []
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct FlowTags: View {
    let items: [String]
    var titles: [String: String] = [:]
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
            ForEach(items, id: \.self) { item in
                Button {
                    if selected.contains(item) {
                        selected.remove(item)
                    } else {
                        selected.insert(item)
                    }
                } label: {
                    Text(titles[item] ?? item)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(selected.contains(item) ? .white : .primary)
                        .background(selected.contains(item) ? LingoRiseColors.primary : Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct ProfileScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLanguageSheet = false
    @AppStorage("app_language") private var language = "system"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile")
                            .font(.system(size: 34, weight: .bold))
                        Text("Manage your account & settings")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PremiumBadge(isPremium: appState.isPremium) {
                        appState.route = .paywall(source: .profile)
                    }
                }
                .padding(.top, 20)

                if appState.isPremium {
                    PremiumStatusCard()
                } else {
                    PremiumUpgradeCard {
                        appState.route = .paywall(source: .profile)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("GENERAL SETTINGS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        SettingsRow(symbol: "moon.fill", title: "Dark theme", subtitle: appState.isDarkTheme ? "Dark appearance" : "Light appearance", tint: LingoRiseColors.primary) {
                            appState.isDarkTheme.toggle()
                        } trailing: {
                            Toggle("", isOn: $appState.isDarkTheme)
                                .labelsHidden()
                        }
                        Divider().padding(.leading, 72)
                        SettingsRow(symbol: "globe", title: "App language", subtitle: languageLabel(language), tint: Color(hex: 0x60A5FA)) {
                            showLanguageSheet = true
                        }
                        Divider().padding(.leading, 72)
                        SettingsRow(symbol: "arrow.clockwise", title: "Restore purchase", subtitle: nil, tint: Color(hex: 0x22C55E)) {}
                        Divider().padding(.leading, 72)
                        SettingsRow(symbol: "hand.raised.fill", title: "Privacy Policy", subtitle: nil, tint: Color(hex: 0x60A5FA)) {}
                        Divider().padding(.leading, 72)
                        SettingsRow(symbol: "doc.text.fill", title: "Terms of Use", subtitle: nil, tint: Color(hex: 0xA78BFA)) {}
                        Divider().padding(.leading, 72)
                        SettingsRow(symbol: "bubble.left.and.bubble.right.fill", title: "Feedback", subtitle: nil, tint: Color(hex: 0x38BDF8)) {}
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 3)
                }

                Text("Version 1.0")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 112)
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showLanguageSheet) {
            LanguageSheet(language: $language)
                .presentationDetents([.medium])
        }
    }

    private func languageLabel(_ tag: String) -> String {
        if tag == "system" { return "System default" }
        return LanguageSheet.options.first(where: { $0.tag == tag })?.title ?? tag
    }
}

struct PremiumUpgradeCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(hex: 0x1D4ED8), Color(hex: 0x111621)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Premium Access")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFACC15))
                    Text("Master English\n3x Faster")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Get unlimited speaking practice, AI feedback, and ad-free experience.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                    Text("Upgrade Now")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(.white)
                        .background(LingoRiseColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(20)
            }
            .frame(minHeight: 210)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PremiumStatusCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Premium Plan")
                .font(.system(size: 22, weight: .bold))
            Text("All stories and practice unlocked")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            HStack {
                PremiumBenefitChip(text: "Stories")
                PremiumBenefitChip(text: "Practice")
                PremiumBenefitChip(text: "Audio")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct PremiumBenefitChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: 0x22C55E))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: 0x22C55E, alpha: 0.14))
            .clipShape(Capsule())
    }
}

struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let subtitle: String?
    let tint: Color
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    init(symbol: String, title: String, subtitle: String?, tint: Color, action: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                trailing()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

struct LanguageSheet: View {
    struct Option: Identifiable {
        let id = UUID()
        let tag: String
        let title: String
    }

    static let options: [Option] = [
        .init(tag: "system", title: "System default"),
        .init(tag: "en-US", title: "English (United States)"),
        .init(tag: "fr-FR", title: "Français (France)"),
        .init(tag: "it", title: "Italiano"),
        .init(tag: "pt-PT", title: "Português (Portugal)"),
        .init(tag: "es-419", title: "Español (Latinoamérica)"),
        .init(tag: "vi", title: "Tiếng Việt"),
        .init(tag: "ru-RU", title: "Русский"),
        .init(tag: "ar", title: "العربية"),
        .init(tag: "ja-JP", title: "日本語"),
        .init(tag: "id", title: "Bahasa Indonesia"),
        .init(tag: "ko-KR", title: "한국어"),
        .init(tag: "es-ES", title: "Español (España)"),
        .init(tag: "pt-BR", title: "Português (Brasil)"),
        .init(tag: "de-DE", title: "Deutsch"),
        .init(tag: "tr-TR", title: "Türkçe")
    ]

    @Environment(\.dismiss) private var dismiss
    @Binding var language: String

    var body: some View {
        NavigationStack {
            List(Self.options) { option in
                Button {
                    language = option.tag
                    dismiss()
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer()
                        if option.tag == language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(LingoRiseColors.primary)
                        }
                    }
                }
            }
            .navigationTitle("Choose language")
        }
    }
}

struct StoryDetailScreen: View {
    @EnvironmentObject private var appState: AppState
    let storyId: String
    let isDailyPick: Bool
    @State private var content: Content?
    @State private var isLoading = false
    @State private var hasError = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ZStack(alignment: .bottomLeading) {
                            AsyncStoryImage(url: content.imageUrl)
                                .frame(height: 410)
                                .overlay(
                                    LinearGradient(colors: [.clear, Color(hex: 0x111621, alpha: 0.94)], startPoint: .center, endPoint: .bottom)
                                )
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Badge(text: content.contentType.label)
                                    Badge(text: content.level)
                                    if isDailyPick {
                                        Badge(text: "Free today", tint: Color(hex: 0xFACC15))
                                    }
                                }
                                Text(content.title)
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("By \(content.author.isEmpty ? "LingoRise" : content.author)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .padding(22)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 0))

                        HStack(spacing: 10) {
                            DetailStat(value: localizedDuration(content.duration), label: "Duration")
                            DetailStat(value: "\(content.wordCount)", label: "Words")
                            if let rating = content.rating {
                                DetailStat(value: String(format: "%.1f", rating), label: "Rating")
                            } else {
                                DetailStat(value: "—", label: "Rating")
                            }
                        }
                        .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Synopsis")
                                .font(.system(size: 22, weight: .bold))
                            Text(content.summary)
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .lineSpacing(5)
                        }
                        .padding(.horizontal, 20)

                        if !content.targetWords.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Key Vocabulary")
                                    .font(.system(size: 22, weight: .bold))
                                ForEach(content.targetWords.prefix(5)) { word in
                                    KeyVocabularyItem(word: word)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("About this content")
                                .font(.system(size: 22, weight: .bold))
                            Text("Format: \(content.contentType.label)")
                            Text("Voice: \(content.accent.label)")
                            if let source = content.sourceReferences.first {
                                Text("Source: \(source.publisher)")
                            }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                        Button {
                            appState.route = .reading(storyId, isDailyPick)
                        } label: {
                            Text("Start Reading")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .foregroundStyle(.white)
                                .background(LingoRiseColors.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
                .ignoresSafeArea(edges: .top)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MessageState(title: hasError ? "Story unavailable" : "Story not found", message: "No content available")
            }

            CircleAction(systemName: "chevron.left") {
                appState.route = .main
            }
            .padding(.leading, 18)
            .padding(.top, 54)
        }
        .task {
            await load()
        }
    }

    @MainActor
    private func load() async {
        if let selected = appState.selectedContent, selected.id == storyId {
            content = selected
            return
        }
        isLoading = true
        do {
            content = try await appState.contentService.getContent(id: storyId)
            hasError = content == nil
        } catch {
            hasError = true
        }
        isLoading = false
    }
}

struct Badge: View {
    let text: String
    var tint: Color = LingoRiseColors.primaryLight

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DetailStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct KeyVocabularyItem: View {
    let word: TargetWord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(word.text)
                    .font(.system(size: 16, weight: .bold))
                Text(word.pronunciation)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(LingoRiseColors.primary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ReadingScreen: View {
    @EnvironmentObject private var appState: AppState
    let storyId: String
    let isDailyPick: Bool
    @State private var content: Content?
    @State private var currentIndex = 0
    @State private var isPlaying = false
    @State private var speed: Double = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ReadingHeader(title: content?.title ?? "Reading Mode") {
                    appState.route = .storyDetail(storyId, isDailyPick)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let content {
                                Text("Chapter 1: \(content.title)")
                                    .font(.system(size: 24, weight: .bold))
                                    .padding(.bottom, 10)
                                ForEach(Array(content.sentences.enumerated()), id: \.offset) { index, sentence in
                                    Text(sentence.text)
                                        .font(.system(size: index == currentIndex ? 22 : 20, weight: index == currentIndex ? .semibold : .regular))
                                        .lineSpacing(8)
                                        .foregroundStyle(index == currentIndex ? LingoRiseColors.primary : .primary)
                                        .id(index)
                                        .onTapGesture {
                                            currentIndex = index
                                        }
                                }
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 120)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 20)
                        .padding(.bottom, 170)
                    }
                    .onChange(of: currentIndex) { _, newValue in
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
            if let content {
                ReadingAudioDock(
                    content: content,
                    currentIndex: $currentIndex,
                    isPlaying: $isPlaying,
                    speed: $speed
                ) {
                    appState.route = .practice(storyId, isDailyPick)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .task { await loadPackage() }
    }

    @MainActor
    private func loadPackage() async {
        if content != nil { return }
        do {
            let package = try await appState.contentService.getStoryPackage(id: storyId)
            content = package
            appState.storyPackage = package
        } catch {
            content = appState.selectedContent
        }
    }
}

struct ReadingHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 42, height: 42)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Reading Mode")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
            }
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
}

struct ReadingAudioDock: View {
    let content: Content
    @Binding var currentIndex: Int
    @Binding var isPlaying: Bool
    @Binding var speed: Double
    let onPractice: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Sentence \(min(currentIndex + 1, content.sentences.count)) · \(formatTime(currentSentence.durationMs)) / \(formatTime(totalDuration))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("\(speedLabel)") {
                    speed = speed == 1 ? 0.75 : speed == 0.75 ? 1.25 : 1
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LingoRiseColors.primary)
            }
            Slider(value: Binding(get: {
                Double(currentIndex)
            }, set: { value in
                currentIndex = min(max(Int(value.rounded()), 0), max(content.sentences.count - 1, 0))
            }), in: 0...Double(max(content.sentences.count - 1, 0)))
            HStack(spacing: 18) {
                Button {
                    currentIndex = max(0, currentIndex - 1)
                } label: {
                    Image(systemName: "gobackward.10")
                }
                Button {
                    isPlaying.toggle()
                    if isPlaying {
                        Task {
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            await MainActor.run {
                                if currentIndex < content.sentences.count - 1 {
                                    currentIndex += 1
                                } else {
                                    isPlaying = false
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(LingoRiseColors.primary)
                        .clipShape(Circle())
                }
                Button {
                    currentIndex = min(content.sentences.count - 1, currentIndex + 1)
                } label: {
                    Image(systemName: "goforward.10")
                }
                Spacer()
                Button(action: onPractice) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color(hex: 0x22C55E))
                        .clipShape(Circle())
                }
            }
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.primary)
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private var currentSentence: SentenceAudio {
        guard !content.sentences.isEmpty else {
            return SentenceAudio(index: 0, text: "", audioUrl: "", durationMs: 0, pronunciation: "")
        }
        return content.sentences[min(currentIndex, content.sentences.count - 1)]
    }

    private var totalDuration: Int {
        content.sentences.reduce(0) { $0 + $1.durationMs }
    }

    private var speedLabel: String {
        speed == 1 ? "1x" : speed == 0.75 ? "0.75x" : "1.25x"
    }
}

struct PracticeScreen: View {
    @EnvironmentObject private var appState: AppState
    let storyId: String
    let isDailyPick: Bool
    @State private var content: Content?
    @State private var index = 0
    @State private var selectedTokens: [String] = []
    @State private var checked: Bool?
    @State private var showCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleAction(systemName: "xmark") {
                    appState.route = .storyDetail(storyId, isDailyPick)
                }
                Spacer()
                Text("SPEAKING DRILL")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(min(index + 1, sentences.count)) / \(max(sentences.count, 1))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(18)

            if sentences.isEmpty {
                MessageState(title: "Practice is not ready yet", message: "This content does not have short audio sentences for practice yet.")
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Listen and build the sentence")
                        .font(.system(size: 28, weight: .bold))
                    Text("Play the audio, then tap the words in the order you hear them.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button {
                    } label: {
                        Label("Listen", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(LingoRiseColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tap the words below to build the sentence.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        SelectedTokenLine(tokens: selectedTokens) { token in
                            selectedTokens.removeAll { $0 == token }
                            checked = nil
                        }
                        TokenBank(tokens: shuffledTokens) { token in
                            selectedTokens.append(token)
                            checked = nil
                        }
                    }
                    if let checked {
                        Text(checked ? "Nice work. You caught the full sentence." : "Almost. Listen again and rebuild the sentence.")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(checked ? Color(hex: 0x22C55E) : Color(hex: 0xEF4444))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((checked ? Color(hex: 0x22C55E) : Color(hex: 0xEF4444)).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button("PREVIOUS") {
                            index = max(0, index - 1)
                            selectedTokens = []
                            checked = nil
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button(index == sentences.count - 1 ? "Finish" : "Check") {
                            if checked == true {
                                if index == sentences.count - 1 {
                                    showCompleted = true
                                } else {
                                    index += 1
                                    selectedTokens = []
                                    checked = nil
                                }
                            } else {
                                checked = selectedTokens.joined(separator: " ") == sentenceTokens.joined(separator: " ")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(22)
            }
        }
        .task { await loadPackage() }
        .sheet(isPresented: $showCompleted) {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(Color(hex: 0x22C55E))
                Text("Practice Completed!")
                    .font(.system(size: 26, weight: .bold))
                Text("Great work! You are one step closer to fluency.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Explore Stories") {
                    showCompleted = false
                    appState.route = .main
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(28)
            .presentationDetents([.height(330)])
        }
    }

    private var sentences: [SentenceAudio] {
        let all = content?.sentences ?? []
        let indexes = content?.practiceSentenceIndexes ?? []
        if indexes.isEmpty { return Array(all.prefix(5)) }
        return all.filter { indexes.contains($0.index) }
    }

    private var currentSentence: SentenceAudio {
        sentences[min(index, max(sentences.count - 1, 0))]
    }

    private var sentenceTokens: [String] {
        currentSentence.text
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .split(separator: " ")
            .map(String.init)
    }

    private var shuffledTokens: [String] {
        sentenceTokens.filter { !selectedTokens.contains($0) }.sorted()
    }

    @MainActor
    private func loadPackage() async {
        if let package = appState.storyPackage, package.id == storyId {
            content = package
            return
        }
        do {
            content = try await appState.contentService.getStoryPackage(id: storyId)
        } catch {
            content = appState.selectedContent
        }
    }
}

struct SelectedTokenLine: View {
    let tokens: [String]
    let remove: (String) -> Void

    var body: some View {
        HStack {
            if tokens.isEmpty {
                Text(" ")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowLayout(items: tokens) { token in
                    Button(token) { remove(token) }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(LingoRiseColors.primary.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .frame(minHeight: 74)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TokenBank: View {
    let tokens: [String]
    let select: (String) -> Void

    var body: some View {
        FlowLayout(items: tokens) { token in
            Button(token) { select(token) }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
    }
}

struct FlowLayout<Data: RandomAccessCollection, ContentView: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> ContentView

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
            }
        }
    }
}

struct PaywallScreen: View {
    @EnvironmentObject private var appState: AppState
    let source: PaywallSource
    @State private var selectedPlan = "yearly"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    appState.dismissPaywall(source: source)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Text("Your English")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(heroTitle)
                            .font(.system(size: 44, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    }
                    Text("Learners build stronger habits with a clear weekly path.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFACC15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(hex: 0xFACC15, alpha: 0.12))
                        .clipShape(Capsule())
                    VStack(spacing: 12) {
                        PremiumValueRow(symbol: "map.fill", title: "Guided weekly path", subtitle: "Milestones matched to your pace")
                        PremiumValueRow(symbol: "book.fill", title: "Unlimited stories", subtitle: "Read as much as you want")
                        PremiumValueRow(symbol: "speaker.wave.2.fill", title: "Listen & read", subtitle: "Stories with professional audio")
                        PremiumValueRow(symbol: "puzzlepiece.fill", title: "Listening sentence puzzles", subtitle: "Hear it, rebuild the sentence")
                    }
                    PlanCard(title: "Weekly", price: "$9.99", period: "/ week", badge: "Flexible start", selected: selectedPlan == "weekly") {
                        selectedPlan = "weekly"
                    }
                    PlanCard(title: "Yearly", price: "$39.99", period: "/ year", badge: "Best value", selected: selectedPlan == "yearly") {
                        selectedPlan = "yearly"
                    }
                    Button {
                        appState.isPremium = true
                        appState.completePaywall(source: source)
                    } label: {
                        Text(cta)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .foregroundStyle(.white)
                            .background(LingoRiseColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    Button("Restore Purchases") {}
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        Text("Privacy Policy")
                        Text("Terms of Use")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var heroTitle: String {
        switch source {
        case .personalizedOnboarding: return "plan is ready"
        case .profileYearlyUpgrade: return "all year long"
        default: return "rise starts now"
        }
    }

    private var subtitle: String {
        switch source {
        case .personalizedOnboarding: return "Your guided path is prepared. Unlock premium lessons, AI feedback, and every milestone."
        case .profileYearlyUpgrade: return "You already know Premium works for you. Switch to yearly and keep your progress going for less."
        default: return "Speak, listen, and read with a premium path built for consistent English progress."
        }
    }

    private var cta: String {
        selectedPlan == "yearly" ? "Claim My Year of Growth" : "Start This Week’s Rise"
    }
}

struct PremiumValueRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(LingoRiseColors.primary)
                .frame(width: 42, height: 42)
                .background(LingoRiseColors.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct PlanCard: View {
    let title: String
    let price: String
    let period: String
    let badge: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(title)
                            .font(.system(size: 19, weight: .bold))
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(selected ? .white : LingoRiseColors.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selected ? LingoRiseColors.primary : LingoRiseColors.primary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(price)
                            .font(.system(size: 28, weight: .bold))
                        Text(period)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(selected ? LingoRiseColors.primary : .secondary)
            }
            .padding(18)
            .foregroundStyle(.primary)
            .background(Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? LingoRiseColors.primary : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct AsyncStoryImage: View {
    let url: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x26344F), LingoRiseColors.primary.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let parsed = URL(string: url), !url.isEmpty {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "book.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.16))
                    }
                }
            } else {
                Image(systemName: "book.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.16))
            }
        }
        .clipped()
    }
}

struct CircleAction: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(.regularMaterial)
                .clipShape(Circle())
        }
    }
}

struct MessageState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LingoRiseColors.primary)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(LingoRiseColors.primary.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.primary)
            .background(Color(.secondarySystemBackground).opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

func localizedDuration(_ duration: String) -> String {
    duration.replacingOccurrences(of: "minutes", with: "min").replacingOccurrences(of: "minute", with: "min")
}

func difficultyLabel(_ level: String) -> String {
    switch level.uppercased() {
    case "A1", "A2": return "Beginner"
    case "B1", "B2": return "Intermediate"
    case "C1", "C2": return "Advanced"
    default: return level
    }
}

func difficultyColor(_ level: String) -> Color {
    switch level.uppercased() {
    case "A1", "A2": return Color(hex: 0xBFDBFE)
    case "B1", "B2": return Color(hex: 0xFDE68A)
    case "C1", "C2": return Color(hex: 0xFECACA)
    default: return Color(hex: 0xE5E7EB)
    }
}

func formatTime(_ ms: Int) -> String {
    let totalSeconds = max(ms / 1000, 0)
    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
}

@MainActor
final class ContentService {
    private let projectId = "lingorise-d8497"
    private let session: URLSession
    private var categoryCache: [Category]?
    private var catalogCache: [Content]?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func getCategories() async throws -> [Category] {
        if let categoryCache { return categoryCache }
        do {
            let docs = try await fetchDocuments(collection: "categories")
            let categories = docs.compactMap(Self.category(from:)).sorted { lhs, rhs in
                lhs.title < rhs.title
            }
            if !categories.isEmpty {
                categoryCache = categories
                return categories
            }
        } catch {}
        categoryCache = SampleData.categories
        return SampleData.categories
    }

    func getDailyPick() async throws -> Content? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let dateId = formatter.string(from: Date())
        do {
            let document = try await fetchDocument(collection: "daily_picks", id: dateId)
            if let contentId = document.string("contentId"), !contentId.isEmpty {
                return try await getContent(id: contentId)
            }
        } catch {}
        return try await getExploreStories().first
    }

    func getStories(categoryId: String, limit: Int) async throws -> [Content] {
        Array(try await getExploreStories().filter { $0.category.id == categoryId }.prefix(limit))
    }

    func getExploreStories() async throws -> [Content] {
        if let catalogCache { return catalogCache }
        do {
            let docs = try await fetchDocuments(collection: "content_catalog")
            let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
            let contents = docs.compactMap { Self.content(from: $0, categories: categories) }
                .filter { !$0.title.isEmpty }
                .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            if !contents.isEmpty {
                catalogCache = contents
                return contents
            }
        } catch {}
        catalogCache = SampleData.contents
        return SampleData.contents
    }

    func getContent(id: String) async throws -> Content? {
        if let cached = try await getExploreStories().first(where: { $0.id == id }) {
            return cached
        }
        do {
            let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
            let doc = try await fetchDocument(collection: "content_catalog", id: id)
            return Self.content(from: doc, categories: categories)
        } catch {
            return SampleData.contents.first(where: { $0.id == id })
        }
    }

    func getStoryPackage(id: String) async throws -> Content {
        let metadata = try await getContent(id: id) ?? SampleData.contents[0]
        do {
            let package = try await callContentPackage(id: id)
            return metadata.withPackage(
                sentences: package.sentences.isEmpty ? metadata.sentences : package.sentences,
                targetWords: package.targetWords.isEmpty ? metadata.targetWords : package.targetWords,
                practiceSentenceIndexes: package.practiceSentenceIndexes
            )
        } catch {
            if metadata.sentences.isEmpty {
                return metadata.withPackage(sentences: SampleData.sentences, targetWords: metadata.targetWords, practiceSentenceIndexes: [0, 1, 2])
            }
            return metadata
        }
    }

    private func fetchDocuments(collection: String) async throws -> [FirestoreDocument] {
        let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(collection)")!
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(FirestoreListResponse.self, from: data)
        return response.documents ?? []
    }

    private func fetchDocument(collection: String, id: String) async throws -> FirestoreDocument {
        let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(collection)/\(id)")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(FirestoreDocument.self, from: data)
    }

    private func callContentPackage(id: String) async throws -> StoryPackage {
        let url = URL(string: "https://us-central1-\(projectId).cloudfunctions.net/getContentPackage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["contentId": id]])
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(CallablePackageResponse.self, from: data)
        return decoded.result
    }

    private static func category(from doc: FirestoreDocument) -> Category? {
        let id = doc.string("id") ?? doc.documentId
        let title = doc.string("title") ?? id
        return Category(id: id, title: title, symbol: symbol(for: doc.string("iconName")))
    }

    private static func content(from doc: FirestoreDocument, categories: [String: Category]) -> Content? {
        let id = doc.string("id") ?? doc.documentId
        let title = doc.string("title") ?? ""
        guard !id.isEmpty, !title.isEmpty else { return nil }
        let categoryId = doc.string("categoryId") ?? ""
        let category = categories[categoryId] ?? Category(id: categoryId, title: categoryId.isEmpty ? "Stories" : categoryId, symbol: "book.fill")
        let type = ContentType(rawValue: (doc.string("contentType") ?? "story").lowercased()) ?? .story
        let accent = EnglishAccent(rawValue: doc.string("accent") ?? "en-US") ?? .us
        return Content(
            id: id,
            title: title,
            author: doc.string("author") ?? "",
            summary: doc.string("summary") ?? "",
            category: category,
            level: doc.string("level") ?? "",
            duration: doc.string("duration") ?? "",
            imageUrl: doc.string("imageUrl") ?? "",
            durationMs: doc.int("durationMs") ?? 0,
            sentences: [],
            isPremium: doc.bool("isPremium") ?? true,
            createdAt: doc.timestamp("publishedAt"),
            wordCount: doc.int("wordCount") ?? 0,
            targetWords: doc.array("targetWords").compactMap(Self.targetWord),
            contentType: type,
            rating: doc.double("averageRating").flatMap { $0 > 0 ? $0 : nil },
            ratingCount: doc.int("ratingCount") ?? 0,
            accent: accent,
            sourceReferences: doc.array("sourceReferences").compactMap(Self.sourceReference),
            practiceSentenceIndexes: []
        )
    }

    private static func targetWord(_ value: FirestoreValue) -> TargetWord? {
        guard case let .mapValue(map) = value, let fields = map.fields else { return nil }
        return TargetWord(
            text: fields["text"]?.stringValue ?? "",
            pronunciation: fields["pronunciation"]?.stringValue ?? "",
            audioUrl: fields["audioUrl"]?.stringValue ?? ""
        )
    }

    private static func sourceReference(_ value: FirestoreValue) -> SourceReference? {
        guard case let .mapValue(map) = value, let fields = map.fields else { return nil }
        return SourceReference(
            title: fields["title"]?.stringValue ?? "",
            publisher: fields["publisher"]?.stringValue ?? "",
            url: fields["url"]?.stringValue ?? "",
            publishedAt: fields["publishedAt"]?.stringValue ?? "",
            countryCode: fields["countryCode"]?.stringValue ?? "",
            isLocal: fields["isLocal"]?.booleanValue ?? false
        )
    }

    private static func symbol(for iconName: String?) -> String {
        switch iconName {
        case "TravelExplore", "Public": return "airplane"
        case "Business": return "briefcase.fill"
        case "Science": return "atom"
        case "LocalCafe": return "cup.and.saucer.fill"
        case "Explore": return "safari.fill"
        case "Movie": return "film.fill"
        case "People": return "person.2.fill"
        case "Article": return "doc.text.fill"
        default: return "book.fill"
        }
    }
}

extension Content {
    func withPackage(sentences: [SentenceAudio], targetWords: [TargetWord], practiceSentenceIndexes: [Int]) -> Content {
        Content(
            id: id,
            title: title,
            author: author,
            summary: summary,
            category: category,
            level: level,
            duration: duration,
            imageUrl: imageUrl,
            durationMs: durationMs,
            sentences: sentences,
            isPremium: isPremium,
            createdAt: createdAt,
            wordCount: wordCount,
            targetWords: targetWords,
            contentType: contentType,
            rating: rating,
            ratingCount: ratingCount,
            accent: accent,
            sourceReferences: sourceReferences,
            practiceSentenceIndexes: practiceSentenceIndexes
        )
    }
}

struct FirestoreListResponse: Decodable {
    let documents: [FirestoreDocument]?
}

struct FirestoreDocument: Decodable {
    let name: String
    let fields: [String: FirestoreValue]?

    var documentId: String {
        name.split(separator: "/").last.map(String.init) ?? ""
    }

    func string(_ key: String) -> String? { fields?[key]?.stringValue }
    func bool(_ key: String) -> Bool? { fields?[key]?.booleanValue }
    func int(_ key: String) -> Int? { fields?[key]?.intValue }
    func double(_ key: String) -> Double? { fields?[key]?.doubleValue }
    func array(_ key: String) -> [FirestoreValue] { fields?[key]?.arrayValue?.values ?? [] }
    func timestamp(_ key: String) -> Date? {
        guard let text = fields?[key]?.timestampValue else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}

indirect enum FirestoreValue: Decodable {
    case stringValue(String)
    case integerValue(String)
    case doubleValue(Double)
    case booleanValue(Bool)
    case timestampValue(String)
    case arrayValue(FirestoreArray)
    case mapValue(FirestoreMap)
    case null

    var stringValue: String? {
        if case let .stringValue(value) = self { return value }
        return nil
    }

    var booleanValue: Bool? {
        if case let .booleanValue(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case let .integerValue(value): return Int(value)
        case let .doubleValue(value): return Int(value)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .doubleValue(value): return value
        case let .integerValue(value): return Double(value)
        default: return nil
        }
    }

    var timestampValue: String? {
        if case let .timestampValue(value) = self { return value }
        return nil
    }

    var arrayValue: FirestoreArray? {
        if case let .arrayValue(value) = self { return value }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .stringValue) {
            self = .stringValue(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .integerValue) {
            self = .integerValue(value)
        } else if let value = try container.decodeIfPresent(Double.self, forKey: .doubleValue) {
            self = .doubleValue(value)
        } else if let value = try container.decodeIfPresent(Bool.self, forKey: .booleanValue) {
            self = .booleanValue(value)
        } else if let value = try container.decodeIfPresent(String.self, forKey: .timestampValue) {
            self = .timestampValue(value)
        } else if let value = try container.decodeIfPresent(FirestoreArray.self, forKey: .arrayValue) {
            self = .arrayValue(value)
        } else if let value = try container.decodeIfPresent(FirestoreMap.self, forKey: .mapValue) {
            self = .mapValue(value)
        } else {
            self = .null
        }
    }

    enum CodingKeys: String, CodingKey {
        case stringValue
        case integerValue
        case doubleValue
        case booleanValue
        case timestampValue
        case arrayValue
        case mapValue
    }
}

struct FirestoreArray: Decodable {
    let values: [FirestoreValue]?
}

struct FirestoreMap: Decodable {
    let fields: [String: FirestoreValue]?
}

struct CallablePackageResponse: Decodable {
    let result: StoryPackage
}

struct StoryPackage: Decodable {
    let sentences: [SentenceAudio]
    let targetWords: [TargetWord]
    let practiceSentenceIndexes: [Int]
}

extension SentenceAudio: Decodable {
    enum CodingKeys: String, CodingKey {
        case index
        case text
        case audioUrl
        case durationMs
        case pronunciation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        audioUrl = try container.decodeIfPresent(String.self, forKey: .audioUrl) ?? ""
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
    }
}

extension TargetWord: Decodable {}

enum SampleData {
    static let categories = [
        Category(id: "short_easy", title: "Short & Easy", symbol: "book.fill"),
        Category(id: "travel", title: "Travel", symbol: "airplane"),
        Category(id: "business", title: "Business", symbol: "briefcase.fill")
    ]

    static let sentences = [
        SentenceAudio(index: 0, text: "The mist rolled in from the northern peaks.", audioUrl: "", durationMs: 4200, pronunciation: ""),
        SentenceAudio(index: 1, text: "She listened closely as the ancient stones began to glow.", audioUrl: "", durationMs: 5600, pronunciation: ""),
        SentenceAudio(index: 2, text: "Every story became a new path into English.", audioUrl: "", durationMs: 4700, pronunciation: "")
    ]

    static let contents: [Content] = [
        Content(
            id: "sample-lost-city",
            title: "The Lost City of Z",
            author: "LingoRise",
            summary: "A short immersive story for listening, reading, and speaking practice.",
            category: categories[0],
            level: "B1",
            duration: "15 min",
            imageUrl: "",
            durationMs: 900000,
            sentences: sentences,
            isPremium: false,
            createdAt: Date(),
            wordCount: 840,
            targetWords: [
                TargetWord(text: "mist", pronunciation: "/mɪst/", audioUrl: ""),
                TargetWord(text: "ancient", pronunciation: "/ˈeɪnʃənt/", audioUrl: ""),
                TargetWord(text: "journey", pronunciation: "/ˈdʒɜːrni/", audioUrl: "")
            ],
            contentType: .story,
            rating: 4.8,
            ratingCount: 124,
            accent: .us,
            sourceReferences: [],
            practiceSentenceIndexes: [0, 1, 2]
        ),
        Content(
            id: "sample-coffee",
            title: "Coffee Culture in Italy",
            author: "LingoRise",
            summary: "Learn everyday English through a warm travel scene in an Italian cafe.",
            category: categories[1],
            level: "A2",
            duration: "8 min",
            imageUrl: "",
            durationMs: 480000,
            sentences: sentences,
            isPremium: true,
            createdAt: Date().addingTimeInterval(-86400),
            wordCount: 520,
            targetWords: [TargetWord(text: "culture", pronunciation: "/ˈkʌltʃər/", audioUrl: "")],
            contentType: .article,
            rating: 4.6,
            ratingCount: 89,
            accent: .uk,
            sourceReferences: [],
            practiceSentenceIndexes: [0, 1]
        ),
        Content(
            id: "sample-tech",
            title: "Tech Trends 2024",
            author: "LingoRise",
            summary: "A modern reading about technology, habits, and clear business vocabulary.",
            category: categories[2],
            level: "B2",
            duration: "12 min",
            imageUrl: "",
            durationMs: 720000,
            sentences: sentences,
            isPremium: true,
            createdAt: Date().addingTimeInterval(-172800),
            wordCount: 720,
            targetWords: [TargetWord(text: "trend", pronunciation: "/trend/", audioUrl: "")],
            contentType: .news,
            rating: nil,
            ratingCount: 0,
            accent: .us,
            sourceReferences: [],
            practiceSentenceIndexes: [1, 2]
        )
    ]
}
