import Foundation

enum SearchEngine: String, CaseIterable, Codable, Identifiable {
    case bing
    case google

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bing: return "Bing"
        case .google: return "Google"
        }
    }

    var queryURL: String {
        switch self {
        case .bing: return "https://www.bing.com/search?q="
        case .google: return "https://www.google.com/search?q="
        }
    }
}
