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
          if viewModel.isHeaderVisible {
            VStack(spacing: 14) {
              searchBar
              actionRow
              if viewModel.showAIField {
                AIResponseView(
                  query: $viewModel.aiQuery,
                  response: viewModel.aiResponse,
                  isWorking: viewModel.isAIWorking,
                  onSubmit: viewModel.fetchAIResponse
                )
                .padding(.top, 4)
              }
            }
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
            .padding(.top, 4)
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
        // ... your existing settings code remains unchanged ...
        VStack(alignment: .leading, spacing: 20) {
            // (keep your settings content as-is)
        }
        
    case .none:
        EmptyView()
    }
}
}
private struct SectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.headline)
      .foregroundColor(.primary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
private struct ActionButton: View {
  let label: String
  let symbol: String
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.title3)
        .frame(width: 32, height: 32)
        .background(tint.opacity(0.12))
        .foregroundColor(tint)
        .cornerRadius(10)
        .accessibilityLabel(Text(label))
    }
  }
}



// MARK: - Bookmark Row (Uniform Height + Trash Button)
private struct BookmarkRow: View {
    let item: BrowserItem
    var onDelete: (() -> Void)? = nil   // optional if you want to pass delete from parent
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "globe").foregroundColor(.accentColor))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Text(item.url.host ?? item.url.absoluteString)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Visible Delete Button
            Button(action: {
                onDelete?()
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(height: 80)                    // ← Uniform height
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

// MARK: - History Row (Clearly Different Style + Trash Button)
private struct HistoryRow: View {
    let item: BrowserItem
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title ?? "Untitled")
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(item.url.absoluteString)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Visible Trash Button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 72)                    // ← Consistent but slightly different height
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}