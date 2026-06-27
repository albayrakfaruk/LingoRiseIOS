import AVFoundation
import Combine
import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseCore
import FirebaseFirestore
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

@main
struct LingoRiseApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environment(\.locale, Locale(identifier: AppLocalization.localeIdentifier(for: appState.appLanguage)))
                .preferredColorScheme(appState.preferredColorScheme)
                .id(appState.appLanguage)
        }
    }
}

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

enum NewsScope: String, Codable {
    case global
    case regional
}

enum ExploreSortOption: String, CaseIterable {
    case newest = "Newest"
    case shortestDuration = "Shortest Duration"
    case longestDuration = "Longest Duration"

    var titleKey: String {
        switch self {
        case .newest: return "explore_sort_newest"
        case .shortestDuration: return "explore_sort_shortest"
        case .longestDuration: return "explore_sort_longest"
        }
    }
}

struct ExplorePageResult {
    let items: [Content]
    let lastCreatedAt: Date?
    let lastDocId: String?
    let hasMore: Bool
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

struct ImageAttribution: Hashable {
    let source: String
    let creator: String
    let sourcePageUrl: String
    let license: String
    let attribution: String
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
    let newsScope: NewsScope?
    let regionCode: String
    let regionLabel: String
    let countryCodes: [String]
    let sourceReferences: [SourceReference]
    let imageAttribution: ImageAttribution?
    let practiceSentenceIndexes: [Int]
}

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



struct MainScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var homeModel = HomeModel()
    @StateObject private var exploreModel = ExploreModel()
    @State private var activeExploreSheet: ExploreSheetKind?
    @State private var isProfileLanguageSheetPresented = false

