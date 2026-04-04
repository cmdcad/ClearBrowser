import SwiftUI
import UIKit

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
        GeometryReader { geometry in
            if isOpen {
                ZStack(alignment: .trailing) {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .onTapGesture { isOpen = false }

                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.6))
                            .frame(width: 44, height: 5)
                            .padding(.top, 14)
                            .padding(.bottom, 14)

                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        content
                            .padding(.horizontal)
                            .padding(.top, 6)
                    }
                    .frame(width: min(geometry.size.width * 0.82, 360), height: geometry.size.height)
                    .background(.regularMaterial)
                    .cornerRadius(20, corners: [.topLeft, .bottomLeft])
                    .shadow(radius: 20, y: 5)
                    .offset(x: 0)
                    .transition(.move(edge: .trailing))
                    .gesture(
                        DragGesture(minimumDistance: 16)
                            .onEnded { value in
                                if value.translation.width > 100 {
                                    isOpen = false
                                }
                            }
                    )
                }
                .animation(.easeOut(duration: 0.22), value: isOpen)
            }
        }
    }
}

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
