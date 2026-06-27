import AVFoundation
import CryptoKit
import StoreKit
import SwiftUI

enum PracticeAnswerStatus {
    case idle
    case correct
    case incorrect
}

struct PracticePuzzleToken: Identifiable, Hashable {
    let id: Int
    let text: String
}

struct PracticePuzzleSegment: Identifiable, Hashable {
    let id: Int
    let correctTokens: [PracticePuzzleToken]
    let shuffledTokens: [PracticePuzzleToken]

    var text: String {
        correctTokens.map(\.text).joined(separator: " ")
    }
}

struct ListeningPuzzle: Identifiable, Hashable {
    var id: Int { sentenceIndex }
    let sentenceIndex: Int
    let audioUrl: String
    let segments: [PracticePuzzleSegment]
    let correctTokens: [PracticePuzzleToken]
    let shuffledTokens: [PracticePuzzleToken]
}

private struct PracticeSessionState {
    let selectedSegmentIds: [Int]
    let completedSegmentIds: [Int]
    let answerStatus: PracticeAnswerStatus
    let feedbackTitle: String
    let feedbackMessage: String
}

@MainActor
final class PracticeRecordingModel: ObservableObject {
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var unitTitle = ""
    @Published var currentIndex = 1
    @Published var totalCount = 0
    @Published var currentItem: ListeningPuzzle?
    @Published var completedSegmentIds: [Int] = []
    @Published var selectedSegmentIds: [Int] = []
    @Published var answerStatus: PracticeAnswerStatus = .idle
    @Published var feedbackTitle = ""
    @Published var feedbackMessage = ""
    @Published var isListening = false
    @Published var hasNoItems = false
    @Published var showCompletionDialog = false
    @Published var selectedRating = 0

    private let storyId: String
    private let contentService: ContentService
    private let ratingService: StoryRatingService
    private var practiceItems: [ListeningPuzzle] = []
    private var storyLevel: String?
    private var sessions: [Int: PracticeSessionState] = [:]
    private var loaded = false
    private var didLogComplete = false
    private var lastNextAt = Date.distantPast
    private var lastPreviousAt = Date.distantPast
    private var ratingTask: Task<Void, Never>?

    init(
        storyId: String,
        contentService: ContentService,
        ratingService: StoryRatingService = StoryRatingService()
    ) {
        self.storyId = storyId
        self.contentService = contentService
        self.ratingService = ratingService
    }

    var canShowContent: Bool {
        !isLoading && errorMessage == nil && !hasNoItems
    }

    var audioUrl: String {
        currentItem?.audioUrl ?? ""
    }

    var canContinue: Bool {
        answerStatus == .correct
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        sessions.removeAll()
        isLoading = true
        errorMessage = nil
        hasNoItems = false
        do {
            let story = try await contentService.getStoryPackage(id: storyId)
            let items = selectListeningPuzzleSentences(
                sentences: story.sentences,
                preferredIndexes: story.practiceSentenceIndexes,
                level: story.level
            ).map { sentenceToListeningPuzzle($0, storyId: story.id, level: story.level) }

            storyLevel = story.level
            practiceItems = items
            unitTitle = story.title
            selectedRating = ratingService.getLocalRating(storyId: storyId)

            guard !items.isEmpty else {
                showNoItems(story.title)
                return
            }

            isLoading = false
            totalCount = items.count
            currentIndex = 1
            AppAnalytics.logPracticeStart(
                storyId: story.id,
                storyTitle: story.title,
                totalSentences: items.count
            )
            applyItem(at: 0)
        } catch {
            isLoading = false
            errorMessage = L10n.t("error_something_went_wrong")
        }
    }

    func retry() async {
        loaded = false
        await load()
    }

    func selectPuzzleToken(_ segmentId: Int) {
        guard answerStatus != .correct,
              let puzzle = currentItem,
              puzzle.segments.contains(where: { $0.id == segmentId }),
              !completedSegmentIds.contains(segmentId),
              !selectedSegmentIds.contains(segmentId)
        else { return }
        selectedSegmentIds.append(segmentId)
        clearFeedback()
    }

    func removePuzzleToken(_ segmentId: Int) {
        guard answerStatus != .correct, selectedSegmentIds.contains(segmentId) else { return }
        selectedSegmentIds.removeAll { $0 == segmentId }
        clearFeedback()
    }

    func checkAnswer() {
        guard canShowContent, !isListening, let item = currentItem else { return }
        let correctIds = item.segments.map(\.id)
        guard selectedSegmentIds.count == correctIds.count else {
            answerStatus = .incorrect
            feedbackTitle = L10n.t("practice_try_again_title")
            feedbackMessage = L10n.t("practice_select_all_words")
            return
        }

        let correct = selectedSegmentIds == correctIds
        answerStatus = correct ? .correct : .incorrect
        completedSegmentIds = correct ? correctIds : completedSegmentIds
        feedbackTitle = L10n.t(correct ? "practice_correct_title" : "practice_try_again_title")
        feedbackMessage = L10n.t(correct ? "practice_listening_correct" : "practice_listening_incorrect")

        AppAnalytics.logListeningPuzzleEvaluated(
            storyId: storyId,
            storyTitle: unitTitle,
            level: storyLevel,
            sentenceIndex: item.sentenceIndex,
            questionIndex: currentIndex,
            totalQuestions: totalCount,
            segmentCount: item.segments.count,
            tokenCount: item.correctTokens.count,
            success: correct
        )
    }

