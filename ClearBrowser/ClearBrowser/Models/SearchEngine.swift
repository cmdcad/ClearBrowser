import Foundation




enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case google, bing, duckduckgo
    var id: String { self.rawValue }
    var title: String { self.rawValue.capitalized }
    var queryURL: String {
        switch self {
        case .google: return "https://www.google.com/search?q="
        case .bing: return "https://www.bing.com/search?q="
        case .duckduckgo: return "https://duckduckgo.com/?q="
        }
    }
}
