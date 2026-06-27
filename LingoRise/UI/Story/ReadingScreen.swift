import AVFoundation
import CryptoKit
import StoreKit
import SwiftUI

@MainActor
final class ReadingModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var content: Content?
    @Published var currentSentenceIndex = 0
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var hasAudioError = false
    @Published var positionMs = 0
    @Published var currentSentenceElapsedMs = 0
    @Published var currentSentenceDurationMs = 0
    @Published var playbackSpeed: Float = 1
    @Published var showPracticeCta = false
    @Published var fontScaleIndex = 1

    private var player: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var progressTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var downloadTasks: [String: Task<URL, Error>] = [:]
    private var cachedAudioURLs: [String: URL] = [:]
    private var playRequestId = 0
    private var loadedStoryId = ""
    private var didLogCompletion = false
    private let fontScales: [CGFloat] = [0.75, 1, 1.25]

    var fontScale: CGFloat { fontScales[fontScaleIndex] }
    var sentences: [SentenceAudio] { content?.sentences ?? [] }
    var durationMs: Int { max(sentences.reduce(0) { $0 + sentenceDuration($1) }, 1) }
    var chapterTitle: String { L10n.format("reading_chapter_title", content?.title ?? "") }
    var storyTitle: String { content?.title ?? "" }

    func load(storyId: String, cachedPackage: Content?, service: ContentService) async {
        if loadedStoryId == storyId, content != nil, errorMessage == nil { return }
        loadedStoryId = storyId
        isLoading = true
        errorMessage = nil
        hasAudioError = false
        showPracticeCta = false
        didLogCompletion = false

        do {
            let package: Content
            if let cachedPackage, cachedPackage.id == storyId {
                package = cachedPackage
            } else {
                package = try await service.getStoryPackage(id: storyId)
            }
            guard !package.sentences.isEmpty else {
                content = package
                errorMessage = L10n.t("error_content_unavailable")
                isLoading = false
                return
            }
            content = package
            currentSentenceIndex = 0
            positionMs = 0
            currentSentenceElapsedMs = 0
            currentSentenceDurationMs = package.sentences.first.map { sentenceDuration($0) } ?? 0
            isLoading = false
            startPreloading(from: 0)
        } catch {
            errorMessage = L10n.t("error_something_went_wrong")
            isLoading = false
        }
    }

    func cycleFontScale() {
        fontScaleIndex = (fontScaleIndex + 1) % fontScales.count
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.enableRate = true
        player?.rate = speed
        if let content {
            AppAnalytics.logReadingPlaybackSpeed(storyId: content.id, speed: Double(speed))
        }
    }

    func cyclePlaybackSpeed() {
        if playbackSpeed <= 0.8 {
            setPlaybackSpeed(1)
        } else if playbackSpeed <= 1.1 {
            setPlaybackSpeed(1.25)
        } else {
            setPlaybackSpeed(0.75)
        }
    }

    func playPause() {
        if isPlaying {
            pause()
        } else {
            if positionMs >= durationMs {
                currentSentenceIndex = 0
                applyPosition(sentenceIndex: 0, elapsedMs: 0)
                showPracticeCta = false
            }
            beginPlaySentence(currentSentenceIndex, resumeFromCurrent: true, showBuffering: true)
        }
    }

    func pause() {
        playRequestId += 1
        player?.delegate = nil
        player?.pause()
        speechSynthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isBuffering = false
        stopProgressTask()
        stopSpeechTask()
    }

    func seekToSentence(_ index: Int) {
        let bounded = min(max(index, 0), max(sentences.count - 1, 0))
        currentSentenceIndex = bounded
        applyPosition(sentenceIndex: bounded, elapsedMs: 0)
        beginPlaySentence(bounded, resumeFromCurrent: false, showBuffering: true)
    }

    func replay10() {
        let target = max(positionMs - 10_000, 0)
        seekGlobal(to: target)
        if let content {
            AppAnalytics.logReadingReplayForward(storyId: content.id, action: "replay_10")
        }
    }

    func forward10() {
        let target = min(positionMs + 10_000, durationMs)
        seekGlobal(to: target)
        if let content {
            AppAnalytics.logReadingReplayForward(storyId: content.id, action: "forward_10")
        }
        if target >= durationMs {
            completePlayback()
        }
    }

    func seek(progress: Double) {
        let target = Int(Double(durationMs) * min(max(progress, 0), 1))
        seekGlobal(to: target)
        if let content {
            AppAnalytics.logReadingSeek(storyId: content.id, progress: progress)
        }
        if target >= durationMs {
            completePlayback()
        }
    }

    func resetPlayback() {
        pause()
        currentSentenceIndex = 0
        positionMs = 0
        currentSentenceElapsedMs = 0
        currentSentenceDurationMs = sentences.first.map { sentenceDuration($0) } ?? 0
        showPracticeCta = false
    }

    func dismissPracticeCta() {
        showPracticeCta = false
    }

    func presentPracticeCta() {
        pause()
        showPracticeCta = true
    }

    private func seekGlobal(to targetMs: Int) {
        guard !sentences.isEmpty else { return }
        var accumulated = 0
        for (index, sentence) in sentences.enumerated() {
            let next = accumulated + sentenceDuration(sentence)
            if targetMs < next || index == sentences.count - 1 {
                currentSentenceIndex = index
                applyPosition(sentenceIndex: index, elapsedMs: max(targetMs - accumulated, 0))
                beginPlaySentence(index, resumeFromCurrent: true, showBuffering: true)
                return
            }
            accumulated = next
        }
    }

    private func beginPlaySentence(_ index: Int, resumeFromCurrent: Bool, showBuffering: Bool) {
        playRequestId += 1
        let requestId = playRequestId
        Task { [weak self] in
            await self?.playSentence(index, resumeFromCurrent: resumeFromCurrent, requestId: requestId, showBuffering: showBuffering)
        }
    }

    private func playSentence(_ index: Int, resumeFromCurrent: Bool, requestId: Int, showBuffering: Bool) async {
        guard requestId == playRequestId else { return }
        guard index >= 0, index < sentences.count else { return }
        configureAudioSession()
        let sentence = sentences[index]
        guard !sentence.audioUrl.isEmpty else {
            playSpeechFallback(sentence, index: index, resumeFromCurrent: resumeFromCurrent, requestId: requestId)
            return
        }

        player?.delegate = nil
        player?.stop()
        speechSynthesizer.stopSpeaking(at: .immediate)
        stopProgressTask()
        stopSpeechTask()
        isBuffering = showBuffering
        hasAudioError = false
        if !showBuffering {
            isPlaying = true
        }
        do {
            let url = try await cachedAudioURL(for: sentence)
            guard requestId == playRequestId else { return }
            player?.delegate = nil
            player?.stop()
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.enableRate = true
            player?.rate = playbackSpeed
            player?.prepareToPlay()
            if resumeFromCurrent, currentSentenceIndex == index {
                player?.currentTime = Double(currentSentenceElapsedMs) / 1000
            } else {
                currentSentenceElapsedMs = 0
            }
            currentSentenceIndex = index
            currentSentenceDurationMs = sentenceDuration(sentence)
            isBuffering = false
            isPlaying = true
            if player?.play() == true {
                startProgressTask(requestId: requestId)
                startPreloading(from: index + 1)
            } else {
                playSpeechFallback(sentence, index: index, resumeFromCurrent: resumeFromCurrent, requestId: requestId)
            }
        } catch {
            guard requestId == playRequestId else { return }
            isBuffering = false
            playSpeechFallback(sentence, index: index, resumeFromCurrent: resumeFromCurrent, requestId: requestId)
        }
    }

    private func cachedAudioURL(for sentence: SentenceAudio) async throws -> URL {
        let key = audioCacheKey(sentence)
        if let cachedURL = cachedAudioURLs[key], Self.isUsableAudioFile(cachedURL) {
            return cachedURL
        }
        let fileURL = Self.audioCacheDirectory().appendingPathComponent(key).appendingPathExtension("mp3")
        if FileManager.default.fileExists(atPath: fileURL.path),
           Self.isUsableAudioFile(fileURL) {
            cachedAudioURLs[key] = fileURL
            return fileURL
        }
        if let existingTask = downloadTasks[key] {
            return try await existingTask.value
        }
        guard let remoteURL = URL(string: sentence.audioUrl) else { throw URLError(.badURL) }
        let task = Task.detached(priority: .utility) {
            try await Self.downloadAudio(remoteURL: remoteURL, fileURL: fileURL)
        }
        downloadTasks[key] = task
        do {
            let url = try await task.value
            cachedAudioURLs[key] = url
            downloadTasks[key] = nil
            return url
        } catch {
            downloadTasks[key] = nil
            throw error
        }
    }

    private func audioCacheKey(_ sentence: SentenceAudio) -> String {
        let raw = "\(loadedStoryId)|sentence|\(sentence.index)|\(sentence.text)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func startPreloading(from startIndex: Int) {
        preloadTask?.cancel()
        guard !sentences.isEmpty else { return }
        let start = min(max(startIndex, 0), sentences.count)
        preloadTask = Task { [weak self] in
            guard let self else { return }
            for index in start..<sentences.count {
                if Task.isCancelled { return }
                let sentence = sentences[index]
                guard !sentence.audioUrl.isEmpty else { continue }
                _ = try? await cachedAudioURL(for: sentence)
            }
        }
    }

    nonisolated private static func audioCacheDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio-clips", isDirectory: true)
    }

    nonisolated private static func isUsableAudioFile(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
    }

    nonisolated private static func downloadAudio(remoteURL: URL, fileURL: URL) async throws -> URL {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path), isUsableAudioFile(fileURL) {
            return fileURL
        }

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
        guard isUsableAudioFile(tempURL) else {
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

    private func startProgressTask(requestId: Int) {
        stopProgressTask()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    self?.publishProgress(requestId: requestId)
                }
            }
        }
    }

    private func stopProgressTask() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func playSpeechFallback(_ sentence: SentenceAudio, index: Int, resumeFromCurrent: Bool, requestId: Int) {
        guard requestId == playRequestId else { return }
        player?.delegate = nil
        player?.stop()
        speechSynthesizer.stopSpeaking(at: .immediate)
        currentSentenceIndex = index
        currentSentenceDurationMs = sentenceDuration(sentence)
        if !resumeFromCurrent {
            currentSentenceElapsedMs = 0
        }
        hasAudioError = false
        isBuffering = false
        isPlaying = true

        let utterance = AVSpeechUtterance(string: sentence.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rateForSpeech(playbackSpeed)
        speechSynthesizer.speak(utterance)
        startSpeechProgressTask(requestId: requestId)
    }

    private func startSpeechProgressTask(requestId: Int) {
        stopProgressTask()
        stopSpeechTask()
        speechTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    self?.tickSpeechProgress(requestId: requestId)
                }
            }
        }
    }

    private func stopSpeechTask() {
        speechTask?.cancel()
        speechTask = nil
    }

    private func tickSpeechProgress(requestId: Int) {
        guard requestId == playRequestId, isPlaying else { return }
        currentSentenceElapsedMs = min(currentSentenceElapsedMs + Int(200 * playbackSpeed), currentSentenceDurationMs)
        applyPosition(sentenceIndex: currentSentenceIndex, elapsedMs: currentSentenceElapsedMs)
        if currentSentenceElapsedMs >= currentSentenceDurationMs {
            stopSpeechTask()
            if currentSentenceIndex < sentences.count - 1 {
                beginPlaySentence(currentSentenceIndex + 1, resumeFromCurrent: false, showBuffering: false)
            } else {
                completePlayback()
            }
        }
    }

    private func estimatedSpeechDurationMs(_ text: String) -> Int {
        max(text.split(separator: " ").count * 420, 1_500)
    }

    private func sentenceDuration(_ sentence: SentenceAudio) -> Int {
        sentence.durationMs > 0 ? sentence.durationMs : estimatedSpeechDurationMs(sentence.text)
    }

    private func rateForSpeech(_ speed: Float) -> Float {
        switch speed {
        case ..<0.9: return 0.38
        case 0.9..<1.2: return 0.46
        default: return 0.54
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("reading_audio_session_failed", error)
            #endif
        }
    }

    private func publishProgress(requestId: Int) {
        guard requestId == playRequestId else { return }
        guard let player else { return }
        applyPosition(sentenceIndex: currentSentenceIndex, elapsedMs: Int(player.currentTime * 1000))
    }

    private func applyPosition(sentenceIndex: Int, elapsedMs: Int) {
        let before = sentences.prefix(sentenceIndex).reduce(0) { $0 + sentenceDuration($1) }
        let duration = sentences[safe: sentenceIndex].map { sentenceDuration($0) } ?? 0
        currentSentenceElapsedMs = min(max(elapsedMs, 0), duration)
        currentSentenceDurationMs = duration
        positionMs = min(before + currentSentenceElapsedMs, durationMs)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard flag else {
                if let sentence = sentences[safe: currentSentenceIndex] {
                    playSpeechFallback(sentence, index: currentSentenceIndex, resumeFromCurrent: false, requestId: playRequestId)
                } else {
                    hasAudioError = true
                    isPlaying = false
                }
                return
            }
            if currentSentenceIndex < sentences.count - 1 {
                beginPlaySentence(currentSentenceIndex + 1, resumeFromCurrent: false, showBuffering: false)
            } else {
                completePlayback()
            }
        }
    }

    private func completePlayback() {
        stopProgressTask()
        stopSpeechTask()
        player?.delegate = nil
        player?.stop()
        speechSynthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        positionMs = durationMs
        showPracticeCta = true
        if !didLogCompletion, let content {
            didLogCompletion = true
            AppAnalytics.logReadingComplete(storyId: content.id, storyTitle: content.title)
        }
    }

    deinit {
        progressTask?.cancel()
        speechTask?.cancel()
        preloadTask?.cancel()
        downloadTasks.values.forEach { $0.cancel() }
    }
}

