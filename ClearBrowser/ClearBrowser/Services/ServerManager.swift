import Foundation
import AVFoundation
import WebKit

@MainActor
final class ServerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let defaultServerBaseURL = URL(string: "http://10.0.0.41:4000")!
    private let fallbackServerBaseURLs: [URL] = [
        URL(string: "https://mirror-api-991075429415.us-central1.run.app")!
    ]

    private var audioPlayer: AVAudioPlayer?
    private(set) var lastAudioData: Data? = nil

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

    private var configuredServerBaseURLs: [URL] {
        var urls: [URL] = []


        if let configuredURL = Bundle.main.object(forInfoDictionaryKey: "AudioServerBaseURL") as? String,
           let url = URL(string: configuredURL) {
            urls.append(url)
        }

        if let fallbackURLs = Bundle.main.object(forInfoDictionaryKey: "AudioServerFallbackURLs") as? [String] {
            for entry in fallbackURLs {
                if let url = URL(string: entry) {
                    urls.append(url)
                }
            }
        }

        for fallback in fallbackServerBaseURLs where !urls.contains(fallback) {
            urls.append(fallback)
        }

        if urls.isEmpty {
            urls.append(defaultServerBaseURL)
        }

        return urls
    }

    private func synthesizeEndpointCandidates(for baseURL: URL) -> [URL] {
        let urlString = baseURL.absoluteString.lowercased()

        // Mirror service only uses /tts endpoint (no timings)
        if urlString.contains("mirror-api") {
            return [baseURL.appendingPathComponent("tts")]
        }

        // Other servers use /api/audio
        return [baseURL.appendingPathComponent("api/audio")]
    }
    
    private func getFriendlyServerName(for url: URL) -> String {
        let urlString = url.absoluteString.lowercased()

        if urlString.contains("10.0.0.41") || urlString.contains("localhost") {
            return "home server"
        } else if urlString.contains("mirror-api") {
            return "cloud server"
        } else if urlString.contains("mike-tts") || urlString.contains("fly.dev") {
            return "cloud backup"
        } else {
            return "server"
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
                }
                self.hasExtractableContent = false
                completion(nil)
                return
            }

            if let text = result as? String, !text.isEmpty {
                if notifyUser {
                    self.lastAudioEventMessage = "Found text to read"
                }
                self.hasExtractableContent = true
                completion(text)
            } else {
                if notifyUser {
                    self.lastAudioEventMessage = "No text found on this page"
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
        audioRequestSent = false

        // Check cache first
        let cacheKey = generateCacheKey(text: text, voice: voice)
        if let cachedAudio = audioCache[cacheKey] {
            lastAudioEventMessage = "Using cached audio"
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
            throw ServerManagerError.invalidText
        }

        lastAudioEventMessage = "Getting text ready for reading..."
        audioRequestSent = true

        let payload: [String: Any] = [
            "text": text,
            "voice": voice,
            "rate": rate,
            "source": "ClearBrowser",
            "requestType": "synthesize"
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        struct AttemptError {
            let baseURL: URL
            let endpointURL: URL
            let statusCode: Int?
            let error: Error
        }

        var attempts: [AttemptError] = []

        for baseURL in configuredServerBaseURLs {
            let serverName = getFriendlyServerName(for: baseURL)
            lastAudioEventMessage = "Trying \(serverName)..."

            // Give servers up to 3 minutes to complete audio generation
            let timeout: TimeInterval = 180

            for endpointURL in synthesizeEndpointCandidates(for: baseURL) {
                do {
                    let request = try makeRequest(to: endpointURL, body: payloadData, text: text, voice: voice, timeout: timeout)
                    lastAudioEventMessage = "Asking \(serverName) to read this..."
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        let err = ServerManagerError.serverError(message: "No HTTP response from server")
                        attempts.append(AttemptError(baseURL: baseURL, endpointURL: endpointURL, statusCode: nil, error: err))
                        continue
                    }

                    if (200..<300).contains(httpResponse.statusCode) {
                        // Mirror service processes synchronously, no separate acknowledgment
                        if serverName == "cloud server" {
                            lastAudioEventMessage = "\(serverName) is generating audio..."
                        } else {
                            // Home server acknowledges receipt separately
                            lastAudioEventMessage = "\(serverName) accepted the request..."
                        }

                        let audioData = try await resolveAudioPayload(from: data, response: httpResponse)
                        lastAudioEventMessage = "Got the audio from \(serverName)!"
                        audioReceived = true
                        self.lastAudioData = audioData

                        // Cache the audio
                        let cacheKey = generateCacheKey(text: text, voice: voice)
                        cacheAudio(cacheKey, audioData)

                        let player = try AVAudioPlayer(data: audioData)
                        player.delegate = self
                        self.audioPlayer = player
                        player.prepareToPlay()
                        return player
                    }

                    let responseBody = String(data: data, encoding: .utf8) ?? ""
                    let detail = responseBody.isEmpty ? "empty response body" : responseBody
                    let serverErr = ServerManagerError.serverError(message: "Status \(httpResponse.statusCode) from \(endpointURL.absoluteString): \(detail)")
                    attempts.append(AttemptError(baseURL: baseURL, endpointURL: endpointURL, statusCode: httpResponse.statusCode, error: serverErr))
                } catch let error as ServerManagerError {
                    attempts.append(AttemptError(baseURL: baseURL, endpointURL: endpointURL, statusCode: nil, error: error))
                } catch let error as URLError {
                    lastAudioEventMessage = "\(serverName) didn't respond, trying next option..."
                    let netErr = ServerManagerError.networkError("Could not connect to server: \(error.localizedDescription)")
                    attempts.append(AttemptError(baseURL: baseURL, endpointURL: endpointURL, statusCode: nil, error: netErr))
                } catch let error {
                    lastAudioEventMessage = "\(serverName) had an issue, trying next option..."
                    let netErr = ServerManagerError.networkError(error.localizedDescription)
                    attempts.append(AttemptError(baseURL: baseURL, endpointURL: endpointURL, statusCode: nil, error: netErr))
                }
            }
        }

        if !attempts.isEmpty {
            // Try cloud server fallback
            do {
                lastAudioEventMessage = "Trying cloud server..."
                let player = try await fallbackToTTSService(text: text, voice: voice, rate: rate)
                audioReceived = true
                return player
            } catch {
                // If cloud server also fails, throw the best original error
                let primaryURL = configuredServerBaseURLs.first

                func rank(_ attempt: AttemptError) -> Int {
                    let isPrimary = (primaryURL != nil && attempt.baseURL == primaryURL)
                    let scoreMultiplier = isPrimary ? 10 : 1

                    if let statusCode = attempt.statusCode {
                        if statusCode == 404 || statusCode == 405 {
                            return 5 * scoreMultiplier
                        } else {
                            return 10 * scoreMultiplier
                        }
                    } else {
                        return 2 * scoreMultiplier
                    }
                }
                
                var bestAttempt = attempts[0]
                var bestRank = rank(bestAttempt)
                for attempt in attempts.dropFirst() {
                    let r = rank(attempt)
                    if r > bestRank {
                        bestAttempt = attempt
                        bestRank = r
                    }
                }
                
                throw bestAttempt.error
            }
        }


        throw ServerManagerError.serverError(message: "No audio server endpoint responded")
    }

    private func makeRequest(to endpointURL: URL, body: Data, text: String, voice: String, timeout: TimeInterval) throws -> URLRequest {
        guard let requestURL = URL(string: endpointURL.absoluteString) else {
            throw ServerManagerError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout

        // Check if this is the simple /tts endpoint (mirror service)
        if requestURL.path.hasSuffix("/tts") {
            // Simple form data for /tts endpoint
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let formData = "text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)&voice=\(voice.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? voice)"
            request.httpBody = formData.data(using: .utf8)
        } else {
            // JSON for /api/audio endpoint
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = body
        }

        return request
    }

    private func resolveAudioPayload(from data: Data, response: HTTPURLResponse) async throws -> Data {
        // If response is direct audio (not JSON), cache and return it
        if let contentType = response.mimeType, contentType.contains("audio") {
            lastAudioEventMessage = "Received audio file"
            return data
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Normalize server response to standard format
            guard let normalizedResponse = normalizeServerResponse(jsonObject) else {
                // normalizeServerResponse returned nil, indicating async job response
                throw ServerManagerError.serverError(message: "Server returned async job ID but polling is disabled")
            }

            // Handle direct audio URL response (sync response)
            if let audioURLString = resolveAudioURL(from: normalizedResponse) {
                lastAudioEventMessage = "Downloading the audio file..."
                let audioData = try await downloadAudioData(from: audioURLString)
                return audioData
            }

            if let base64String = normalizedResponse["audioData"] as? String,
               let decoded = Data(base64Encoded: base64String) {
                return decoded
            }

            if let dataString = normalizedResponse["data"] as? String,
               let decoded = Data(base64Encoded: dataString) {
                return decoded
            }

            if let status = normalizedResponse["status"] as? String, status.lowercased() != "ok" && status.lowercased() != "success" {
                throw ServerManagerError.serverError(message: "Server status: \(status)")
            }

            // If we got here, the response is JSON but we couldn't extract audio
            throw ServerManagerError.serverError(message: "Server returned JSON but no audio data found")
        }

        if let contentType = response.mimeType, contentType.contains("json") {
            throw ServerManagerError.serverError(message: "Server returned JSON instead of audio")
        }

        return data
    }

    /// Normalize different server response formats to a standard format
    /// Returns nil if the response indicates an async job (polling required)
    private func normalizeServerResponse(_ response: [String: Any]) -> [String: Any]? {
        var normalized = response

        // Handle async job responses - these should fail immediately since we removed polling
        if response["jobId"] as? String != nil || response["id"] as? String != nil {
            // Check if this is a job ID response (async) vs artifact ID (sync)
            let urlString = response["audioUrl"] as? String ?? response["url"] as? String ?? ""
            if urlString.isEmpty {
                // This is an async job response, not a sync response
                lastAudioEventMessage = "Server returned async job ID but polling is disabled"
                return nil // Indicate this response should be rejected
            }
        }

        // Ensure standard field names are present
        if response["audioUrl"] == nil, let url = response["url"] as? String {
            normalized["audioUrl"] = url
        }
        if response["url"] == nil, let audioUrl = response["audioUrl"] as? String {
            normalized["url"] = audioUrl
        }

        // Normalize timings structure
        if var timings = response["timings"] as? [String: Any] {
            // Ensure all timing types are present
            if timings["wordTimings"] == nil, let words = timings["words"] as? [Any] {
                timings["wordTimings"] = words
            }
            if timings["verseTimings"] == nil, let verses = timings["verses"] as? [Any] {
                timings["verseTimings"] = verses
            }
            if timings["sentenceTimings"] == nil, let sentences = timings["sentences"] as? [Any] {
                timings["sentenceTimings"] = sentences
            }
            normalized["timings"] = timings
        }

        // Normalize counts structure
        if var counts = response["counts"] as? [String: Any] {
            // Ensure standard count fields
            if counts["words"] == nil, let wordCount = response["wordCount"] as? Int {
                counts["words"] = wordCount
            }
            if counts["verses"] == nil, let verseCount = response["verseCount"] as? Int {
                counts["verses"] = verseCount
            }
            if counts["sentences"] == nil, let sentenceCount = response["sentenceCount"] as? Int {
                counts["sentences"] = sentenceCount
            }
            normalized["counts"] = counts
        }

        return normalized
    }
    }

    private func resolveAudioURL(from payload: [String: Any]) -> String? {
        let candidateKeys = ["audioURL", "audioUrl", "audio_url", "audioFileUrl", "audioFileURL", "audioPath", "fileURL", "url", "audio"]
        for key in candidateKeys {
            if let value = payload[key] as? String, !value.isEmpty {
                return value
            }
        }

        for key in payload.keys {
            if let nested = payload[key] as? [String: Any], let resolved = resolveAudioURL(from: nested) {
                return resolved
            }
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
            throw ServerManagerError.serverError(message: "Audio download failed")
        }

        return downloadedData
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


extension ServerManager {

    func fallbackToTTSService(text: String, voice: String, rate: Double) async throws -> AVAudioPlayer {
        let tts = TTSService(baseURL: URL(string: "https://mirror-api-991075429415.us-central1.run.app")!)
        let verses = [text]   // ServerManager sends whole text, not verse-by-verse

        lastAudioEventMessage = "Trying cloud server..."
        let (audioData, _) = try await tts.synthesize(verses: verses, voice: voice)

        let player = try AVAudioPlayer(data: audioData)
        player.delegate = self
        self.audioPlayer = player
        self.lastAudioData = audioData
        player.prepareToPlay()
        return player
    }
}

typealias AudioVixService = ServerManager
typealias AudioVixError = ServerManagerError

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
