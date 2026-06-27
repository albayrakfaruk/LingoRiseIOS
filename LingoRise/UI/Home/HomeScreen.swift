import SwiftUI

@MainActor
final class HomeModel: ObservableObject {
    @Published var isLoading = false
    @Published var hasCompletedInitialLoad = false
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
        guard let service else { return }
        if isLoading { return }
        if loaded, !hasError, !categories.isEmpty, !storiesByCategory.isEmpty { return }
        isLoading = true
        hasError = false
        do {
            let loadedCategories = try await service.getCategories()
            if loadedCategories.isEmpty {
                categories = []
                dailyStory = nil
                storiesByCategory = [:]
                loaded = true
                hasCompletedInitialLoad = true
                isLoading = false
                return
            }
            categories = loadedCategories
            var grouped: [String: [Content]] = [:]
            async let daily = service.getDailyPick()
            try await withThrowingTaskGroup(of: (String, [Content]).self) { group in
                for category in loadedCategories {
                    group.addTask {
                        let stories = try await service.getStories(categoryId: category.id, limit: 5)
                        return (category.id, Array(stories.prefix(5)))
                    }
                }
                for try await (categoryId, stories) in group {
                    grouped[categoryId] = stories
                }
            }
            dailyStory = try await daily
            storiesByCategory = grouped
            loaded = true
            hasCompletedInitialLoad = true
            isLoading = false
        } catch {
            hasError = true
            hasCompletedInitialLoad = true
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
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: HomeModel
    let onShowCategory: (Category) -> Void

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width - 40, 0)
            let isDark = appState.effectiveDarkTheme(systemColorScheme: colorScheme)
            let palette = HomePalette(isDark: isDark)

            ZStack {
            palette.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(formattedDate())
                            .font(LexendFont.font(14, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(palette.onSurfaceVariant)
                        Text(L10n.t("home_hi_there"))
                            .font(LexendFont.font(32, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .foregroundStyle(palette.onBackground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    PremiumBadge(isPremium: appState.isPremium) {
                        appState.route = .paywall(source: .home)
                    }
                }
                .frame(height: 72)
                .padding(.horizontal, 20)
                .padding(.top, 10)

                if model.isLoading || !model.hasCompletedInitialLoad {
                    Spacer()
                    ProgressView()
                        .tint(LingoRiseColors.primary)
                    Spacer()
                } else if model.hasError {
                    HomeMessageState(title: L10n.t("home_load_error_title"), message: L10n.t("home_load_error_message"), actionTitle: L10n.t("common_retry")) {
                        Task { await model.retry() }
                    }
                } else if model.dailyStory == nil && model.storiesByCategory.values.allSatisfy({ $0.isEmpty }) {
                    HomeMessageState(title: L10n.t("home_empty_title"), message: L10n.t("home_empty_message"))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if let daily = model.dailyStory {
                                HomeHeroCard(story: daily, width: contentWidth, palette: palette) {
                                    appState.show(daily, dailyPick: true)
                                }
                                .padding(.bottom, 30)
                            }
                            ForEach(model.categories) { category in
                                let stories = model.storiesByCategory[category.id] ?? []
                                if !stories.isEmpty {
                                    HomeCategorySection(category: category, stories: stories, palette: palette) {
                                        AppAnalytics.logCategorySelect(categoryId: category.id, categoryName: category.title)
                                        onShowCategory(category)
                                    } onStory: { story in
                                        appState.show(story)
                                    }
                                }
                            }
                            Text(L10n.t("home_tagline"))
                                .font(LexendFont.font(12, weight: .light))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            Spacer(minLength: 48)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 110)
                    }
                }
            }
            }
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: AppLocalization.localeIdentifier(for: appState.appLanguage))
        return formatter.string(from: Date())
    }
}

struct PremiumBadge: View {
    let isPremium: Bool
    let action: () -> Void

    var body: some View {
        Button(action: isPremium ? {} : action) {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(L10n.t("premium_badge_short"))
                    .font(LexendFont.font(11, weight: .bold))
                if isPremium {
                    Image(systemName: "checkmark")
                        .font(LexendFont.font(10, weight: .bold))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .foregroundStyle(isPremium ? Color(hex: 0x5FD39A) : Color(hex: 0xF2C14E))
            .background(Color(hex: isPremium ? 0x15221D : 0x1D1A15))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(hex: 0xF2C14E).opacity(isPremium ? 0.45 : 0.82), lineWidth: 1)
            )
        }
    }
}

struct HomePalette {
    let isDark: Bool