struct ReadingScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = ReadingModel()
    @State private var didRequestCompletionReview = false

    let storyId: String
    let isDailyPick: Bool

    var body: some View {
        let isDark = appState.effectiveDarkTheme(systemColorScheme: colorScheme)
        let palette = ReadingPalette(isDark: isDark)

        ZStack {
            palette.background.ignoresSafeArea()
            if model.isLoading {
                ProgressView()
                    .tint(LingoRiseColors.primary)
            } else if let error = model.errorMessage {
                MessageState(title: L10n.t("common_error"), message: error)
            } else {
                ReadingContent(
                    model: model,
                    palette: palette,
                    onBack: {
                        model.pause()
                        appState.route = .storyDetail(storyId, isDailyPick)
                    },
                    onCloseComplete: {
                        requestCompletionReviewOnce()
                        model.dismissPracticeCta()
                        model.pause()
                        appState.route = .storyDetail(storyId, isDailyPick)
                    },
                    onPractice: {
                        model.pause()
                        model.resetPlayback()
                        if AppRemoteConfig.shared.isPracticePaywallEnabled && !appState.isPremium {
                            appState.route = .paywall(source: .practice)
                        } else {
                            appState.route = .practice(storyId, isDailyPick)
                        }
                    },
                    onHome: {
                        requestCompletionReviewOnce()
                        model.dismissPracticeCta()
                        model.pause()
                        appState.route = .main
                    }
                )
            }
        }
        .task(id: storyId) {
            await model.load(storyId: storyId, cachedPackage: appState.storyPackage, service: appState.contentService)
            if let content = model.content {
                appState.storyPackage = content
                if content.isPremium && !appState.isPremium && !isDailyPick {
                    appState.route = .paywall(source: .reading)
                }
            }
        }
        .onDisappear {
            model.pause()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.pause()
            }
        }
    }

    private func requestCompletionReviewOnce() {
        guard !didRequestCompletionReview else { return }
        didRequestCompletionReview = true
        requestReview()
    }
}

