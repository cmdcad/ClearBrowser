import Foundation
import AVFoundation
import WebKit
import UIKit

@MainActor
final class ServerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let mirrorService = MirrorTTSService()

    private var audioPlayer: AVAudioPlayer?
    private(set) var lastAudioData: Data? = nil

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var lastAudioEventMessage: String? = nil

    private func triggerHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // Diagnostic properties for debugging audio flow
    @Published var hasExtractableContent: Bool = false
    @Published var audioRequestSent: Bool = false
    @Published var audioReceived: Bool = false

    private var displayLink: CADisplayLink?

    // Audio caching
    private var audioCache: [String: Data] = [:]
    private let maxCacheSize = 3

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

    // MARK: - Audio Caching

    private func generateCacheKey(text: String, voice: String) -> String {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedText)_\(voice)".hashValue.description
    }

    private func cacheAudio(_ key: String, _ data: Data) {
        // Implement LRU cache: remove oldest if over limit
        if audioCache.count >= maxCacheSize {
            if let oldestKey = audioCache.keys.first {
                audioCache.removeValue(forKey: oldestKey)
            }
        }
        audioCache[key] = data
    }

    /// Extracts article text content from HTML using JavaScript injection.
    func extractArticleContent(from webView: WKWebView, notifyUser: Bool = false, completion: @escaping (String?) -> Void) {
        let javascriptCode = """
        (function() {
            // Remove noise elements from body to keep text clean
            const noiseSelectors = [
                'nav', 'header', 'footer', 'aside', 'script', 'style', 'noscript', 'iframe',
                '.nav', '.navbar', '.footer', '.sidebar', '.menu', '.ads', '.comments', '.comment-list',
                '#comments', '#sidebar', '#header', '#footer', '.advertisement', '.social-share',
                '.cookie-banner', '.newsletter-signup', '.related-posts'
            ];
            
            // Clone document body to mutate safely without affecting the UI
            const bodyClone = document.body.cloneNode(true);
            
            // Remove noise elements from clone
            noiseSelectors.forEach(selector => {
                bodyClone.querySelectorAll(selector).forEach(el => el.remove());
            });

            // Try to find the primary article container in the cleaned clone
            let mainContent = bodyClone.querySelector('article') 
                || bodyClone.querySelector('main')
                || bodyClone.querySelector('[role="main"]')
                || bodyClone.querySelector('[class*="article-content"]')
                || bodyClone.querySelector('[class*="post-content"]')
                || bodyClone.querySelector('[class*="entry-content"]');

            if (mainContent) {
                let text = (mainContent.innerText || mainContent.textContent || "").trim();
                if (text.length > 100) {
                    return text;
                }
            }

            // Try overlay or dialog content before falling back to body paragraphs.
            const overlaySelectors = [
                'dialog',
                '[role="dialog"]',
                '[role="alertdialog"]',
                '.modal',
                '.popup',
                '.overlay',
                '.popover',
                '.drawer',
                '.sheet'
            ];
            for (const selector of overlaySelectors) {
                const overlay = bodyClone.querySelector(selector);
                if (overlay) {
                    const text = (overlay.innerText || overlay.textContent || '').trim();
                    if (text.length > 40) {
                        return text;
                    }
                }
            }

            // Fallback: Gather all paragraph text blocks that have reasonable length
            const paragraphs = bodyClone.querySelectorAll('p');
            let paragraphTexts = [];
            paragraphs.forEach(p => {
                let text = (p.innerText || p.textContent || '').trim();
                if (text.length > 20) {
                    paragraphTexts.push(text);
                }
            });

            if (paragraphTexts.length > 0) {
                return paragraphTexts.join('\\n\\n');
            }

            // Final fallback to entire cleaned body
            return (bodyClone.innerText || bodyClone.textContent || "").trim();
        })();
        """

        webView.evaluateJavaScript(javascriptCode) { [weak self] result, error in
            guard let self = self else { completion(nil); return }

            if error != nil {
                if notifyUser {
                    self.lastAudioEventMessage = "Couldn't read the page"
                    self.triggerHapticFeedback()
                }
                self.hasExtractableContent = false
                completion(nil)
                return
            }

            if let text = result as? String, !text.isEmpty {
                if notifyUser {
                    self.lastAudioEventMessage = "Found text to read"
                    self.triggerHapticFeedback()
                }
                self.hasExtractableContent = true
                completion(text)
            } else {
                if notifyUser {
                    self.lastAudioEventMessage = "No text found on this page"
                    self.triggerHapticFeedback()
                }
                self.hasExtractableContent = false
                completion(nil)
            }
        }
    }

    /// Sends text to the configured server and resolves the returned audio payload.
    func synthesizeSpeech(text: String, voice: String = "Eric", rate: Double = 1.0) async throws -> AVAudioPlayer {
        isLoading = true
        errorMessage = nil
        lastAudioEventMessage = "Starting to read..."
        triggerHapticFeedback()
        audioRequestSent = false

        // Check cache first
        let cacheKey = generateCacheKey(text: text, voice: voice)
        if let cachedAudio = audioCache[cacheKey] {
            lastAudioEventMessage = "Using cached audio"
            triggerHapticFeedback()
            audioReceived = true
            let player = try AVAudioPlayer(data: cachedAudio)
            player.delegate = self
            player.enableRate = true
            player.rate = Float(rate)
            self.audioPlayer = player
            self.lastAudioData = cachedAudio
            player.prepareToPlay()
            currentTime = 0
            duration = player.duration
            isLoading = false
            return player
        }
        audioReceived = false
        defer { isLoading = false }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastAudioEventMessage = "Nothing to read here"
            triggerHapticFeedback()
            throw ServerManagerError.invalidText
        }

        lastAudioEventMessage = "Getting text ready for reading..."
        triggerHapticFeedback()
        audioRequestSent = true

        // Use mirror service for audio generation
        lastAudioEventMessage = "Generating audio..."
        triggerHapticFeedback()

        do {
            let audioData = try await mirrorService.getAudio(from: text, voice: voice)

            lastAudioEventMessage = "Got the audio!"
            triggerHapticFeedback()
            audioReceived = true
            self.lastAudioData = audioData

            // Cache the audio
            cacheAudio(cacheKey, audioData)

            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            player.enableRate = true
            player.rate = Float(rate)
            self.audioPlayer = player
            player.prepareToPlay()
            currentTime = 0
            duration = player.duration

            return player
        } catch {
            lastAudioEventMessage = "Failed to generate audio"
            triggerHapticFeedback()
            throw ServerManagerError.serverError(message: "Audio generation failed: \(error.localizedDescription)")
        }
                            baseURL: baseURL,
                            endpointURL: endpointURL,
    }

    // MARK: - Playback Controls

    func play(audioPlayer: AVAudioPlayer? = nil) {
        let playerToPlay = audioPlayer ?? self.audioPlayer
        guard let player = playerToPlay else {
            errorMessage = "No audio available to play"
            isPlaying = false
            return
        }
        player.play()
        isPlaying = true
        startProgressTracking()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTracking()
    }

    func resume() {
        guard audioPlayer != nil else {
            errorMessage = "No audio available to resume"
            isPlaying = false
            return
        }
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

func preparePlayer(with audioData: Data) throws {
        let player = try AVAudioPlayer(data: audioData)
        player.delegate = self
        player.enableRate = true
        self.audioPlayer = player
        self.lastAudioData = audioData
        player.prepareToPlay()
        currentTime = 0
        duration = player.duration
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

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            currentTime = 0
            stopProgressTracking()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            errorMessage = "Audio playback error: \(error?.localizedDescription ?? "Unknown error")"
            isPlaying = false
        }
    }
}

enum ServerManagerError: Error, LocalizedError {
    case invalidURL
    case serverError(message: String = "Audio server error - please check the server connection")
    case audioPlaybackError(String)
    case invalidText
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server address doesn't look right"
        case .serverError(let message):
            return message
        case .audioPlaybackError(let message):
            return "Couldn't play the audio: \(message)"
        case .invalidText:
            return "There's no text to read"
        case .networkError(let message):
            return "Connection problem: \(message)"
        }
    }
}
