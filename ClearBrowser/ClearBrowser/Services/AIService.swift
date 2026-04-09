import Foundation

// Minimal OpenAI chat client using the Chat Completions endpoint.
final class AIService {
    private let keyAccount = "openAIKey"
    private let serviceName = Bundle.main.bundleIdentifier ?? "ClearBrowser"

    func answer(query: String) async -> String {
        guard let apiKey = KeychainHelper.standard.read(service: serviceName, account: keyAccount), !apiKey.isEmpty else {
            return "OpenAI API key not configured. Add your key in Settings to enable the AI assistant."
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [["role": "user", "content": query]],
            "max_tokens": 500,
            "temperature": 0.2
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, response) = try await URLSession.shared.data(for: req)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let errText = String(data: data, encoding: .utf8) ?? "Unknown server error"
                return "AI service error: \(errText)"
            }

            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            if let content = decoded.choices.first?.message.content {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                return "No answer returned by AI."
            }
        } catch {
            return "AI request failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Response Models
private struct ChatCompletionResponse: Decodable {
    let id: String
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let index: Int
    let message: ChatMessage
}

private struct ChatMessage: Decodable {
    let role: String
    let content: String
}

