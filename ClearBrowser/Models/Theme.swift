import SwiftUI

struct Theme {
    static let primary = Color(uiColor: .systemBackground)
    static let secondary = Color(uiColor: .secondarySystemBackground)
    static let accent = Color.blue
    static let text = Color.primary
    static let textSecondary = Color.secondary
    static let border = Color(uiColor: .separator)
    
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
    
    struct Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
    }
}