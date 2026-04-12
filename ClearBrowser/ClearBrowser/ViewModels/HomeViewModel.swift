import Foundation
import UIKit
import SwiftUI
import AuthenticationServices
import FirebaseAuth
import FirebaseStorage
import CryptoKit

enum URLParseError: Error {
    case invalidURL
}

enum BrowserNavigationCommand {
    case back
    case forward
    case reload
    case stop
}

enum AuthSheetType: Identifiable {
    case login, register // No change needed here
    var id: Self { self }
}




enum ToolbarPosition: String, CaseIterable, Identifiable {
    case top, bottom
    var id: Self { self }
    var title: String { self.rawValue.capitalized }
}

@MainActor
final class HomeViewModel: NSObject, ObservableObject {
    @Published var addressBarText: String = "https://www.bing.com"
    @Published var currentURL: URL? = URL(string: "https://www.bing.com")
    @Published var pageTitle: String = "ClearBrowser"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0.0
    @Published var selectedDrawer: DrawerType? = nil
    @Published var isAutoScrolling = false
    @Published var isHeaderVisible = true

    private var currentNonce: String?
    @Published var isPrivateMode = false
    @Published var toolbarPosition: ToolbarPosition = .top {
        didSet { saveSettings() }
    }

    @Published var isLoggedIn = false
    @Published var currentUserEmail: String? = nil
    @Published var displayName: String? = nil
    @Published var profileImageUrl: URL? = nil
    @Published var favorites: [BrowserItem] = [] // New: Favorites list
    @Published var authSheet: AuthSheetType? = nil
    @Published var openAIKey: String = "" {
        didSet {
            KeychainHelper.standard.save(openAIKey, service: Bundle.main.bundleIdentifier ?? "ClearBrowser", account: "openAIKey")
        }
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

    override init() {
        super.init()
        loadPersistentData()
        autoScrollManager.speed = CGFloat(autoScrollSpeed)
    }
    
    func loadAddress() {
        let targetURL = resolveInput(addressBarText)
        currentURL = targetURL
        requestURL = targetURL
        loadingProgress = 0.0
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showAIField.toggle()
        }
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
            storageManager.syncBookmarksToFirebase(bookmarks)
        }
    }

    func removeBookmark(_ item: BrowserItem) {
        bookmarks.removeAll { $0.id == item.id }
        storageManager.saveBookmarks(bookmarks)
        storageManager.syncBookmarksToFirebase(bookmarks)
    }

    func openBookmark(_ item: BrowserItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedDrawer = nil
            addressBarText = item.url.absoluteString
            requestURL = item.url
            addHistoryItem(title: item.title, url: item.url)
        }
    }

    var isCurrentPageFavorited: Bool {
        guard let url = currentURL else { return false }
        return favorites.contains(where: { $0.url == url })
    }

    func toggleFavorite() {
        guard let url = currentURL else { return }
        if isCurrentPageFavorited {
            removeFavorite(BrowserItem(title: pageTitle, url: url))
        } else {
            addFavorite()
        }
    }

    func addFavorite() {
        guard let url = currentURL else { return }
        let item = BrowserItem(title: pageTitle, url: url)
        if !favorites.contains(where: { $0.url == url }) {
            favorites.insert(item, at: 0)
            storageManager.saveFavorites(favorites)
            storageManager.syncFavoritesToFirebase(favorites)
        }
    }

    func removeFavorite(_ item: BrowserItem) {
        favorites.removeAll { $0.id == item.id }
        storageManager.saveFavorites(favorites)
        storageManager.syncFavoritesToFirebase(favorites)
    }

    func openFavorite(_ item: BrowserItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedDrawer = nil
            addressBarText = item.url.absoluteString
            requestURL = item.url
            addHistoryItem(title: item.title, url: item.url)
        }
    }

    func openHistory(_ item: BrowserItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedDrawer = nil
            addressBarText = item.url.absoluteString
            requestURL = item.url
            addHistoryItem(title: item.title, url: item.url)
        }
    }

    func clearHistory() {
        history.removeAll()
        storageManager.saveHistory(history)
        storageManager.syncHistoryToFirebase(history)
    }

    func removeHistoryItem(_ item: BrowserItem) {
        history.removeAll { $0.id == item.id }
        storageManager.saveHistory(history)
        storageManager.syncHistoryToFirebase(history)
    }

    func removeHistoryItems(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        storageManager.saveHistory(history)
        storageManager.syncHistoryToFirebase(history)
    }

    func moveHistoryItem(from source: IndexSet, to destination: Int) {
        history.move(fromOffsets: source, toOffset: destination)
        storageManager.saveHistory(history)
        storageManager.syncHistoryToFirebase(history)
    }

    func login(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let error = error {
                    print("Firebase login error: \(error.localizedDescription)")
                    return
                }
                self.syncUser(result?.user)
                self.authSheet = nil
            }
        }
    }
    
    func loginWithGoogle() {
        //  directURI = "\(callbackScheme):/oauth2redirect"

        // 3. Generate Nonce for OpenID Connect security
        let rawNonce = randomNonceString()
        currentNonce = rawNonce
        let hashedNonce = sha256(rawNonce)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "id_token"),
            URLQueryItem(name: "scope", value: "email profile"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "nonce", value: hashedNonce)
        ]

        guard let authURL = components.url else { retur
        let session = ASWebAuthenticationSession(url: authURL, r
            if let error = error {
                print("Authentication error: \(error.localizedDescription)")
                return
            }
            
            guard let url = callbackURL else { return }
            
            // 4. Extract id_token from the URL fragment or query
            let fragment = url.fragment ?? url.query ?? ""
            let params = fragment.components(separatedBy: "&")
            let idToken = params.first(where: { $0.hasPrefix("id_token=") })?
                .components(separatedBy: "=").last
    
cessToken: nil)
          
            Task { @MainActor in
                do {
                    let result = try await Auth.auth().signIn(with: credential)
                    self.syncUser(result.user)
                } catch {
                    print("Firebase Google Auth Error: \(error.localizedDescription)")
                }
                self.authSheet = nil
            }
        }

        session.presentationCont
                    print("Firebase register error: \(error.localizedDescription)")
                    return
                }
                if let key = apiKey, !key.isEmpty {
                    self.openAIKey = key
                }
                self.syncUser(result?.user)
                self.authSheet = nil
            }
        }
    }

    func updateProfile(name: String) {
        Task {
            // Update local state immediately so the UI responds
            self.displayName = name
            
            // Attempt Firebase update if a real user exists
            guard let user = Auth.auth().currentUser else { 
                print("Note: Local state updated, but no Firebase user found (using mock login).")
                return 
            }
            
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = name
            
            do {
                try await changeRequest.commitChanges()
                print("Firebase profile name updated successfully.")
            } catch {
                print("Error updating Firebase profile: \(error.localizedDescription)")
            }
        }
    }

    func uploadProfilePicture(_ image: UIImage) {
        guard let user = Auth.auth().currentUser else { 
            print("Cannot upload: No Firebase user logged in.")
            return 
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return }
        
        let storageRef = Storage.storage().reference().child("profile_images/\(user.uid).jpg")
        
        Task {
            do {
                // 1. Upload to Firebase Storage
                let _ = try await storageRef.putDataAsync(imageData)
                
                // 2. Get the download URL
                let downloadURL = try await storageRef.downloadURL()
                
                // 3. Update the user's profile in Firebase Auth
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.photoURL = downloadURL
                try await changeRequest.commitChanges()
                
                await MainActor.run {
                    self.profileImageUrl = downloadURL
                    print("Profile picture updated successfully.")
                }
            } catch {
                print("Error uploading profile picture: \(error.localizedDescription)")
            }
        }
    }

    func logout() {
        try? Auth.auth().signOut()
        syncUser(nil)
    }

    private func syncUser(_ user: User?) {
        guard let user = user else {
            isLoggedIn = false
            currentUserEmail = nil
            displayName = nil
            profileImageUrl = nil
            return
        }
        isLoggedIn = true
        currentUserEmail = user.email
        displayName = user.displayName ?? user.email
        profileImageUrl = user.photoURL
        
        // Load data from Firebase after user logs in
        loadDataFromFirebase()
    }
    
    private func loadDataFromFirebase() {
        storageManager.loadBookmarksFromFirebase { [weak self] bookmarks in
            self?.bookmarks = bookmarks
        }
        
        storageManager.loadFavoritesFromFirebase { [weak self] favorites in
            self?.favorites = favorites
        }
        
        storageManager.loadHistoryFromFirebase { [weak self] history in
            self?.history = history
        }
    }

    func fetchAIResponse() {
        let query = aiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isAIWorking = true
        aiResponse = nil

        Task {
            let response = await aiService.answer(query: query)
            await MainActor.run {
                self.aiResponse = response
                self.isAIWorking = false
            }
        }
    }

    func shareCurrentPage() {
        guard let url = currentURL else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // For iPad compatibility
            activityVC.popoverPresentationController?.sourceView = rootVC.view
            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Security Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in UInt8.random(in: 0...255) }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func loadPersistentData() {
        if let user = Auth.auth().currentUser {
            syncUser(user)
        }

        bookmarks = storageManager.loadBookmarks()
        history = storageManager.loadHistory()
        favorites = storageManager.loadFavorites() // New: Load favorites
        settings = storageManager.loadSettings()
        defaultSearchEngine = settings.defaultSearchEngine
        autoScrollSpeed = settings.autoScrollSpeed
        openAIKey = KeychainHelper.standard.read(service: Bundle.main.bundleIdentifier ?? "ClearBrowser", account: "openAIKey") ?? ""

        if let pos = UserDefaults.standard.string(forKey: "toolbarPosition"),
           let position = ToolbarPosition(rawValue: pos) {
            toolbarPosition = position
        }

        if let last = settings.lastOpenedURL, let url = URL(string: last) {
            requestURL = url
            currentURL = url
            addressBarText = last
        }
    }

    private func saveSettings() {
        storageManager.saveSettings(settings)
    }

    private func parseOrThrow(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Regex matches: yahoo.com, www.yahoo.com, http://yahoo.com, https://www.x.com
        let pattern = #"^(https?:\/\/)?(www\.)?([A-Za-z0-9-]+\.[A-Za-z]{2,})(\/.*)?$"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw URLParseError.invalidURL
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)

        guard let match = regex.firstMatch(in: trimmed, range: range) else {
            throw URLParseError.invalidURL
        }

        // Extract components
        let protocolRange = Range(match.range(at: 1), in: trimmed)
        let wwwRange = Range(match.range(at: 2), in: trimmed)
        let domainRange = Range(match.range(at: 3), in: trimmed)
        let pathRange = Range(match.range(at: 4), in: trimmed)

        let proto = protocolRange != nil ? String(trimmed[protocolRange!]) : "https://"
        let www = wwwRange != nil ? String(trimmed[wwwRange!]) : ""
        let domain = domainRange != nil ? String(trimmed[domainRange!]) : ""
        let path = pathRange != nil ? String(trimmed[pathRange!]) : ""

        let finalString = "\(proto)\(www)\(domain)\(path)"

        guard let url = URL(string: finalString) else {
            throw URLParseError.invalidURL
        }

        return url
    }

    private func resolveInput(_ input: String) -> URL {
        do {
            return try parseOrThrow(input)
        } catch {
            // Fallback: treat input as a search query using the configured engine
            let query = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
            return URL(string: defaultSearchEngine.queryURL + query)!
        }
    }

    private func addHistoryItem(title: String, url: URL) {
        guard !isPrivateMode else { return } // Do not save history in private mode
        
        let item = BrowserItem(title: title, url: url)
        history.removeAll { $0.url == url }
        history.insert(item, at: 0)
        history = Array(history.prefix(50))
        storageManager.saveHistory(history)
        storageManager.syncHistoryToFirebase(history)
    }
}

extension HomeViewModel: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first ?? ASPresentationAnchor()
    }
}
