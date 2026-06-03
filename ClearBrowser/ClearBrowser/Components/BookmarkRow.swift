import SwiftUI

struct BookmarkRow: View {
    let item: BrowserItem
    

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
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
        }
        .padding(8)
        .frame(height: 72) 
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