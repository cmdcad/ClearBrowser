import Foundation

//enum DrawerType: String, CaseIterable {
//    case bookmarks = "Bookmarks"
//    case history = "History"
//    case settings = "Settings"
//    case favorites = "Favorites"
//}
enum DrawerType: String, Identifiable {
    case bookmarks, history, settings
    var id: String { self.rawValue }
}
