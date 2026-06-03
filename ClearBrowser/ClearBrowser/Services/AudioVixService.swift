import Foundation
import AVFoundation
import WebKit

final class AudioVixService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let audioVixBaseURL = "http://10.0.0.152:4000"
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
    
    /// Extracts article text content from HTML using JavaScript injection
    func extractArticleContent(from webView: WKWebView, notifyUser: Bool = false, completion: @escaping (String?) -> Void) {
        let javascriptCode = """
        (function() {
            // Try to find article content using common selectors
            let content = null;
            
            // Check for article tags first
            const article = document.querySelector('article');
            if (article) {
                content = article.innerText;
            }
            
            // Fallback to main content areas
            if (!content) {
                const main = document.querySelector('main');
                if (main) content = main.innerText;
            }
            
            // Fallback to specific article class patterns
            if (!content) {
                const articleDiv = document.querySelector('[class*="article"], [class*="post-content"], [class*="entry-content"]');
                if (articleDiv) content = articleDiv.innerText;
            }
            
            // Final fallback: get body text
            if (!content) {
                content = document.body.innerText;
            }
            
            // Clean up whitespace
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
    
    /// Sends text to the audioVix server for speech synthesis
    func synthesizeSpeech(text: String) async throws -> AVAudioPlayer {
        isLoading = true
        errorMessage = nil
        lastAudioEventMessage = nil
        audioRequestSent = false
        audioReceived = false
        defer { isLoading = false }
        
        guard let url = URL(string: "\(audioVixBaseURL)/synthesize") else {
            lastAudioEventMessage = "Invalid audio server URL"
            throw AudioVixError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "text": text,
            "voice": "default",
            "rate": 1.0
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        lastAudioEventMessage = "Sending audio request..."
        audioRequestSent = true
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            lastAudioEventMessage = "Audio server error"
            throw AudioVixError.serverError
        }
        
        lastAudioEventMessage = "Audio received"
        audioReceived = true
        
        do {
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
            player.delegate = self
            self.audioPlayer = player
            return player
        } catch {
            print("[AudioVix] ✗ Failed to create audio player: \(error.localizedDescription)")
            throw AudioVixError.audioPlaybackError(error.localizedDescription)
        }
    }
    
    /// Plays the synthesized audio
    func play(audioPlayer: AVAudioPlayer? = nil) {
        let playerToPlay = audioPlayer ?? self.audioPlayer
        playerToPlay?.play()
        isPlaying = true
        startProgressTracking()
    }
    
    /// Pauses the current playback
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTracking()
    }
    
    /// Resumes playback
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        startProgressTracking()
    }
    
    /// Stops playback and resets
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopProgressTracking()
    }
    
    /// Updates the playback rate
    func setPlaybackRate(_ rate: Float) {
        audioPlayer?.rate = max(0.5, min(2.0, rate)) // Clamp between 0.5x and 2.0x
    }
    
    // MARK: - Private Helper Methods
    
    private func startProgressTracking() {
        stopProgressTracking()
        
        displayLink = CADisplayLink(
            target: self,
            selector: #selector(updateProgress)
        )
        displayLink?.preferredFramesPerSecond = 1 // Update once per second
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

enum AudioVixError: Error, LocalizedError {
    case invalidURL
    case serverError
    case audioPlaybackError(String)
    case invalidText
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid audioVix server URL"
        case .serverError:
            return "audioVix server error - please check connection"
        case .audioPlaybackError(let message):
            return "Audio playback error: \(message)"
        case .invalidText:
            return "No valid text content to read"
        }
    }
}
