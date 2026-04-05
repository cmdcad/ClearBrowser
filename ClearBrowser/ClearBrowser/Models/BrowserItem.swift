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
 
