import SwiftUI

@MainActor
final class ExploreModel: ObservableObject {
    private let pageSize = 20
    private enum Keys {
        static let searchQuery = "explore_search_query"
        static let selectedLevels = "explore_selected_levels"
        static let selectedCategories = "explore_selected_categories"
        static let sortOption = "explore_sort_option"
    }

    @Published var categories: [Category] = []
    @Published var exploreStories: [Content] = []
    @Published var exploreLastCreatedAt: Date?
    @Published var exploreLastDocId: String?
    @Published var exploreHasMore = true
    @Published var isLoadingExplorePage = false
    @Published var isLoadingCategories = false
    @Published var hasLoadError = false
    @Published var query = ""
    @Published var selectedLevels: Set<String> = []
    @Published var selectedCategories: Set<String> = []
    @Published var sort: ExploreSortOption = .newest

    private var service: ContentService?
    private var hasLoadedInitialState = false
    private var searchTask: Task<Void, Never>?

    var visibleStories: [Content] {
        exploreStories
    }

    var isDefaultDiscovery: Bool {
        query.count < 3 && selectedLevels.isEmpty && selectedCategories.isEmpty
    }

    var hasActiveFilters: Bool {
        !selectedLevels.isEmpty || !selectedCategories.isEmpty
    }

    func configure(service: ContentService) {
        self.service = service
        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true
        restoreDiscoveryState()
    }

    func load() async {
        guard let service, categories.isEmpty && exploreStories.isEmpty else { return }
        hasLoadError = false
        isLoadingCategories = true
        do {
            categories = try await service.getCategories()
            isLoadingCategories = false
            await loadFirstPage()
        } catch {
            hasLoadError = true
            isLoadingCategories = false
        }
    }

    func loadFirstPage() async {
        guard let service else { return }
        searchTask?.cancel()
        hasLoadError = false
        isLoadingExplorePage = true
        exploreStories = []
        exploreLastCreatedAt = nil
        exploreLastDocId = nil
        exploreHasMore = true
        do {
            let page = try await service.getExploreStoriesPage(
                limit: pageSize,
                startAfterDocId: nil,
                searchQuery: query.count >= 3 ? query : nil,
                selectedLevels: selectedLevels,
                selectedCategories: selectedCategories,
                sortOption: sort
            )
            apply(page: page, append: false)
        } catch {
            hasLoadError = true
            isLoadingExplorePage = false
        }
    }

    func loadNextPage() async {
        guard let service, exploreHasMore, !isLoadingExplorePage else { return }
        isLoadingExplorePage = true
        hasLoadError = false
        do {
            let page = try await service.getExploreStoriesPage(
                limit: pageSize,
                startAfterDocId: exploreLastDocId,
                searchQuery: query.count >= 3 ? query : nil,
                selectedLevels: selectedLevels,
                selectedCategories: selectedCategories,
                sortOption: sort
            )
            apply(page: page, append: true)
        } catch {
            hasLoadError = true
            isLoadingExplorePage = false
        }
    }

    func updateSearchQuery(_ value: String) {
        query = value
        saveDiscoveryState()
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            if !value.isEmpty {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.loadFirstPage()
        }
    }

    func updateFilters(levels: Set<String>, categories: Set<String>) {
        selectedLevels = levels
        selectedCategories = categories
        saveDiscoveryState()
        Task { await loadFirstPage() }
    }

    func updateSortOption(_ option: ExploreSortOption) {
        sort = option
        saveDiscoveryState()
        Task { await loadFirstPage() }
    }

    func clearDiscovery() {
        searchTask?.cancel()
        query = ""
        selectedLevels = []
        selectedCategories = []
        sort = .newest
        saveDiscoveryState()
        Task { await loadFirstPage() }
    }

    func selectCategory(_ categoryId: String) {
        searchTask?.cancel()
        query = ""
        selectedLevels = []
        selectedCategories = [categoryId]
        sort = .newest
        saveDiscoveryState()
        Task { await loadFirstPage() }
    }

    private func apply(page: ExplorePageResult, append: Bool) {
        if append {
            exploreStories.append(contentsOf: page.items)
        } else {
            exploreStories = page.items
        }
        exploreLastCreatedAt = page.lastCreatedAt
        exploreLastDocId = page.lastDocId
        exploreHasMore = page.hasMore
        isLoadingExplorePage = false
    }

    private func restoreDiscoveryState() {
        let defaults = UserDefaults.standard
        query = defaults.string(forKey: Keys.searchQuery) ?? ""
        selectedLevels = Set(defaults.stringArray(forKey: Keys.selectedLevels) ?? [])
        selectedCategories = Set(defaults.stringArray(forKey: Keys.selectedCategories) ?? [])
        if let saved = defaults.string(forKey: Keys.sortOption),
           let option = ExploreSortOption(rawValue: saved) {
            sort = option
        }
    }

