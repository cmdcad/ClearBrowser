import Foundation

// MARK: - Bookmark Model
struct Bookmark: Identifiable, Codable {
    let id: UUID
    let url: URL
    let title: String
    let dateAdded: Date
}

// MARK: - History Item Model
struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let url: URL
    let title: String
    let visitedAt: Date
}

// MARK: - Search Engine Enum
enum SearchEngine: String, CaseIterable {
    case bing
    case google
    
    var displayName: String {
        switch self {
        case .bing: return "Bing"
        case .google: return "Google"
        }
    }
    
    var baseURL: String {
        switch self {
        case .bing: return "https://www.bing.com/search?q="
        case .google: return "https://www.google.com/search?q="
        }
    }
}

// MARK: - Page Content Model (for future AI integration)
struct PageContent: Codable {
    let title: String
    let url: URL
    let text: String
    let images: [String]
    let extractedAt: Date
}