    func canCheckCurrentAnswer() -> Bool {
        guard let item = currentItem else { return false }
        return !isListening && !item.segments.isEmpty && selectedSegmentIds.count == item.segments.count
    }

    func listenStarted() {
        guard canShowContent, !isListening, !audioUrl.isEmpty else { return }
        isListening = true
    }

    func listenFinished() {
        guard isListening else { return }
        isListening = false
    }

    func listenFailed(_ message: String) {
        isListening = false
        answerStatus = .incorrect
        feedbackTitle = L10n.t("error_audio_unavailable")
        feedbackMessage = message
    }

    func cancelActiveInteraction() {
        isListening = false
    }

    func previous() {
        guard !isListening, currentIndex > 1, totalCount > 0, debounce(&lastPreviousAt) else { return }
        saveCurrentSession()
        currentIndex -= 1
        showCompletionDialog = false
        applyItem(at: currentIndex - 1)
    }

    func next() {
        guard !isListening, debounce(&lastNextAt) else { return }
        if currentIndex >= totalCount, totalCount > 0 {
            saveCurrentSession()
            if !didLogComplete {
                didLogComplete = true
                AppAnalytics.logPracticeComplete(storyId: storyId, storyTitle: unitTitle, totalSentences: totalCount)
            }
            showCompletionDialog = true
            return
        }
        guard totalCount > 0 else { return }
        saveCurrentSession()
        currentIndex += 1
        applyItem(at: currentIndex - 1)
    }

    func dismissCompletion() {
        showCompletionDialog = false
    }

    func rateStory(_ rating: Int, requestReview: @escaping () -> Void) {
        guard ratingTask == nil else { return }
        let normalized = min(max(rating, 1), 5)
        selectedRating = normalized
        ratingTask = Task { [weak self] in
            guard let self else { return }
            defer { self.ratingTask = nil }
            do {
                _ = try await ratingService.rateStory(storyId: storyId, rating: normalized)
                AppAnalytics.logStoryRating(storyId: storyId, rating: normalized)
                if normalized >= 4 {
                    requestReview()
                }
            } catch {
                AppAnalytics.logStoryRating(storyId: storyId, rating: normalized)
            }
        }
    }

    private func showNoItems(_ title: String) {
        isLoading = false
        hasNoItems = true
        unitTitle = title
        totalCount = 0
        currentIndex = 0
        currentItem = nil
    }

    private func applyItem(at index: Int) {
        guard practiceItems.indices.contains(index) else { return }
        let session = sessions[index]
        currentItem = practiceItems[index]
        selectedSegmentIds = session?.selectedSegmentIds ?? []
        completedSegmentIds = session?.completedSegmentIds ?? []
        answerStatus = session?.answerStatus ?? .idle
        feedbackTitle = session?.feedbackTitle ?? ""
        feedbackMessage = session?.feedbackMessage ?? ""
        isListening = false
    }

    private func saveCurrentSession() {
        let index = currentIndex - 1
        guard practiceItems.indices.contains(index) else { return }
        sessions[index] = PracticeSessionState(
            selectedSegmentIds: selectedSegmentIds,
            completedSegmentIds: completedSegmentIds,
            answerStatus: answerStatus,
            feedbackTitle: feedbackTitle,
            feedbackMessage: feedbackMessage
        )
    }

    private func clearFeedback() {
        answerStatus = .idle
        feedbackTitle = ""
        feedbackMessage = ""
    }

    private func debounce(_ date: inout Date) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(date) >= 0.5 else { return false }
        date = now
        return true
    }
}

