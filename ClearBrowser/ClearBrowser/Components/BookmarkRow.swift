import SwiftUI

struct BookmarkRow: View {
    let item: BrowserItem
    var onDelete: (() -> Void)? = nil
    
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
        .padding(8)
        .frame(height: 72)
        .background(Color(.systemBackground))
    }
}