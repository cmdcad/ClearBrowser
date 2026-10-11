import SwiftUI
import WebKit

/// URL metadata only: no page, form, or credential inspection.
struct BingSearchURLTracker {
    private(set) var lastQueryKey: String?
    private var day = BingQueries.localDate()
    static func query(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), host == "bing.com" || host.hasSuffix(".bing.com"),
              url.path == "/search", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = components.queryItems?.first(where: { $0.name == "q" })?.value else { return nil }
        let normalized = BingQueries.normalize(query)
        return normalized.isEmpty ? nil : normalized
    }
    mutating func finished(url: URL, succeeded: Bool, historyOrReload: Bool, on date: String = BingQueries.localDate()) -> String? {
        if day != date { lastQueryKey = nil; day = date }
        guard succeeded, let query = Self.query(from: url) else { return nil }
        let key = BingQueries.key(query), changed = key != lastQueryKey
        lastQueryKey = key
        return changed && !historyOrReload ? query : nil
    }
}

@MainActor
final class BingBotBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var webView: WKWebView
    @Published var address = "https://www.bing.com"
    @Published private(set) var progress = 0.0
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var isClearingSession = false
    @Published var message: String?
    private var observation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var currentNavigation: WKNavigation?
    private var skipNextNavigation = false
    private var skipCurrentNavigation = false
    private var responseFailed = false
    private var searchTracker = BingSearchURLTracker()
    var onSearchCompleted: ((String) -> Void)?

    // A dedicated persistent store retains BingBot website logins without sharing
    // ClearBrowser's default store or accessing cookie/credential contents.
    private static let storeID = UUID(uuidString: "90F6D93A-DF43-4F24-9F8E-663D3C542AF1")!
    private static func freshView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        return WKWebView(frame: .zero, configuration: configuration)
    }
    override init() {
        webView = Self.freshView()
        super.init()
        configure()
    }
    private func configure() {
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            let progress = view.estimatedProgress
            Task { @MainActor [weak self] in self?.progress = progress }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            let url = view.url
            Task { @MainActor [weak self] in
                guard let self, let url, self.webView.url == url,
                      !self.isClearingSession else { return }
                self.address = url.absoluteString
                // Bing can change its search URL through page history without
                // starting a WKNavigation. Full loads are handled by didFinish.
                guard !self.webView.isLoading, self.currentNavigation == nil else { return }
                self.recordSearch(url: url, historyOrReload: false)
            }
        }
        webView.load(URLRequest(url: URL(string: "https://www.bing.com")!))
    }
    static func validatedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.contains(":") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = components.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }), components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }
    func go(_ text: String) {
        guard !isClearingSession else { return }
        guard let url = Self.validatedURL(text) else { message = "Enter a valid HTTP or HTTPS address."; return }
        stopLoading(); webView.load(URLRequest(url: url))
    }
    func goBack() { guard !isClearingSession else { return }; stopLoading(); skipNextNavigation = true; webView.goBack() }
    func reload() { guard !isClearingSession else { return }; stopLoading(); skipNextNavigation = true; webView.reload() }
    func resetSearchTracking() { searchTracker = BingSearchURLTracker() }
    func stopLoading() { currentNavigation = nil; webView.stopLoading(); isLoading = false; skipNextNavigation = false }
    func resetSession() {
        guard !isClearingSession else { return }
        isClearingSession = true; stopLoading(); observation = nil; urlObservation = nil
        let store = webView.configuration.websiteDataStore
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        Task {
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            webView = Self.freshView(); address = "https://www.bing.com"; progress = 0; canGoBack = false
            searchTracker = BingSearchURLTracker(); isClearingSession = false
            configure()
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Sites use empty frames during sign-in and popup setup.
        if action.request.url?.absoluteString == "about:blank" {
            decisionHandler(.allow); return
        }
        guard let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            // Background frames and automatic app-link attempts should stay quiet.
            if action.navigationType == .linkActivated && action.targetFrame?.isMainFrame != false {
                message = "This link cannot open inside BingBot. Use an HTTP or HTTPS website link."
            }
            decisionHandler(.cancel); return
        }
        if action.targetFrame?.isMainFrame == true {
            skipNextNavigation = skipNextNavigation || action.navigationType == .backForward || action.navigationType == .reload
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse { responseFailed = http.statusCode >= 400 }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        currentNavigation = navigation; isLoading = true; responseFailed = false
        skipCurrentNavigation = skipNextNavigation; skipNextNavigation = false
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard currentNavigation === navigation, currentNavigation != nil else { return }
        currentNavigation = nil; isLoading = false; progress = 1; canGoBack = webView.canGoBack
        address = webView.url?.absoluteString ?? ""
        guard let url = webView.url else { return }
        recordSearch(url: url, historyOrReload: skipCurrentNavigation)
    }
    private func recordSearch(url: URL, historyOrReload: Bool) {
        if let query = searchTracker.finished(url: url, succeeded: !responseFailed, historyOrReload: historyOrReload) {
            onSearchCompleted?(query)
        }
    }
    private func failed(_ navigation: WKNavigation?, error: Error) {
        guard currentNavigation === navigation, currentNavigation != nil else { return }
        currentNavigation = nil; isLoading = false
        let failure = error as NSError
        guard !(failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) else { return }
        message = "The page could not load. Check your connection and retry. No search was counted."
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(navigation, error: error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(navigation, error: error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        currentNavigation = nil; isLoading = false; message = "The browser stopped unexpectedly. Reload the page. No search was counted."
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url { go(url.absoluteString) }
        return nil
    }
}

#if os(macOS)
struct BingBotWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct BingBotWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
