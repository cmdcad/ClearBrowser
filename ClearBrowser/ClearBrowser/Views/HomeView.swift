import SwiftUI
import WebKit
import Foundation

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchInput = ""
    @State private var showAIResults = false
    
    // Fixed: Local state for AI search to prevent direct @EnvironmentObject mutation issues
    @State private var aiSearchQuery = ""
    
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
                        // Hero section
                        VStack(spacing: Theme.Spacing.md) {
                            Text("Search the web")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(Theme.text)
                            
                            Text("or enter a URL")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.top, Theme.Spacing.xxl)
                        
                        // Professional Search Bar (same height, cleaner look)
                        VStack(spacing: Theme.Spacing.md) {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(Theme.textSecondary)
                                    .font(.system(size: 18))
                                
                                TextField("Search or enter URL", text: $searchInput)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(Theme.text)
                                    .font(.system(size: 17))
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                
                                if !searchInput.isEmpty {
                                    Button(action: { searchInput = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Theme.textSecondary)
                                            .font(.system(size: 18))
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.md)   // Same height as before
                            .background(
                                Theme.secondary
                                    .cornerRadius(Theme.Radius.md)
                                    .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 3)
                            )
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
                        
                        // AI Search Section (fixed)
                        VStack(spacing: Theme.Spacing.md) {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(Theme.accent)
                                    .font(.system(size: 18))
                                
                                TextField("Ask AI about...", text: $aiSearchQuery)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(Theme.text)
                                    .font(.system(size: 17))
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.secondary)
                            .cornerRadius(Theme.Radius.md)
                            
                            Button(action: {
                                if !aiSearchQuery.isEmpty {
                                    appState.searchQuery = aiSearchQuery
                                    appState.performAISearch(aiSearchQuery)
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
                            .disabled(appState.aiLoading || aiSearchQuery.isEmpty)
                            
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
                                        .font(.system(size: 14, weight: .regular))
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
 
  private var headerContent: some View {
    VStack(spacing: 14) {
      searchBar
      actionRow
        .padding(.horizontal, 16)
      if viewModel.showAIField {
        AIResponseView(
          query: $viewModel.aiQuery,
          response: viewModel.aiResponse,
          isWorking: viewModel.isAIWorking,
          onSubmit: viewModel.fetchAIResponse
        )
        .padding(.top, 4)
        .padding(.horizontal, 16)
      }
    }
  }

  private var drawerTitle: String {
    switch viewModel.selectedDrawer {
    case .bookmarks: return "Bookmarks"
    case .history: return "History"
    case .settings: return "Settings"
    case .none: return ""
    }
  }

  private var searchBar: some View {
    HStack(spacing: 12) {
      TextField(
        "Search or enter URL", text: $viewModel.addressBarText, onCommit: viewModel.loadAddress
      )
      .textFieldStyle(.roundedBorder)
      .keyboardType(.URL)
      .autocorrectionDisabled(true)
      .textInputAutocapitalization(.never)
      .submitLabel(.go)

      ActionButton(label: "Reload", symbol: "arrow.clockwise", tint: .blue) {
        viewModel.reload()
      }

      ActionButton(label: "Bookmarks", symbol: "bookmark.add.plus", tint: .green) {
        viewModel.selectedDrawer = .bookmarks
      }
    }
    .padding(.horizontal, 16)
  }

  private var actionRow: some View {
    //ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ActionButton(label: "Search", symbol: "magnifyingglass", tint: .blue) {
          viewModel.openSearchEngineHome()
        }

        ActionButton(label: "Bookmarks", symbol: "bookmark", tint: .green) {
          viewModel.selectedDrawer = .bookmarks
        }

        ActionButton(label: "History", symbol: "clock.arrow.circlepath", tint: .orange) {
          viewModel.selectedDrawer = .history
        }

        ActionButton(label: "Settings", symbol: "gearshape", tint: .purple) {
          viewModel.selectedDrawer = .settings
        }

        ActionButton(label: "AI", symbol: "bubble.left.and.bubble.right", tint: .teal) {
          viewModel.toggleAIField()
        }

        Spacer()

        HStack(spacing: 12) {   
            ActionButton(label: "back", symbol: "chevron.left", tint: .purple) {
            viewModel.goBack()
            } 
            ActionButton(label: "forward", symbol: "chevron.right", tint: .teal) {
            viewModel.goForward()
            } 
        } 
    //   }
    //   .padding(.vertical, 4)
    }
  }

  private var statusOverlay: some View {
    VStack {
      if viewModel.isLoading {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle())
          .padding(10)
          .background(.regularMaterial)
          .cornerRadius(16)
          .padding(.top, 12)
      }
      Spacer()
    }
  }
 

// MARK: - Drawer Content (Improved)
@ViewBuilder
private var drawerContent: some View {
    switch viewModel.selectedDrawer {
    case .bookmarks:
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.bookmarks.isEmpty {
                Text("No bookmarks yet.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(viewModel.bookmarks) { item in
                        BookmarkRow(item: item)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        viewModel.removeBookmark(item)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        
    case .history:
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent history")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    viewModel.clearHistory()
                }
                .buttonStyle(.bordered)
            }
            
            if viewModel.history.isEmpty {
                Text("No history yet.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(viewModel.history) { item in
                        HistoryRow(item: item) { 
                            withAnimation {
                                viewModel.removeHistoryItem(item)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        
    case .settings:
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: "Search") {
                    Picker("Search Engine", selection: $viewModel.defaultSearchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.title).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SettingsSection(title: "Appearance") {
                    Picker("Toolbar Position", selection: $viewModel.toolbarPosition) {
                        ForEach(ToolbarPosition.allCases) { pos in
                            Text(pos.title).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SettingsSection(title: "Auto-Scroll") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(String(format: "%.2f", viewModel.autoScrollSpeed))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.autoScrollSpeed, in: 0.1...1.0)
                    }
                }

                SettingsSection(title: "Account") {
                    if viewModel.isLoggedIn {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Signed in as")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(viewModel.currentUserEmail ?? "")
                                    .font(.subheadline)
                            }
                            Spacer()
                            Button("Log Out") {
                                viewModel.isLoggedIn = false
                                viewModel.currentUserEmail = nil
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        Button("Sign In / Register") {
                            viewModel.authSheet = .login
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .padding(.vertical)
        }
    case .none:
        EmptyView()
    }
}
}