import SwiftUI
import WebKit
import Foundation
import UIKit

enum DrawerType {
    case bookmarks
    case history
    case settings
}

class AppState: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    // MARK: - Published Properties
    @Published var currentURL: URL?
    @Published var pageTitle: String = "New Tab"
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var searchQuery = ""
    @Published var showHome = true
    
    @Published var bookmarks: [Bookmark] = []
    @Published var history: [HistoryItem] = []
    @Published var activeDrawer: DrawerType?
    
    @Published var autoScrollEnabled = false
    @Published var autoScrollSpeed: Double = 1.0
    @Published var searchEngine: SearchEngine = .bing
    
    @Published var aiResponse: String?
    @Published var aiLoading = false
    
    // MARK: - Services
    let storageManager = StorageManager.shared
    let autoScrollManager = AutoScrollManager()
    let searchManager = SearchManager()
    let aiService = AIService()
    
    var webView: WKWebView?
    
    override init() {
        super.init()
        loadPersistedData()
    }
    
    // MARK: - Navigation
    func loadURL(_ url: URL) {
        let request = URLRequest(url: url)
        webView?.load(request)
        currentURL = url
        pageTitle = url.host ?? "Browser"
        showHome = false
    }
    
    func loadSearch(_ query: String) {
        guard let url = searchManager.buildSearchURL(query, engine: searchEngine) else { return }
        loadURL(url)
    }
    
    func handleInput(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        if let url = searchManager.parseInput(trimmed) {
            loadURL(url)
        } else {
            loadSearch(trimmed)
        }
    }
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    func reload() {
        webView?.reload()
    }
    
    func goHome() {
        showHome = true
        searchQuery = ""
        aiResponse = nil
    }
    
    // MARK: - Bookmarks & History
    func addBookmark(url: URL, title: String) {
        let bookmark = Bookmark(
            id: UUID(),
            url: url,
            title: title,
            dateAdded: Date()
        )
        bookmarks.insert(bookmark, at: 0)
        storageManager.saveBookmarks(bookmarks)
    }
    
    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        storageManager.saveBookmarks(bookmarks)
    }
    
    func addHistory(url: URL, title: String) {
        let item = HistoryItem(
            id: UUID(),
            url: url,
            title: title,
            visitedAt: Date()
        )
        history.insert(item, at: 0)
        if history.count > 500 {
            history.removeLast()
        }
        storageManager.saveHistory(history)
    }
    
    func clearHistory() {
        history.removeAll()
        storageManager.saveHistory(history)
    }
    
    // MARK: - Auto Scroll
    func toggleAutoScroll() {
        autoScrollEnabled.toggle()
        if autoScrollEnabled {
            autoScrollManager.startAutoScroll(webView: webView, speed: autoScrollSpeed)
        } else {
            autoScrollManager.stopAutoScroll()
        }
    }
    
    func updateAutoScrollSpeed(_ speed: Double) {
        autoScrollSpeed = speed
        if autoScrollEnabled {
            autoScrollManager.updateSpeed(speed)
        }
    }
    
    // MARK: - AI Search
    func performAISearch(_ query: String) {
        aiLoading = true
        aiResponse = nil
        
        Task {
            let response = await aiService.search(query)
            DispatchQueue.main.async {
                self.aiResponse = response
                self.aiLoading = false
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        isLoading = true
    }
    
    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        isLoading = false
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        
        // Update page title
        webView.evaluateJavaScript("document.title") { [weak self] result, _ in
            if let title = result as? String {
                self?.pageTitle = title.isEmpty ? webView.url?.host ?? "Browser" : title
            }
        }
        
        // Add to history
        if let url = webView.url {
            addHistory(url: url, title: pageTitle)
        }
    }
    
    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        isLoading = false
    }
    
    // MARK: - Persistence
    private func loadPersistedData() {
        bookmarks = storageManager.loadBookmarks()
        history = storageManager.loadHistory()
        
        if let savedEngine = UserDefaults.standard.string(forKey: "searchEngine"),
           let engine = SearchEngine(rawValue: savedEngine) {
            searchEngine = engine
        }
        
        autoScrollSpeed = UserDefaults.standard.double(forKey: "autoScrollSpeed")
        if autoScrollSpeed == 0 {
            autoScrollSpeed = 1.0
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(searchEngine.rawValue, forKey: "searchEngine")
        UserDefaults.standard.set(autoScrollSpeed, forKey: "autoScrollSpeed")
    }
    
    // MARK: - Drawer Management
    func openDrawer(_ drawer: DrawerType) {
        activeDrawer = drawer
    }
    
    func closeDrawer() {
        activeDrawer = nil
    }
    
    func toggleDrawer(_ drawer: DrawerType) {
        if activeDrawer == drawer {
            closeDrawer()
        } else {
            openDrawer(drawer)
        }
    }
}