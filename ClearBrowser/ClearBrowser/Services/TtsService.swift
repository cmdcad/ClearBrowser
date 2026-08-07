//
//  TtsService.swift
//  ClearBrowser
//
//  Created by tosinMac8 on 8/6/26.
//

import Foundation



final class TTSService {
    private let baseURL: URL

    init(baseURL: URL = URL(string: "https://mike-tts.fly.dev")!) {
        self.baseURL = baseURL
    }

    /// Sends verses (one per array element) + voice choice, gets back the
    /// combined audio and per-verse timings in one response.
    func synthesize(verses: [String], voice: String = "lessac") async throws -> (audio: Data, timings: [VerseTiming]) {
        var request = URLRequest(url: baseURL.appendingPathComponent("tts"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Long chapters (e.g. Psalm 119) can take a couple minutes to
        // synthesize + align server-side — give this real headroom.
        request.timeoutInterval = 360

        // Server splits on "\n" to recover verse boundaries — same contract
        // as the WinUI client.
        let text = verses.joined(separator: "\n")
        request.httpBody = formURLEncodedBody(fields: [
            "text": text,
            "voice": voice,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TTSError.badResponse
        }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
                ?? String(data: data, encoding: .utf8)
                ?? "Server returned \(http.statusCode)"
            throw TTSError.serverError(message)
        }

        let decoded = try JSONDecoder().decode(TTSResponse.self, from: data)
        guard let audioData = Data(base64Encoded: decoded.audio_base64) else {
            throw TTSError.badResponse
        }
        return (audioData, decoded.verses)
    }

    /// Proper x-www-form-urlencoded percent-encoding (space -> "+", not "%20"),
    /// since some form parsers are stricter about this than others.
    private func formURLEncodedBody(fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._* ")

        let pairs = fields.map { key, value -> String in
            let encodedValue = value
                .addingPercentEncoding(withAllowedCharacters: allowed)?
                .replacingOccurrences(of: " ", with: "+") ?? value
            return "\(key)=\(encodedValue)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}



/// One verse's position within the combined audio track, in milliseconds.
struct VerseTiming: Codable {
    let index: Int
    let start_ms: Int
    let end_ms: Int
}

/// Full JSON body returned by POST /tts
struct TTSResponse: Codable {
    let audio_base64: String
    let audio_format: String
    let voice: String
    let verses: [VerseTiming]
}

enum TTSError: LocalizedError {
    case badResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Could not decode audio from server response."
        case .serverError(let message):
            return message
        }
    }
}
