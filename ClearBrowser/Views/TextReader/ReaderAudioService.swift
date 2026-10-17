import Foundation

/// AudioVix's /api/audio contract: inline timings or timing URLs, plus async jobs.
struct ReaderAudioService {
    private struct Response: Decodable {
        var status: String?
        var statusUrl: String?
        var error: String?
        var message: String?
        var audioUrl: String?
        var url: String?
        var timings: ReaderTimings?
        var wordTimings: [ReaderTiming]?
        var sentenceTimings: [ReaderTiming]?
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "TextReader", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func checked(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Self.failure("Audio service request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)). Please retry.")
        }
        return data
    }

    func generate(text: String, audioURL: URL, timingURL: URL) async throws -> ReaderTimings {
        let local = Bundle.main.object(forInfoDictionaryKey: "AudioServerBaseURL") as? String ?? "http://10.0.0.41:4000"
        let cloud = URL(string: "https://mirror-api-991075429415.us-central1.run.app/api/audio")!
        var endpoint = cloud
        if let base = URL(string: local) {
            var health = URLRequest(url: base.appendingPathComponent("health"))
            health.timeoutInterval = 5
            if (try? await checked(health)) != nil {
                endpoint = base.appendingPathComponent("api/audio")
            }
        }
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("respond-async", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text, "voice": "en-US-AndrewNeural", "variant": "original", "version": "AudioVix",
            "verses": ReaderText.sentences(text).enumerated().map { ["verse": String($0.offset + 1), "text": $0.element] }
        ])
        var data = try await checked(request)
        var response = try JSONDecoder().decode(Response.self, from: data)
        var pendingURL: URL?
        do {
            for _ in 0..<440 {
                let status = response.status?.lowercased() ?? "done"
                if ["failed", "cancelled"].contains(status) {
                    throw Self.failure(response.error ?? response.message ?? "Audio generation failed.")
                }
                guard ["queued", "processing", "cancelling"].contains(status) else { break }
                if let link = response.statusUrl { pendingURL = URL(string: link, relativeTo: endpoint)?.absoluteURL }
                guard let pollURL = pendingURL else { throw Self.failure("Audio job is missing its status URL.") }
                try await Task.sleep(nanoseconds: 1_500_000_000)
                var poll = URLRequest(url: pollURL)
                poll.timeoutInterval = 30
                data = try await checked(poll)
                response = try JSONDecoder().decode(Response.self, from: data)
            }
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled, let pendingURL {
                var cancel = URLRequest(url: pendingURL.appendingPathComponent("cancel"))
                cancel.httpMethod = "POST"
                cancel.timeoutInterval = 5
                _ = try? await URLSession.shared.data(for: cancel)
            }
            throw error
        }
        guard let link = response.audioUrl ?? response.url,
              let remote = URL(string: link, relativeTo: endpoint)?.absoluteURL else {
            throw Self.failure("Audio generation timed out or returned no audio URL.")
        }
        var timings = response.timings ?? ReaderTimings()
        timings.wordTimings = response.wordTimings ?? timings.wordTimings
        timings.sentenceTimings = response.sentenceTimings ?? timings.sentenceTimings ?? timings.verseTimings
        if (timings.sentenceTimings ?? []).isEmpty,
           let link = timings.allUrl ?? timings.sentencesUrl,
           let remoteTiming = URL(string: link, relativeTo: endpoint)?.absoluteURL {
            // Timing failure must not prevent listening to successfully generated audio.
            if let fetched = try? await checked(URLRequest(url: remoteTiming)),
               let decoded = try? JSONDecoder().decode(ReaderTimings.self, from: fetched) {
                timings = decoded
                timings.sentenceTimings = decoded.sentenceTimings ?? decoded.verseTimings
            }
        }
        let audio = try await checked(URLRequest(url: remote))
        try Task.checkCancellation()
        try audio.write(to: audioURL, options: .atomic)
        try JSONEncoder().encode(timings).write(to: timingURL, options: .atomic)
        return timings
    }
}
