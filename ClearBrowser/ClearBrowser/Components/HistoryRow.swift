import SwiftUI

struct HistoryRow: View {
    let item: BrowserItem
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title ?? "Untitled")
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(item.url.absoluteString)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 72)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .contextMenu {
            Button(action: {
                UIPasteboard.general.url = item.url
            }) {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
        }
    }
}