struct PracticeScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @StateObject private var model: PracticeRecordingModel
    @StateObject private var audio = PracticeAudioController()
    @State private var selectedListenSpeed: Float = 1

    let storyId: String
    let isDailyPick: Bool

    init(storyId: String, isDailyPick: Bool) {
        self.storyId = storyId
        self.isDailyPick = isDailyPick
        _model = StateObject(wrappedValue: PracticeRecordingModel(storyId: storyId, contentService: ContentService()))
    }

    var body: some View {
        let palette = PracticePalette(isDark: appState.effectiveDarkTheme(systemColorScheme: colorScheme))
        ZStack {
            palette.background.ignoresSafeArea()
            PracticeRecordingContent(
                state: model,
                palette: palette,
                selectedListenSpeed: selectedListenSpeed,
                onClose: closePractice,
                onListen: listen,
                onSpeedSelected: { selectedListenSpeed = $0 },
                onRetry: { Task { await model.retry() } },
                onSelectPuzzleToken: model.selectPuzzleToken,
                onRemovePuzzleToken: model.removePuzzleToken,
                onCheck: checkAnswer,
                onPrevious: {
                    audio.cancel()
                    model.previous()
                },
                onNext: {
                    audio.cancel()
                    model.next()
                }
            )

            if model.showCompletionDialog {
                PracticeCompletionScreen(
                    selectedRating: model.selectedRating,
                    palette: palette,
                    onRate: { rating in
                        model.rateStory(rating) {
                            requestReview()
                        }
                    },
                    onFinish: {
                        audio.cancel()
                        model.dismissCompletion()
                        appState.route = .main
                    }
                )
                .transition(.opacity)
            }
        }
        .task {
            await model.load()
        }
        .onChange(of: model.audioUrl) { _, audioUrl in
            audio.prepare(audioUrl: audioUrl)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                audio.cancel()
                model.cancelActiveInteraction()
            }
        }
        .onDisappear {
            audio.cancel()
            model.cancelActiveInteraction()
        }
        .animation(.easeInOut(duration: 0.18), value: model.showCompletionDialog)
    }

    private func listen() {
        guard appState.isPremium else {
            appState.route = .paywall(source: .practice)
            return
        }
        guard !model.audioUrl.isEmpty, !model.isListening else { return }
        model.listenStarted()
        audio.play(speed: selectedListenSpeed) {
            model.listenFinished()
        } onFailure: { message in
            model.listenFailed(message)
        }
    }

    private func checkAnswer() {
        guard appState.isPremium else {
            appState.route = .paywall(source: .practice)
            return
        }
        model.checkAnswer()
    }

    private func closePractice() {
        audio.cancel()
        model.cancelActiveInteraction()
        appState.route = .storyDetail(storyId, isDailyPick)
    }
}

private struct PracticeRecordingContent: View {
    @ObservedObject var state: PracticeRecordingModel
    let palette: PracticePalette
    let selectedListenSpeed: Float
    let onClose: () -> Void
    let onListen: () -> Void
    let onSpeedSelected: (Float) -> Void
    let onRetry: () -> Void
    let onSelectPuzzleToken: (Int) -> Void
    let onRemovePuzzleToken: (Int) -> Void
    let onCheck: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PracticeHeader(
                unitTitle: state.unitTitle.isEmpty ? L10n.t("practice_listening_title") : state.unitTitle,
                currentIndex: min(max(state.currentIndex, 0), max(state.totalCount, 1)),
                totalCount: state.totalCount,
                palette: palette,
                onClose: onClose
            )

            if state.isLoading {
                PracticeCenteredState {
                    ProgressView()
                        .tint(LingoRiseColors.primary)
                }
            } else if let errorMessage = state.errorMessage {
                PracticeCenteredState {
                    Text(errorMessage)
                        .font(LexendFont.font(17))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                    Button(L10n.t("common_retry"), action: onRetry)
                        .font(LexendFont.font(15, weight: .semibold))
                        .foregroundStyle(LingoRiseColors.primary)
                        .padding(.top, 6)
                }
            } else if state.hasNoItems {
                PracticeCenteredState {
                    Text(L10n.t("practice_not_ready_title"))
                        .font(LexendFont.font(22, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                        .multilineTextAlignment(.center)
                    Text(L10n.t("practice_not_ready_message"))
                        .font(LexendFont.font(14))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            } else {
                PracticeBody(
                    state: state,
                    palette: palette,
                    selectedListenSpeed: selectedListenSpeed,
                    onListen: onListen,
                    onSpeedSelected: onSpeedSelected,
                    onSelectPuzzleToken: onSelectPuzzleToken,
                    onRemovePuzzleToken: onRemovePuzzleToken
                )
                PracticeBottomBar(
                    answerStatus: state.answerStatus,
                    canCheck: state.canCheckCurrentAnswer(),
                    canContinue: state.canContinue,
                    previousEnabled: state.currentIndex > 1 && !state.isListening,
                    nextLabel: state.currentIndex >= state.totalCount ? L10n.t("practice_finish") : L10n.t("common_continue"),
                    palette: palette,
                    onPrevious: onPrevious,
                    onCheck: onCheck,
                    onNext: onNext
                )
            }
        }
    }
}

private struct PracticeCenteredState<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 14, content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
    }
}

