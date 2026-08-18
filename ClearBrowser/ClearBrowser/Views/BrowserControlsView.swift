import SwiftUI

struct BrowserControlsView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) { 

            HStack(spacing: 12) {
                ActionButton(label: "Back", symbol: "chevron.left", tint: .purple, isEnabled: viewModel.canGoBack) {
                    viewModel.goBack()
                }

                ActionButton(label: "Forward", symbol: "chevron.right", tint: .teal, isEnabled: viewModel.canGoForward) {
                    viewModel.goForward()
                }

                ActionButton(
                    label: viewModel.isAutoScrolling ? "Pause" : "Auto Scroll",
                    symbol: viewModel.isAutoScrolling ? "pause.fill" : "play.fill",
                    tint: .green,
                    isActive: viewModel.isAutoScrolling
                ) {
                    viewModel.toggleAutoScroll()
                }

                ActionButton(
                    label: viewModel.isReadAloudPlaying ? "Pause" : "Read Aloud",
                    symbol: viewModel.isReadAloudPlaying ? "pause.circle.fill" : "play.circle.fill",
                    tint: .orange,
                    isEnabled: viewModel.isReadAloudPlaying || viewModel.isReadAloudAvailable || viewModel.currentWebView != nil
                ) {
                    if viewModel.isReadAloudPlaying {
                        viewModel.pauseReadAloud()
                    } else if viewModel.isReadAloudAvailable {
                        viewModel.resumeReadAloud()
                    } else if let webView = viewModel.currentWebView {
                        viewModel.startReadAloud(from: webView)
                    }
                }

                if viewModel.isReadAloudPlaying {
                    ActionButton(label: "Stop", symbol: "stop.fill", tint: .red) {
                        viewModel.stopReadAloud()
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
        } 
    }
}
