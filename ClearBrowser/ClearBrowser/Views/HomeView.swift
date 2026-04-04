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

          BrowserView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 10)
            .overlay(statusOverlay, alignment: .top)
            .overlay(
              Group {
                if !isKeyboardVisible {
                  navigationControls
                }
              },
              alignment: .bottom
            )
            .padding(.top, 4)
        }
        .padding(.horizontal)
        .padding(.top, 8)

        if viewModel.selectedDrawer != nil {
          DrawerView(title: viewModel.selectedDrawer?.rawValue ?? "", isOpen: drawerOpenBinding) {
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

      ActionButton(label: "Bookmarks", symbol: "arrow.clockwise", tint: .blue) {
        viewModel.reload()
      }

      ActionButton(label: "Bookmarks", symbol: "bookmark", tint: .green) {
        viewModel.selectedDrawer = .bookmarks
      }
    }
  }

  private var actionRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
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
      }
      .padding(.vertical, 4)
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

  private var navigationControls: some View {
    HStack(spacing: 16) {
      Button(action: viewModel.goBack) {
        Image(systemName: "chevron.left")
          .frame(width: 32, height: 32)
      }
      .disabled(!viewModel.canGoBack)
      .buttonStyle(.bordered)

      Spacer()

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
          .background(Color.pink.opacity(0.12))
          .foregroundColor(.pink)
          .cornerRadius(10)
      }

      Spacer()

      Button(action: viewModel.goForward) {
        Image(systemName: "chevron.right")
          .frame(width: 32, height: 32)
      }
      .disabled(!viewModel.canGoForward)
      .buttonStyle(.bordered)

    }
    .padding(12)
  }

  @ViewBuilder
  private var drawerContent: some View {
    switch viewModel.selectedDrawer {
    case .bookmarks:
      VStack(alignment: .leading, spacing: 16) {
        if viewModel.bookmarks.isEmpty {
          Text("No bookmarks yet.")
            .foregroundColor(.secondary)
            .padding(.vertical, 30)
        } else {
          List {
            ForEach(viewModel.bookmarks) { item in
              Button(action: { viewModel.openBookmark(item) }) {
                BookmarkRow(item: item)
                  .padding(.vertical, 6)
              }
              .buttonStyle(.plain)
              .listRowInsets(EdgeInsets())
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  withAnimation {
                    viewModel.removeBookmark(item)
                  }
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
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
            viewModel.clearHistory()
          }
          .buttonStyle(.bordered)
        }

        if viewModel.history.isEmpty {
          Text("No history yet.")
            .foregroundColor(.secondary)
            .padding(.vertical, 30)
        } else {
          List {
            ForEach(viewModel.history) { item in
              Button(action: { viewModel.openHistory(item) }) {
                HStack {
                  Text(item.title ?? "")
                  Spacer()
                }
                .padding(.vertical, 8)
              }
              .buttonStyle(.plain)
              .listRowInsets(EdgeInsets())
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                  withAnimation {
                    viewModel.removeHistoryItem(item)
                  }
                } label: {
                  Label("Delete", systemImage: "trash")
                }
                .tint(.red)
                .actionSheet(
                  isPresented: $isDeleting,
                  content: {
                    SwipeToDeleteView(onDelete: {
                      viewModel.removeHistoryItem(item)
                    })
                  })
              }
            }
            .onDelete(perform: viewModel.removeHistoryItems)
            .onMove(perform: viewModel.moveHistoryItem)
          }
        }
      }
    case .settings:
      VStack(alignment: .leading, spacing: 20) {
        SectionHeader(title: "Search engine")
        Picker("Default search engine", selection: $viewModel.defaultSearchEngine) {
          ForEach(SearchEngine.allCases) { engine in
            Text(engine.title).tag(engine)
          }
        }
        .pickerStyle(.segmented)

        SectionHeader(title: "Auto-scroll speed")
        HStack {
          Slider(value: $viewModel.autoScrollSpeed, in: 0.05...5.0, step: 0.05)
          Text(String(format: "%.2fx", viewModel.autoScrollSpeed))
            .font(.caption)
            .foregroundColor(.secondary)
        }

        SectionHeader(title: "Account")

        if viewModel.isLoggedIn {
          VStack(alignment: .leading, spacing: 8) {
            Text("Logged in as \(viewModel.currentUserEmail ?? "User")")
              .font(.footnote)
            Button("Log out") {
              viewModel.isLoggedIn = false
              viewModel.currentUserEmail = nil
            }
            .buttonStyle(.bordered)
          }
        } else {
          VStack(alignment: .leading, spacing: 12) {
            Text("Create an account or log in to sync favorites and history across devices.")
              .font(.footnote)
              .foregroundColor(.secondary)
            HStack {
              Button("Log In") { viewModel.authSheet = .login }
              Button("Register") { viewModel.authSheet = .register }
            }
            .buttonStyle(.borderedProminent)
          }
        }

        Spacer()
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
private struct BookmarkRow: View {
  let item: BrowserItem

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.accentColor.opacity(0.2))
        .frame(width: 44, height: 44)
        .overlay(Image(systemName: "globe").foregroundColor(.accentColor))

      VStack(alignment: .leading, spacing: 6) {
        Text(item.title)
          .font(.body)
          .foregroundColor(.primary)
          .lineLimit(2)

        Text(item.url.host ?? item.url.absoluteString)
          .font(.footnote)
          .foregroundColor(.secondary)
      }

      Spacer()

      VStack {
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundColor(.secondary)
        Spacer()
      }
    }
    .padding(14)
    .background(Color(.systemBackground))
    .cornerRadius(16)
    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 4)

  }
}
