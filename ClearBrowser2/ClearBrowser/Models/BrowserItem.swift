import Foundation

struct BrowserItem: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let url: URL
    let date: Date

    init(id: UUID = UUID(), title: String, url: URL, date: Date = .now) {
        self.id = id
        self.title = title
        self.url = url
        self.date = date
    }
}
