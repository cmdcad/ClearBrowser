import SwiftUI

struct BookmarkRow: View {
    let item: BrowserItem
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "globe").foregroundColor(.accentColor))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Text(item.url.host ?? item.url.absoluteString)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                onDelete?()
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(height: 80)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}