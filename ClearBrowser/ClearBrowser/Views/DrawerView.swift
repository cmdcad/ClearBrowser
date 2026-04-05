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
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isOpen = false
                        }
                    }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 20)

                    content
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 40)
                }
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(25, corners: [.topLeft, .topRight])
                .transition(.move(edge: .bottom))
                .shadow(radius: 10)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .zIndex(100)
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