    private func saveDiscoveryState() {
        let defaults = UserDefaults.standard
        defaults.set(query, forKey: Keys.searchQuery)
        defaults.set(Array(selectedLevels).sorted(), forKey: Keys.selectedLevels)
        defaults.set(Array(selectedCategories).sorted(), forKey: Keys.selectedCategories)
        defaults.set(sort.rawValue, forKey: Keys.sortOption)
    }
}

struct ExploreScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: ExploreModel
    @Binding var activeSheet: ExploreSheetKind?
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        let palette = HomePalette(isDark: appState.isDarkTheme || colorScheme == .dark)
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("nav_explore"))
                    .font(LexendFont.font(26, weight: .bold))
                    .foregroundStyle(palette.onBackground)
                Spacer()
                HStack(spacing: 12) {
                    CircleIcon(
                        systemName: "slider.horizontal.3",
                        active: model.hasActiveFilters,
                        palette: palette
                    ) {
                        activeSheet = .filters
                    }
                    CircleIcon(systemName: "line.3.horizontal.decrease", palette: palette) {
                        activeSheet = .sort
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.onSurfaceVariant)
                TextField(
                    L10n.t("explore_search_placeholder"),
                    text: Binding(
                        get: { model.query },
                        set: { model.updateSearchQuery($0) }
                    )
                )
                    .textInputAutocapitalization(.never)
                    .font(LexendFont.font(15))
                    .foregroundStyle(palette.onSurface)
                if !model.query.isEmpty {
                    Button {
                        model.updateSearchQuery("")
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .frame(width: 40, height: 40)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 18)

            ZStack {
                if model.exploreStories.isEmpty {
                    if (model.isLoadingCategories || model.isLoadingExplorePage) && model.exploreStories.isEmpty {
                        ProgressView()
                            .tint(LingoRiseColors.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.hasLoadError {
                        ExploreMessageState(
                            title: L10n.t("explore_load_error_title"),
                            message: L10n.t("explore_load_error_message"),
                            buttonTitle: L10n.t("common_retry"),
                            buttonStyle: .primary,
                            palette: palette
                        ) {
                            Task { await model.loadFirstPage() }
                        }
                    } else if model.isDefaultDiscovery {
                        ExploreMessageState(
                            title: L10n.t("explore_no_stories_found"),
                            message: L10n.t("explore_catalog_empty_message"),
                            palette: palette
                        )
                    } else {
                        ExploreMessageState(
                            title: L10n.t("explore_no_stories_found"),
                            message: L10n.t("explore_no_stories_hint"),
                            buttonTitle: L10n.t("explore_clear_all_filters"),
                            buttonStyle: .surface,
                            palette: palette
                        ) {
                            model.clearDiscovery()
                        }
                    }
                } else {
                    GeometryReader { proxy in
                        let horizontalPadding: CGFloat = 20
                        let gridSpacing: CGFloat = 12
                        let cardWidth = max((proxy.size.width - horizontalPadding * 2 - gridSpacing) / 2, 156)
                        let fixedColumns = [
                            GridItem(.fixed(cardWidth), spacing: gridSpacing),
                            GridItem(.fixed(cardWidth), spacing: gridSpacing)
                        ]

                        ScrollView {
                            LazyVGrid(columns: fixedColumns, spacing: 12) {
                                ForEach(Array(model.exploreStories.enumerated()), id: \.element.id) { index, story in
                                    ExploreStoryCard(story: story, width: cardWidth, palette: palette) {
                                        if story.isPremium && !appState.isPremium {
                                            appState.route = .paywall(source: .explore)
                                        } else {
                                            appState.show(story)
                                        }
                                    }
                                    .onAppear {
                                        if index >= model.exploreStories.count - 2 {
                                            Task { await model.loadNextPage() }
                                        }
                                    }
                                }
                                if model.exploreHasMore || model.isLoadingExplorePage {
                                    ProgressView()
                                        .tint(LingoRiseColors.primary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 56)
                                        .gridCellColumns(2)
                                }
                            }
                            .frame(width: proxy.size.width)
                            .padding(.top, 8)
                            .padding(.bottom, 100)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.background.ignoresSafeArea())
    }
}

enum ExploreSheetKind: Equatable {
    case filters
    case sort
}

struct ExploreBottomSheet<Content: View>: View {
    let palette: HomePalette
    let maxHeight: CGFloat?
    @ViewBuilder let content: Content
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let sheetMaxHeight = maxHeight.map { min($0, geometry.size.height * 0.72) }
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.30)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 0) {
                    content
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 12))
                }
                .frame(width: geometry.size.width)
                .frame(maxHeight: sheetMaxHeight, alignment: .top)
                .background(palette.surface)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(palette.isDark ? 0.38 : 0.16), radius: 20, x: 0, y: -8)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

struct CircleIcon: View {
    let systemName: String
    var active = false
    let palette: HomePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .frame(width: 40, height: 40)
                    .background(palette.surfaceVariant)
                    .clipShape(Circle())
                if active {
                    Circle()
                        .fill(LingoRiseColors.primary)
                        .frame(width: 8, height: 8)
                        .padding(6)
                }
            }
        }
    }
}

