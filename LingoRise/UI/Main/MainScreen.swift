import SwiftUI

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
        .onChange(of: appState.selectedTab) { _, tab in
            activeExploreSheet = nil
            isProfileLanguageSheetPresented = false
            if tab == .home {
                AppNotificationService.shared.requestAuthorizationFromHomeIfNeeded()
            }
        }
        .onAppear {
            homeModel.configure(service: appState.contentService)
            exploreModel.configure(service: appState.contentService)
            AppNotificationService.shared.requestAuthorizationFromHomeIfNeeded()
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