private struct ReadingContent: View {
    @ObservedObject var model: ReadingModel
    let palette: ReadingPalette
    let onBack: () -> Void
    let onCloseComplete: () -> Void
    let onPractice: () -> Void
    let onHome: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ReadingTopBar(
                    title: model.chapterTitle,
                    palette: palette,
                    onBack: onBack,
                    onTextSettings: model.cycleFontScale
                )
                Divider().overlay(palette.outlineVariant)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.sentences.enumerated()), id: \.offset) { index, sentence in
                                ReadingSentenceRow(
                                    text: sentence.text,
                                    highlighted: index == model.currentSentenceIndex,
                                    fontScale: model.fontScale,
                                    palette: palette
                                ) {
                                    model.seekToSentence(index)
                                }
                                .id(index)
                            }
                            Spacer(minLength: 300)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                    }
                    .onChange(of: model.currentSentenceIndex) { _, index in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }

            ReadingAudioDock(model: model, palette: palette, onShowPracticeCta: model.presentPracticeCta)
                .frame(maxHeight: .infinity, alignment: .bottom)

            if model.showPracticeCta {
                ReadingCompletedOverlay(palette: palette, onPractice: onPractice, onClose: onCloseComplete, onHome: onHome)
                    .transition(.opacity)
            }
        }
    }
}

