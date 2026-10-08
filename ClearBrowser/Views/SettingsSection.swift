import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.xs)
            
            content
                .padding(Theme.Spacing.md)
                .background(Theme.secondary.opacity(0.5))
                .cornerRadius(Theme.Radius.md)
        }
    }
}