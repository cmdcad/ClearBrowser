// SAMPLE HOME VIEWS - DESIGN VARIATIONS
// Use these as inspiration or drop-in replacements for HomeView.swift

// =============================================================================
// VARIANT 1: MINIMALIST DARK HOME
// =============================================================================

import SwiftUI
import WebKit
import Foundation


struct HomeViewMinimalist: View {
    @EnvironmentObject var appState: AppState
    @State private var searchInput = ""
    
    var body: some View {
        ZStack {
            Theme.primary.ignoresSafeArea()
            
            VStack(spacing: Theme.Spacing.xl) {
                // Header bar
                HStack {
                    Text("Search")
                        .font(.system(size: 32, weight: .bold, design: .default))
                        .foregroundColor(Theme.text)
                    
                    Spacer()
                    
//                    NavigationLink(destination: SettingsView()) {
//                        Image(systemName: "gear")
//                            .font(.system(size: 18, weight: .semibold))
//                            .foregroundColor(Theme.accent)
//                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                
                Spacer()
                
                // Big search input
                VStack(spacing: Theme.Spacing.lg) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(Theme.accent)
                        
                        TextField("Search or URL", text: $searchInput)
                            .font(.system(size: 18, weight: .semibold))
                            .textFieldStyle(.plain)
                            .foregroundColor(Theme.text)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(Theme.Spacing.lg)
                    .background(Theme.secondary)
                    .cornerRadius(Theme.Radius.md)
                    .onSubmit {
                        appState.handleInput(searchInput)
                    }
                    
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach([("Bookmarks", "bookmark"), ("History", "clock")], id: \.0) { label, icon in
                            Button(action: {
                                appState.openDrawer(label == "Bookmarks" ? .bookmarks : .history)
                            }) {
                                VStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: icon)
                                        .font(.system(size: 20))
                                    Text(label)
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(Theme.Spacing.md)
                                .background(Theme.secondary)
                                .cornerRadius(Theme.Radius.md)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                
                Spacer()
                
                // Quick links
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Quick Links")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, Theme.Spacing.lg)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(["Google", "GitHub", "Stack Overflow", "MDN"], id: \.self) { site in
                                Button(action: {
                                    appState.handleInput(site)
                                }) {
                                    Text(site)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Theme.accent)
                                        .padding(.horizontal, Theme.Spacing.md)
                                        .padding(.vertical, Theme.Spacing.sm)
                                        .background(Theme.secondary)
                                        .cornerRadius(Theme.Radius.sm)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.lg)
        }
    }
}

// =============================================================================
// VARIANT 2: CARD-BASED HOME
// =============================================================================

struct HomeViewCards: View {
    @EnvironmentObject var appState: AppState
    @State private var searchInput = ""
    @State private var selectedQuickLink: String?
    
    var body: some View {
        ZStack {
            Theme.primary.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("Browser")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                    
                    Spacer()
                    
                    Button(action: { appState.openDrawer(.settings) }) {
                        Image(systemName: "gear")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.accent)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        // Search card
                        VStack(spacing: Theme.Spacing.md) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(Theme.accent)
                                
                                TextField("Search or enter URL", text: $searchInput)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(Theme.text)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                
                                if !searchInput.isEmpty {
                                    Button(action: { searchInput = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.secondary)
                            .cornerRadius(Theme.Radius.md)
                            
                            Button(action: { appState.handleInput(searchInput) }) {
                                Text("Search")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.Spacing.md)
                                    .background(Theme.accent)
                                    .cornerRadius(Theme.Radius.md)
                            }
                        }
                        .padding(Theme.Spacing.lg)
                        .background(Theme.secondary)
                        .cornerRadius(Theme.Radius.lg)
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        // Stats cards
                        HStack(spacing: Theme.Spacing.md) {
                            StatCard(
                                value: "\(appState.bookmarks.count)",
                                label: "Saved",
                                icon: "bookmark.fill"
                            )
                            
                            StatCard(
                                value: "\(appState.history.count)",
                                label: "Visited",
                                icon: "clock.fill"
                            )
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        // Action cards
                        VStack(spacing: Theme.Spacing.md) {
                            ActionCardButton(
                                icon: "bookmark",
                                title: "Bookmarks",
                                subtitle: "Your saved pages",
                                action: { appState.openDrawer(.bookmarks) }
                            )
                            
                            ActionCardButton(
                                icon: "clock",
                                title: "History",
                                subtitle: "Recently visited",
                                action: { appState.openDrawer(.history) }
                            )
                            
                            ActionCardButton(
                                icon: "gear",
                                title: "Settings",
                                subtitle: "Preferences",
                                action: { appState.openDrawer(.settings) }
                            )
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                    .padding(.vertical, Theme.Spacing.lg)
                }
            }
        }
    }
}

// Helper components for card variant
struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Theme.accent)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.text)
            
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .background(Theme.secondary)
        .cornerRadius(Theme.Radius.md)
    }
}

struct ActionCardButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.primary)
                    .cornerRadius(Theme.Radius.md)
                
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Theme.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.secondary)
            .cornerRadius(Theme.Radius.md)
        }
    }
}

// =============================================================================
// VARIANT 3: GLASSMORPHISM HOME
// =============================================================================

