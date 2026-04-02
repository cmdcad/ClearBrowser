import Foundation

struct SearchManager {
    func pageURL(for input: String, defaultSearchEngine: SearchEngine) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = url(from: trimmed) {
            return url
        }

        guard let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        return URL(string: "\(defaultSearchEngine.queryURL)\(encodedQuery)")
    }

    private func url(from rawText: String) -> URL? {
        if let url = URL(string: rawText), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }

        if rawText.contains(" ") == false,
           let candidate = URL(string: "https://\(rawText)"),
           candidate.host != nil {
            return candidate
        }

        return nil
    }
}
