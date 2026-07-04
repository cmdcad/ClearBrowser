import SwiftUI
import WebKit

@MainActor
struct BrowserView: UIViewRepresentable {
    @ObservedObject var viewModel: HomeViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        viewModel.currentWebView = webView
        
        // Bypasses Google's 'disallowed_useragent' block by identifying as a standard Mobile Safari browser.
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

        context.coordinator.setupProgressObservation(for: webView)

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.bounces = true
        context.coordinator.autoScrollManager.scrollView = webView.scrollView
        print("[AutoScroll] makeUIView assigned scrollView: \(webView.scrollView)")

        if let url = viewModel.requestURL {
            webView.load(URLRequest(url: url))
            context.coordinator.lastLoadedURL = url
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if viewModel.currentWebView != uiView {
            viewModel.currentWebView = uiView
        }
        
        print("[AutoScroll] updateUIView called. isAutoScrolling=\(viewModel.isAutoScrolling), scrollView=\(String(describing: context.coordinator.autoScrollManager.scrollView))")
        if let requested = viewModel.requestURL,
           requested != context.coordinator.lastLoadedURL {
            uiView.load(URLRequest(url: requested))
            context.coordinator.lastLoadedURL = requested
        }

        if let command = viewModel.navigationCommand {
            switch command {
            case .back:
                if uiView.canGoBack { uiView.goBack() }
            case .forward:
                if uiView.canGoForward { uiView.goForward() }
            case .reload:
                uiView.reload()
            case .stop:
                uiView.stopLoading()
            }
            DispatchQueue.main.async {
                self.viewModel.navigationCommand = nil
            }
        }

        if viewModel.isAutoScrolling {
            context.coordinator.autoScrollManager.speed = CGFloat(viewModel.autoScrollSpeed)
            print("[AutoScroll] requesting start() from updateUIView; speed=\(viewModel.autoScrollSpeed)")
            context.coordinator.autoScrollManager.start()
        } else if context.coordinator.autoScrollManager.isRunning {
            print("[AutoScroll] requesting stop() from updateUIView")
            context.coordinator.autoScrollManager.stop()
        }

    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate {
        let viewModel: HomeViewModel
        let autoScrollManager: AutoScrollManager
        var lastLoadedURL: URL?
        private var progressObservation: NSKeyValueObservation?

        init(viewModel: HomeViewModel) {
            self.viewModel = viewModel
            self.autoScrollManager = viewModel.autoScrollManager
            super.init()
                self.autoScrollManager.didStop = { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                Task { @MainActor in
                    print("[AutoScroll] didStop closure running; clearing viewModel.isAutoScrolling")
                    viewModel.isAutoScrolling = false
                }
                }
        }

        deinit {
            progressObservation?.invalidate()
        }

        func setupProgressObservation(for webView: WKWebView) {
            // Use KVO to monitor the loading progress of the WKWebView
            progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] _, change in
                guard let progress = change.newValue, let viewModel = self?.viewModel else { return }
                // Switch to the MainActor to update the published loadingProgress
                Task { @MainActor in
                    viewModel.loadingProgress = progress
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.isLoading = false
            viewModel.updateNavigationState(canGoBack: webView.canGoBack,
                                            canGoForward: webView.canGoForward,
                                            title: webView.title,
                                            url: webView.url)
            autoScrollManager.scrollView = webView.scrollView
            print("[AutoScroll] webView didFinish: assigned scrollView -> \(webView.scrollView)")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.isLoading = false
            viewModel.updateNavigationState(canGoBack: webView.canGoBack,
                                            canGoForward: webView.canGoForward,
                                            title: webView.title,
                                            url: webView.url)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            viewModel.isLoading = false
        }
        
        func webView(_ webView: WKWebView,
             decidePolicyFor navigationAction: WKNavigationAction,
             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            let url = navigationAction.request.url!

            // Check if this URL is forced to open in-app (blocked scheme or domain)
            if viewModel.isForcedInApp(url) {
                // If it's a non-http(s) scheme (like twitter://), cancel to prevent the external app from opening
                if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
                    decisionHandler(.cancel)
                    return
                }
                
                // If it's a web link and the user tapped it, cancel standard navigation 
                // to prevent Universal Links, and manually load it to force it in WKWebView.
                if navigationAction.navigationType == .linkActivated {
                    decisionHandler(.cancel)
                    webView.load(URLRequest(url: url))
                    return
                }
            }

            // Block universal links from opening externally for other non-http schemes
            if navigationAction.navigationType == .linkActivated {
                if !url.absoluteString.hasPrefix("http") {
                    decisionHandler(.cancel)
                    return
                }
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Intercept navigation attempts that would normally open in a new window or tab.
            // Instead of returning a new WKWebView, we load the request in the current one.
            guard navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false else {
                return nil
            }
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // MARK: - UIScrollViewDelegate
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Only update visibility if the user is actively dragging
            guard scrollView.isDragging else { return }
            
            let translation = scrollView.panGestureRecognizer.translation(in: scrollView.superview)
            
            if viewModel.toolbarPosition == .top {
                // Top Bar Logic
                if translation.y < -10 {
                    // Swiping Up (Scrolling Down) -> Hide Header
                    if viewModel.isHeaderVisible {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.isHeaderVisible = false
                        }
                    }
                } else if translation.y > 10 {
                    // Swiping Down (Scrolling Up) -> Show Header
                    if !viewModel.isHeaderVisible {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.isHeaderVisible = true
                        }
                    }
                }
            } else {
                // Bottom Bar Logic
                if translation.y > 10 {
                    // Swiping Down (Scrolling Up) -> Hide Header
                    if viewModel.isHeaderVisible {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.isHeaderVisible = false
                        }
                    }
                } else if translation.y < -10 {
                    // Swiping Up (Scrolling Down) -> Show Header
                    if !viewModel.isHeaderVisible {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.isHeaderVisible = true
                        }
                    }
                }
            }
        }
    }
}
