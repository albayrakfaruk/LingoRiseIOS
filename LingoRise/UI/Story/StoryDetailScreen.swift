import AVFoundation
import SwiftUI

@MainActor
final class StoryDetailModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorKey: String?
    @Published var content: Content?

    private var loadedStoryId = ""

    func load(storyId: String, selectedContent: Content?, service: ContentService) async {
        if loadedStoryId == storyId, !isLoading, errorKey == nil {
            return
        }

        isLoading = true
        errorKey = nil
        loadedStoryId = storyId

        do {
            let story = try await service.getContent(id: storyId) ?? (selectedContent?.id == storyId ? selectedContent : nil)
            guard let story else {
                content = nil
                errorKey = "error_story_not_found"
                isLoading = false
                return
            }

            content = story
            isLoading = false
            AppAnalytics.logStoryView(
                storyId: story.id,
                storyTitle: story.title,
                level: story.level,
                categoryName: story.category.title
            )

            if let packaged = try? await service.getStoryPackage(id: storyId), !packaged.targetWords.isEmpty {
                content = story.withPackage(
                    sentences: packaged.sentences.isEmpty ? story.sentences : packaged.sentences,
                    targetWords: packaged.targetWords,
                    practiceSentenceIndexes: packaged.practiceSentenceIndexes.isEmpty ? story.practiceSentenceIndexes : packaged.practiceSentenceIndexes
                )
            }
        } catch {
            content = nil
            errorKey = "error_story_unavailable"
            isLoading = false
        }
    }
}

struct StoryDetailScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = StoryDetailModel()
    @StateObject private var audioPlayer = TargetWordAudioPlayer()

    let storyId: String
    let isDailyPick: Bool

    var body: some View {
        GeometryReader { geometry in
            let isDark = appState.effectiveDarkTheme(systemColorScheme: colorScheme)
            let palette = StoryDetailPalette(isDark: isDark)
            let heroHeight = geometry.size.height * 0.45

            ZStack(alignment: .topLeading) {
                palette.background.ignoresSafeArea()

                if model.isLoading {
                    ProgressView()
                        .tint(LingoRiseColors.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    StoryDetailBody(
                        content: model.content,
                        errorKey: model.errorKey,
                        heroHeight: heroHeight,
                        width: geometry.size.width,
                        palette: palette,
                        onOpenURL: openURL(_:),
                        onSpeakWord: { index, word in
                            audioPlayer.play(cacheKey: audioCacheKey(index: index, word: word), word: word)
                        }
                    )
                    .ignoresSafeArea(edges: .top)
                }

                StoryBackButton {
                    appState.route = .main
                }
                .position(x: 44, y: 54)

                if !model.isLoading {
                    StoryBottomBar(palette: palette) {
                        if let content = model.content {
                            AppAnalytics.logStartReading(storyId: content.id, storyTitle: content.title)
                            appState.route = .reading(storyId, isDailyPick)
                        } else {
                            appState.route = .main
                        }
                    } label: {
                        Label(
                            model.content == nil ? L10n.t("cd_back") : L10n.t("story_start_reading"),
                            systemImage: "book.fill"
                        )
                    }
                }
            }
            .task(id: storyId) {
                await model.load(
                    storyId: storyId,
                    selectedContent: appState.selectedContent,
                    service: appState.contentService
                )
            }
            .onChange(of: model.content?.targetWords ?? []) { _, words in
                for (index, word) in words.enumerated() where !word.audioUrl.isEmpty {
                    audioPlayer.preload(cacheKey: audioCacheKey(index: index, word: word), audioUrl: word.audioUrl)
                }
            }
        }
    }

    private func audioCacheKey(index: Int, word: TargetWord) -> String {
        "\(storyId)-word-\(index)-\(word.text)"
    }

    private func openURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        UIApplication.shared.open(url)
    }
}

