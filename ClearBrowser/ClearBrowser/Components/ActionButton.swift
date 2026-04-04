import SwiftUI

struct ActionButton: View {
    let label: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12))
                .foregroundColor(tint)
                .cornerRadius(10)
                .accessibilityLabel(Text(label))
        }
    }
}