private struct PracticeBody: View {
    @ObservedObject var state: PracticeRecordingModel
    let palette: PracticePalette
    let selectedListenSpeed: Float
    let onListen: () -> Void
    let onSpeedSelected: (Float) -> Void
    let onSelectPuzzleToken: (Int) -> Void
    let onRemovePuzzleToken: (Int) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let item = state.currentItem {
                ListeningPuzzleCard(
                    item: item,
                    completedSegmentIds: state.completedSegmentIds,
                    selectedSegmentIds: state.selectedSegmentIds,
                    answerStatus: state.answerStatus,
                    feedbackTitle: state.feedbackTitle,
                    feedbackMessage: state.feedbackMessage,
                    isListening: state.isListening,
                    listenEnabled: !state.audioUrl.isEmpty && state.canShowContent && !state.isListening,
                    selectedListenSpeed: selectedListenSpeed,
                    palette: palette,
                    onListen: onListen,
                    onSpeedSelected: onSpeedSelected,
                    onSelectPuzzleToken: onSelectPuzzleToken,
                    onRemovePuzzleToken: onRemovePuzzleToken
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

private struct ListeningPuzzleCard: View {
    let item: ListeningPuzzle
    let completedSegmentIds: [Int]
    let selectedSegmentIds: [Int]
    let answerStatus: PracticeAnswerStatus
    let feedbackTitle: String
    let feedbackMessage: String
    let isListening: Bool
    let listenEnabled: Bool
    let selectedListenSpeed: Float
    let palette: PracticePalette
    let onListen: () -> Void
    let onSpeedSelected: (Float) -> Void
    let onSelectPuzzleToken: (Int) -> Void
    let onRemovePuzzleToken: (Int) -> Void

    private var selectedSegments: [PracticePuzzleSegment] {
        selectedSegmentIds.compactMap { id in item.segments.first(where: { $0.id == id }) }
    }

    private var shuffledSegments: [PracticePuzzleSegment] {
        stableShuffle(item.segments, seed: item.sentenceIndex + item.correctTokens.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.t("practice_listen_build_title"))
                .font(LexendFont.font(24, weight: .bold))
                .foregroundStyle(palette.onSurface)
                .multilineTextAlignment(.center)
            Text(L10n.t("practice_listen_build_subtitle"))
                .font(LexendFont.font(14))
                .foregroundStyle(palette.onSurfaceVariant)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            PracticeListenControls(
                isListening: isListening,
                enabled: listenEnabled,
                selectedSpeed: selectedListenSpeed,
                palette: palette,
                onListen: onListen,
                onSpeedSelected: onSpeedSelected
            )
            .padding(.top, 24)

            PuzzleAnswerArea(
                correctSegments: item.segments,
                selectedSegments: selectedSegments,
                answerStatus: answerStatus,
                palette: palette,
                onRemovePuzzleToken: onRemovePuzzleToken
            )
            .padding(.top, 22)

            PracticeFlowLayout(spacing: 8, rowSpacing: 10) {
                ForEach(shuffledSegments) { segment in
                    PuzzleTokenChip(
                        text: segment.text,
                        enabled: !selectedSegmentIds.contains(segment.id)
                            && !completedSegmentIds.contains(segment.id)
                            && answerStatus != .correct,
                        selected: false,
                        isError: false,
                        palette: palette
                    ) {
                        onSelectPuzzleToken(segment.id)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)

            PracticeFeedback(
                answerStatus: answerStatus,
                title: feedbackTitle,
                message: feedbackMessage,
                palette: palette
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.outlineVariant, lineWidth: 1))
    }
}

private struct PuzzleAnswerArea: View {
    let correctSegments: [PracticePuzzleSegment]
    let selectedSegments: [PracticePuzzleSegment]
    let answerStatus: PracticeAnswerStatus
    let palette: PracticePalette
    let onRemovePuzzleToken: (Int) -> Void

    var body: some View {
        let borderColor: Color = switch answerStatus {
        case .correct: Color(hex: 0x22C55E)
        case .incorrect: Color(hex: 0xF97316)
        case .idle: palette.outlineVariant
        }

        PracticeFlowLayout(spacing: 8, rowSpacing: 8) {
            if selectedSegments.isEmpty {
                Text(L10n.t("practice_tap_words_hint"))
                    .font(LexendFont.font(14))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(selectedSegments.enumerated()), id: \.element.id) { index, segment in
                    let wrongPosition = answerStatus == .incorrect && correctSegments[safe: index]?.id != segment.id
                    PuzzleTokenChip(
                        text: segment.text,
                        enabled: answerStatus != .correct,
                        selected: true,
                        isError: wrongPosition,
                        palette: palette
                    ) {
                        onRemovePuzzleToken(segment.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(palette.surfaceVariant.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(borderColor, lineWidth: 1))
    }
}

private struct PracticeListenControls: View {
    let isListening: Bool
    let enabled: Bool
    let selectedSpeed: Float
    let palette: PracticePalette
    let onListen: () -> Void
    let onSpeedSelected: (Float) -> Void

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onListen) {
                ZStack {
                    if isListening {
                        Circle()
                            .stroke(Color.white.opacity(0.34), lineWidth: 2)
                            .frame(width: 76, height: 76)
                            .scaleEffect(pulse ? 1.22 : 1)
                            .opacity(pulse ? 0 : 1)
                        Circle()
                            .stroke(Color.white.opacity(0.42), lineWidth: 2)
                            .frame(width: 58, height: 58)
                            .scaleEffect(pulse ? 1.14 : 1)
                            .opacity(pulse ? 0 : 1)
                    }
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle((enabled || isListening) ? .white : .white.opacity(0.45))
                        .scaleEffect(isListening && pulse ? 1.08 : 1)
                }
                .frame(width: 86, height: 86)
                .background((enabled || isListening) ? LingoRiseColors.primary : palette.surfaceVariant)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .onChange(of: isListening) { _, value in
                pulse = value
            }
            .onAppear { pulse = isListening }
            .animation(.easeOut(duration: 0.95).repeatForever(autoreverses: false), value: pulse)

            HStack(spacing: 10) {
                PracticeSpeedChip(
                    label: L10n.t("practice_speed_normal"),
                    enabled: enabled,
                    selected: selectedSpeed >= 0.95,
                    palette: palette
                ) {
                    onSpeedSelected(1)
                }
                PracticeSpeedChip(
                    label: L10n.t("practice_speed_slow"),
                    enabled: enabled,
                    selected: selectedSpeed < 0.95,
                    palette: palette
                ) {
                    onSpeedSelected(0.75)
                }
            }
        }
    }
}

private struct PracticeSpeedChip: View {
    let label: String
    let enabled: Bool
    let selected: Bool
    let palette: PracticePalette
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Text(label)
                .font(LexendFont.font(13, weight: .bold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selected ? LingoRiseColors.primary.opacity(0.14) : palette.surfaceVariant.opacity(0.72))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? LingoRiseColors.primary : palette.outlineVariant, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var textColor: Color {
        if !enabled { return palette.onSurfaceVariant.opacity(0.45) }
        return selected ? LingoRiseColors.primary : palette.onSurface
    }
}

private struct PuzzleTokenChip: View {
    let text: String
    let enabled: Bool
    let selected: Bool
    let isError: Bool
    let palette: PracticePalette
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Text(text)
                .font(LexendFont.font(17, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(background)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(borderColor, lineWidth: isError ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var background: Color {
        if isError { return Color(hex: 0xFFEDD5) }
        if selected { return LingoRiseColors.primary }
        if enabled { return palette.background }
        return palette.surfaceVariant.opacity(0.45)
    }

    private var textColor: Color {
        if isError { return Color(hex: 0x9A3412) }
        if selected { return .white }
        if enabled { return palette.onSurface }
        return palette.onSurfaceVariant.opacity(0.35)
    }

    private var borderColor: Color {
        if isError { return Color(hex: 0xEA580C) }
        if selected { return LingoRiseColors.primary }
        return palette.outlineVariant
    }
}

private struct PracticeFeedback: View {
    let answerStatus: PracticeAnswerStatus
    let title: String
    let message: String
    let palette: PracticePalette

    var body: some View {
        if answerStatus != .idle, !title.isEmpty, !message.isEmpty {
            let color = answerStatus == .correct ? Color(hex: 0x22C55E) : Color(hex: 0xF97316)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: answerStatus == .correct ? "checkmark" : "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LexendFont.font(15, weight: .bold))
                        .foregroundStyle(palette.onSurface)
                    Text(message)
                        .font(LexendFont.font(12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .lineSpacing(3)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.35), lineWidth: 1))
            .padding(.top, 20)
        }
    }
}

private struct PracticeHeader: View {
    let unitTitle: String
    let currentIndex: Int
    let totalCount: Int
    let palette: PracticePalette
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                Text(L10n.t("practice_mode"))
                    .font(LexendFont.font(13, weight: .bold))
                    .foregroundStyle(LingoRiseColors.primary)
                Text(unitTitle)
                    .font(LexendFont.font(14))
                    .foregroundStyle(palette.onBackground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 5) {
                    if totalCount <= 8 && totalCount > 0 {
                        ForEach(0..<totalCount, id: \.self) { index in
                            Circle()
                                .fill(index < currentIndex ? LingoRiseColors.primary : palette.surfaceVariant)
                                .frame(width: 6, height: 6)
                        }
                    } else {
                        ProgressView(value: Double(currentIndex), total: Double(max(totalCount, 1)))
                            .tint(LingoRiseColors.primary)
                            .frame(width: 52, height: 4)
                    }
                    Text(L10n.format("practice_index_format", currentIndex, max(totalCount, 1)))
                        .font(LexendFont.font(11))
                        .foregroundStyle(palette.onSurfaceVariant)
                }
                .padding(.top, 5)
            }
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(palette.background)
    }
}

private struct PracticeBottomBar: View {
    let answerStatus: PracticeAnswerStatus
    let canCheck: Bool
    let canContinue: Bool
    let previousEnabled: Bool
    let nextLabel: String
    let palette: PracticePalette
    let onPrevious: () -> Void
    let onCheck: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(previousEnabled ? palette.onSurface : palette.onSurfaceVariant.opacity(0.4))
                    .frame(width: 52, height: 52)
                    .background(palette.surfaceVariant)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!previousEnabled)

            Button(action: canContinue ? onNext : onCheck) {
                Text(canContinue ? nextLabel : L10n.t("practice_check"))
                    .font(LexendFont.font(16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background((canContinue || canCheck) ? LingoRiseColors.primary : LingoRiseColors.primary.opacity(0.42))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(canContinue ? false : !canCheck)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(canContinue ? LingoRiseColors.primary : palette.onSurfaceVariant.opacity(0.35))
                    .frame(width: 52, height: 52)
                    .background(canContinue ? LingoRiseColors.primary.opacity(0.12) : palette.surfaceVariant)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(palette.surface)
        .overlay(Rectangle().fill(palette.outlineVariant).frame(height: 1), alignment: .top)
    }
}

private struct PracticeCompletionScreen: View {
    let selectedRating: Int
    let palette: PracticePalette
    let onRate: (Int) -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(palette.outlineVariant, lineWidth: 1))
                ZStack {
                    Circle()
                        .fill(Color(hex: 0x17336B))
                        .frame(width: 220, height: 220)
                    Circle()
                        .fill(Color(hex: 0x3B82F6))
                        .frame(width: 164, height: 164)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                    Image(systemName: "checkmark")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(Color(hex: 0x3B82F6))
                }
                Image(systemName: "sparkles")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(Color(hex: 0x34D399))
                    .offset(x: 88, y: -82)
                Image(systemName: "star.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFACC15))
                    .offset(x: 102, y: -46)
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC084FC))
                    .offset(x: -92, y: 52)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 16)

            Text(L10n.t("practice_completed_title"))
                .font(LexendFont.font(28, weight: .bold))
                .foregroundStyle(palette.onBackground)
                .multilineTextAlignment(.center)
                .padding(.top, 34)
            Text(L10n.t("practice_completed_message"))
                .font(LexendFont.font(17))
                .foregroundStyle(palette.onSurfaceVariant)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 12)

            Text(L10n.t("reading_rate_story"))
                .font(LexendFont.font(11))
                .tracking(2)
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 28)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        onRate(rating)
                    } label: {
                        Image(systemName: "star.fill")
                            .font(.system(size: 35, weight: .regular))
                            .foregroundStyle(rating <= selectedRating ? Color(hex: 0xFACC15) : palette.outline)
                            .frame(width: 40, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 26)
            Button(action: onFinish) {
                Text(L10n.t("practice_done"))
                    .font(LexendFont.font(16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(LingoRiseColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .background(palette.background.ignoresSafeArea())
    }
}

@MainActor
private final class PracticeAudioController: ObservableObject {
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var prepareTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var generation = 0
    private var preparedAudioUrl = ""
    private var requestInFlight = false
    private var pendingSpeed: Float = 1
    private var onFinished: (() -> Void)?
    private var onFailure: ((String) -> Void)?

    func prepare(audioUrl: String) {
        generation += 1
        let currentGeneration = generation
        requestInFlight = false
        preparedAudioUrl = ""
        watchdogTask?.cancel()
        prepareTask?.cancel()
        clearPlayer()
        guard !audioUrl.isEmpty else { return }

        prepareTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await withThrowingTaskGroup(of: URL.self) { group in
                    group.addTask {
                        try await PracticeAudioCache.shared.cachedURL(cacheKey: PracticeAudioCache.stableKey("practice", audioUrl), audioUrl: audioUrl)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 15_000_000_000)
                        throw URLError(.timedOut)
                    }
                    guard let localURL = try await group.next() else { throw URLError(.unknown) }
                    group.cancelAll()
                    await MainActor.run {
                        guard currentGeneration == self.generation else { return }
                        self.installPlayer(url: localURL, audioUrl: audioUrl)
                    }
                }
            } catch {
                await MainActor.run {
                    guard currentGeneration == self.generation else { return }
                    self.fail(L10n.t("error_something_went_wrong"))
                }
            }
        }
    }

    func play(speed: Float, onFinished: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
        guard !requestInFlight else { return }
        self.onFinished = onFinished
        self.onFailure = onFailure
        pendingSpeed = speed
        requestInFlight = true
        if player != nil, !preparedAudioUrl.isEmpty {
            startPreparedPlayback()
        }
    }

    func cancel() {
        generation += 1
        requestInFlight = false
        watchdogTask?.cancel()
        prepareTask?.cancel()
        clearPlayer()
    }

    private func installPlayer(url: URL, audioUrl: String) {
        clearPlayer()
        preparedAudioUrl = audioUrl
        let player = AVPlayer(url: url)
        self.player = player
        if let item = player.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.finish()
                }
            }
        }
        if requestInFlight {
            startPreparedPlayback()
        }
    }