    var background: Color { isDark ? LingoRiseColors.backgroundDark : LingoRiseColors.backgroundLight }
    var surface: Color { isDark ? LingoRiseColors.surfaceDark : LingoRiseColors.surfaceLight }
    var surfaceVariant: Color { isDark ? Color(hex: 0x202A3E) : LingoRiseColors.surfaceVariantLight }
    var onBackground: Color { isDark ? LingoRiseColors.onBackgroundDark : LingoRiseColors.onBackgroundLight }
    var onSurface: Color { isDark ? LingoRiseColors.onSurfaceDark : LingoRiseColors.onSurfaceLight }
    var onSurfaceVariant: Color { isDark ? LingoRiseColors.onSurfaceVariantDark : LingoRiseColors.onSurfaceVariantLight }
    var outlineVariant: Color { isDark ? LingoRiseColors.outlineVariantDark : LingoRiseColors.outlineVariantLight }
}

struct HomeHeroCard: View {
    let story: Content
    let width: CGFloat
    let palette: HomePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: 0x22304A), LingoRiseColors.primary.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "book.fill")
                        .font(.system(size: 72, weight: .regular))
                        .foregroundStyle(.white.opacity(0.16))
                    AsyncStoryImage(url: story.imageUrl)
                }
                .frame(width: width, height: 348)
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color(hex: 0x111621, alpha: 0.20), location: 0.42),
                            .init(color: Color(hex: 0x111621), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        HeroPill(text: L10n.t("home_today_pick"), background: Color(hex: 0x1955CC))
                        HeroPill(text: L10n.t("home_free_today"), background: Color(hex: 0x16A34A))
                        DurationPill(duration: story.duration, compact: true)
                    }
                    .padding(.bottom, 12)
                    Text(story.title)
                        .font(LexendFont.font(38, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 5)
                    Text(String(story.summary.prefix(120)))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color(hex: 0xCBD5E1))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 14)
                    HStack(spacing: 12) {
                        Text(L10n.t("home_start_reading"))
                            .font(LexendFont.font(16, weight: .semibold))
                        Image(systemName: "arrow.forward")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(height: 48)
                    .padding(.horizontal, 17)
                    .foregroundStyle(.white)
                    .background(LingoRiseColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(18)
                .frame(width: width, alignment: .leading)
            }
            .frame(width: width, height: 348)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct HeroPill: View {
    let text: String
    let background: Color

    var body: some View {
        Text(text)
            .font(LexendFont.font(12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
    }
}

struct DurationPill: View {
    let duration: String
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: "timer")
                .font(.system(size: compact ? 14 : 14, weight: .semibold))
            Text(localizedDuration(duration))
                .font(LexendFont.font(compact ? 12 : 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 10 : 8)
        .padding(.vertical, compact ? 4 : 5)
        .background(.white.opacity(0.13))
        .clipShape(Capsule())
    }
}

struct HomeCategorySection: View {
    let category: Category
    let stories: [Content]
    let palette: HomePalette
    let onShowAll: () -> Void
    let onStory: (Content) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(category.title)
                    .font(LexendFont.font(18, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(palette.onBackground)
                Spacer()
                Button(L10n.t("show_all"), action: onShowAll)
                    .font(LexendFont.font(14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x1955CC))
                    .buttonStyle(.plain)
            }
            .padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(stories) { story in
                        HomeStoryCard(story: story, palette: palette) {
                            onStory(story)
                        }
                    }
                }
                .padding(.trailing, 24)
            }
        }
        .padding(.bottom, 32)
    }
}

struct HomeStoryCard: View {
    let story: Content
    let palette: HomePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ZStack {
                        LinearGradient(
                            colors: [Color(hex: 0x26344F), LingoRiseColors.primary.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "book.fill")
                            .font(.system(size: 40, weight: .regular))
                            .foregroundStyle(.white.opacity(0.14))
                        AsyncStoryImage(url: story.imageUrl)
                    }
                    .frame(width: 156, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(difficultyLabel(story.level))
                        .font(LexendFont.font(9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(difficultyColor(story.level).opacity(0.90))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(8)
                }
                .padding(.bottom, 12)
                Text(story.title)
                    .font(LexendFont.font(15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)
                    .lineLimit(2)
                    .frame(width: 156, height: 44, alignment: .topLeading)
                    .padding(.bottom, 4)
                Text(String(story.summary.prefix(80)))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .lineLimit(2)
                    .frame(width: 156, alignment: .topLeading)
                    .padding(.bottom, 12)
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 14, weight: .regular))
                    Text(localizedDuration(story.duration))
                        .font(LexendFont.font(11, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(palette.onSurfaceVariant)
            }
            .padding(12)
            .frame(width: 180, alignment: .leading)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.outlineVariant, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct HomeMessageState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(LexendFont.font(22, weight: .bold))
                .foregroundStyle(Color(.label))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(LexendFont.font(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(LingoRiseColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 12)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
