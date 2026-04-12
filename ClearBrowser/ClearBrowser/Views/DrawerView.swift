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
        ZStack(alignment: .trailing) {
            // Background Dimming Overlay
            if isOpen {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isOpen = false
                        }
                    }
                    .transition(.opacity)
            }

            // Side Panel
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(.title3.bold())
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isOpen = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)

                Divider()

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: UIScreen.main.bounds.width * 0.85)
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(20, corners: [.topLeft, .bottomLeft])
            .shadow(color: .black.opacity(0.1), radius: 10, x: -5, y: 0)
        }
        .ignoresSafeArea(edges: .bottom)
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