    private func startPreparedPlayback() {
        guard let player else { return }
        watchdogTask?.cancel()
        player.pause()
        player.seek(to: .zero)
        player.rate = pendingSpeed
        watchdogTask = Task { [weak self] in
            let duration = player.currentItem?.asset.duration.seconds ?? 0
            let timeout = duration.isFinite && duration > 0 ? duration + 5 : 60
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await MainActor.run {
                guard self?.requestInFlight == true else { return }
                self?.fail(L10n.t("error_something_went_wrong"))
            }
        }
    }

    private func finish() {
        requestInFlight = false
        watchdogTask?.cancel()
        player?.pause()
        player?.seek(to: .zero)
        onFinished?()
    }

    private func fail(_ message: String) {
        requestInFlight = false
        watchdogTask?.cancel()
        clearPlayer()
        onFailure?(message)
    }

    private func clearPlayer() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player = nil
    }

    deinit {
        prepareTask?.cancel()
        watchdogTask?.cancel()
    }
}

private actor PracticeAudioCache {
    static let shared = PracticeAudioCache()

    private var inFlight: [String: Task<URL, Error>] = [:]

    func cachedURL(cacheKey: String, audioUrl: String) async throws -> URL {
        guard !audioUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw URLError(.badURL)
        }
        let key = sha256(cacheKey.isEmpty ? audioUrl : cacheKey)
        let fileURL = Self.directory().appendingPathComponent(key).appendingPathExtension("mp3")
        if Self.isUsable(fileURL) { return fileURL }

        if let task = inFlight[key] {
            return try await task.value
        }
        let task = Task<URL, Error> {
            guard let remoteURL = URL(string: audioUrl) else { throw URLError(.badURL) }
            return try await Self.download(remoteURL: remoteURL, fileURL: fileURL)
        }
        inFlight[key] = task

        do {
            let url = try await task.value
            inFlight[key] = nil
            return url
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    nonisolated static func stableKey(_ parts: Any?...) -> String {
        parts.map { "\($0 ?? "")" }.joined(separator: "|")
    }

    private nonisolated static func directory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio-clips", isDirectory: true)
    }

    private nonisolated static func isUsable(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
    }

    private nonisolated static func download(remoteURL: URL, fileURL: URL) async throws -> URL {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if isUsable(fileURL) { return fileURL }

        let tempURL = directory.appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent).appendingPathExtension("tmp")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 20
        let (downloadedURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw URLError(.badServerResponse)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: tempURL)
        guard isUsable(tempURL) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw URLError(.zeroByteResource)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        do {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        } catch {
            try FileManager.default.copyItem(at: tempURL, to: fileURL)
            try? FileManager.default.removeItem(at: tempURL)
        }
        return fileURL
    }

    private nonisolated func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct PracticePalette {
    let isDark: Bool

    var background: Color { isDark ? LingoRiseColors.backgroundDark : LingoRiseColors.backgroundLight }
    var surface: Color { isDark ? LingoRiseColors.surfaceDark : LingoRiseColors.surfaceLight }
    var onBackground: Color { isDark ? LingoRiseColors.onBackgroundDark : LingoRiseColors.onBackgroundLight }
    var onSurface: Color { isDark ? LingoRiseColors.onSurfaceDark : LingoRiseColors.onSurfaceLight }
    var surfaceVariant: Color { isDark ? LingoRiseColors.surfaceVariantDark : LingoRiseColors.surfaceVariantLight }
    var onSurfaceVariant: Color { isDark ? LingoRiseColors.onSurfaceVariantDark : LingoRiseColors.onSurfaceVariantLight }
    var outline: Color { isDark ? LingoRiseColors.outlineDark : LingoRiseColors.outlineLight }
    var outlineVariant: Color { isDark ? LingoRiseColors.outlineVariantDark : LingoRiseColors.outlineVariantLight }
}

