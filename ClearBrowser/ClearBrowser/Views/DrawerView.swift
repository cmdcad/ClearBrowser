import SwiftUI

struct DrawerView<Content: View>: View {
    let title: String
    @Binding var isOpen: Bool
    let content: Content

    init(title: String, isOpen: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isOpen = isOpen
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isOpen {
                // Dimmed backdrop with tap-to-dismiss
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    // Top handle + header
                    VStack(spacing: 12) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 44, height: 6)
                            .padding(.top, 8)

                        HStack {
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: { close() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 6)

                    // Content area
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal)
                        .padding(.bottom, safeAreaBottomPadding())
                }
                .background(
                    // Use a subtle visual effect for modern look
                    VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
                        .background(Color(uiColor: .systemBackground).opacity(0.6))
                )
                .cornerRadius(18, corners: [.topLeft, .topRight])
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: -8)
                .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .zIndex(100)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: isOpen)
    }

    private func close() {
        withAnimation { isOpen = false }
    }

    private func safeAreaBottomPadding() -> CGFloat {
        UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 20
    }
}

// VisualEffectBlur for SwiftUI (light wrapper around UIVisualEffectView)
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}