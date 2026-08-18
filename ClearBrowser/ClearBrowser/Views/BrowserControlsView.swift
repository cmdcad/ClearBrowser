import SwiftUI

struct BrowserControlsView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close browser controls")
                
                Spacer()

                Text("Browser Controls")
                    .font(.headline)
            }

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
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 70 {
                    onDismiss()
                }
            }
        )
    }
}
