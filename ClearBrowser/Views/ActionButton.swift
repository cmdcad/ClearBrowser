import SwiftUI

struct ActionButton: View {
    let label: String
    let symbol: String
    let tint: Color
    var isActive: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isEnabled ? (isActive ? .white : tint) : .gray)
                    .frame(width: 40, height: 40)
                    .background(isEnabled ? (isActive ? tint : tint.opacity(0.12)) : Color.gray.opacity(0.1))
                    .clipShape(Circle())
                
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isEnabled ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}