private struct StoryDetailBody: View {
    let content: Content?
    let errorKey: String?
    let heroHeight: CGFloat
    let width: CGFloat
    let palette: StoryDetailPalette
    let onOpenURL: (String) -> Void
    let onSpeakWord: (Int, TargetWord) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            StoryHero(content: content, errorKey: errorKey, height: heroHeight, width: width)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: heroHeight)

                    VStack(alignment: .leading, spacing: 0) {
                        StoryStatsRow(content: content, palette: palette)
                            .padding(.vertical, 24)

                        Divider()
                            .overlay(palette.outlineVariant)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.t("story_synopsis"))
                                .font(LexendFont.font(18, weight: .semibold))
                                .foregroundStyle(palette.onBackground)

                            Text(content?.summary ?? L10n.t("error_content_unavailable"))
                                .font(LexendFont.font(15))
                                .foregroundStyle(palette.onSurfaceVariant)
                                .lineSpacing(4)
                        }
                        .padding(.top, 16)

                        if let attribution = content?.imageAttribution, !attribution.attribution.isEmpty {
                            StoryPhotoCredit(attribution: attribution, palette: palette, onOpenURL: onOpenURL)
                                .padding(.top, 10)
                        }

                        if let sources = content?.sourceReferences, !sources.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.t("story_sources"))
                                    .font(LexendFont.font(18, weight: .semibold))
                                    .foregroundStyle(palette.onBackground)

                                ForEach(sources) { source in
                                    Button {
                                        onOpenURL(source.url)
                                    } label: {
                                        Text(source.publisher)
                                            .font(LexendFont.font(13))
                                            .underline()
                                            .foregroundStyle(LingoRiseColors.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding(.top, 18)
                        }

                        if let words = content?.targetWords, !words.isEmpty {
                            Divider()
                                .overlay(palette.outlineVariant)
                                .padding(.top, 18)
                                .padding(.bottom, 14)

                            Text(L10n.t("story_key_vocabulary"))
                                .font(LexendFont.font(18, weight: .semibold))
                                .foregroundStyle(palette.onBackground)
                                .padding(.bottom, 12)

                            VStack(spacing: 8) {
                                ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                                    StoryVocabularyRow(word: word, palette: palette) {
                                        onSpeakWord(index, word)
                                    }
                                }
                            }
                        }

                        Divider()
                            .overlay(palette.outlineVariant)
                            .padding(.horizontal, 0)
                            .padding(.top, 16)
                            .padding(.bottom, 220)
                    }
                    .padding(.horizontal, 20)
                    .frame(width: width)
                    .background(palette.background)
                }
                .frame(width: width)
            }
        }
        .frame(width: width)
    }
}

private struct StoryHero: View {
    let content: Content?
    let errorKey: String?
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                LinearGradient(
                    colors: [Color(.secondarySystemBackground), LingoRiseColors.primary.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "book.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white.opacity(0.16))
                if let content {
                    AsyncStoryImage(url: content.imageUrl)
                }
            }
            .frame(width: width)
            .frame(height: height)

            LinearGradient(
                colors: [.clear, Color(hex: 0x111621, alpha: 0.80), Color(hex: 0x111621)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)

            VStack(alignment: .leading, spacing: 0) {
                StoryBadgeFlow(content: content)
                    .padding(.bottom, 8)

                Text(errorKey.map(L10n.t) ?? content?.title ?? "")
                    .font(LexendFont.font(34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.format("story_by_author", author(content)))
                    .font(LexendFont.font(13))
                    .foregroundStyle(Color(hex: 0x93C5FD))
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .frame(width: width, alignment: .leading)
        }
        .frame(width: width, height: height)
    }

    private func author(_ content: Content?) -> String {
        guard let value = content?.author, !value.isEmpty else { return "LingoRise" }
        return value
    }
}

private struct StoryBadgeFlow: View {
    let content: Content?

    var body: some View {
        WrappingFlowLayout(spacing: 8, rowSpacing: 6, fallbackWidth: UIScreen.main.bounds.width - 40, usesContentWidth: true) {
            if let level = content?.level, !level.isEmpty {
                StoryBadge(text: L10n.format("story_level_format", level), primary: true, showPulseDot: true)
            }
            if let category = content?.category.title, !category.isEmpty {
                StoryBadge(text: category)
            }
            if let type = content?.contentType {
                StoryBadge(text: contentTypeLabel(type))
            }
            if let accent = content?.accent {
                StoryBadge(text: accentVoiceLabel(accent))
            }
            if content?.contentType == .news {
                StoryBadge(text: newsScopeLabel(content))
            }
        }
    }

    private func contentTypeLabel(_ type: ContentType) -> String {
        switch type {
        case .story: return L10n.t("content_type_story")
        case .fact: return L10n.t("content_type_fact")
        case .article: return L10n.t("content_type_article")
        case .news: return L10n.t("content_type_news")
        }
    }

    private func accentVoiceLabel(_ accent: EnglishAccent) -> String {
        let flag = accent == .uk ? "🇬🇧" : "🇺🇸"
        let key = accent == .uk ? "story_accent_uk" : "story_accent_us"
        return L10n.format("story_voice_accent_format", flag, L10n.t(key))
    }

    private func newsScopeLabel(_ content: Content?) -> String {
        if content?.newsScope == .regional {
            return content?.regionLabel.isEmpty == false ? content?.regionLabel ?? "" : L10n.t("story_news_regional")
        }
        return L10n.t("story_news_global")
    }
}

private struct StoryBadge: View {
    let text: String
    var primary = false
    var showPulseDot = false

    var body: some View {
        HStack(spacing: 6) {
            if showPulseDot && primary {
                TimelineView(.animation) { timeline in
                    let alpha = 0.6 + 0.4 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * .pi / 0.8))
                    Circle()
                        .fill(Color.white.opacity(alpha))
                        .frame(width: 6, height: 6)
                }
                .frame(width: 6, height: 6)
            }

            Text(text)
                .font(LexendFont.font(11, weight: primary ? .semibold : .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(primary ? LingoRiseColors.primary : Color(hex: 0x1A2233, alpha: 0.80))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(primary ? 0.22 : 0.10), lineWidth: 1))
    }
}

private struct StoryStatsRow: View {
    let content: Content?
    let palette: StoryDetailPalette

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let rating = content?.rating {
                    StoryRatingStat(rating: rating, ratingCount: content?.ratingCount ?? 0, palette: palette)
                } else {
                    EmptyRatingStat(palette: palette)
                }
            }
            .frame(maxWidth: .infinity)

