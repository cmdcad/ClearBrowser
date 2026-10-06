import SwiftUI

struct CapsuleActionButton: View {
    let symbol: String
    let tint: Color
    var isActive: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isEnabled ? (isActive ? .white : tint) : .gray)
                .frame(width: 32, height: 10)
                .background(isEnabled ? (isActive ? tint : tint.opacity(0.3)) : Color.gray.opacity(0.3))
                .clipShape(Capsule())
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
    }
}

struct BrowserControlsView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {

            HStack(spacing: 12) {
                CapsuleActionButton(symbol: "chevron.left", tint: .purple, isEnabled: viewModel.canGoBack) {
                    viewModel.goBack()
                }

                CapsuleActionButton(symbol: "chevron.right", tint: .teal, isEnabled: viewModel.canGoForward) {
                    viewModel.goForward()
                }

                Spacer()
                    .frame(width: 20)

                CapsuleActionButton(
                    symbol: viewModel.isAutoScrolling ? "pause.fill" : "play.fill",
                    tint: .green,
                    isActive: viewModel.isAutoScrolling
                ) {
                    viewModel.toggleAutoScroll()
                }

                CapsuleActionButton(
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
                    CapsuleActionButton(symbol: "stop.fill", tint: .red) {
                        viewModel.stopReadAloud()
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}
