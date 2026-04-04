import SwiftUI
import UIKit

struct HomeView: View {
  @StateObject var viewModel: HomeViewModel
  @State private var isKeyboardVisible = false

  private var drawerOpenBinding: Binding<Bool> {
    Binding<Bool>(
      get: { viewModel.selectedDrawer != nil },
      set: { if !$0 { viewModel.selectedDrawer = nil } }
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
              .padding(.bottom, 14)
              .transition(.move(edge: .top).combined(with: .opacity))
          }

          BrowserView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 10)
            .overlay(statusOverlay, alignment: .top)
            .overlay(
              Group {
                if !isKeyboardVisible {
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
                }
              },
              alignment: .bottom
            )
            .padding(.top, viewModel.toolbarPosition == .top ? 4 : 0)
            .padding(.bottom, viewModel.toolbarPosition == .bottom ? 4 : 0)

          if viewModel.toolbarPosition == .bottom && viewModel.isHeaderVisible {
            headerContent
              .padding(.top, 14)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }  

        if viewModel.selectedDrawer != nil {
          DrawerView(title: drawerTitle, isOpen: drawerOpenBinding) {
            drawerContent
          }
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
      .padding(.vertical, Theme.Spacing.md)
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
      }
      
      Divider()
        .background(Theme.border)
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

      ActionButton(label: "Reload", symbol: "arrow.clockwise", tint: .blue) {
        viewModel.reload()
      }
    }
    .padding(.horizontal, Theme.Spacing.lg)
  }

  private var actionRow: some View {
    HStack(spacing: Theme.Spacing.md) {
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

      HStack(spacing: Theme.Spacing.md) {
        ActionButton(label: "back", symbol: "chevron.left", tint: .purple) {
          viewModel.goBack()
        }
        ActionButton(label: "forward", symbol: "chevron.right", tint: .teal) {
          viewModel.goForward()
        }
      }
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