private struct ReadingTopBar: View {
    let title: String
    let palette: ReadingPalette
    let onBack: () -> Void
    let onTextSettings: () -> Void

    var body: some View {
        ZStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 48, height: 48)
            }
            .foregroundStyle(palette.onBackground)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 2) {
                Text(L10n.t("reading_mode"))
                    .font(LexendFont.font(12, weight: .bold))
                    .foregroundStyle(LingoRiseColors.primary)
                Text(title)
                    .font(LexendFont.font(14))
                    .foregroundStyle(palette.onBackground)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 58)

            Button(action: onTextSettings) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 21, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .foregroundStyle(palette.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [palette.background.opacity(0.90), palette.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct ReadingSentenceRow: View {
    let text: String
    let highlighted: Bool
    let fontScale: CGFloat
    let palette: ReadingPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text + " ")
                .font(LexendFont.font((highlighted ? 22 : 20) * fontScale, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(highlighted ? highlightedText : palette.onSurfaceVariant.opacity(0.72))
                .lineSpacing(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, highlighted ? 8 : 0)
                .padding(.vertical, highlighted ? 6 : 6)
                .background(highlighted ? highlightedBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var highlightedBackground: Color {
        palette.isDark ? LingoRiseColors.primary.opacity(0.28) : LingoRiseColors.primary.opacity(0.16)
    }

    private var highlightedText: Color {
        palette.isDark ? .white : LingoRiseColors.primary
    }
}

private struct ReadingAudioDock: View {
    @ObservedObject var model: ReadingModel
    let palette: ReadingPalette
    let onShowPracticeCta: () -> Void
    @State private var sliderPosition: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, palette.background], startPoint: .top, endPoint: .bottom)
                .frame(height: 4)
            VStack(spacing: 0) {
                ReadingSeekBar(
                    value: sliderValue,
                    enabled: !model.hasAudioError,
                    palette: palette
                ) { value in
                    sliderPosition = value
                } onFinished: { value in
                    model.seek(progress: value)
                }

                HStack {
                    Text(formatTime(model.positionMs))
                    Spacer()
                    Text(formatTime(model.durationMs))
                }
                .font(LexendFont.font(11, weight: .medium))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 8)

                if model.currentSentenceIndex >= 0, model.currentSentenceIndex < model.sentences.count, model.currentSentenceDurationMs > 0 {
                    Text(L10n.format("reading_sentence_time", model.currentSentenceIndex + 1, formatTime(model.currentSentenceElapsedMs), formatTime(model.currentSentenceDurationMs)))
                        .font(LexendFont.font(11))
                        .foregroundStyle(palette.onSurfaceVariant.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }

                if model.hasAudioError {
                    Button(L10n.t("reading_audio_retry")) {
                        model.playPause()
                    }
                    .font(LexendFont.font(13, weight: .semibold))
                    .foregroundStyle(LingoRiseColors.primary)
                    .padding(.top, 10)
                }

                HStack(spacing: 0) {
                    Button(action: model.cyclePlaybackSpeed) {
                        Text(speedLabel)
                            .font(LexendFont.font(11, weight: .bold))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .frame(width: 44, height: 48)
                    }
                    .disabled(model.hasAudioError)

                    HStack(spacing: 8) {
                        ControlIcon(systemName: "gobackward.10", label: L10n.t("cd_replay_10s"), enabled: !model.hasAudioError, action: model.replay10)
                        Button(action: model.playPause) {
                            ZStack {
                                Circle().fill(LingoRiseColors.primary)
                                if model.isBuffering && !model.isPlaying {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                        .offset(x: model.isPlaying ? 0 : 2)
                                }
                            }
                            .frame(width: 56, height: 56)
                        }
                        .disabled(model.hasAudioError)
                        .accessibilityLabel(model.isPlaying ? L10n.t("cd_pause") : L10n.t("cd_play"))

                        ControlIcon(systemName: "goforward.10", label: L10n.t("cd_forward_10s"), enabled: !model.hasAudioError, action: model.forward10)
                    }
                    .frame(maxWidth: .infinity)

                    ControlIcon(systemName: "mic.fill", label: L10n.t("cd_go_to_practice"), enabled: true, action: onShowPracticeCta)
                        .frame(width: 44)
                }
                .padding(.top, 16)
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .background(palette.background)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                    .stroke(palette.outlineVariant, lineWidth: 1)
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .background(palette.background.ignoresSafeArea(edges: .bottom))
        .onChange(of: model.positionMs) { _, _ in
            sliderPosition = sliderValue
        }
    }

    private var sliderValue: Double {
        model.durationMs > 0 ? min(max(Double(model.positionMs) / Double(model.durationMs), 0), 1) : 0
    }

    private var speedLabel: String {
        model.playbackSpeed == 1 ? "1x" : model.playbackSpeed == 0.75 ? "0.75x" : "1.25x"
    }
}

private struct ReadingSeekBar: View {
    let value: Double
    let enabled: Bool
    let palette: ReadingPalette
    let onChanged: (Double) -> Void
    let onFinished: (Double) -> Void
    @State private var editingValue: Double?

    var body: some View {
        GeometryReader { geometry in
            let current = editingValue ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceVariant).frame(height: 12)
                Capsule().fill(LingoRiseColors.primary).frame(width: max(16, geometry.size.width * current), height: 12)
                Circle()
                    .fill(LingoRiseColors.primary)
                    .frame(width: 16, height: 16)
                    .offset(x: min(max(geometry.size.width * current - 8, 0), geometry.size.width - 16))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        let next = min(max(gesture.location.x / max(geometry.size.width, 1), 0), 1)
                        editingValue = next
                        onChanged(next)
                    }
                    .onEnded { gesture in
                        guard enabled else { return }
                        let next = min(max(gesture.location.x / max(geometry.size.width, 1), 0), 1)
                        editingValue = nil
                        onFinished(next)
                    }
            )
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
    }
}

