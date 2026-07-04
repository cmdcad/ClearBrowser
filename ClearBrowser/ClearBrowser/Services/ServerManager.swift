import Foundation
import AVFoundation
import WebKit

@MainActor
final class ServerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let defaultServerBaseURL = URL(string: "http://10.0.0.41:4000")!
    private var audioPlayer: AVAudioPlayer?

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var lastAudioEventMessage: String? = nil

    // Diagnostic properties for debugging audio flow
    @Published var hasExtractableContent: Bool = false
    @Published var audioRequestSent: Bool = false
    @Published var audioReceived: Bool = false

    private var displayLink: CADisplayLink?

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: .duckOthers)
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
        }
    }

    private var configuredServerBaseURLs: [URL] {
        var urls: [URL] = []

        if let configuredURL = Bundle.main.object(forInfoDictionaryKey: "ChapterAudioServiceURL") as? String,
           let url = URL(string: configuredURL) {
            urls.append(url)
        }

        if let configuredURL = Bundle.main.object(forInfoDictionaryKey: "AudioServerBaseURL") as? String,
           let url = URL(string: configuredURL) {
            urls.append(url)
        }

        if let fallbackURLs = Bundle.main.object(forInfoDictionaryKey: "ChapterAudioServiceFallbackURLs") as? [String] {
            for entry in fallbackURLs {
                if let url = URL(string: entry) {
                    urls.append(url)
                }
            }
        }

        if urls.isEmpty {
            urls.append(defaultServerBaseURL)
        }

        return urls
    }

    private var synthesizeEndpointURL: URL {
        let baseURL = configuredServerBaseURLs.first ?? defaultServerBaseURL
        return baseURL.appendingPathComponent("synthesize")
    }

    /// Extracts article text content from HTML using JavaScript injection.
    func extractArticleContent(from webView: WKWebView, notifyUser: Bool = false, completion: @escaping (String?) -> Void) {
        let javascriptCode = """
        (function() {
            let content = document.querySelector('article')?.innerText
                ?? document.querySelector('main')?.innerText
                ?? document.querySelector('[class*="article"], [class*="post-content"], [class*="entry-content"]')?.innerText
                ?? document.body?.innerText;
            return content ? content.trim() : null;
        })();
        """

        webView.evaluateJavaScript(javascriptCode) { [weak self] result, error in
            guard let self = self else { completion(nil); return }

            if let error = error {
                if notifyUser {
                    self.lastAudioEventMessage = "Unable to read page content"
                }
                self.hasExtractableContent = false
                completion(nil)
                return
            }

            if let text = result as? String, !text.isEmpty {
                if notifyUser {
                    self.lastAudioEventMessage = "Audio content found"
                }
                self.hasExtractableContent = true
                completion(text)
            } else {
                if notifyUser {
                    self.lastAudioEventMessage = "No extractable audio content"
                }
                self.hasExtractableContent = false
                completion(nil)
            }
        }
    }

    /// Sends text to the configured server and resolves the returned audio payload.
    func synthesizeSpeech(text: String, voice: String = "default", rate: Double = 1.0) async throws -> AVAudioPlayer {
        isLoading = true
        errorMessage = nil
        lastAudioEventMessage = nil
        audioRequestSent = false
        audioReceived = false
        defer { isLoading = false }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastAudioEventMessage = "No valid text to synthesize"
            throw ServerManagerError.invalidText
        }

        let endpointURL = synthesizeEndpointURL
        guard let requestURL = URL(string: endpointURL.absoluteString) else {
            lastAudioEventMessage = "Invalid audio server URL"
            throw ServerManagerError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        let payload: [String: Any] = [
            "text": text,
            "voice": voice,
            "rate": rate,
            "source": "ClearBrowser",
            "requestType": "synthesize"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        lastAudioEventMessage = "Sending audio request..."
        audioRequestSent = true

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            lastAudioEventMessage = "Audio server error"
            throw ServerManagerError.serverError
        }

        let audioData = try await resolveAudioPayload(from: data, response: httpResponse)
        lastAudioEventMessage = "Audio response received"
        audioReceived = true

        do {
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            self.audioPlayer = player
            player.prepareToPlay()
            return player
        } catch {
            print("[ServerManager] ✗ Failed to create audio player: \(error.localizedDescription)")
            throw ServerManagerError.audioPlaybackError(error.localizedDescription)
        }
    }

    private func resolveAudioPayload(from data: Data, response: HTTPURLResponse) async throws -> Data {
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let audioURLString = resolveAudioURL(from: jsonObject) {
                lastAudioEventMessage = "Downloading audio from server"
                return try await downloadAudioData(from: audioURLString)
            }

            if let base64String = jsonObject["audioData"] as? String,
               let decoded = Data(base64Encoded: base64String) {
                return decoded
            }

            if let dataString = jsonObject["data"] as? String,
               let decoded = Data(base64Encoded: dataString) {
                return decoded
            }
        }

        if let contentType = response.mimeType, contentType.contains("json") {
            throw ServerManagerError.serverError
        }

        return data
    }

    private func resolveAudioURL(from payload: [String: Any]) -> String? {
        let candidateKeys = ["audioURL", "audioUrl", "audio_url", "url", "audioFileUrl", "audioFileURL"]
        for key in candidateKeys {
            if let value = payload[key] as? String, !value.isEmpty {
                return value
            }
        }

        if let nestedAudio = payload["audio"] as? [String: Any] {
            return resolveAudioURL(from: nestedAudio)
        }

        return nil
    }

    private func downloadAudioData(from remoteString: String) async throws -> Data {
        guard let remoteURL = URL(string: remoteString) else {
            throw ServerManagerError.invalidURL
        }

        let resolvedURL: URL
        if remoteURL.scheme != nil {
            resolvedURL = remoteURL
        } else {
            resolvedURL = (configuredServerBaseURLs.first ?? defaultServerBaseURL).appendingPathComponent(remoteString)
        }

        let (downloadedData, downloadedResponse) = try await URLSession.shared.data(from: resolvedURL)
        guard let response = downloadedResponse as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw ServerManagerError.serverError
        }

        return downloadedData
    }

    // MARK: - Playback Controls

    func play(audioPlayer: AVAudioPlayer? = nil) {
        let playerToPlay = audioPlayer ?? self.audioPlayer
        playerToPlay?.play()
        isPlaying = true
        startProgressTracking()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTracking()
    }

    func resume() {
        audioPlayer?.play()
        isPlaying = true
        startProgressTracking()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopProgressTracking()
    }

    func setPlaybackRate(_ rate: Float) {
        audioPlayer?.rate = max(0.5, min(2.0, rate))
    }

    // MARK: - Private Helper Methods

    private func startProgressTracking() {
        stopProgressTracking()

        displayLink = CADisplayLink(
            target: self,
            selector: #selector(updateProgress)
        )
        displayLink?.preferredFramesPerSecond = 1
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopProgressTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateProgress() {
        if let player = audioPlayer {
            currentTime = player.currentTime
            duration = player.duration
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        stopProgressTracking()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        errorMessage = "Audio playback error: \(error?.localizedDescription ?? "Unknown error")"
        isPlaying = false
    }
}

typealias AudioVixService = ServerManager
typealias AudioVixError = ServerManagerError

enum ServerManagerError: Error, LocalizedError {
    case invalidURL
    case serverError
    case audioPlaybackError(String)
    case invalidText

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid audio server URL"
        case .serverError:
            return "Audio server error - please check the server connection"
        case .audioPlaybackError(let message):
            return "Audio playback error: \(message)"
        case .invalidText:
            return "No valid text content to read"
        }
    }
}
