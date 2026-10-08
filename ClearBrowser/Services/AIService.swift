import Foundation
import CryptoKit
import CommonCrypto

// Minimal OpenAI chat client using the Chat Completions endpoint.
final class AIService {
    func answer(query: String, apiKey: String) async -> String {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return "OpenAI API key not configured. Add your key in Settings to enable the AI assistant."
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

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
                let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedContent.isEmpty ? "AI returned an empty response." : trimmedContent
            } else {
                return "No answer returned by AI."
            }
        } catch {
            return "AI request failed: \(error.localizedDescription)"
        }
    }
}

struct EncryptedAIKey {
    let salt: String
    let ciphertext: String
}

enum AIKeyEncryption {
    private static let iterations: UInt32 = 600_000
    private static let keyLength = 32

    static func normalizedPassphrase(_ phrase: String) -> String {
        phrase.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    static func isValidPassphrase(_ phrase: String) -> Bool {
        normalizedPassphrase(phrase).split(separator: " ").count == 4
    }

    static func encrypt(_ apiKey: String, passphrase: String) throws -> EncryptedAIKey {
        guard isValidPassphrase(passphrase) else {
            throw AIKeyEncryptionError.invalidPassphrase
        }

        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let symmetricKey = try deriveKey(passphrase: passphrase, salt: salt)
        let sealedBox = try AES.GCM.seal(Data(apiKey.utf8), using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw AIKeyEncryptionError.encryptionFailed
        }

        return EncryptedAIKey(salt: salt.base64EncodedString(), ciphertext: combined.base64EncodedString())
    }

    static func decrypt(_ encryptedKey: EncryptedAIKey, passphrase: String) throws -> String {
        guard isValidPassphrase(passphrase),
              let salt = Data(base64Encoded: encryptedKey.salt),
              let combined = Data(base64Encoded: encryptedKey.ciphertext) else {
            throw AIKeyEncryptionError.invalidEncryptedData
        }

        let symmetricKey = try deriveKey(passphrase: passphrase, salt: salt)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)
        guard let apiKey = String(data: plaintext, encoding: .utf8) else {
            throw AIKeyEncryptionError.invalidEncryptedData
        }
        return apiKey
    }

    private static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        let password = Data(normalizedPassphrase(passphrase).utf8)
        var derivedKey = Data(count: keyLength)
        let result = derivedKey.withUnsafeMutableBytes { keyBuffer in
            password.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        keyBuffer.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard result == kCCSuccess else {
            throw AIKeyEncryptionError.keyDerivationFailed
        }
        return SymmetricKey(data: derivedKey)
    }
}

enum AIKeyEncryptionError: LocalizedError {
    case invalidPassphrase
    case invalidEncryptedData
    case encryptionFailed
    case keyDerivationFailed
    case notSignedIn
    case keychainStorageFailed

    var errorDescription: String? {
        switch self {
        case .invalidPassphrase:
            return "Enter a recovery passphrase containing exactly four words."
        case .invalidEncryptedData:
            return "The saved AI key data is invalid or the recovery passphrase is incorrect."
        case .encryptionFailed:
            return "The AI key could not be encrypted."
        case .keyDerivationFailed:
            return "A secure encryption key could not be derived."
        case .notSignedIn:
            return "Sign in before saving or restoring an AI key."
        case .keychainStorageFailed:
            return "The AI key could not be securely saved on this device."
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
