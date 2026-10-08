import Foundation

struct BrowserTab: Identifiable, Codable, Equatable {
    let id: UUID
    var url: URL
    var title: String
    
    init(id: UUID = UUID(), url: URL, title: String = "New Tab") {
        self.id = id
        self.url = url
        self.title = title
    }
}