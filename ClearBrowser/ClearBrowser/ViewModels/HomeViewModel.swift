import Foundation
import UIKit
import SwiftUI
import AuthenticationServices
import FirebaseAuth
import FirebaseStorage
import CryptoKit
import WebKit

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

enum AccountSheetDestination: Identifiable {
    case hub
    case login
    case register
    case profile

    var id: Self { self }
}




enum ToolbarPosition: String, CaseIterable, Identifiable {
    case top, bottom
    var id: Self { self }
    var title: String { self.rawValue.capitalized }
}

@MainActor
final class HomeViewModel: NSObject, ObservableObject {
    // MARK: - Tab Management
    @Published var tabs: [BrowserTab] = [BrowserTab(url: URL(string: "https://www.bing.com")!)]
    @Published var activeTabID: UUID
    
    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabID }
    }

    // Update these to be computed or updated based on the active tab
    @Published var addressBarText: String = ""
    @Published var currentURL: URL?
    @Published var pageTitle: String = "ClearBrowser"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0.0
    @Published var selectedDrawer: DrawerType? = nil
    @Published var isAutoScrolling = false
    @Published var isHeaderVisible = true

    private var authListenerHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    @Published var isPrivateMode = false
    @Published var toolbarPosition: ToolbarPosition = .top {
        didSet { saveSettings() }
    }

    @Published var isLoggedIn = false
    @Published var currentUserEmail: String? = nil
    @Published var displayName: String? = nil
    @Published var profileImageUrl: URL? = nil
    @Published var localProfileImagePath: String? = nil
    @Published var favorites: [BrowserItem] = [] // New: Favorites list
    @Published var authSheet: AuthSheetType? = nil
    @Published var accountSheet: AccountSheetDestination? = nil
    @Published var openAIKey: String = "" {
        didSet {
            _ = KeychainHelper.standard.save(openAIKey, service: Bundle.main.bundleIdentifier ?? "ClearBrowser", account: "openAIKey")
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
    @Published var blockedSchemes: [String] = []
    @Published var aiQuery: String = ""
    @Published var aiResponse: String? = nil
    @Published var isAIWorking: Bool = false
    @Published var showAIField: Bool = false
    @Published var navigationCommand: BrowserNavigationCommand? = nil
    @Published var requestURL: URL? = URL(string: "https://www.bing.com")
    
    // MARK: - Read Aloud Properties
    @Published var isReadAloudAvailable = false
    @Published var isReadAloudPlaying = false
    @Published var readAloudProgress: TimeInterval = 0
    @Published var readAloudDuration: TimeInterval = 0
    
    // WebView reference for read-aloud functionality
    var currentWebView: WKWebView?

    private(set) var autoScrollManager = AutoScrollManager()
    private let searchManager = SearchManager()
    private let storageManager = StorageManager()
    private let aiService = AIService()
    private var settings = BrowserSettings()
    @Published var audioVixService = AudioVixService()

    override init() {
        // 1. Initialize activeTabID with a placeholder to satisfy Phase 1 initialization.
        // We cannot access 'self.tabs' yet because 'self' isn't fully initialized.
        self.activeTabID = UUID()

        super.init()
        
        // 2. Load saved data. This will attempt to overwrite activeTabID from settings.
        loadPersistentData()

        // 3. Listen for Auth changes to handle auto-sync on launch/re-install
        setupAuthListener()

        // 3. Fallback: If no saved session was loaded, sync with the default first tab.
        if activeTab == nil {
            activeTabID = tabs[0].id
        }

        self.addressBarText = activeTab?.url.absoluteString ?? ""
        autoScrollManager.speed = CGFloat(autoScrollSpeed)
        
        // 4. Setup audio playback progress tracking
        setupAudioPlaybackTracking()
    }

    deinit {
        if let handle = authListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    private func setupAuthListener() {
        authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            Task { @MainActor in
                self.syncUser(user)
            }
        }
    }
    
    private func setupAudioPlaybackTracking() {
        // Observe audioVixService changes and update published properties
        audioVixService.$isPlaying.assign(to: &$isReadAloudPlaying)
        audioVixService.$currentTime.assign(to: &$readAloudProgress)
        audioVixService.$duration.assign(to: &$readAloudDuration)
    }
    func loadAddress() {
        let targetURL = resolveInput(addressBarText)
        currentURL = targetURL
        requestURL = targetURL
        loadingProgress = 0.0
        addHistoryItem(title: addressBarText, url: targetURL)
        
        // Update the tab model
        if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[index].url = targetURL
            saveSettings()
        }
    }

    func createNewTab(url: URL = URL(string: "https://www.bing.com")!) {
        let newTab = BrowserTab(url: url)
        tabs.append(newTab)
        switchTab(to: newTab.id)
        saveSettings()
    }

    func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        tabs.removeAll { $0.id == id }
        if activeTabID == id {
            activeTabID = tabs.last?.id ?? tabs[0].id
            if let active = activeTab {
                addressBarText = active.url.absoluteString
                requestURL = active.url
            }
        }
        saveSettings()
    }

    func switchTab(to id: UUID) {
        activeTabID = id
        if let active = activeTab {
            addressBarText = active.url.absoluteString
            requestURL = active.url
        }
        saveSettings()
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

    func isForcedInApp(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        
        // Check scheme for custom apps (e.g. twitter://)
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            if blockedSchemes.contains(scheme) {
                return true
            }
        }
        
        // Check host for web domains (e.g. youtube.com)
        if let host = url.host?.lowercased() {
            for blocked in blockedSchemes {
                if host == blocked || host.hasSuffix("." + blocked) {
                    return true
                }
            }
        }
        
        return false
    }

    func forceableEntity(from url: URL?) -> String? {
        guard let url = url else { return nil }
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            return scheme
        }
        
        // For standard web links, strip www. for a cleaner rule
        if let host = url.host?.lowercased() {
            var cleanHost = host
            if cleanHost.hasPrefix("www.") {
                cleanHost.removeFirst(4)
            }
            return cleanHost
        }
        return nil
    }

    func isBrowserItemForcedInApp(_ item: BrowserItem) -> Bool {
        return isForcedInApp(item.url)
    }

    func toggleForceInApp(for item: BrowserItem) {
        guard let entity = forceableEntity(from: item.url) else { return }
        if let index = blockedSchemes.firstIndex(of: entity) {
            blockedSchemes.remove(at: index)
        } else {
            blockedSchemes.append(entity)
        }
        storageManager.saveBlockedSchemes(blockedSchemes)
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

    func login(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        syncUser(result.user)
    }

    func register(email: String, password: String, displayName: String, apiKey: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let user = result.user

        if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            try await changeRequest.commitChanges()
        }

        openAIKey = apiKey
        syncUser(Auth.auth().currentUser ?? user)
    }
    
    
    func register(email: String, password: String, apiKey: String?) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            Task { @MainActor in
                if let error = error {
                    print("Firebase register error: \(error.localizedDescription)")
                    return
                }
                self?.isLoggedIn = true
                self?.currentUserEmail = result?.user.email
                if let key = apiKey, !key.isEmpty {
                    self?.openAIKey = key
                }
                self?.authSheet = nil
            }
        }
    }
    
    private var googleClientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
    }

    private var googleRedirectURI: String? {
        Bundle.main.object(forInfoDictionaryKey: "GOOGLE_REDIRECT_URI") as? String
    }

    func loginWithGoogle(completion: ((Bool) -> Void)? = nil) {
        guard let clientID = googleClientID, !clientID.isEmpty,
              let redirectURI = googleRedirectURI, !redirectURI.isEmpty,
              let authURL = makeGoogleAuthURL(clientID: clientID, redirectURI: redirectURI) else {
            print("Google login cannot start: missing client ID or redirect URI.")
            completion?(false)
            return
        }

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: URL(string: redirectURI)?.scheme) { callbackURL, error in
            if let error = error {
                print("Authentication error: \(error.localizedDescription)")
                completion?(false)
                return
            }

            guard let callbackURL = callbackURL else { return }
            let fragment = callbackURL.fragment ?? callbackURL.query ?? ""
            let params = fragment.components(separatedBy: "&")
            guard let idToken = params.first(where: { $0.hasPrefix("id_token=") })?.split(separator: "=").last.map(String.init) else {
                print("Google login failed: no id_token returned.")
                completion?(false)
                return
            }

            Task { @MainActor in
                do {
                    let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: "")
                    let result = try await Auth.auth().signIn(with: credential)
                    self.syncUser(result.user)
                    completion?(true)
                } catch {
                    print("Firebase Google Auth Error: \(error.localizedDescription)")
                    completion?(false)
                }
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        session.start()
    }

    private func makeGoogleAuthURL(clientID: String, redirectURI: String) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "id_token"),
            URLQueryItem(name: "scope", value: "email profile"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "nonce", value: sha256(randomNonceString()))
        ]
        return components?.url
    }

    func updateProfile(name: String) {
        Task {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Update local state immediately so the UI responds
            self.displayName = trimmedName
            self.persistProfileSnapshot()
            
            // Attempt Firebase update if a real user exists
            guard let user = Auth.auth().currentUser else { 
                print("Note: Local state updated, but no Firebase user found (using mock login).")
                return 
            }
            
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = trimmedName
            
            do {
                try await changeRequest.commitChanges()
                print("Firebase profile name updated successfully.")
            } catch {
                print("Error updating Firebase profile: \(error.localizedDescription)")
            }
        }
    }

    func uploadProfilePicture(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return }

        let localFilename = Auth.auth().currentUser.map { "profile-image-\($0.uid).jpg" } ?? "profile-image-local.jpg"
        localProfileImagePath = storageManager.saveProfileImageData(imageData, filename: localFilename)
        persistProfileSnapshot()

        guard let user = Auth.auth().currentUser else {
            print("Saved profile image locally. Firebase upload skipped because no user is logged in.")
            return
        }

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
                    self.persistProfileSnapshot()
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
        let cachedProfile = storageManager.loadProfileSnapshot()

        guard let user = user else {
            isLoggedIn = false
            currentUserEmail = cachedProfile?.email
            displayName = cachedProfile?.displayName
            profileImageUrl = cachedProfile.flatMap { snapshot in
                guard let remotePhotoURL = snapshot.remotePhotoURL else { return nil }
                return URL(string: remotePhotoURL)
            }
            localProfileImagePath = cachedProfile?.localPhotoPath
            return
        }

        isLoggedIn = true
        currentUserEmail = user.email ?? cachedProfile?.email
        displayName = user.displayName ?? cachedProfile?.displayName ?? user.email

        if let userPhotoURL = user.photoURL {
            profileImageUrl = userPhotoURL
        } else if let cachedURL = cachedProfile?.remotePhotoURL {
            profileImageUrl = URL(string: cachedURL)
        } else {
            profileImageUrl = nil
        }

        localProfileImagePath = cachedProfile?.localPhotoPath
        persistProfileSnapshot()

        // Load data from Firebase after the user logs in.
        loadDataFromFirebase()
    }
    
    private func loadDataFromFirebase() {
        storageManager.loadBookmarksFromFirebase { [weak self] bookmarks in
            self?.bookmarks = bookmarks
            self?.storageManager.saveBookmarks(bookmarks)
        }
        
        storageManager.loadFavoritesFromFirebase { [weak self] favorites in
            self?.favorites = favorites
            self?.storageManager.saveFavorites(favorites)
        }
        
        storageManager.loadHistoryFromFirebase { [weak self] history in
            self?.history = history
            self?.storageManager.saveHistory(history)
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
        if let cachedProfile = storageManager.loadProfileSnapshot() {
            currentUserEmail = cachedProfile.email
            displayName = cachedProfile.displayName
            profileImageUrl = cachedProfile.remotePhotoURL.flatMap(URL.init(string:))
            localProfileImagePath = cachedProfile.localPhotoPath
        }

        bookmarks = storageManager.loadBookmarks()
        history = storageManager.loadHistory()
        favorites = storageManager.loadFavorites() // New: Load favorites
        blockedSchemes = storageManager.loadBlockedSchemes()
        settings = storageManager.loadSettings()
        defaultSearchEngine = settings.defaultSearchEngine
        autoScrollSpeed = settings.autoScrollSpeed
        openAIKey = KeychainHelper.standard.read(service: Bundle.main.bundleIdentifier ?? "ClearBrowser", account: "openAIKey") ?? ""

        if let pos = UserDefaults.standard.string(forKey: "toolbarPosition"),
           let position = ToolbarPosition(rawValue: pos) {
            toolbarPosition = position
        }

        if let savedTabs = settings.tabs, !savedTabs.isEmpty {
            self.tabs = savedTabs
            if let savedActiveID = settings.activeTabID, tabs.contains(where: { $0.id == savedActiveID }) {
                self.activeTabID = savedActiveID
            } else {
                self.activeTabID = tabs[0].id
            }
        }

        if let active = activeTab {
            requestURL = active.url
            currentURL = active.url
            addressBarText = active.url.absoluteString
        }
    }

    private func saveSettings() {
        settings.tabs = tabs
        settings.activeTabID = activeTabID
        storageManager.saveSettings(settings)
    }

    private func persistProfileSnapshot() {
        let profile = UserProfileSnapshot(
            email: currentUserEmail,
            displayName: displayName,
            remotePhotoURL: profileImageUrl?.absoluteString,
            localPhotoPath: localProfileImagePath
        )
        storageManager.saveProfileSnapshot(profile)
    }

    private func parseOrThrow(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw URLParseError.invalidURL }

        // 1. If it already has a valid scheme, trust it.
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }

        // 2. Check if it's a host-like string (no spaces, contains dot or colon for port, or localhost)
        let hasSpaces = trimmed.contains { $0.isWhitespace }
        let hasDot = trimmed.contains(".")
        let hasColonPort = trimmed.range(of: #":\d+"#, options: .regularExpression) != nil
        let isLocalhost = trimmed.lowercased().contains("localhost")

        if !hasSpaces && (hasDot || hasColonPort || isLocalhost) {
            let withScheme = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://\(trimmed)"
            if let url = URL(string: withScheme) {
                return url
            }
        }

        throw URLParseError.invalidURL
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
    
    // MARK: - Read Aloud Methods
    
    func startReadAloud(from webView: WKWebView) {
        audioVixService.extractArticleContent(from: webView) { [weak self] content in
            guard let self = self, let content = content, !content.isEmpty else {
                self?.audioVixService.errorMessage = "No article content found"
                return
            }
            
            Task {
                do {
                    _ = try await self.audioVixService.synthesizeSpeech(text: content)
                    await MainActor.run {
                        self.audioVixService.play()
                        self.isReadAloudPlaying = true
                        self.isReadAloudAvailable = true
                    }
                } catch let error as AudioVixError {
                    await MainActor.run {
                        self.audioVixService.errorMessage = error.localizedDescription
                    }
                } catch {
                    await MainActor.run {
                        self.audioVixService.errorMessage = "Failed to synthesize speech: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func pauseReadAloud() {
        audioVixService.pause()
        isReadAloudPlaying = false
    }
    
    func resumeReadAloud() {
        audioVixService.resume()
        isReadAloudPlaying = true
    }
    
    func stopReadAloud() {
        audioVixService.stop()
        isReadAloudPlaying = false
        isReadAloudAvailable = false
    }
    
    func setReadAloudSpeed(_ speed: Float) {
        audioVixService.setPlaybackRate(speed)
    }
}

extension HomeViewModel: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first ?? ASPresentationAnchor()
    }
}
