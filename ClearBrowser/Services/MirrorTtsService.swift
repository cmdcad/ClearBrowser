import AVFoundation
import Foundation

struct MirrorAudioResponse: Decodable {
    let audioUrl: String?
    let url: String?
}

final class MirrorTTSService {

    private let localBaseURL = URL(string: "http://10.0.0.41:4000")!
    private let cloudEndpoint = URL(
        string: "https://mirror-api-991075429415.us-central1.run.app/api/audio"
    )!

    private struct ProbeResponse: Decodable {
        let error: String?
        let detail: String?
    }

    /// A bounded HTTP check verifies the service, rather than just the host.
    private func preferredEndpoint() async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        // The local AudioVIX server has no /health route. Empty input safely
        // checks the real audio route without generating or storing audio.
        var request = URLRequest(url: localBaseURL.appendingPathComponent("api/audio"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"text\":\"\"}".utf8)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse,
               http.statusCode == 400,
               let probe = try? JSONDecoder().decode(ProbeResponse.self, from: data),
               ["text or verses is required", "text is required"].contains(probe.error ?? probe.detail ?? "") {
                return localBaseURL.appendingPathComponent("api/audio")
            }
        } catch {
            try Task.checkCancellation()
        }
        return cloudEndpoint
    }

    func getAudio(
        from text: String,
        voice: String = "en-US-AndrewNeural"
    ) async throws -> Data {

        let body: [String: Any] = [
            "text": text,
            "voice": voice,
            "variant": "original"
        ]

        let endpoint = try await preferredEndpoint()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.timeoutInterval = 180

        request.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )

        // Send text to mirror server
        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {

            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let server = endpoint.host == localBaseURL.host ? "Local" : "Cloud"
            let message = status == 404
                ? "\(server) audio service was not found (404). Check its server address and /api/audio route."
                : "\(server) audio service could not generate audio (HTTP \(status)). Please try again."

            throw NSError(
                domain: "MirrorTTSService",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [
                    NSLocalizedDescriptionKey: message
                ]
            )
        }

        // Extract generated audio URL
        let result = try JSONDecoder().decode(
            MirrorAudioResponse.self,
            from: data
        )

        guard let audioURLString = result.audioUrl ?? result.url,
              let audioURL = URL(string: audioURLString) else {

            throw NSError(
                domain: "MirrorTTSService",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Mirror server did not return an audio URL."
                ]
            )
        }

        // Download generated audio
        let (audioData, audioResponse) =
            try await URLSession.shared.data(from: audioURL)

        guard let audioHTTP = audioResponse as? HTTPURLResponse,
              (200...299).contains(audioHTTP.statusCode) else {

            throw NSError(
                domain: "MirrorTTSService",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not download generated audio."
                ]
            )
        }

        return audioData
    }
}



final class AudioPlayerService {
    private var player: AVAudioPlayer?

    func play(data: Data) throws {
        try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio
        )

        try AVAudioSession.sharedInstance().setActive(true)

        player = try AVAudioPlayer(data: data)
        player?.prepareToPlay()
        player?.play()
    }
}


/*
Usage:
let service = MirrorAudioService()

let audioData = try await service.synthesize(
    text: "In the beginning God created the heaven and the earth."
)

let player = AudioPlayerService()
try player.play(data: audioData)


or 

let service = MirrorTTSService()

let audio = try await service.getAudio(
    from: extractedDocumentText
)
*/