struct HomeViewGlass: View {
    @EnvironmentObject var appState: AppState
    @State private var searchInput = ""
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.10, blue: 0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: Theme.Spacing.xl) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Welcome back")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                        
                        Text("Start exploring")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.text)
                    }
                    
                    Spacer()
                    
                    Button(action: { appState.openDrawer(.settings) }) {
                        Image(systemName: "gear")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(
                                Color.white.opacity(0.1)
                                    .blur(radius: 10)
                            )
                            .cornerRadius(Theme.Radius.md)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                
                Spacer()
                
                // Glass search card
                VStack(spacing: Theme.Spacing.md) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Theme.accent)
                        
                        TextField("Search or URL", text: $searchInput)
                            .textFieldStyle(.plain)
                            .foregroundColor(Theme.text)
                            .autocapitalization(.none)
                        
                        if !searchInput.isEmpty {
                            Button(action: { searchInput = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .background(
                        Color.white.opacity(0.1)
                            .blur(radius: 20)
                            .background(Color.white.opacity(0.05))
                    )
                    .cornerRadius(Theme.Radius.md)
                    .border(
                        Color.white.opacity(0.2),
                        width: 1
                    )
                    
                    Button(action: { appState.handleInput(searchInput) }) {
                        Text("Explore")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.accent)
                            .cornerRadius(Theme.Radius.md)
                    }
                }
                .padding(Theme.Spacing.lg)
                
                Spacer()
                
                // Quick actions
                VStack(spacing: Theme.Spacing.md) {
                    ForEach([
                        ("bookmark", "Bookmarks"),
                        ("clock", "History")
                    ], id: \.1) { icon, label in
                        Button(action: {
                            appState.openDrawer(label == "Bookmarks" ? .bookmarks : .history)
                        }) {
                            HStack {
                                Image(systemName: icon)
                                    .foregroundColor(Theme.accent)
                                Text(label)
                                    .foregroundColor(Theme.text)
                                Spacer()
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .padding(Theme.Spacing.lg)
                            .background(
                                Color.white.opacity(0.05)
                                    .blur(radius: 10)
                            )
                            .cornerRadius(Theme.Radius.md)
                            .border(
                                Color.white.opacity(0.1),
                                width: 1
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.xl)
        }
    }
}

// =============================================================================
// VARIANT 4: TABS-BASED HOME
// =============================================================================

struct HomeViewTabs: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: String = "search"
    @State private var searchInput = ""
    
    var body: some View {
        ZStack {
            Theme.primary.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(["search", "bookmarks", "history"], id: \.self) { tab in
                        VStack(spacing: Theme.Spacing.xs) {
                            Button(action: { selectedTab = tab }) {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: tabIcon(tab))
                                    Text(tabLabel(tab))
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(
                                    selectedTab == tab ? Theme.accent : Theme.textSecondary
                                )
                            }
                            
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Theme.accent)
                                    .frame(height: 3)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.secondary)
                
                Divider().background(Theme.border)
                
                // Content
                Group {
                    if selectedTab == "search" {
                        SearchTabContent(searchInput: $searchInput)
                            .environmentObject(appState)
                    } else if selectedTab == "bookmarks" {
                        BookmarksTabContent()
                            .environmentObject(appState)
                    } else {
                        HistoryTabContent()
                            .environmentObject(appState)
                    }
                }
                
                Spacer()
            }
        }
    }
    
    private func tabIcon(_ tab: String) -> String {
        switch tab {
        case "search": return "magnifyingglass"
        case "bookmarks": return "bookmark"
        case "history": return "clock"
        default: return "circle"
        }
    }
    
    private func tabLabel(_ tab: String) -> String {
        switch tab {
        case "search": return "Search"
        case "bookmarks": return "Saved"
        case "history": return "History"
        default: return ""
        }
    }
}

struct SearchTabContent: View {
    @EnvironmentObject var appState: AppState
    @Binding var searchInput: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textSecondary)
                
                TextField("Search or URL", text: $searchInput)
                    .textFieldStyle(.plain)
                    .foregroundColor(Theme.text)
                    .autocapitalization(.none)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.secondary)
            .cornerRadius(Theme.Radius.md)
            
            Button(action: { appState.handleInput(searchInput) }) {
                Text("Go")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.accent)
                    .cornerRadius(Theme.Radius.md)
            }
            
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }
}

struct BookmarksTabContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            if appState.bookmarks.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(Theme.textSecondary)
                    Text("No bookmarks")
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(appState.bookmarks) { bookmark in
                        Button(action: {
                            appState.loadURL(bookmark.url)
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                
                                Text(bookmark.url.host ?? "")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.md)
                            .background(Theme.secondary)
                            .cornerRadius(Theme.Radius.md)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }
}

struct HistoryTabContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            if appState.history.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "clock")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(Theme.textSecondary)
                    Text("No history")
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(appState.history.prefix(20)), id: \.id) { item in
                        Button(action: {
                            appState.loadURL(item.url)
                        }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                
                                Text(item.url.host ?? "")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.md)
                            .background(Theme.secondary)
                            .cornerRadius(Theme.Radius.md)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }
}

// =============================================================================
// PREVIEW
// =============================================================================

#Preview("Minimalist") {
    HomeViewMinimalist()
        .environmentObject(AppState())
}

#Preview("Cards") {
    HomeViewCards()
        .environmentObject(AppState())
}

#Preview("Glass") {
    HomeViewGlass()
        .environmentObject(AppState())
}

#Preview("Tabs") {
    HomeViewTabs()
        .environmentObject(AppState())
}
