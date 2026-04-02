import Foundation
import SwiftUI

enum BrowserNavigationCommand {
    case back
    case forward
    case reload
    case stop
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var addressBarText: String = "https://www.bing.com"
    @Published var currentURL: URL? = URL(string: "https://www.bing.com")
    @Published var pageTitle: String = "ClearBrowser"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var selectedDrawer: DrawerType? = nil
    @Published var isAutoScrolling = false
    @Published var autoScrollSpeed: Double = 0.35 {
        didSet { settings.autoScrollSpeed = autoScrollSpeed; saveSettings() }
    }
    @Published var defaultSearchEngine: SearchEngine = .bing {
        didSet { settings.defaultSearchEngine = defaultSearchEngine; saveSettings() }
    }
    @Published var bookmarks: [BrowserItem] = []
    @Published var history: [BrowserItem] = []
    @Published var aiQuery: String = ""
    @Published var aiResponse: String? = nil
    @Published var isAIWorking: Bool = false
    @Published var navigationCommand: BrowserNavigationCommand? = nil
    @Published var requestURL: URL? = URL(string: "https://www.bing.com")

    private(set) var autoScrollManager = AutoScrollManager()
    private let searchManager = SearchManager()
    private let storageManager = StorageManager()
    private let aiService = AIService()
    private var settings = BrowserSettings()

    init() {
        loadPersistentData()
        autoScrollManager.speed = CGFloat(autoScrollSpeed)
    }

    func loadAddress() {
        guard let targetURL = searchManager.pageURL(for: addressBarText, defaultSearchEngine: defaultSearchEngine) else {
            return
        }

        currentURL = targetURL
        requestURL = targetURL
        addHistoryItem(title: addressBarText, url: targetURL)
    }

    func reload() {
        navigationCommand = .reload
    }

    func goBack() {
        navigationCommand = .back
    }

    func goForward() {
        navigationCommand = .forward
    }

    func stopLoading() {
        navigationCommand = .stop
    }

    func toggleAutoScroll() {
        isAutoScrolling.toggle()
        if isAutoScrolling {
            autoScrollManager.start()
        } else {
            autoScrollManager.stop()
        }
    }

    func updateNavigationState(canGoBack: Bool, canGoForward: Bool, title: String?, url: URL?) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.pageTitle = title ?? url?.host ?? "ClearBrowser"
        if let url = url {
            self.addressBarText = url.absoluteString
            self.currentURL = url
        }
    }

    func addBookmark() {
        guard let url = currentURL else { return }
        let title = pageTitle.isEmpty ? url.host ?? url.absoluteString : pageTitle
        let item = BrowserItem(title: title, url: url)
        if !bookmarks.contains(item) {
            bookmarks.insert(item, at: 0)
            storageManager.saveBookmarks(bookmarks)
        }
    }

    func removeBookmark(_ item: BrowserItem) {
        bookmarks.removeAll { $0.id == item.id }
        storageManager.saveBookmarks(bookmarks)
    }

    func openBookmark(_ item: BrowserItem) {
        selectedDrawer = nil
        addressBarText = item.url.absoluteString
        requestURL = item.url
        addHistoryItem(title: item.title, url: item.url)
    }

    func openHistory(_ item: BrowserItem) {
        selectedDrawer = nil
        addressBarText = item.url.absoluteString
        requestURL = item.url
    }

    func clearHistory() {
        history.removeAll()
        storageManager.saveHistory(history)
    }

    func fetchAIResponse() {
        let query = aiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isAIWorking = true
        aiResponse = nil

        Task {
            let pageContext = currentURL?.host
            let response = await aiService.answer(query: query, pageContext: pageContext)
            await MainActor.run {
                self.aiResponse = response
                self.isAIWorking = false
            }
        }
    }

    private func loadPersistentData() {
        bookmarks = storageManager.loadBookmarks()
        history = storageManager.loadHistory()
        settings = storageManager.loadSettings()
        defaultSearchEngine = settings.defaultSearchEngine
        autoScrollSpeed = settings.autoScrollSpeed
    }

    private func saveSettings() {
        storageManager.saveSettings(settings)
    }

    private func addHistoryItem(title: String, url: URL) {
        let item = BrowserItem(title: title, url: url)
        history.removeAll { $0.url == url }
        history.insert(item, at: 0)
        history = Array(history.prefix(50))
        storageManager.saveHistory(history)
    }
}
