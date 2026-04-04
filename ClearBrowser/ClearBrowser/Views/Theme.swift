import SwiftUI

struct Theme {
    static let primary = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let secondary = Color(red: 0.12, green: 0.12, blue: 0.15)
    static let accent = Color.blue
    static let text = Color.white
    static let textSecondary = Color.gray
    static let border = Color.gray.opacity(0.2)

    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 48
    }

    struct Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 24
    }
}