            StoryVerticalDivider(palette: palette)

            StoryDurationStat(duration: content?.duration ?? "", palette: palette)
                .frame(maxWidth: .infinity)

            StoryVerticalDivider(palette: palette)

            StoryStatBlock(
                value: (content?.wordCount ?? 0) > 0 ? "\(content?.wordCount ?? 0)" : "-",
                label: L10n.t("story_words"),
                palette: palette
            )
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StoryRatingStat: View {
    let rating: Double
    let ratingCount: Int
    let palette: StoryDetailPalette

    var body: some View {
        VStack(spacing: 0) {
            Text(String(format: "%.1f", min(max(rating, 0), 5)))
                .font(LexendFont.font(22, weight: .bold))
                .foregroundStyle(palette.onBackground)

            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: starName(index: index))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xEAB308))
                }
            }
            .padding(.top, 6)

            Text(L10n.format("story_rating_count_format", ratingCount))
                .font(LexendFont.font(11))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 4)
        }
    }

    private func starName(index: Int) -> String {
        let rounded = (min(max(rating, 0), 5) * 2).rounded() / 2
        let fullStars = Int(floor(rounded))
        let hasHalf = rounded - Double(fullStars) >= 0.5
        if index < fullStars { return "star.fill" }
        if index == fullStars && hasHalf { return "star.leadinghalf.filled" }
        return "star"
    }
}

private struct EmptyRatingStat: View {
    let palette: StoryDetailPalette

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "star")
                .font(.system(size: 24))
                .foregroundStyle(Color(hex: 0xEAB308))
            Text(L10n.t("story_not_rated_yet"))
                .font(LexendFont.font(11))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 8)
        }
    }
}

private struct StoryDurationStat: View {
    let duration: String
    let palette: StoryDetailPalette

    var body: some View {
        let parts = localizedDuration(duration).split(separator: " ", maxSplits: 1).map(String.init)
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parts.first ?? localizedDuration(duration))
                    .font(LexendFont.font(22, weight: .bold))
                    .foregroundStyle(palette.onBackground)
                if parts.count > 1 {
                    Text(parts[1])
                        .font(LexendFont.font(15, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }

            Text(L10n.t("story_duration"))
                .font(LexendFont.font(11))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 6)
        }
    }
}

private struct StoryStatBlock: View {
    let value: String
    let label: String
    let palette: StoryDetailPalette

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(LexendFont.font(22, weight: .bold))
                .foregroundStyle(palette.onBackground)
                .lineLimit(1)
            Text(label)
                .font(LexendFont.font(11))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 4)
        }
    }
}

