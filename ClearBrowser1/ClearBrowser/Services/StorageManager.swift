import Foundation

struct BrowserSettings: Codable {
    var defaultSearchEngine: SearchEngine = .bing
    var autoScrollSpeed: Double = 0.35
}

final class StorageManager {
    private enum Key {
        static let bookmarks = "ClearBrowser.bookmarks"
        static let history = "ClearBrowser.history"
        static let settings = "ClearBrowser.settings"
    }

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadBookmarks() -> [BrowserItem] {
        guard let data = defaults.data(forKey: Key.bookmarks),
              let items = try? decoder.decode([BrowserItem].self, from: data) else {
            return []
        }
        return items
    }

    func saveBookmarks(_ items: [BrowserItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: Key.bookmarks)
    }

    func loadHistory() -> [BrowserItem] {
        guard let data = defaults.data(forKey: Key.history),
              let items = try? decoder.decode([BrowserItem].self, from: data) else {
            return []
        }
        return items
    }

    func saveHistory(_ items: [BrowserItem]) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: Key.history)
    }

    func loadSettings() -> BrowserSettings {
        guard let data = defaults.data(forKey: Key.settings),
              let settings = try? decoder.decode(BrowserSettings.self, from: data) else {
            return BrowserSettings()
        }
        return settings
    }

    func saveSettings(_ settings: BrowserSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Key.settings)
    }
}
