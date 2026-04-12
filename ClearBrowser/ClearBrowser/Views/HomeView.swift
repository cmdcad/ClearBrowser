import SwiftUI
import UIKit
import PhotosUI

struct HomeView: View {
  @StateObject var viewModel: HomeViewModel
  @State private var isKeyboardVisible = false

  @State private var bottomBarOffset: CGFloat = 75   // Lowered resting position
  @State private var lastDragValue: CGFloat = 0
  @State private var isBottomBarExpanded = false     // Optional: track expanded state for animations

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
  
            // New draggable bottom bar:
            .overlay(alignment: .bottom) {
            if !isKeyboardVisible {
                VStack(spacing: 0) {

                    // MARK: - Grip Handle (More Grippable)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle()) // Makes entire area tappable

                    // MARK: - Bottom Bar Buttons
                    HStack(alignment: .center, spacing: Theme.Spacing.md) {
                        ActionButton(label: "Back", symbol: "chevron.left", tint: .purple) {
                            viewModel.goBack()
                        }

                        Button(action: {
                            print("[AutoScroll] auto button tapped (before toggle). isAutoScrolling=\(viewModel.isAutoScrolling)")
                            viewModel.toggleAutoScroll()
                            print("[AutoScroll] auto button action completed. isAutoScrolling now=\(viewModel.isAutoScrolling)")
                        }) {
                            Image(systemName: viewModel.isAutoScrolling ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(.white)
                                .foregroundColor(.green.opacity(0.5))
                                .cornerRadius(12)
                        }

                        ActionButton(label: "Forward", symbol: "chevron.right", tint: .teal) {
                            viewModel.goForward()
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, 20)
                }
                .padding(.top, 4)
                .background(
                    RoundedRectangle(cornerRadius: 45) // Increased for a deeper "crescent" curve
                        .fill(Theme.primary.opacity(0.95))
                        .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 6)
                )

                // MARK: - Offset (Controls Visibility)
                .offset(y: bottomBarOffset)

                // MARK: - Drag Gesture
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let dragAmount = value.translation.height

                            // Clamp between fully visible (0) and max hidden (85)
                            bottomBarOffset = min(
                                max(bottomBarOffset + dragAmount * 0.8, 0),
                                85
                            )

                            lastDragValue = dragAmount
                        }
                        .onEnded { value in
                            let velocity = value.velocity.height

                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                if velocity > 300 || bottomBarOffset > 40 {
                                    // Hide (resting hidden position lowered to 75)
                                    bottomBarOffset = 75
                                    isBottomBarExpanded = false
                                } else {
                                    // Show fully
                                    bottomBarOffset = 0
                                    isBottomBarExpanded = true
                                }
                            }
                        }
                )

                // MARK: - Tap to Toggle
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        bottomBarOffset = bottomBarOffset > 30 ? 0 : 75
                    }
                }
            }
        }
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
            DrawerContentView(viewModel: viewModel)
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
           ZStack(alignment: .bottom) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: viewModel.currentURL?.scheme == "https" ? "lock.fill" : "info.circle")
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.currentURL?.scheme == "https" ? .green : .secondary)
                
                TextField("Search or enter URL", text: $viewModel.addressBarText, onCommit: viewModel.loadAddress)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .keyboardType(.URL)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                
                if viewModel.isLoading {
                    Button(action: { viewModel.stopLoading() }) {
                        Image(systemName: "xmark").foregroundColor(.secondary)
                    }
                } else {
                    Button(action: { viewModel.reload() }) {
                        Image(systemName: "arrow.clockwise").foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            
            if viewModel.isLoading {
                ProgressView(value: viewModel.loadingProgress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
        } 
  
    .padding(.horizontal, Theme.Spacing.lg)
  }

  private var actionRow: some View { // Changed "Search" to "Favorite" (add current page) and added "Favorites" (open drawer)
       ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 24) {
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
 
}
 
