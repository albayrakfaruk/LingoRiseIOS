import StoreKit
import SwiftUI

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
    let hasPracticeAccess: Bool

    init(storyId: String, isDailyPick: Bool, hasPracticeAccess: Bool) {
        self.storyId = storyId
        self.isDailyPick = isDailyPick
        self.hasPracticeAccess = hasPracticeAccess
        _model = StateObject(wrappedValue: PracticeRecordingModel(storyId: storyId))
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
                        } onRatingUpdated: { averageRating, ratingCount in
                            appState.updateCurrentRating(
                                storyId: storyId,
                                averageRating: averageRating,
                                ratingCount: ratingCount
                            )
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
            await model.load(cachedPackage: appState.storyPackage, service: appState.contentService)
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
        guard hasPracticeAccess else {
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
        guard hasPracticeAccess else {
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
        .padding(.top, 8)
        .padding(.bottom, 14)
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
            .padding(.top, 20)

            PuzzleAnswerArea(
                correctSegments: item.segments,
                selectedSegments: selectedSegments,
                answerStatus: answerStatus,
                palette: palette,
                onRemovePuzzleToken: onRemovePuzzleToken
            )
            .padding(.top, 18)

            WrappingFlowLayout(spacing: 8, rowSpacing: 10) {
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
            .padding(.top, 18)

            PracticeFeedback(
                answerStatus: answerStatus,
                title: feedbackTitle,
                message: feedbackMessage,
                palette: palette
            )
        }
        .padding(20)
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

        WrappingFlowLayout(spacing: 8, rowSpacing: 8) {
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
                .padding(12)
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
                .font(LexendFont.font(16, weight: .semibold))
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
        .padding(.bottom, 8)
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
    @State private var decorationsAnimating = false

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
                    .rotationEffect(.degrees(decorationsAnimating ? 8 : -6))
                    .scaleEffect(decorationsAnimating ? 1.08 : 0.96)
                    .offset(x: 88, y: -82)
                    .animation(
                        .easeInOut(duration: 1.15).repeatForever(autoreverses: true),
                        value: decorationsAnimating
                    )
                Image(systemName: "star.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFACC15))
                    .rotationEffect(.degrees(decorationsAnimating ? -7 : 7))
                    .scaleEffect(decorationsAnimating ? 0.94 : 1.12)
                    .offset(x: 102, y: decorationsAnimating ? -50 : -43)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: decorationsAnimating
                    )
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC084FC))
                    .rotationEffect(.degrees(decorationsAnimating ? -9 : 5))
                    .scaleEffect(decorationsAnimating ? 1.07 : 0.97)
                    .offset(x: -92, y: decorationsAnimating ? 48 : 55)
                    .animation(
                        .easeInOut(duration: 1.25).repeatForever(autoreverses: true),
                        value: decorationsAnimating
                    )
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
        .onAppear {
            decorationsAnimating = true
        }
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Practice") {
    PracticeScreen(storyId: "preview", isDailyPick: false, hasPracticeAccess: true)
        .environmentObject(AppState())
}
