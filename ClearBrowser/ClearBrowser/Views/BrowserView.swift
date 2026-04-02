import SwiftUI
import WebKit

struct BrowserView: UIViewRepresentable {
    @ObservedObject var viewModel: HomeViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.bounces = true
        context.coordinator.autoScrollManager.scrollView = webView.scrollView

        if let url = viewModel.requestURL {
            webView.load(URLRequest(url: url))
            context.coordinator.lastLoadedURL = url
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
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
            context.coordinator.autoScrollManager.start()
        } else {
            context.coordinator.autoScrollManager.stop()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let viewModel: HomeViewModel
        let autoScrollManager: AutoScrollManager
        var lastLoadedURL: URL?

        init(viewModel: HomeViewModel) {
            self.viewModel = viewModel
            self.autoScrollManager = viewModel.autoScrollManager
            super.init()
            self.autoScrollManager.didStop = { [weak viewModel] in
                Task { @MainActor in
                    viewModel?.isAutoScrolling = false
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
    }
}
