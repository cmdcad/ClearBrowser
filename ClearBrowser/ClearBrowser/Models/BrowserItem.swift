import Foundation
import SwiftUI

struct BrowserItem: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let url: URL
    let timestamp: Date
    
    init(id: UUID = UUID(), title: String, url: URL, timestamp: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.timestamp = timestamp
    }
}

struct BookmarkRow: View {
    let item: BrowserItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "safari.fill")
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(item.url.absoluteString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

typealias HistoryRow = BookmarkRow