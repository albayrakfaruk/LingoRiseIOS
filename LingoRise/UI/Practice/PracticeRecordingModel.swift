import Combine
import Foundation

enum PracticeAnswerStatus {
    case idle
    case correct
    case incorrect
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
    private let ratingService: StoryRatingService
    private var contentService: ContentService?
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
        ratingService: StoryRatingService = StoryRatingService()
    ) {
        self.storyId = storyId
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

    func load(cachedPackage: Content?, service: ContentService) async {
        guard !loaded else { return }
        loaded = true
        contentService = service
        sessions.removeAll()
        isLoading = true
        errorMessage = nil
        hasNoItems = false
        do {
            let story = if let cachedPackage, cachedPackage.id == storyId {
                cachedPackage
            } else {
                try await service.getStoryPackage(id: storyId)
            }
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
        guard let contentService else { return }
        loaded = false
        await load(cachedPackage: nil, service: contentService)
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

    func rateStory(
        _ rating: Int,
        requestReview: @escaping () -> Void,
        onRatingUpdated: @escaping (_ averageRating: Double, _ ratingCount: Int) -> Void
    ) {
        guard ratingTask == nil else { return }
        let normalized = min(max(rating, 1), 5)
        selectedRating = normalized
        ratingTask = Task { [weak self] in
            guard let self else { return }
            defer { self.ratingTask = nil }
            do {
                let result = try await ratingService.rateStory(storyId: storyId, rating: normalized)
                AppAnalytics.logStoryRating(storyId: storyId, rating: normalized)
                contentService?.updateCurrentRating(
                    storyId: storyId,
                    averageRating: result.averageRating,
                    ratingCount: result.ratingCount
                )
                onRatingUpdated(result.averageRating, result.ratingCount)
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
