import Foundation

final class AIService {
    func answer(query: String, pageContext: String?) async -> String {
        let contextLine = pageContext?.isEmpty == false ? "\nSite content available for future context-aware answers." : ""
        try? await Task.sleep(nanoseconds: 400_000_000)
        return "AI Reading Assistant:\n\nFor \"\(query)\", the browser can help you navigate faster, summarize page content, and save results for later.\(contextLine)\n\nThis placeholder service is ready to be replaced with a real text-only API in the future."
    }
}