struct ExploreStoryCard: View {
    let story: Content
    let width: CGFloat
    let palette: HomePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    AsyncStoryImage(url: story.imageUrl)
                        .frame(width: width, height: width / 1.22)
                    Text(difficultyLabel(story.level))
                        .font(LexendFont.font(9, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(difficultyColor(story.level).opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(7)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(story.title)
                        .font(LexendFont.font(12, weight: .semibold))
                        .foregroundStyle(palette.onSurface)
                        .lineLimit(2)
                        .frame(height: 34, alignment: .topLeading)
                    Text(story.category.title)
                        .font(LexendFont.font(10, weight: .regular))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                    Text(voiceLabel(story.accent))
                        .font(LexendFont.font(10, weight: .regular))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .regular))
                        Text(localizedDuration(story.duration))
                            .font(LexendFont.font(10, weight: .regular))
                    }
                    .foregroundStyle(palette.onSurfaceVariant)
                }
                .padding(10)
            }
            .frame(width: width)
            .background(palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.outlineVariant, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SortSheet: View {
    let selection: ExploreSortOption
    let palette: HomePalette
    let onSelect: (ExploreSortOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("explore_sort_by"))
                .font(LexendFont.font(22, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .padding(.vertical, 12)
            ForEach(ExploreSortOption.allCases, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack {
                        Text(L10n.t(option.titleKey))
                        Spacer()
                        if selection == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(LingoRiseColors.primary)
                        }
                    }
                    .font(LexendFont.font(17, weight: selection == option ? .semibold : .regular))
                    .foregroundStyle(selection == option ? LingoRiseColors.primary : palette.onSurface)
                    .padding(.vertical, 16)
                }
                if option != ExploreSortOption.allCases.last! {
                    Rectangle()
                        .fill(palette.outlineVariant)
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 32)
    }
}

struct FilterSheet: View {
    let categories: [Category]
    let selectedLevels: Set<String>
    let selectedCategories: Set<String>
    let palette: HomePalette
    let onApply: (Set<String>, Set<String>) -> Void
    @State private var draftSelectedLevels: Set<String>
    @State private var draftSelectedCategories: Set<String>
    private let levels = ["A1", "A2", "B1", "B2", "C1"]

    init(
        categories: [Category],
        selectedLevels: Set<String>,
        selectedCategories: Set<String>,
        palette: HomePalette,
        onApply: @escaping (Set<String>, Set<String>) -> Void
    ) {
        self.categories = categories
        self.selectedLevels = selectedLevels
        self.selectedCategories = selectedCategories
        self.palette = palette
        self.onApply = onApply
        _draftSelectedLevels = State(initialValue: selectedLevels)
        _draftSelectedCategories = State(initialValue: selectedCategories)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.t("explore_filters"))
                    .font(LexendFont.font(22, weight: .bold))
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Button(L10n.t("explore_reset")) {
                    draftSelectedLevels = []
                    draftSelectedCategories = []
                }
                .font(LexendFont.font(15, weight: .semibold))
                .foregroundStyle(LingoRiseColors.primary)
            }

            Spacer().frame(height: 32)

            Text(L10n.t("explore_level"))
                .font(LexendFont.font(13, weight: .bold))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.bottom, 16)
            FlowTags(items: levels, selected: $draftSelectedLevels, palette: palette)

            Spacer().frame(height: 32)

            Text(L10n.t("explore_category"))
                .font(LexendFont.font(13, weight: .bold))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.bottom, 16)
            FlowTags(
                items: categories.map(\.id),
                titles: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.title) }),
                selected: $draftSelectedCategories,
                palette: palette
            )

            Spacer().frame(height: 24)

            Button {
                onApply(draftSelectedLevels, draftSelectedCategories)
            } label: {
                Text(L10n.t("explore_apply"))
                    .font(LexendFont.font(17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .foregroundStyle(.white)
            .background(LingoRiseColors.primary)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: LingoRiseColors.primary.opacity(0.22), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 40)
    }
}

enum ExploreMessageButtonStyle {
    case primary
    case surface
}

struct ExploreMessageState: View {
    let title: String
    let message: String
    var buttonTitle: String?
    var buttonStyle: ExploreMessageButtonStyle = .primary
    let palette: HomePalette
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(LexendFont.font(22, weight: .bold))
                .foregroundStyle(palette.onBackground)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Text(message)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(palette.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            if let buttonTitle, let action {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(height: 44)
                        .padding(.horizontal, 18)
                }
                .foregroundStyle(buttonStyle == .primary ? .white : LingoRiseColors.primary)
                .background(buttonStyle == .primary ? LingoRiseColors.primary : palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 32)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FlowTags: View {
    let items: [String]
    var titles: [String: String] = [:]
    @Binding var selected: Set<String>
    let palette: HomePalette

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
                        .foregroundStyle(selected.contains(item) ? .white : palette.onSurfaceVariant)
                        .background(selected.contains(item) ? LingoRiseColors.primary : palette.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selected.contains(item) ? Color.clear : palette.outlineVariant, lineWidth: 1)
                        )
                }
            }
        }
    }
}

