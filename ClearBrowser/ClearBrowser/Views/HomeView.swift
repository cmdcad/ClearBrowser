import SwiftUI
import UIKit

struct HomeView: View {
  @StateObject var viewModel: HomeViewModel
  @State private var isKeyboardVisible = false

  private var drawerOpenBinding: Binding<Bool> {
    Binding<Bool>(
      get: { viewModel.selectedDrawer != nil },
      set: { if !$0 { 
          withAnimation(.easeInOut(duration: 0.25)) {
              viewModel.selectedDrawer = nil 
          }
      } }
    )
  }

  var body: some View {
      
    NavigationView {
      ZStack {
        Color(uiColor: .systemGroupedBackground)
          .ignoresSafeArea()

        VStack(spacing: 0) {
          if viewModel.toolbarPosition == .top && viewModel.isHeaderVisible {
            headerContent
              .transition(.move(edge: .top).combined(with: .opacity))
          }

          BrowserView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, Theme.Spacing.sm)
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
            .overlay(statusOverlay, alignment: .top)
            .overlay(
              Group {
                if !isKeyboardVisible {
                     HStack(spacing: Theme.Spacing.md, alignment: .center) {
                        ActionButton(label: "Back", symbol: "chevron.left", tint: .purple) {
                        viewModel.goBack()
                        }

                        Button(action: {
                        print(
                        "[AutoScroll] auto button tapped (before toggle). isAutoScrolling=\(viewModel.isAutoScrolling)"
                        )
                        viewModel.toggleAutoScroll()
                        print(
                        "[AutoScroll] auto button action completed. isAutoScrolling now=\(viewModel.isAutoScrolling)"
                        )
                        }) {
                            Image(systemName: viewModel.isAutoScrolling ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .frame(width: 32, height: 32)
                                .background(.white)
                                .foregroundColor(.pink)
                                .cornerRadius(10)
                        }
                        .padding(.bottom, 20)


                        ActionButton(label: "Forward", symbol: "chevron.right", tint: .teal) {
                        viewModel.goForward()
                        }
                    }
                  
                }
              },
              alignment: .bottom
            )
            .padding(.vertical, Theme.Spacing.sm)

          if viewModel.toolbarPosition == .bottom && viewModel.isHeaderVisible {
            headerContent
              .padding(.top, 8)
              .padding(.bottom, 8)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }  

        if viewModel.selectedDrawer != nil {
          DrawerView(title: drawerTitle, isOpen: drawerOpenBinding) {
            drawerContent
          }
          .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
      .navigationBarHidden(true)
    }
    .sheet(item: $viewModel.authSheet) { type in
      if type == .login {
        LoginView(viewModel: viewModel)
      } else {
        RegisterView(viewModel: viewModel)
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification))
    { _ in
      withAnimation(.easeOut(duration: 0.2)) { isKeyboardVisible = true }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
    { _ in
      withAnimation(.easeIn(duration: 0.2)) { isKeyboardVisible = false }
    }
  }

  private var headerContent: some View {
    VStack(spacing: 0) {
      VStack(spacing: Theme.Spacing.md) {
        searchBar
        actionRow
          .padding(.horizontal, Theme.Spacing.lg)
      }
      .padding(.top, Theme.Spacing.md)
      .padding(.bottom, !viewModel.showAIField ? Theme.Spacing.md   : 0)
      .background(Theme.secondary.opacity(0.95))
      
      if viewModel.showAIField {
        AIResponseView(
          query: $viewModel.aiQuery,
          response: viewModel.aiResponse,
          isWorking: viewModel.isAIWorking,
          onSubmit: viewModel.fetchAIResponse
        )
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
        .background(Theme.secondary.opacity(0.95))
        .transition(.move(edge: .top).combined(with: .opacity))
      }
       
    }
  }

  private var drawerTitle: String {
    switch viewModel.selectedDrawer {
    case .bookmarks: return "Bookmarks"
    case .history: return "History"
    case .settings: return "Settings"
    case .favorites: return "Favorites"
    case .none: return ""
    }
  }

  private var searchBar: some View {
    HStack(spacing: Theme.Spacing.md) {
      HStack(spacing: Theme.Spacing.sm) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(Theme.textSecondary)
        
        TextField(
          "Search or enter URL",
          text: $viewModel.addressBarText,
          onCommit: viewModel.loadAddress
        )
        .font(.subheadline)
        .foregroundColor(Theme.text)
        .keyboardType(.URL)
        .autocorrectionDisabled(true)
        .textInputAutocapitalization(.never)
        .submitLabel(.go)
      }
      .padding(.horizontal, Theme.Spacing.md)
      .padding(.vertical, 8)
      .background(Theme.primary.opacity(0.6))
      .cornerRadius(Theme.Radius.md)
      .overlay(
        RoundedRectangle(cornerRadius: Theme.Radius.md)
          .stroke(Theme.border, lineWidth: 0.5)
      )

      if viewModel.isLoading {
        ActionButton(label: "Stop", symbol: "xmark", tint: .red) {
          viewModel.stopLoading()
        }
      } else {
        ActionButton(label: "Reload", symbol: "arrow.clockwise", tint: .blue) {
          viewModel.reload()
        }
      }
    }
    .padding(.horizontal, Theme.Spacing.lg)
  }

  private var actionRow: some View { // Changed "Search" to "Favorite" (add current page) and added "Favorites" (open drawer)
    HStack(spacing: Theme.Spacing.md) {
      ActionButton(label: "Favorite", symbol: "star.fill", tint: .yellow) {
        viewModel.addFavorite()
      }

      ActionButton(label: "Bookmarks", symbol: "bookmark", tint: .green) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          viewModel.selectedDrawer = .bookmarks
        }
      }

      ActionButton(label: "History", symbol: "clock.arrow.circlepath", tint: .orange) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          viewModel.selectedDrawer = .history
        }
      }

      ActionButton(label: "Favorites", symbol: "star.circle", tint: .blue) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          viewModel.selectedDrawer = .favorites
        }
      }
    
      ActionButton(label: "Settings", symbol: "gearshape", tint: .purple) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          viewModel.selectedDrawer = .settings
        }
      }

      ActionButton(label: "AI", symbol: "bubble.left.and.bubble.right", tint: .teal) {
        viewModel.toggleAIField()
      }
      

      Spacer()

     
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
            HStack {
                Text("All bookmarks")
                    .font(.headline)
                Spacer()
                Button(action: {
                    viewModel.addBookmark() // Add current page as bookmark
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }

            if viewModel.bookmarks.isEmpty {
                Text("No bookmarks yet.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(viewModel.bookmarks) { item in
                        Button(action: { viewModel.openBookmark(item) }) { // Tap to open bookmark
                            BookmarkRow(item: item)
                        }
                            .buttonStyle(.plain)
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
                Button("Clear") {
                    withAnimation { // Added animation
                        viewModel.clearHistory()
                    }
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
                        Button(action: { viewModel.openHistory(item) }) {
                            HistoryRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation { viewModel.removeHistoryItem(item) }
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
        
    case .favorites: // New favorites drawer content
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("All favorites")
                    .font(.headline)
                Spacer()
                Button(action: {
                    viewModel.addFavorite() // Add current page as favorite
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }

            if viewModel.favorites.isEmpty {
                Text("No favorites yet.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(viewModel.favorites) { item in
                        Button(action: { viewModel.openFavorite(item) }) { // Tap to open favorite
                            BookmarkRow(item: item) // Reusing BookmarkRow for display
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation {
                                    viewModel.removeFavorite(item)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        
    case .settings:
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SettingsSection(title: "Search") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Label("Search Engine", systemImage: "magnifyingglass.circle.fill")
                            .font(.subheadline)
                        
                        Picker("Search Engine", selection: $viewModel.defaultSearchEngine) {
                            ForEach(SearchEngine.allCases) { engine in
                                Text(engine.title).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                SettingsSection(title: "Appearance") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Label("Toolbar Position", systemImage: "dock.rectangle")
                            .font(.subheadline)
                            
                        Picker("Toolbar Position", selection: $viewModel.toolbarPosition) {
                            ForEach(ToolbarPosition.allCases) { pos in
                                Text(pos.title).tag(pos)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                SettingsSection(title: "Auto-Scroll") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Label("Scroll Speed", systemImage: "gauge.with.needle.fill")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.2f", viewModel.autoScrollSpeed))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(Theme.textSecondary)
                        }
                        
                        Slider(value: $viewModel.autoScrollSpeed, in: 0.1...1.0)
                            .tint(Theme.accent)
                    }
                }

                SettingsSection(title: "Account") {
                    if viewModel.isLoggedIn {
                        VStack(spacing: Theme.Spacing.md) {
                            HStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundColor(Theme.accent)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.currentUserEmail ?? "User")
                                        .font(.headline)
                                        .foregroundColor(Theme.text)
                                    Text("Logged in")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                            }
                            
                            Divider().background(Theme.border)
                            
                            Button(role: .destructive, action: {
                                viewModel.isLoggedIn = false
                                viewModel.currentUserEmail = nil
                            }) {
                                Label("Log Out", systemImage: "arrow.right.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text("Sync your bookmarks and history across devices.")
                                .font(.footnote)
                                .foregroundColor(Theme.textSecondary)
                            
                            Button(action: { viewModel.authSheet = .login }) {
                                Label("Sign In / Register", systemImage: "person.badge.key.fill")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Theme.accent)
                                    .foregroundColor(.white)
                                    .cornerRadius(Theme.Radius.sm)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.lg)
        }
    case .none:
        EmptyView()
    }
}
}
 