private struct ControlIcon: View {
    let systemName: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .foregroundStyle(.secondary)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
    }
}

private struct ReadingCompletedOverlay: View {
    let palette: ReadingPalette
    let onPractice: () -> Void
    let onClose: () -> Void
    let onHome: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            GeometryReader { proxy in
                RadialGradient(
                    colors: [LingoRiseColors.primary.opacity(0.12), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 130
                )
                .frame(width: 260, height: 260)
                .position(x: proxy.size.width + 80, y: -80)

                RadialGradient(
                    colors: [LingoRiseColors.primary.opacity(0.10), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 130
                )
                .frame(width: 260, height: 260)
                .position(x: -80, y: proxy.size.height + 80)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    CircleButton(systemName: "house.fill", palette: palette, action: onHome)
                    Spacer()
                    CircleButton(systemName: "xmark", palette: palette, action: onClose)
                }
                .padding(.top, 8)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.25).delay(0.08), value: appeared)

                completedArt
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .scaleEffect(appeared ? 1 : 0.96)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.48, dampingFraction: 0.82).delay(0.05), value: appeared)

                Text(L10n.t("reading_completed_title"))
                    .font(LexendFont.font(28, weight: .bold))
                    .foregroundStyle(palette.onBackground)
                    .multilineTextAlignment(.center)
                    .padding(.top, 34)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.28).delay(0.10), value: appeared)
                Text(L10n.t("reading_completed_message"))
                    .font(LexendFont.font(17))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 12)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.28).delay(0.12), value: appeared)

                Spacer()
                    .frame(height: 82)

                Spacer(minLength: 26)

                Button(action: onPractice) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                        Text(L10n.t("reading_practice_now"))
                            .font(LexendFont.font(16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(LingoRiseColors.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.18), value: appeared)
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .onAppear {
            appeared = false
            DispatchQueue.main.async {
                appeared = true
            }
        }
    }

    private var completedArt: some View {
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
                .rotationEffect(.degrees(appeared ? 8 : -6))
                .scaleEffect(appeared ? 1.08 : 0.96)
                .offset(x: 88, y: -82)
                .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: appeared)
            Image(systemName: "star.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(hex: 0xFACC15))
                .rotationEffect(.degrees(appeared ? -7 : 7))
                .scaleEffect(appeared ? 0.94 : 1.12)
                .offset(x: 102, y: appeared ? -50 : -43)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: appeared)
            Image(systemName: "party.popper.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(hex: 0xC084FC))
                .rotationEffect(.degrees(appeared ? -9 : 5))
                .scaleEffect(appeared ? 1.07 : 0.97)
                .offset(x: -92, y: appeared ? 48 : 55)
                .animation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true), value: appeared)
        }
    }
}

private struct CircleButton: View {
    let systemName: String
    let palette: ReadingPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 40, height: 40)
                .background(palette.surfaceVariant)
                .clipShape(Circle())
        }
        .foregroundStyle(palette.onSurfaceVariant)
    }
}

private struct ReadingPalette {
    let isDark: Bool
    var background: Color { isDark ? LingoRiseColors.backgroundDark : LingoRiseColors.backgroundLight }
    var surface: Color { isDark ? LingoRiseColors.surfaceDark : LingoRiseColors.surfaceLight }
    var surfaceVariant: Color { isDark ? LingoRiseColors.surfaceVariantDark : LingoRiseColors.surfaceVariantLight }
    var onBackground: Color { isDark ? LingoRiseColors.onBackgroundDark : LingoRiseColors.onBackgroundLight }
    var onSurfaceVariant: Color { isDark ? LingoRiseColors.onSurfaceVariantDark : LingoRiseColors.onSurfaceVariantLight }
    var outlineVariant: Color { isDark ? LingoRiseColors.outlineVariantDark : LingoRiseColors.outlineVariantLight }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Reading") {
    ReadingScreen(storyId: SampleData.contents[0].id, isDailyPick: false)
        .environmentObject(AppState())
}
