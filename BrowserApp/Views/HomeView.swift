import SwiftUI
import WebKit
import Foundation
import UIKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchInput = ""
    @State private var showAIResults = false
    
    var body: some View {
        ZStack {
            Theme.primary.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("Browser")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundColor(Theme.text)
                    
                    Spacer()
                    
                    Button(action: { appState.openDrawer(.settings) }) {
                        Image(systemName: "gear")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.secondary.opacity(0.5))
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        // Logo/Hero space
                        VStack(spacing: Theme.Spacing.md) {
                            Text("Search the web")
                                .font(.system(size: 24, weight: .semibold, design: .default))
                                .foregroundColor(Theme.text)
                            
                            Text("or enter a URL")
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.top, Theme.Spacing.xxl)
                        
                        // Search input
                        VStack(spacing: Theme.Spacing.md) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(Theme.textSecondary)
                                
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
                            .onSubmit {
                                appState.handleInput(searchInput)
                            }
                            
                            // Action buttons
                            HStack(spacing: Theme.Spacing.md) {
                                Button(action: {
                                    appState.handleInput(searchInput)
                                }) {
                                    HStack(spacing: Theme.Spacing.sm) {
                                        Image(systemName: "magnifyingglass")
                                        Text("Search")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.Spacing.md)
                                    .background(Theme.accent)
                                    .cornerRadius(Theme.Radius.md)
                                }
                                
                                Button(action: { appState.openDrawer(.bookmarks) }) {
                                    HStack(spacing: Theme.Spacing.sm) {
                                        Image(systemName: "bookmark")
                                        Text("Bookmarks")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Theme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.Spacing.md)
                                    .background(Theme.secondary)
                                    .cornerRadius(Theme.Radius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                                            .stroke(Theme.accent, lineWidth: 1)
                                    )
                                }
                            }
                            
                            HStack(spacing: Theme.Spacing.md) {
                                Button(action: { appState.openDrawer(.history) }) {
                                    HStack(spacing: Theme.Spacing.sm) {
                                        Image(systemName: "clock")
                                        Text("History")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Theme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.Spacing.md)
                                    .background(Theme.secondary)
                                    .cornerRadius(Theme.Radius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                                            .stroke(Theme.accent, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        // Quick stats
                        HStack(spacing: Theme.Spacing.lg) {
                            VStack(spacing: Theme.Spacing.sm) {
                                Text("\(appState.bookmarks.count)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Theme.accent)
                                Text("Bookmarks")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Theme.Spacing.md)
                            .background(Theme.secondary)
                            .cornerRadius(Theme.Radius.md)
                            
                            VStack(spacing: Theme.Spacing.sm) {
                                Text("\(appState.history.count)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Theme.accent)
                                Text("History")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Theme.Spacing.md)
                            .background(Theme.secondary)
                            .cornerRadius(Theme.Radius.md)
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        // AI Search Section
                        VStack(spacing: Theme.Spacing.md) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(Theme.accent)
                                
                                TextField("Ask AI about...", text: $appState.searchQuery)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(Theme.text)
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.secondary)
                            .cornerRadius(Theme.Radius.md)
                            
                            Button(action: {
                                if !appState.searchQuery.isEmpty {
                                    appState.performAISearch(appState.searchQuery)
                                    showAIResults = true
                                }
                            }) {
                                if appState.aiLoading {
                                    HStack(spacing: Theme.Spacing.sm) {
                                        ProgressView()
                                            .tint(Theme.accent)
                                        Text("Thinking...")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                } else {
                                    Text("Get AI Response")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.accent)
                            .cornerRadius(Theme.Radius.md)
                            .disabled(appState.aiLoading || appState.searchQuery.isEmpty)
                            
                            if let response = appState.aiResponse, showAIResults {
                                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                    HStack {
                                        Text("AI Response")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Theme.textSecondary)
                                        
                                        Spacer()
                                        
                                        Button(action: { showAIResults = false }) {
                                            Image(systemName: "xmark")
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                    }
                                    
                                    Text(response)
                                        .font(.system(size: 14, weight: .regular, design: .default))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(nil)
                                }
                                .padding(Theme.Spacing.lg)
                                .background(Theme.secondary)
                                .cornerRadius(Theme.Radius.md)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}