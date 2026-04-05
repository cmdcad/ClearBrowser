import SwiftUI

struct ActionButton: View {
    let label: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
                
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}