import Foundation
import SwiftUI

enum BrowserNavigationCommand {
    case back
    case forward
    case reload
    case stop
}

enum AuthSheetType: Identifiable {
    case login, register
    var id: Self { self }
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

    @Published var isLoggedIn = false
    @Published var currentUserEmail: String? = nil
    @Published var authSheet: AuthSheetType? = nil
    @Published var openAIKey: String = "" {
        didSet { UserDefaults.standard.set(openAIKey, forKey: "openAIKey") }
    }

    private var _rawAutoScrollSpeed: Double = 0.35
    
    @Published var autoScrollSpeed: Double = 0.35 {
        didSet {
            settings.autoScrollSpeed = autoScrollSpeed
            autoScrollManager.speed = CGFloat(autoScrollSpeed)
        }
    }
    
    @Published var defaultSearchEngine: SearchEngine = .bing {
        didSet { settings.defaultSearchEngine = defaultSearchEngine; saveSettings() }
    }
    @Published var bookmarks: [BrowserItem] = []
    @Published var history: [BrowserItem] = []
    @Published var aiQuery: String = ""
    @Published var aiResponse: String? = nil
    @Published var isAIWorking: Bool = false
    @Published var showAIField: Bool = false
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

    func openSearchEngineHome() {
        let urlString = defaultSearchEngine == .google ? "https://www.google.com" : "https://www.bing.com"
        if let url = URL(string: urlString) {
            addressBarText = urlString
            requestURL = url
            currentURL = url
            addHistoryItem(title: defaultSearchEngine.title, url: url)
        }
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
        // Only toggle the state here. `BrowserView.updateUIView` will start/stop
        // the AutoScrollManager when the WKWebView's scrollView is available.
        isAutoScrolling.toggle()
        print("[AutoScroll] toggleAutoScroll -> \(isAutoScrolling)")
    }

    func toggleAIField() {
        showAIField.toggle()
    }

    func updateNavigationState(canGoBack: Bool, canGoForward: Bool, title: String?, url: URL?) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.pageTitle = title ?? url?.host ?? "ClearBrowser"
        if let url = url {
            if url != currentURL {
                addHistoryItem(title: title ?? url.host ?? "Untitled", url: url)
            }
            self.addressBarText = url.absoluteString
            self.currentURL = url
            // persist last opened URL
            settings.lastOpenedURL = url.absoluteString
            saveSettings()
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

    func removeHistoryItem(_ item: BrowserItem) {
        history.removeAll { $0.id == item.id }
        storageManager.saveHistory(history)
    }

    func login(email: String) {
        isLoggedIn = true
        currentUserEmail = email
        authSheet = nil
    }

    func register(email: String, apiKey: String?) {
        isLoggedIn = true
        currentUserEmail = email
        if let key = apiKey, !key.isEmpty {
            self.openAIKey = key
        }
        authSheet = nil
    }

    func fetchAIResponse() {
        let query = aiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isAIWorking = true
        aiResponse = nil

        Task {
            let response = await aiService.answer(query: query, apiKey: openAIKey)
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
        openAIKey = UserDefaults.standard.string(forKey: "openAIKey") ?? ""
        if let last = settings.lastOpenedURL, let url = URL(string: last) {
            requestURL = url
            currentURL = url
            addressBarText = last
        }
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
