import SwiftUI
import WebKit
import Foundation
import UIKit

struct DrawerView: View {
    @EnvironmentObject var appState: AppState
    let drawer: DrawerType
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            ZStack(alignment: .topLeading) {
                Theme.primary.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text(drawerTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.text)
                        
                        Spacer()
                        
                        Button(action: { appState.closeDrawer() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.lg)
                    .background(Theme.secondary)
                    .overlay(
                        Divider().offset(y: 56),
                        alignment: .bottom
                    )
                    
                    // Content
                    Group {
                        switch drawer {
                        case .bookmarks:
                            BookmarksDrawerContent()
                        case .history:
                            HistoryDrawerContent()
                        case .settings:
                            SettingsDrawerContent()
                        }
                    }
                    .environmentObject(appState)
                    
                    Spacer()
                }
            }
            .frame(width: 320)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Theme.border, lineWidth: 1),
                alignment: .leading
            )
        }
    }
    
    var drawerTitle: String {
        switch drawer {
        case .bookmarks: return "Bookmarks"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }
}

// MARK: - Bookmarks Content
struct BookmarksDrawerContent: View {
    @EnvironmentObject var appState: AppState
    @State private var showAlert = false
    @State private var selectedBookmark: Bookmark?
    
    var body: some View {
        ScrollView {
            if appState.bookmarks.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(Theme.textSecondary)
                    
                    Text("No bookmarks yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                    
                    Text("Save pages to access them quickly")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(appState.bookmarks) { bookmark in
                        HStack(spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                    .lineLimit(1)
                                
                                Text(bookmark.url.host ?? bookmark.url.absoluteString)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                selectedBookmark = bookmark
                                showAlert = true
                            }) {
                                Image(systemName: "ellipsis")
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.secondary)
                        .cornerRadius(Theme.Radius.md)
                        .onTapGesture {
                            appState.loadURL(bookmark.url)
                            appState.closeDrawer()
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .alert("Bookmark", isPresented: $showAlert, presenting: selectedBookmark) { bookmark in
            Button("Open", action: {
                appState.loadURL(bookmark.url)
                appState.closeDrawer()
            })
            Button("Delete", role: .destructive, action: {
                appState.removeBookmark(bookmark)
            })
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - History Content
struct HistoryDrawerContent: View {
    @EnvironmentObject var appState: AppState
    @State private var showClearAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if appState.history.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "clock")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(Theme.textSecondary)
                        
                        Text("No history yet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                        
                        Text("Your browsing history will appear here")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.xl)
                } else {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(Array(appState.history.enumerated()), id: \.element.id) { index, item in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                HStack(spacing: Theme.Spacing.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Theme.text)
                                            .lineLimit(1)
                                        
                                        Text(item.url.host ?? item.url.absoluteString)
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundColor(Theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(timeAgo(item.visitedAt))
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .padding(Theme.Spacing.md)
                                .background(Theme.secondary)
                                .cornerRadius(Theme.Radius.md)
                                .onTapGesture {
                                    appState.loadURL(item.url)
                                    appState.closeDrawer()
                                }
                                
                                if index < appState.history.count - 1 {
                                    Divider()
                                        .background(Theme.border)
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
            
            Divider()
                .background(Theme.border)
            
            Button(role: .destructive, action: { showClearAlert = true }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear History")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.md)
            }
            .alert("Clear History", isPresented: $showClearAlert) {
                Button("Delete", role: .destructive, action: appState.clearHistory)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This cannot be undone")
            }
        }
    }
    
    private func timeAgo(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let components = calendar.dateComponents([.hour, .minute], from: date, to: now)
            if let hour = components.hour, hour > 0 {
                return "\(hour)h ago"
            } else if let minute = components.minute, minute > 0 {
                return "\(minute)m ago"
            } else {
                return "Just now"
            }
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Settings Content
struct SettingsDrawerContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Search Engine
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Search Engine")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                    
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(SearchEngine.allCases, id: \.self) { engine in
                            Button(action: {
                                appState.searchEngine = engine
                                appState.saveSettings()
                            }) {
                                Text(engine.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(
                                        appState.searchEngine == engine ? .white : Theme.textSecondary
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.Spacing.md)
                                    .background(
                                        appState.searchEngine == engine ? Theme.accent : Theme.secondary
                                    )
                                    .cornerRadius(Theme.Radius.md)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.secondary)
                .cornerRadius(Theme.Radius.md)
                
                // Auto Scroll Speed
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Text("Auto Scroll Speed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f", appState.autoScrollSpeed))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.accent)
                    }
                    
                    Slider(
                        value: $appState.autoScrollSpeed,
                        in: 0.5...3.0,
                        step: 0.1
                    )
                    .tint(Theme.accent)
                    .onChange(of: appState.autoScrollSpeed) { newValue in
                        appState.updateAutoScrollSpeed(newValue)
                    }
                    
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Slower")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Text("Faster")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.secondary)
                .cornerRadius(Theme.Radius.md)
                
                // Account Info
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Account")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                    
                    Button(action: {}) {
                        HStack {
                            Text("Create Account")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.accent)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundColor(Theme.accent)
                        }
                        .padding(Theme.Spacing.md)
                    }
                    
                    Button(action: {}) {
                        HStack {
                            Text("Login")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.accent)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundColor(Theme.accent)
                        }
                        .padding(Theme.Spacing.md)
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.secondary)
                .cornerRadius(Theme.Radius.md)
                
                // Info
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Version")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Text("1.0.0")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.text)
                    }
                    
                    Divider()
                        .background(Theme.border)
                    
                    HStack {
                        Text("Build")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Text("2025.1")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.text)
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.secondary)
                .cornerRadius(Theme.Radius.md)
            }
            .padding(Theme.Spacing.lg)
        }
    }
}

#Preview {
    ZStack {
        Theme.primary.ignoresSafeArea()
        DrawerView(drawer: .bookmarks)
            .environmentObject(AppState())
    }
}