    var body: some View {
        let isExploreSheetPresented = activeExploreSheet != nil
        let isBottomSheetPresented = isExploreSheetPresented || isProfileLanguageSheetPresented
        let palette = HomePalette(isDark: appState.effectiveDarkTheme(systemColorScheme: colorScheme))
        ZStack(alignment: .bottom) {
            ZStack {
                HomeScreen(model: homeModel) { category in
                    exploreModel.selectCategory(category.id)
                    appState.selectedTab = .explore
                }
                .opacity(appState.selectedTab == .home ? 1 : 0)
                .allowsHitTesting(appState.selectedTab == .home)
                .accessibilityHidden(appState.selectedTab != .home)

                ExploreScreen(model: exploreModel, activeSheet: $activeExploreSheet)
                    .opacity(appState.selectedTab == .explore ? 1 : 0)
                    .allowsHitTesting(appState.selectedTab == .explore)
                    .accessibilityHidden(appState.selectedTab != .explore)

                ProfileScreen(showLanguageSheet: $isProfileLanguageSheetPresented)
                    .opacity(appState.selectedTab == .profile ? 1 : 0)
                    .allowsHitTesting(appState.selectedTab == .profile)
                    .accessibilityHidden(appState.selectedTab != .profile)
            }
            if !isBottomSheetPresented {
                FloatingTabBar(selectedTab: $appState.selectedTab)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }

            if appState.selectedTab == .explore, let activeExploreSheet {
                switch activeExploreSheet {
                case .sort:
                    ExploreBottomSheet(palette: palette, maxHeight: nil) {
                        SortSheet(selection: exploreModel.sort, palette: palette) { option in
                            exploreModel.updateSortOption(option)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                                self.activeExploreSheet = nil
                            }
                        }
                    } onDismiss: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                            self.activeExploreSheet = nil
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .filters:
                    ExploreBottomSheet(palette: palette, maxHeight: nil) {
                        FilterSheet(
                            categories: exploreModel.categories,
                            selectedLevels: exploreModel.selectedLevels,
                            selectedCategories: exploreModel.selectedCategories,
                            palette: palette
                        ) { levels, categories in
                            exploreModel.updateFilters(levels: levels, categories: categories)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                                self.activeExploreSheet = nil
                            }
                        }
                    } onDismiss: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                            self.activeExploreSheet = nil
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            if appState.selectedTab == .profile, isProfileLanguageSheetPresented {
                ExploreBottomSheet(palette: palette, maxHeight: nil) {
                    LanguageSheet(
                        language: Binding(
                            get: { appState.appLanguage },
                            set: { appState.setAppLanguage($0) }
                        ),
                        systemLanguageTag: Locale.preferredLanguages.first ?? "en-US"
                    )
                } onDismiss: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                        isProfileLanguageSheetPresented = false
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isBottomSheetPresented)
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: activeExploreSheet)
        .animation(.spring(response: 0.28, dampingFraction: 0.92), value: isProfileLanguageSheetPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appState.selectedTab) { _, _ in
            activeExploreSheet = nil
            isProfileLanguageSheetPresented = false
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: MainTab

    var body: some View {
        let isDark = appState.effectiveDarkTheme(systemColorScheme: colorScheme)
        let background = isDark ? LingoRiseColors.surfaceDark : Color.white.opacity(0.92)
        let inactive = isDark ? LingoRiseColors.onSurfaceVariantDark : Color(.secondaryLabel)

        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                        Text(L10n.t(tab.titleKey))
                            .font(LexendFont.font(11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .foregroundStyle(selectedTab == tab ? LingoRiseColors.primary : inactive)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.86)
        .background(background)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04), lineWidth: 1))
        .shadow(color: .black.opacity(isDark ? 0.42 : 0.18), radius: 14, x: 0, y: 8)
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

private extension String {
    var firstMatchNumber: Int? {
        firstMatchNumber(pattern: #"\d+"#)
    }

    func firstMatchNumber(pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else {
            return nil
        }
        let matchedRange = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
            ? match.range(at: 1)
            : match.range
        guard let range = Range(matchedRange, in: self) else { return nil }
        return Int(self[range])
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
    switch level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "a1", "beginner": return "A1"
    case "a2", "elementary": return "A2"
    case "b1": return "B1"
    case "b2", "intermediate": return "B2"
    case "c1", "advanced": return "C1"
    default:
        let value = level.uppercased()
        return value.isEmpty ? "-" : value
    }
}

func difficultyColor(_ level: String) -> Color {
    switch difficultyLabel(level) {
    case "A1", "A2": return Color(hex: 0x22C55E)
    case "B1", "B2": return Color(hex: 0xEAB308)
    case "C1": return Color(hex: 0xEF4444)
    default: return Color(hex: 0x9CA3AF)
    }
}

func voiceLabel(_ accent: EnglishAccent) -> String {
    let flag = accent == .uk ? "🇬🇧" : "🇺🇸"
    return L10n.format("story_voice_accent_format", flag, accent.label)
}

func formatTime(_ ms: Int) -> String {
    let totalSeconds = max(ms / 1000, 0)
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
}

@MainActor
enum ContentServiceError: Error {
    case storyNotFound
    case packageFailed(statusCode: Int, body: String)
}

@MainActor
final class ContentService {
    private let projectId = "lingorise-d8497"
    private let functionsRegion = "europe-west1"
    private let session: URLSession
    private var categoryCache: [Category]?
    private var catalogCache: [Content]?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func getCategories() async throws -> [Category] {
        if let categoryCache { return categoryCache }
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                let categories = try await fetchFirestoreCategories()
                if !categories.isEmpty {
                    categoryCache = categories
                    return categories
                }
            } catch {
                debugLog("firestore_categories_failed", error)
            }
        }
        #endif
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
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                let document = try await Firestore.firestore()
                    .collection("daily_picks")
                    .document(dateId)
                    .getDocument()
                if let contentId = document.data()?["contentId"] as? String, !contentId.isEmpty {
                    return try await getContent(id: contentId)
                }
            } catch {
                debugLog("firestore_daily_pick_failed", error)
            }
        }
        #endif
        do {
            let document = try await fetchDocument(collection: "daily_picks", id: dateId)
            if let contentId = document.string("contentId"), !contentId.isEmpty {
                return try await getContent(id: contentId)
            }
        } catch {}
        return try await getExploreStories().first
    }

    func getStories(categoryId: String, limit: Int) async throws -> [Content] {
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                return try await fetchFirestoreStories(categoryId: categoryId, limit: limit)
            } catch {
                debugLog("firestore_category_stories_failed", error)
            }
        }
        #endif
        return Array(try await getExploreStories().filter { $0.category.id == categoryId }.prefix(limit))
    }

    func getExploreStories() async throws -> [Content] {
        if let catalogCache { return catalogCache }
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                let contents = try await fetchFirestoreCatalog()
                if !contents.isEmpty {
                    catalogCache = contents
                    return contents
                }
            } catch {
                debugLog("firestore_catalog_failed", error)
            }
        }
        #endif
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

    func getExploreStoriesPage(
        limit: Int,
        startAfterDocId: String?,
        searchQuery: String?,
        selectedLevels: Set<String>,
        selectedCategories: Set<String>,
        sortOption: ExploreSortOption
    ) async throws -> ExplorePageResult {
        var contents = try await getExploreStories()
        if let searchQuery, !searchQuery.isEmpty {
            let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if needle.count >= 3 {
                contents = contents.filter { content in
                    content.title.localizedCaseInsensitiveContains(needle)
                        || content.author.localizedCaseInsensitiveContains(needle)
                        || content.summary.localizedCaseInsensitiveContains(needle)
                        || content.category.title.localizedCaseInsensitiveContains(needle)
                        || content.targetWords.contains { $0.text.localizedCaseInsensitiveContains(needle) }
                }
            }
        }
        if !selectedLevels.isEmpty {
            let levels = Set(selectedLevels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
            contents = contents.filter { levels.contains($0.level.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) }
        }
        if !selectedCategories.isEmpty {
            contents = contents.filter { selectedCategories.contains($0.category.id) }
        }
        contents = sortExplore(contents, option: sortOption)

        let startIndex: Int
        if let startAfterDocId,
           let foundIndex = contents.firstIndex(where: { $0.id == startAfterDocId }) {
            startIndex = contents.index(after: foundIndex)
        } else {
            startIndex = contents.startIndex
        }
        guard startIndex < contents.endIndex else {
            return ExplorePageResult(items: [], lastCreatedAt: nil, lastDocId: startAfterDocId, hasMore: false)
        }

        let endIndex = contents.index(startIndex, offsetBy: max(limit, 0), limitedBy: contents.endIndex) ?? contents.endIndex
        let pageItems = Array(contents[startIndex..<endIndex])
        return ExplorePageResult(
            items: pageItems,
            lastCreatedAt: pageItems.last?.createdAt,
            lastDocId: pageItems.last?.id ?? startAfterDocId,
            hasMore: endIndex < contents.endIndex
        )
    }

    private func sortExplore(_ contents: [Content], option: ExploreSortOption) -> [Content] {
        switch option {
        case .newest:
            return contents.sorted {
                let lhsDate = $0.createdAt ?? .distantPast
                let rhsDate = $1.createdAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.id < $1.id
            }
        case .shortestDuration:
            return contents.sorted {
                let lhsDuration = durationMsForSort($0)
                let rhsDuration = durationMsForSort($1)
                if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
                let lhsDate = $0.createdAt ?? .distantPast
                let rhsDate = $1.createdAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.id < $1.id
            }
        case .longestDuration:
            return contents.sorted {
                let lhsMissing = durationMsForSort($0) == Int.max
                let rhsMissing = durationMsForSort($1) == Int.max
                if lhsMissing != rhsMissing { return !lhsMissing }
                let lhsDuration = durationMsForSort($0) == Int.max ? Int.min : durationMsForSort($0)
                let rhsDuration = durationMsForSort($1) == Int.max ? Int.min : durationMsForSort($1)
                if lhsDuration != rhsDuration { return lhsDuration > rhsDuration }
                let lhsDate = $0.createdAt ?? .distantPast
                let rhsDate = $1.createdAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.id < $1.id
            }
        }
    }

    private func durationMsForSort(_ content: Content) -> Int {
        if content.durationMs > 0 { return content.durationMs }
        let sentenceDuration = content.sentences.reduce(0) { $0 + $1.durationMs }
        if sentenceDuration > 0 { return sentenceDuration }
        return durationLabelToMs(content.duration) ?? Int.max
    }

    private func durationLabelToMs(_ duration: String) -> Int? {
        let normalized = duration.lowercased()
        if let minutes = firstNumber(in: normalized, units: ["min", "minute", "minutes", "dk"]) {
            return minutes * 60_000
        }
        if let seconds = firstNumber(in: normalized, units: ["sec", "second", "seconds", "sn"]) {
            return seconds * 1_000
        }
        guard let number = normalized.firstMatchNumber else { return nil }
        return number * 60_000
    }

    private func firstNumber(in value: String, units: [String]) -> Int? {
        for unit in units {
            let pattern = #"(\d+)\s*"# + NSRegularExpression.escapedPattern(for: unit)
            if let number = value.firstMatchNumber(pattern: pattern) {
                return number
            }
        }
        return nil
    }

    func getContent(id: String) async throws -> Content? {
        if let cached = try await getExploreStories().first(where: { $0.id == id }) {
            return cached
        }
        #if canImport(FirebaseFirestore)
        if FirebaseApp.app() != nil {
            do {
                let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
                let document = try await Firestore.firestore()
                    .collection("content_catalog")
                    .document(id)
                    .getDocument()
                if let content = Self.content(id: document.documentID, data: document.data() ?? [:], categories: categories) {
                    return content
                }
            } catch {
                debugLog("firestore_content_failed", error)
            }
        }
        #endif
        do {
            let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
            let doc = try await fetchDocument(collection: "content_catalog", id: id)
            return Self.content(from: doc, categories: categories)
        } catch {
            return SampleData.contents.first(where: { $0.id == id })
        }
    }

    func getStoryPackage(id: String) async throws -> Content {
        guard let metadata = try await getContent(id: id) else {
            throw ContentServiceError.storyNotFound
        }
        do {
            let package = try await callContentPackage(id: id)
            return metadata.withPackage(
                sentences: package.sentences.isEmpty ? metadata.sentences : package.sentences,
                targetWords: package.targetWords.isEmpty ? metadata.targetWords : package.targetWords,
                practiceSentenceIndexes: package.practiceSentenceIndexes
            )
        } catch {
            debugLog("content_package_failed", error)
            return metadata
        }
    }

    func updateCurrentRating(storyId: String, averageRating: Double, ratingCount: Int) {
        catalogCache = catalogCache?.map { content in
            content.id == storyId
                ? content.withRating(averageRating: averageRating, ratingCount: ratingCount)
                : content
        }
    }

    #if canImport(FirebaseFirestore)
    private func fetchFirestoreCategories() async throws -> [Category] {
        let snapshot = try await Firestore.firestore()
            .collection("categories")
            .getDocuments()

        return snapshot.documents
            .filter { ($0.data()["active"] as? Bool) ?? true }
            .sorted { lhs, rhs in
                Self.intValue(lhs.data()["order"]) < Self.intValue(rhs.data()["order"])
            }
            .compactMap { Self.category(id: $0.documentID, data: $0.data()) }
    }

    private func fetchFirestoreStories(categoryId: String, limit: Int) async throws -> [Content] {
        let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
        let snapshot = try await Firestore.firestore()
            .collection("content_catalog")
            .whereField("categoryId", isEqualTo: categoryId)
            .whereField("status", isEqualTo: "published")
            .order(by: "publishedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap {
            Self.content(id: $0.documentID, data: $0.data(), categories: categories)
        }
    }

    private func fetchFirestoreCatalog() async throws -> [Content] {
        let categories = Dictionary(uniqueKeysWithValues: try await getCategories().map { ($0.id, $0) })
        let snapshot = try await Firestore.firestore()
            .collection("content_catalog")
            .whereField("status", isEqualTo: "published")
            .order(by: "publishedAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap {
            Self.content(id: $0.documentID, data: $0.data(), categories: categories)
        }
    }
    #endif

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
        #if canImport(FirebaseFunctions)
        if FirebaseApp.app() != nil {
            let result = try await Functions.functions(region: functionsRegion)
                .httpsCallable("getContentPackage")
                .call(["contentId": id])
            let data = try JSONSerialization.data(withJSONObject: result.data)
            return try JSONDecoder().decode(StoryPackage.self, from: data)
        }
        #endif

        let url = URL(string: "https://\(functionsRegion)-\(projectId).cloudfunctions.net/getContentPackage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["contentId": id]])
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw ContentServiceError.packageFailed(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(CallablePackageResponse.self, from: data)
        return decoded.result
    }

    private static func category(from doc: FirestoreDocument) -> Category? {
        let id = doc.string("id") ?? doc.documentId
        let title = doc.string("title") ?? id
        return Category(id: id, title: title, symbol: symbol(for: doc.string("iconName")))
    }

    private static func category(id documentId: String, data: [String: Any]) -> Category? {
        let id = stringValue(data["id"]) ?? documentId
        let title = stringValue(data["title"]) ?? id
        return Category(id: id, title: title, symbol: symbol(for: stringValue(data["iconName"])))
    }

    private static func content(from doc: FirestoreDocument, categories: [String: Category]) -> Content? {
        let id = doc.string("id") ?? doc.documentId
        let title = doc.string("title") ?? ""
        guard !id.isEmpty, !title.isEmpty else { return nil }
        let categoryId = doc.string("categoryId") ?? ""
        let category = categories[categoryId] ?? Category(id: categoryId, title: categoryId.isEmpty ? "Stories" : categoryId, symbol: "book.fill")
        let type = ContentType(rawValue: (doc.string("contentType") ?? "story").lowercased()) ?? .story
        let accent = EnglishAccent(rawValue: doc.string("accent") ?? "en-US") ?? .us
        let newsScope = doc.string("newsScope").flatMap { NewsScope(rawValue: $0.lowercased()) }
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
            newsScope: newsScope,
            regionCode: doc.string("regionCode") ?? "",
            regionLabel: doc.string("regionLabel") ?? "",
            countryCodes: doc.array("countryCodes").compactMap(\.stringValue),
            sourceReferences: doc.array("sourceReferences").compactMap(Self.sourceReference),
            imageAttribution: doc.fields?["imageAttribution"].flatMap(Self.imageAttribution),
            practiceSentenceIndexes: []
        )
    }

    private static func content(id documentId: String, data: [String: Any], categories: [String: Category]) -> Content? {
        let id = stringValue(data["id"]) ?? documentId
        let title = stringValue(data["title"]) ?? ""
        guard !id.isEmpty, !title.isEmpty else { return nil }
        let categoryId = stringValue(data["categoryId"]) ?? ""
        let category = categories[categoryId] ?? Category(id: categoryId, title: categoryId.isEmpty ? "Stories" : categoryId, symbol: "book.fill")
        let type = ContentType(rawValue: (stringValue(data["contentType"]) ?? "story").lowercased()) ?? .story
        let accent = EnglishAccent(rawValue: stringValue(data["accent"]) ?? "en-US") ?? .us
        let newsScope = stringValue(data["newsScope"]).flatMap { NewsScope(rawValue: $0.lowercased()) }
        return Content(
            id: id,
            title: title,
            author: stringValue(data["author"]) ?? "",
            summary: stringValue(data["summary"]) ?? "",
            category: category,
            level: stringValue(data["level"]) ?? "",
            duration: stringValue(data["duration"]) ?? "",
            imageUrl: stringValue(data["imageUrl"]) ?? "",
            durationMs: intValue(data["durationMs"]),
            sentences: [],
            isPremium: boolValue(data["isPremium"]) ?? true,
            createdAt: dateValue(data["publishedAt"]) ?? dateValue(data["createdAt"]),
            wordCount: intValue(data["wordCount"]),
            targetWords: targetWords(data["targetWords"]),
            contentType: type,
            rating: doubleValue(data["averageRating"]).flatMap { $0 > 0 ? $0 : nil },
            ratingCount: intValue(data["ratingCount"]),
            accent: accent,
            newsScope: newsScope,
            regionCode: stringValue(data["regionCode"]) ?? "",
            regionLabel: stringValue(data["regionLabel"]) ?? "",
            countryCodes: stringArray(data["countryCodes"]),
            sourceReferences: sourceReferences(data["sourceReferences"]),
            imageAttribution: imageAttribution(data["imageAttribution"]),
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

    private static func imageAttribution(_ value: FirestoreValue) -> ImageAttribution? {
        guard case let .mapValue(map) = value, let fields = map.fields else { return nil }
        return ImageAttribution(
            source: fields["source"]?.stringValue ?? "",
            creator: fields["creator"]?.stringValue ?? "",
            sourcePageUrl: fields["sourcePageUrl"]?.stringValue ?? "",
            license: fields["license"]?.stringValue ?? "",
            attribution: fields["attribution"]?.stringValue ?? ""
        )
    }

    private static func targetWords(_ raw: Any?) -> [TargetWord] {
        (raw as? [[String: Any]])?.compactMap { item in
            guard let text = stringValue(item["text"]), !text.isEmpty else { return nil }
            return TargetWord(
                text: text,
                pronunciation: stringValue(item["pronunciation"]) ?? "",
                audioUrl: stringValue(item["audioUrl"]) ?? ""
            )
        } ?? []
    }

    private static func sourceReferences(_ raw: Any?) -> [SourceReference] {
        (raw as? [[String: Any]])?.compactMap { item in
            guard let publisher = stringValue(item["publisher"]),
                  let url = stringValue(item["url"]) else { return nil }
            return SourceReference(
                title: stringValue(item["title"]) ?? "",
                publisher: publisher,
                url: url,
                publishedAt: stringValue(item["publishedAt"]) ?? "",
                countryCode: stringValue(item["countryCode"]) ?? "",
                isLocal: boolValue(item["isLocal"]) ?? false
            )
        } ?? []
    }

    private static func imageAttribution(_ raw: Any?) -> ImageAttribution? {
        guard let item = raw as? [String: Any] else { return nil }
        return ImageAttribution(
            source: stringValue(item["source"]) ?? "",
            creator: stringValue(item["creator"]) ?? "",
            sourcePageUrl: stringValue(item["sourcePageUrl"]) ?? "",
            license: stringValue(item["license"]) ?? "",
            attribution: stringValue(item["attribution"]) ?? ""
        )
    }

    private static func stringArray(_ raw: Any?) -> [String] {
        (raw as? [String]) ?? (raw as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func stringValue(_ raw: Any?) -> String? {
        raw as? String
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let value = raw as? Int { return value }
        if let value = raw as? Int64 { return Int(value) }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? NSNumber { return value.intValue }
        return 0
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? Int64 { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        return nil
    }

    private static func dateValue(_ raw: Any?) -> Date? {
        #if canImport(FirebaseFirestore)
        if let timestamp = raw as? Timestamp {
            return timestamp.dateValue()
        }
        #endif
        return raw as? Date
    }

    private func debugLog(_ message: String, _ error: Error) {
        #if DEBUG
        print(message, error.localizedDescription)
        #endif
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
            newsScope: newsScope,
            regionCode: regionCode,
            regionLabel: regionLabel,
            countryCodes: countryCodes,
            sourceReferences: sourceReferences,
            imageAttribution: imageAttribution,
            practiceSentenceIndexes: practiceSentenceIndexes
        )
    }

    func withRating(averageRating: Double, ratingCount: Int) -> Content {
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
            rating: averageRating,
            ratingCount: ratingCount,
            accent: accent,
            newsScope: newsScope,
            regionCode: regionCode,
            regionLabel: regionLabel,
            countryCodes: countryCodes,
            sourceReferences: sourceReferences,
            imageAttribution: imageAttribution,
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let package = try container.decodeIfPresent(StoryPackage.self, forKey: .result) {
            result = package
            return
        }
        if let data = try container.decodeIfPresent(StoryPackage.self, forKey: .data) {
            result = data
            return
        }
        result = try StoryPackage(from: decoder)
    }

    enum CodingKeys: String, CodingKey {
        case result
        case data
    }
}

struct StoryPackage: Decodable {
    let sentences: [SentenceAudio]
    let targetWords: [TargetWord]
    let practiceSentenceIndexes: [Int]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sentences = try container.decodeIfPresent([SentenceAudio].self, forKey: .sentences) ?? []
        targetWords = try container.decodeIfPresent([TargetWord].self, forKey: .targetWords) ?? []
        practiceSentenceIndexes = try container.decodeIfPresent([Int].self, forKey: .practiceSentenceIndexes) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case sentences
        case targetWords
        case practiceSentenceIndexes
    }
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

extension TargetWord: Decodable {
    enum CodingKeys: String, CodingKey {
        case text
        case pronunciation
        case audioUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        audioUrl = try container.decodeIfPresent(String.self, forKey: .audioUrl) ?? ""
    }
}

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
            newsScope: nil,
            regionCode: "",
            regionLabel: "",
            countryCodes: [],
            sourceReferences: [],
            imageAttribution: nil,
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
            newsScope: nil,
            regionCode: "",
            regionLabel: "",
            countryCodes: [],
            sourceReferences: [],
            imageAttribution: nil,
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
            newsScope: .global,
            regionCode: "",
            regionLabel: "",
            countryCodes: [],
            sourceReferences: [],
            imageAttribution: nil,
            practiceSentenceIndexes: [1, 2]
        )
    ]
}
