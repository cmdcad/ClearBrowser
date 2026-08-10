import AVFoundation
import Foundation

struct MirrorAudioResponse: Decodable {
    let audioUrl: String?
    let url: String?
}

final class MirrorTTSService {

    private let endpoint = URL(
        string: "https://mirror-api-991075429415.us-central1.run.app/api/audio"
    )!

    func getAudio(
        from text: String,
        voice: String = "en-US-AndrewNeural"
    ) async throws -> Data {

        let body: [String: Any] = [
            "text": text,
            "voice": voice,
            "variant": "original"
        ]

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

            let message =
                String(data: data, encoding: .utf8)
                ?? "Mirror server request failed."

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