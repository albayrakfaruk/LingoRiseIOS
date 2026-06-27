import AVFoundation
import Combine
import CryptoKit
import Foundation

@MainActor
final class PracticeAudioController: ObservableObject {
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