private struct StoryVerticalDivider: View {
    let palette: StoryDetailPalette

    var body: some View {
        Rectangle()
            .fill(palette.outlineVariant)
            .frame(width: 1, height: 64)
    }
}

private struct StoryVocabularyRow: View {
    let word: TargetWord
    let palette: StoryDetailPalette
    let onSpeak: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.text.localizedCapitalized)
                    .font(LexendFont.font(15, weight: .semibold))
                    .foregroundStyle(palette.onSurface)

                if !word.pronunciation.isEmpty {
                    Text(word.pronunciation)
                        .font(LexendFont.font(13))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }

            Spacer()

            Button(action: onSpeak) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(L10n.format("cd_play_word", word.text))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.outlineVariant, lineWidth: 1)
        )
    }
}

private struct StoryPhotoCredit: View {
    let attribution: ImageAttribution
    let palette: StoryDetailPalette
    let onOpenURL: (String) -> Void

    var body: some View {
        Button {
            if !attribution.sourcePageUrl.isEmpty {
                onOpenURL(attribution.sourcePageUrl)
            }
        } label: {
            Text(L10n.format("story_photo_credit_format", attribution.attribution))
                .font(LexendFont.font(11))
                .underline(!attribution.sourcePageUrl.isEmpty)
                .foregroundStyle(attribution.sourcePageUrl.isEmpty ? palette.onSurfaceVariant : LingoRiseColors.primary)
        }
        .disabled(attribution.sourcePageUrl.isEmpty)
    }
}

private struct StoryBottomBar<LabelContent: View>: View {
    let palette: StoryDetailPalette
    let action: () -> Void
    @ViewBuilder let label: () -> LabelContent

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                Button(action: action) {
                    label()
                        .font(LexendFont.font(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(LingoRiseColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .background(palette.background)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct StoryBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.24))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .accessibilityLabel(L10n.t("cd_back"))
    }
}

private struct StoryDetailPalette {
    let isDark: Bool

    var background: Color { isDark ? LingoRiseColors.backgroundDark : LingoRiseColors.backgroundLight }
    var surface: Color { isDark ? LingoRiseColors.surfaceDark : LingoRiseColors.surfaceLight }
    var onBackground: Color { isDark ? LingoRiseColors.onBackgroundDark : LingoRiseColors.onBackgroundLight }
    var onSurface: Color { isDark ? LingoRiseColors.onSurfaceDark : LingoRiseColors.onSurfaceLight }
    var onSurfaceVariant: Color { isDark ? LingoRiseColors.onSurfaceVariantDark : LingoRiseColors.onSurfaceVariantLight }
    var outlineVariant: Color { isDark ? LingoRiseColors.outlineVariantDark : LingoRiseColors.outlineVariantLight }
}

@MainActor
private final class TargetWordAudioPlayer: ObservableObject {
    private var player: AVPlayer?
    private var cachedURLs: [String: URL] = [:]
    private var preloadTasks: [String: Task<Void, Never>] = [:]

    func preload(cacheKey: String, audioUrl: String) {
        guard cachedURLs[cacheKey] == nil, preloadTasks[cacheKey] == nil, let url = URL(string: audioUrl) else { return }
        preloadTasks[cacheKey] = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(cacheKey.replacingOccurrences(of: "/", with: "-"))
                    .appendingPathExtension("mp3")
                try data.write(to: fileURL, options: .atomic)
                await MainActor.run {
                    self.cachedURLs[cacheKey] = fileURL
                    self.preloadTasks[cacheKey] = nil
                }
            } catch {
                await MainActor.run {
                    self.preloadTasks[cacheKey] = nil
                }
            }
        }
    }

    func play(cacheKey: String, word: TargetWord) {
        if let cachedURL = cachedURLs[cacheKey] {
            player = AVPlayer(url: cachedURL)
            player?.play()
        } else if let url = URL(string: word.audioUrl) {
            player = AVPlayer(url: url)
            player?.play()
        } else {
            speak(word.text)
        }
    }

    private let synthesizer = AVSpeechSynthesizer()

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }

    deinit {
        player?.pause()
        preloadTasks.values.forEach { $0.cancel() }
    }
}

#Preview("Story Detail") {
    StoryDetailScreen(storyId: SampleData.contents[0].id, isDailyPick: false)
        .environmentObject(AppState())
}