private struct PracticeFlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(width: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(width: bounds.width, subviews: subviews)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func layout(width: CGFloat, subviews: Subviews) -> (items: [(index: Int, origin: CGPoint, size: CGSize)], size: CGSize) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var items: [(Int, CGPoint, CGSize)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            items.append((index, CGPoint(x: x, y: y), size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (items, CGSize(width: width, height: y + rowHeight))
    }
}

private func selectListeningPuzzleSentences(
    sentences: [SentenceAudio],
    preferredIndexes: [Int],
    level: String
) -> [SentenceAudio] {
    let preferred = preferredIndexes.compactMap { index in sentences.first(where: { $0.index == index }) }
    let fallback = sentences.filter { sentence in !preferred.contains(where: { $0.index == sentence.index }) }
    let ordered = uniqueByIndex(preferred + fallback)
    let ideal = Array(ordered.filter { isEligiblePuzzleSentence($0, level: level, flexible: false) }.prefix(3))
    if ideal.count >= 2 { return ideal }

    let selectedIndexes = Set(ideal.map(\.index))
    let flexible = ordered
        .filter { !selectedIndexes.contains($0.index) }
        .filter { isEligiblePuzzleSentence($0, level: level, flexible: true) }
        .sorted { lhs, rhs in
            let rules = levelRules(level)
            let left = tokenRangeDistance(tokenizeSentence(lhs.text).count, rules: rules)
            let right = tokenRangeDistance(tokenizeSentence(rhs.text).count, rules: rules)
            if left != right { return left < right }
            return (ordered.firstIndex(where: { $0.index == lhs.index }) ?? 0) < (ordered.firstIndex(where: { $0.index == rhs.index }) ?? 0)
        }
    return Array(uniqueByIndex(ideal + flexible).prefix(3))
}

private func isEligiblePuzzleSentence(_ sentence: SentenceAudio, level: String, flexible: Bool) -> Bool {
    guard !sentence.audioUrl.isEmpty else { return false }
    let tokens = tokenizeSentence(sentence.text)
    let rules = levelRules(level)
    guard tokens.count >= 5 else { return false }
    if !flexible, !(rules.minTokens...rules.maxTokens).contains(tokens.count) { return false }
    if flexible, tokens.count > 24 { return false }
    if !flexible, sentence.text.count > 130 { return false }
    if flexible, sentence.text.count > 170 { return false }
    if !flexible, [":", ";", "(", ")", "—"].contains(where: { sentence.text.contains($0) }) { return false }
    if buildPuzzleSegments(tokens: tokens, sentenceIndex: sentence.index, sentenceText: sentence.text, storyId: "", rules: rules).isEmpty { return false }
    let counts = Dictionary(grouping: tokens.map { $0.lowercased() }, by: { $0 }).mapValues(\.count)
    return !counts.values.contains { $0 >= 3 }
}

private func sentenceToListeningPuzzle(_ sentence: SentenceAudio, storyId: String, level: String) -> ListeningPuzzle {
    let rules = levelRules(level)
    let tokens = tokenizeSentence(sentence.text)
    let segments = buildPuzzleSegments(tokens: tokens, sentenceIndex: sentence.index, sentenceText: sentence.text, storyId: storyId, rules: rules)
    let correctTokens = tokens.enumerated().map { PracticePuzzleToken(id: $0.offset, text: $0.element) }
    var shuffled = stableShuffle(correctTokens, seed: stableSeed("\(storyId)_\(sentence.index)_\(sentence.text)"))
    if shuffled.map(\.id) == correctTokens.map(\.id), shuffled.count > 1 {
        shuffled = Array(shuffled.dropFirst() + shuffled.prefix(1))
    }
    return ListeningPuzzle(
        sentenceIndex: sentence.index,
        audioUrl: sentence.audioUrl,
        segments: segments,
        correctTokens: correctTokens,
        shuffledTokens: shuffled
    )
}

private func tokenizeSentence(_ text: String) -> [String] {
    let pattern = #"\d+(?:[.,]\d+)?|[A-Za-z]+(?:'[A-Za-z]+)?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
        Range(match.range, in: text).map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
    }.filter { !$0.isEmpty }
}

private func buildPuzzleSegments(
    tokens: [String],
    sentenceIndex: Int,
    sentenceText: String,
    storyId: String,
    rules: LevelPuzzleRules
) -> [PracticePuzzleSegment] {
    guard let segmentCount = chooseSegmentCount(tokenCount: tokens.count, rules: rules) else { return [] }
    let sizes = balancedSegmentSizes(tokenCount: tokens.count, segmentCount: segmentCount)
    let seed = stableSeed("\(storyId)_\(sentenceIndex)_\(sentenceText)")
    var nextTokenId = 0
    var cursor = 0
    return sizes.enumerated().map { segmentIndex, size in
        let correct = tokens[cursor..<(cursor + size)].map { token -> PracticePuzzleToken in
            defer { nextTokenId += 1 }
            return PracticePuzzleToken(id: nextTokenId, text: token)
        }
        cursor += size
        var shuffled = stableShuffle(correct, seed: seed + segmentIndex)
        if shuffled.count > 1, shuffled.map(\.id) == correct.map(\.id) {
            shuffled = Array(shuffled.dropFirst() + shuffled.prefix(1))
        }
        return PracticePuzzleSegment(id: segmentIndex, correctTokens: correct, shuffledTokens: shuffled)
    }
}

private func chooseSegmentCount(tokenCount: Int, rules: LevelPuzzleRules) -> Int? {
    let maxSegmentsByTokenCount = tokenCount / 2
    let upper = min(rules.maxSegments, maxSegmentsByTokenCount)
    return upper < 1 ? nil : upper
}

private func balancedSegmentSizes(tokenCount: Int, segmentCount: Int) -> [Int] {
    let base = tokenCount / segmentCount
    let remainder = tokenCount % segmentCount
    return (0..<segmentCount).map { base + ($0 < remainder ? 1 : 0) }
}

private func levelRules(_ level: String) -> LevelPuzzleRules {
    switch level.uppercased() {
    case "A1": return LevelPuzzleRules(minTokens: 5, maxTokens: 7, maxSegments: 2)
    case "A2": return LevelPuzzleRules(minTokens: 6, maxTokens: 9, maxSegments: 3)
    case "B1": return LevelPuzzleRules(minTokens: 8, maxTokens: 12, maxSegments: 4)
    case "B2": return LevelPuzzleRules(minTokens: 10, maxTokens: 16, maxSegments: 5)
    case "C1": return LevelPuzzleRules(minTokens: 12, maxTokens: 20, maxSegments: 6)
    default: return LevelPuzzleRules(minTokens: 8, maxTokens: 12, maxSegments: 4)
    }
}

private func tokenRangeDistance(_ tokenCount: Int, rules: LevelPuzzleRules) -> Int {
    if tokenCount < rules.minTokens { return rules.minTokens - tokenCount }
    if tokenCount > rules.maxTokens { return tokenCount - rules.maxTokens }
    return 0
}

private struct LevelPuzzleRules {
    let minTokens: Int
    let maxTokens: Int
    let maxSegments: Int
}

private func uniqueByIndex(_ sentences: [SentenceAudio]) -> [SentenceAudio] {
    var seen = Set<Int>()
    return sentences.filter { seen.insert($0.index).inserted }
}

private func stableSeed(_ value: String) -> Int {
    var hash = 5381
    for scalar in value.unicodeScalars {
        hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
    }
    return abs(hash)
}

private func stableShuffle<T>(_ values: [T], seed: Int) -> [T] {
    guard values.count > 1 else { return values }
    var result = values
    var generator = SeededGenerator(seed: UInt64(max(seed, 1)))
    for index in stride(from: result.count - 1, through: 1, by: -1) {
        let randomIndex = Int(generator.next() % UInt64(index + 1))
        result.swapAt(index, randomIndex)
    }
    return result
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Practice") {
    PracticeScreen(storyId: "preview", isDailyPick: false)
        .environmentObject(AppState())
}
