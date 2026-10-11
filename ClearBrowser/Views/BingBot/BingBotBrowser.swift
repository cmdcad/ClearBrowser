import SwiftUI
import WebKit

@MainActor
final class BingBotBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var webView: WKWebView
    @Published var address = "https://www.bing.com"
    @Published private(set) var progress = 0.0
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published var message: String?
    private var observation: NSKeyValueObservation?
    private var automated: (navigation: WKNavigation, token: UUID, query: String)?
    var onSuccess: ((UUID) -> Void)?
    var onFailure: ((UUID) -> Void)?
    var onManualNavigation: (() -> Void)?

    private static func freshView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
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
        webView.load(URLRequest(url: URL(string: "https://www.bing.com")!))
    }
    func navigate(to url: URL, token: UUID) {
        stopLoading()
        guard let navigation = webView.load(URLRequest(url: url)) else { onFailure?(token); return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
        automated = (navigation, token, query)
    }
    static func validatedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.contains(":") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = components.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              components.user == nil, components.password == nil, let url = components.url else { return nil }
        return url
    }
    func go(_ text: String) {
        guard let url = Self.validatedURL(text) else { message = "Enter a valid HTTP or HTTPS address."; return }
        onManualNavigation?(); stopLoading(); webView.load(URLRequest(url: url))
    }
    func goBack() { onManualNavigation?(); stopLoading(); webView.goBack() }
    func reload() { onManualNavigation?(); stopLoading(); webView.reload() }
    func stopLoading() { automated = nil; webView.stopLoading(); isLoading = false }
    func resetSession() {
        onManualNavigation?(); stopLoading(); observation = nil
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView = Self.freshView(); address = "https://www.bing.com"; progress = 0; canGoBack = false
        configure()
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            message = "This browser supports HTTP and HTTPS pages only."
            decisionHandler(.cancel); return
        }
        if action.navigationType == .linkActivated || action.navigationType == .formSubmitted || action.navigationType == .formResubmitted {
            onManualNavigation?(); automated = nil
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400,
           let expected = automated {
            automated = nil; isLoading = false; onFailure?(expected.token)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { isLoading = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false; progress = 1; canGoBack = webView.canGoBack
        address = webView.url?.absoluteString ?? ""
        guard let expected = automated, expected.navigation === navigation else { return }
        automated = nil
        guard let url = webView.url, let host = url.host?.lowercased(),
              host == "bing.com" || host.hasSuffix(".bing.com"), url.path == "/search",
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value,
              BingQueries.key(query) == BingQueries.key(expected.query) else { onFailure?(expected.token); return }
        onSuccess?(expected.token)
    }
    private func failed(_ navigation: WKNavigation?) {
        isLoading = false
        guard let expected = automated, expected.navigation === navigation else { return }
        automated = nil; onFailure?(expected.token)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(navigation) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(navigation) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let expected = automated { automated = nil; onFailure?(expected.token) }
        isLoading = false; message = "The browser stopped unexpectedly. Reload the page or retry your search."
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
