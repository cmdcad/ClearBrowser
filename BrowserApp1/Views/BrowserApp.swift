import SwiftUI
import WebKit
import Foundation
import UIKit

import SwiftUI

@main
struct BrowserApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(nil)
        }
    }
}

// MARK: - Theme Configuration
struct Theme {
    static let primary = Color(red: 0.1, green: 0.1, blue: 0.12)
    static let secondary = Color(red: 0.15, green: 0.15, blue: 0.17)
    static let accent = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let text = Color(red: 0.95, green: 0.95, blue: 0.96)
    static let textSecondary = Color(red: 0.7, green: 0.7, blue: 0.72)
    static let border = Color(red: 0.25, green: 0.25, blue: 0.27)
    
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    struct Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }
}