import SwiftUI
import WebKit

struct BrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var urlInput = ""
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Browser toolbar
                BrowserToolbar()
                    .environmentObject(appState)
                
                // URL input bar
                URLInputBar(urlInput: $urlInput)
                    .environmentObject(appState)
                
                // Web view
                WebViewContainer()
                    .environmentObject(appState)
                
                
                // Bottom action bar
                BrowserBottomBar()
                    .environmentObject(appState)
            }
            .background(Theme.primary.ignoresSafeArea())
        }
    }
}

// MARK: - Browser Toolbar
struct BrowserToolbar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: { appState.goHome() }) {
                Image(systemName: "house.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 44, height: 44)
            }
            
            Button(action: { appState.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(appState.canGoBack ? Theme.accent : Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(!appState.canGoBack)
            
            Button(action: { appState.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(appState.canGoForward ? Theme.accent : Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(!appState.canGoForward)
            
            Button(action: { appState.reload() }) {
                if appState.isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .frame(width: 44, height: 44)
                }
            }
            .disabled(appState.isLoading)
            
            Spacer()
            
            Button(action: { appState.toggleDrawer(.bookmarks) }) {
                Image(systemName: "bookmark\(appState.activeDrawer == .bookmarks ? ".fill" : "")")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(appState.activeDrawer == .bookmarks ? Theme.accent : Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            
            Button(action: { appState.toggleDrawer(.history) }) {
                Image(systemName: "clock\(appState.activeDrawer == .history ? ".fill" : "")")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(appState.activeDrawer == .history ? Theme.accent : Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.secondary)
        .overlay(
            Divider().offset(y: 22),
            alignment: .bottom
        )
    }
}

// MARK: - URL Input Bar
struct URLInputBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var urlInput: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "globe")
                .foregroundColor(Theme.textSecondary)
            
            TextField("Search or enter URL", text: $urlInput)
                .textFieldStyle(.plain)
                .foregroundColor(Theme.text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($isFocused)
                .onSubmit {
                    appState.handleInput(urlInput)
                    urlInput = ""
                    isFocused = false
                }
            
            if !urlInput.isEmpty {
                Button(action: { urlInput = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.secondary)
    }
}

// MARK: - Web View Container
struct WebViewContainer: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            WebViewRepresentable()
                .environmentObject(appState)
            
            if appState.isLoading {
                VStack {
                    ProgressView()
                        .tint(Theme.accent)
                    Text("Loading...")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.1))
            }
        }
    }
}

// MARK: - WebView Representable
struct WebViewRepresentable: UIViewRepresentable {
    @EnvironmentObject var appState: AppState
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = appState
        webView.uiDelegate = appState
        webView.backgroundColor = UIColor(Theme.primary)
        webView.isOpaque = false
        
        appState.webView = webView
        
        // Load default page if needed
        if appState.currentURL == nil {
            let html = """
            <!DOCTYPE html>
            <html style="background: #1a1a1f; color: #f2f2f4; font-family: -apple-system;">
            <body style="margin: 0; padding: 40px; text-align: center;">
                <h1 style="font-size: 32px; margin: 0 0 16px 0;">Ready to browse</h1>
                <p style="color: #b2b2b4;">Enter a URL above or search to get started</p>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Update is handled via AppState
    }
}

// MARK: - Bottom Bar
struct BrowserBottomBar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Theme.border)
            
            HStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.pageTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    
                    if let url = appState.currentURL {
                        Text(url.host ?? url.absoluteString)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button(action: { appState.toggleAutoScroll() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.down.forward")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Auto")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(appState.autoScrollEnabled ? Theme.accent : Theme.textSecondary)
                    .frame(width: 50)
                }
                
                Button(action: {
                    if let url = appState.currentURL {
                        appState.addBookmark(url: url, title: appState.pageTitle)
                    }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Save")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Theme.accent)
                    .frame(width: 50)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.secondary)
        }
    }
}

#Preview {
    BrowserView()
        .environmentObject(AppState())
}
