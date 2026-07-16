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
    @Published var darkModeEnabled: Bool = false {
        didSet { settings.darkModeEnabled = darkModeEnabled; saveSettings() }
    }
    @Published var invertColorsEnabled: Bool = false {
        didSet { settings.invertColorsEnabled = invertColorsEnabled; saveSettings() }
    }
    @Published var highlightVerseEnabled: Bool = true {
        didSet { settings.highlightVerseEnabled = highlightVerseEnabled; saveSettings() }
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
    @Published var currentReadAloudText: String = ""

    var estimatedCurrentReadAloudText: String {
        let words = currentReadAloudText.split(separator: " ")
        guard !words.isEmpty else { return "" }
        guard readAloudDuration > 0 else {
            return words.prefix(18).joined(separator: " ")
        }

        let progress = min(max(readAloudProgress / readAloudDuration, 0), 1)
        let currentWordIndex = min(max(Int(Double(words.count) * progress), 0), words.count - 1)
        let startIndex = max(currentWordIndex - 8, 0)
        let endIndex = min(currentWordIndex + 16, words.count)
        return words[startIndex..<endIndex].joined(separator: " ")
    }
    
    // Diagnostic properties for audio flow
    @Published var audioContentCandidate: Bool = false
    @Published var audioRequestSent: Bool = false
    @Published var audioReceived: Bool = false
    
    // Page-level cache for synthesized audio data
    private var pageAudioCache: [URL: Data] = [:]
    private let audioCacheLimit = 5

    // WebView reference for read-aloud functionality
    var currentWebView: WKWebView?

    private(set) var autoScrollManager = AutoScrollManager()
    private let searchManager = SearchManager()
    private let storageManager = StorageManager()
    private let aiService = AIService()
    private var settings = BrowserSettings()

    @Published var serverManager = ServerManager()

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
        
        restoreAudioForCurrentTab()
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
    /*
     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:196:22 Value of type 'HomeViewModel' has no member 'syncUser'

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:352:13 Expected 'var' keyword in property declaration

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:352:13 Invalid redeclaration of 'isReadAloudPlaying'

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:354:5 Extraneous '}' at top level

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:357:25 Cannot find 'currentURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:358:21 Cannot find 'pageTitle' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:358:74 Cannot find 'pageTitle' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:360:13 Cannot find 'bookmarks' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:361:13 Cannot find 'bookmarks' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:362:13 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:362:42 Cannot find 'bookmarks' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:363:13 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:363:52 Cannot find 'bookmarks' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:372:16 Cannot find 'blockedSchemes' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:379:28 Cannot find 'blockedSchemes' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:412:24 Cannot find 'blockedSchemes' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:413:13 Cannot find 'blockedSchemes' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:415:13 Cannot find 'blockedSchemes' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:417:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:417:43 Cannot find 'blockedSchemes' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:421:9 Cannot find 'bookmarks' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:422:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:422:38 Cannot find 'bookmarks' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:423:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:423:48 Cannot find 'bookmarks' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:428:13 Cannot find 'selectedDrawer' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:429:13 Cannot find 'addressBarText' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:430:13 Cannot find 'requestURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:436:25 Cannot find 'currentURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:437:16 Cannot find 'favorites' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:441:25 Cannot find 'currentURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:443:47 Cannot find 'pageTitle' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:450:25 Cannot find 'currentURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:451:39 Cannot find 'pageTitle' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:452:13 Cannot find 'favorites' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:453:13 Cannot find 'favorites' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:454:13 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:454:42 Cannot find 'favorites' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:455:13 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:455:52 Cannot find 'favorites' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:460:9 Cannot find 'favorites' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:461:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:461:38 Cannot find 'favorites' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:462:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:462:48 Cannot find 'favorites' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:467:13 Cannot find 'selectedDrawer' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:468:13 Cannot find 'addressBarText' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:469:13 Cannot find 'requestURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:476:13 Cannot find 'selectedDrawer' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:477:13 Cannot find 'addressBarText' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:478:13 Cannot find 'requestURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:484:9 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:485:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:485:36 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:486:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:486:46 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:490:9 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:491:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:491:36 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:492:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:492:46 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:496:9 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:497:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:497:36 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:498:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:498:46 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:502:9 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:503:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:503:36 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:504:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:504:46 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:522:9 Cannot find 'openAIKey' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:528:78 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:539:35 'nil' requires a contextual type

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:581:21 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:590:47 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:611:13 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:612:13 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:636:9 Cannot find 'localProfileImagePath' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:636:33 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:660:21 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:661:21 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:676:29 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:679:13 Cannot find 'isLoggedIn' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:680:13 Cannot find 'currentUserEmail' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:680:47 Value of optional type 'Optional<_>' must be unwrapped to a value of type '_'

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:681:13 Cannot find 'displayName' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:681:42 Value of optional type 'Optional<_>' must be unwrapped to a value of type '_'

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:682:13 Cannot find 'profileImageUrl' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:686:13 Cannot find 'localProfileImagePath' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:686:52 Value of optional type 'Optional<_>' must be unwrapped to a value of type '_'

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:690:9 Cannot find 'isLoggedIn' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:691:9 Cannot find 'currentUserEmail' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:692:9 Cannot find 'displayName' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:695:13 Cannot find 'profileImageUrl' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:697:13 Cannot find 'profileImageUrl' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:699:13 Cannot find 'profileImageUrl' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:702:9 Cannot find 'localProfileImagePath' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:702:48 Value of optional type 'Optional<_>' must be unwrapped to a value of type '_'

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:710:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:710:58 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:710:64 Cannot infer type of closure parameter 'bookmarks' without a type annotation

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:715:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:715:58 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:715:64 Cannot infer type of closure parameter 'favorites' without a type annotation

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:720:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:720:56 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:720:62 Cannot infer type of closure parameter 'history' without a type annotation

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:727:21 Cannot find 'aiQuery' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:727:53 Cannot infer contextual base in reference to member 'whitespacesAndNewlines'

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:729:9 Cannot find 'isAIWorking' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:730:9 Cannot find 'aiResponse' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:733:34 Cannot find 'aiService' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:735:17 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:736:17 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:742:25 Cannot find 'currentURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:780:32 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:781:13 Cannot find 'currentUserEmail' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:782:13 Cannot find 'displayName' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:783:13 Cannot find 'profileImageUrl' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:784:13 Cannot find 'localProfileImagePath' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:787:9 Cannot find 'bookmarks' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:787:21 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:788:9 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:788:19 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:789:9 Cannot find 'favorites' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:789:21 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:790:9 Cannot find 'blockedSchemes' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:790:26 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:791:9 Cannot find 'settings' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:791:20 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:792:9 Cannot find 'defaultSearchEngine' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:792:31 Cannot find 'settings' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:793:9 Cannot find 'autoScrollSpeed' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:793:27 Cannot find 'settings' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:794:9 Cannot find 'highlightVerseEnabled' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:794:33 Cannot find 'settings' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:795:9 Cannot find 'openAIKey' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:799:13 Cannot find 'toolbarPosition' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:802:28 Cannot find 'settings' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:803:13 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:804:36 Cannot find 'settings' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:804:58 Cannot find 'tabs' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:805:17 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:807:17 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:807:36 Cannot find 'tabs' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:811:25 Cannot find 'activeTab' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:812:13 Cannot find 'requestURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:813:13 Cannot find 'currentURL' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:814:13 Cannot find 'addressBarText' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:819:9 Cannot find 'settings' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:819:25 Cannot find 'tabs' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:820:9 Cannot find 'settings' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:820:32 Cannot find 'activeTabID' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:821:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:821:37 Cannot find 'settings' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:826:20 Cannot find 'currentUserEmail' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:827:26 Cannot find 'displayName' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:828:29 Cannot find 'profileImageUrl' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:829:29 Cannot find 'localProfileImagePath' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:831:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:865:32 Cannot find 'defaultSearchEngine' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:870:16 Cannot find 'isPrivateMode' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:873:9 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:874:9 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:875:9 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:875:25 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:876:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:876:36 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:877:9 Cannot find 'storageManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:877:46 Cannot find 'history' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:887:9 Cannot find 'currentReadAloudText' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:888:9 Cannot find 'isReadAloudPlaying' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:889:9 Cannot find 'isReadAloudAvailable' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:890:9 Cannot find 'audioContentCandidate' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:891:9 Cannot find 'audioRequestSent' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:892:9 Cannot find 'audioReceived' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:896:40 Cannot find 'serverManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:897:37 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:898:21 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:898:41 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:900:17 Cannot find 'serverManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:901:17 Cannot find 'isReadAloudPlaying' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:902:17 Cannot find 'isReadAloudAvailable' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:904:17 Cannot find 'serverManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:906:17 Cannot find 'serverManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:913:9 Cannot find 'isReadAloudPlaying' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:914:9 Cannot find 'isReadAloudAvailable' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:915:9 Cannot find 'currentReadAloudText' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:916:9 Cannot find 'audioContentCandidate' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:917:9 Cannot find 'audioRequestSent' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:918:9 Cannot find 'audioReceived' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:920:9 Cannot find 'serverManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:920:86 Cannot find 'self' in scope; did you mean to use it in a type or extension context?

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:920:92 Cannot infer type of closure parameter 'content' without a type annotation

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:952:9 Cannot find 'serverManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:953:9 Cannot find 'isReadAloudPlaying' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:957:9 Cannot find 'serverManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:958:9 Cannot find 'isReadAloudPlaying' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:962:9 Cannot find 'serverManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:963:9 Cannot find 'isReadAloudPlaying' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:964:9 Cannot find 'isReadAloudAvailable' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:965:9 Cannot find 'currentReadAloudText' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:969:9 Cannot find 'serverManager' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:978:12 Cannot find 'audioContentCandidate' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:984:12 Cannot find 'audioRequestSent' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:990:12 Cannot find 'audioReceived' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:992:19 Cannot find 'audioRequestSent' in scope

     /Users/tosinmac8/Downloads/Git/ClearBrowser/ClearBrowser/ClearBrowser/ViewModels/HomeViewModel.swift:998:1 Extraneous '}' at top level
*/
    private func setupAudioPlaybackTracking() {
        // Observe serverManager changes and update published properties
        serverManager.$isPlaying.assign(to: &$isReadAloudPlaying)
        serverManager.$currentTime.assign(to: &$readAloudProgress)
        serverManager.$duration.assign(to: &$readAloudDuration)

        // Bind diagnostic properties
        serverManager.$hasExtractableContent.assign(to: &$audioContentCandidate)
        serverManager.$audioRequestSent.assign(to: &$audioRequestSent)
        serverManager.$audioReceived.assign(to: &$audioReceived)
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
        restoreAudioForCurrentTab()
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
            
            // Update the active tab's URL for persistence
            if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
                tabs[index].url = url
                tabs[index].title = title ?? url.host ?? "New Tab"
            }
            
            // persist last opened URL
            settings.lastOpenedURL = url.absoluteString
            saveSettings()
        }
    }

    private func restoreAudioForCurrentTab() {
        guard let url = activeTab?.url else { return }
        if let cachedData = pageAudioCache[url] {
            do {
                try serverManager.preparePlayer(with: cachedData)
                isReadAloudAvailable = true
                isReadAloudPlaying = false
                audioReceived = true
                audioRequestSent = false
                audioContentCandidate = true
            } catch {
                // If the cached audio is invalid, remove it and reset state
                pageAudioCache.removeValue(forKey: url)
                isReadAloudAvailable = false
                isReadAloudPlaying = false
                audioReceived = false
                serverManager.errorMessage = "Failed to restore cached audio."
            }
        } else {
            isReadAloudAvailable = false
            isReadAloudPlaying = false
        }
    }

    private func cacheAudioData(_ data: Data, for url: URL) {
        pageAudioCache[url] = data
        if pageAudioCache.count > audioCacheLimit {
            let oldestKey = pageAudioCache.keys.first
            if let oldestKey {
                pageAudioCache.removeValue(forKey: oldestKey)
            }
        }
    }
            isReadAloudPlaying = false
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
        highlightVerseEnabled = settings.highlightVerseEnabled
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
        history = Array(history.prefix(5))
        storageManager.saveHistory(history)
        storageManager.syncHistoryToFirebase(history)
    }
    
    // MARK: - Read Aloud Methods

    private let sampleReadAloudText = """
    ClearBrowser audio test. This is a sample passage to confirm that the read aloud button can send text to the configured server, receive synthesized speech, and play it back in the app.
    """

    func startSampleReadAloud() {
        currentReadAloudText = sampleReadAloudText
        isReadAloudPlaying = false
        isReadAloudAvailable = false
        audioContentCandidate = true
        audioRequestSent = false
        audioReceived = false

        Task {
            do {
                let player = try await serverManager.synthesizeSpeech(text: sampleReadAloudText)
                if let currentURL = self.currentURL {
                    self.cacheAudioData(self.serverManager.lastAudioData ?? Data(), for: currentURL)
                }
                serverManager.play(audioPlayer: player)
                isReadAloudPlaying = true
                isReadAloudAvailable = true
            } catch let error as AudioVixError {
                serverManager.errorMessage = error.localizedDescription
            } catch {
                serverManager.errorMessage = "Failed to synthesize sample audio: \(error.localizedDescription)"
            }
        }
    }
    
    func startReadAloud(from webView: WKWebView) {
        // Reset diagnostic flags for new request
        isReadAloudPlaying = false
        isReadAloudAvailable = false
        currentReadAloudText = ""
        audioContentCandidate = false
        audioRequestSent = false
        audioReceived = false
        
        serverManager.extractArticleContent(from: webView, notifyUser: true) { [weak self] content in
            guard let self = self, let content = content, !content.isEmpty else {
                self?.serverManager.errorMessage = "No article content found"
                return
            }
            self.currentReadAloudText = content

            Task {
                do {
                    let player = try await self.serverManager.synthesizeSpeech(text: content)
                    if let url = self.activeTab?.url, let audioData = self.serverManager.lastAudioData {
                        self.cacheAudioData(audioData, for: url)
                    }
                    await MainActor.run {
                        self.serverManager.play(audioPlayer: player)
                        self.isReadAloudPlaying = true
                        self.isReadAloudAvailable = true
                    }
                } catch let error as AudioVixError {
                    await MainActor.run {
                        self.serverManager.errorMessage = error.localizedDescription
                    }
                } catch {
                    await MainActor.run {
                        self.serverManager.errorMessage = "Failed to synthesize speech: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func pauseReadAloud() {
        serverManager.pause()
        isReadAloudPlaying = false
    }

    func resumeReadAloud() {
        serverManager.resume()
        isReadAloudPlaying = true
    }

    func stopReadAloud() {
        serverManager.stop()
        isReadAloudPlaying = false
        isReadAloudAvailable = false
        currentReadAloudText = ""
    }

    func setReadAloudSpeed(_ speed: Float) {
        serverManager.setPlaybackRate(speed)
    }
    
    // MARK: - Diagnostic Helper
    
    /// Returns a formatted status string showing the audio flow state
    var audioFlowDiagnostics: String {
        var status: [String] = []
        
        if audioContentCandidate {
            status.append("✓ Content found")
        } else {
            status.append("✗ No content")
        }
        
        if audioRequestSent {
            status.append("✓ Request sent")
        } else {
            status.append("○ Waiting")
        }
        
        if audioReceived {
            status.append("✓ Audio ready")
        } else if audioRequestSent {
            status.append("○ Loading...")
        }
        
        return status.joined(separator: " → ")
    }
}

extension HomeViewModel: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first ?? ASPresentationAnchor()
    }
}
