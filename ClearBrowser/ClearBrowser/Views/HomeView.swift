import SwiftUI
import UIKit
import PhotosUI

struct HomeView: View {
  @StateObject var viewModel: HomeViewModel
  @State private var isKeyboardVisible = false
  @FocusState private var isAddressBarFocused: Bool

  @State private var showTabManager = false
  @State private var bottomBarOffset: CGFloat = 75   // Lowered resting position
  @State private var lastDragValue: CGFloat = 0
  @State private var isBottomBarExpanded = false     // Optional: track expanded state for animations
  @State private var toastMessage: String? = nil

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

          browserContent
          
          if viewModel.toolbarPosition == .bottom && viewModel.isHeaderVisible {
            headerContent
              .padding(.top, 8)
              .padding(.bottom, 8)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }

        // Drawers overlay
        if viewModel.selectedDrawer != nil {
          drawerOverlay
        }

        // Toast overlay
        if let message = toastMessage {
          VStack {
            Spacer()
            Text(message)
              .font(.footnote)
              .foregroundColor(.white)
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
              .background(.ultraThinMaterial.opacity(0.95))
              .background(Color.black.opacity(0.75))
              .cornerRadius(16)
              .padding(.bottom, 140)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
          .padding(.horizontal, 20)
          .zIndex(3)
        }
      }
      .navigationBarHidden(true)
    }
    .fullScreenCover(item: $viewModel.accountSheet) { destination in
      AccountFlowView(viewModel: viewModel, startDestination: destination)
    }
    .sheet(isPresented: $showTabManager) {
      TabManagerView(viewModel: viewModel)
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      withAnimation(.easeOut(duration: 0.2)) { isKeyboardVisible = true }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      withAnimation(.easeIn(duration: 0.2)) { isKeyboardVisible = false }
    }
    .onChange(of: viewModel.serverManager.lastAudioEventMessage) { _, message in
      guard let message = message else { return }
      showToast(message)
    }
    .onChange(of: viewModel.serverManager.errorMessage) { _, message in
      guard let message = message else { return }
      showToast(message)
    }
  }

  private var browserContent: some View {
    BrowserView(viewModel: viewModel)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Theme.primary)
      .clipShape(RoundedRectangle(cornerRadius: 18))
      .padding(.horizontal, Theme.Spacing.sm)
      .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
      .overlay(statusOverlay, alignment: .top)
      .overlay(alignment: .bottom) {
        if !isKeyboardVisible {
          draggableBottomBar
        }
      }
  }

  private var draggableBottomBar: some View {
    VStack(spacing: 0) {
      gripHandle
      bottomBarButtons
    }
    .padding(.top, 4)
    .background(bottomBarBackground)
    .offset(y: bottomBarOffset)
    .gesture(dragGesture)
    .onTapGesture {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
        bottomBarOffset = bottomBarOffset > 30 ? 0 : 75
      }
    }
  }

  private var gripHandle: some View {
    RoundedRectangle(cornerRadius: 3)
      .fill(Color.secondary.opacity(0.35))
      .frame(width: 40, height: 5)
      .padding(.top, 8)
      .padding(.bottom, 4)
      .contentShape(Rectangle())
  }

  private var bottomBarButtons: some View {
    HStack(alignment: .center, spacing: Theme.Spacing.md) {
      ActionButton(label: "Back", symbol: "chevron.left", tint: .purple, isEnabled: viewModel.canGoBack) {
        viewModel.goBack()
      }

      autoScrollButton

      ActionButton(label: "Forward", symbol: "chevron.right", tint: .teal, isEnabled: viewModel.canGoForward) {
        viewModel.goForward()
      }

      if viewModel.isReadAloudPlaying {
        stopReadAloudButton
      }

      readAloudButton
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .padding(.bottom, 20)
  }

  private var autoScrollButton: some View {
    Button(action: {
      print("[AutoScroll] auto button tapped (before toggle). isAutoScrolling=\(viewModel.isAutoScrolling)")
      viewModel.toggleAutoScroll()
      print("[AutoScroll] auto button action completed. isAutoScrolling now=\(viewModel.isAutoScrolling)")
    }) {
      Image(systemName: viewModel.isAutoScrolling ? "pause.fill" : "play.fill")
        .font(.title3)
        .frame(width: 44, height: 44)
        .background(viewModel.isAutoScrolling ? Color.green : .white)
        .foregroundColor(viewModel.isAutoScrolling ? .white : .green.opacity(0.5))
        .cornerRadius(12)
    }
  }

  private var stopReadAloudButton: some View {
    Button(action: {
      viewModel.stopReadAloud()
    }) {
      Image(systemName: "stop.fill")
        .font(.subheadline.weight(.semibold))
        .frame(width: 34, height: 34)
        .background(Color.red.opacity(0.12))
        .foregroundColor(.red)
        .clipShape(Circle())
    }
    .transition(.scale.combined(with: .opacity))
  }

  private var readAloudButton: some View {
    Button(action: {
      if viewModel.isReadAloudPlaying {
        viewModel.pauseReadAloud()
      } else if viewModel.isReadAloudAvailable {
        viewModel.resumeReadAloud()
      } else if let webView = viewModel.currentWebView {
        viewModel.startReadAloud(from: webView)
      }
    }) {
      if viewModel.serverManager.isLoading {
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .orange))
          .frame(width: 44, height: 44)
          .background(Color.white)
          .cornerRadius(12)
      } else {
        Image(systemName: viewModel.isReadAloudPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
          .font(.title3)
          .frame(width: 44, height: 44)
          .background(viewModel.isReadAloudPlaying ? Color.orange : .white)
          .foregroundColor(viewModel.isReadAloudPlaying ? .white : .orange.opacity(0.75))
          .cornerRadius(12)
      }
    }
    .disabled(viewModel.serverManager.isLoading)
  }

  private var bottomBarBackground: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 45)
        .fill(Theme.primary.opacity(0.98))
      RoundedRectangle(cornerRadius: 45)
        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
    }
    .background(
      RoundedRectangle(cornerRadius: 45)
        .fill(Theme.primary)
        .blur(radius: 10)
    )
    .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 6)
  }

  private var dragGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        let dragAmount = -value.translation.height
        bottomBarOffset = min(
          max(bottomBarOffset + dragAmount * 0.8, 0),
          85
        )
        lastDragValue = dragAmount
      }
      .onEnded { value in
        let velocity = -value.velocity.height
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
          if velocity < -300 || bottomBarOffset > 40 {
            bottomBarOffset = 75
            isBottomBarExpanded = false
          } else {
            bottomBarOffset = 0
            isBottomBarExpanded = true
          }
        }
      }
  }

  @ViewBuilder
  private var drawerOverlay: some View {
    if viewModel.selectedDrawer != nil {
      DrawerView(title: drawerTitle, isOpen: drawerOpenBinding) {
        DrawerContentView(viewModel: viewModel)
      }
      .transition(.move(edge: .trailing).combined(with: .opacity))
    }
  }

  private var drawerTitle: String {
    switch viewModel.selectedDrawer {
    case .history: return "History"
    case .bookmarks: return "Bookmarks"
    case .settings: return "Settings"
    case .none: return ""
    }
  }

  private func showToast(_ message: String) {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      toastMessage = message
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
      withAnimation(.easeOut(duration: 0.25)) {
        if toastMessage == message {
          toastMessage = nil
        }
      }
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
    case .bookmarks: return "Sites"
    case .history: return "History"
    case .settings: return "Settings" 
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
                    .focused($isAddressBarFocused)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .keyboardType(.URL)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .onChange(of: isAddressBarFocused) { _, focused in
                        if focused {
                            // Select all text on focus
                            DispatchQueue.main.async {
                                UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                            }
                        }
                    }
                
                // Clear Button
                if !viewModel.addressBarText.isEmpty && isAddressBarFocused {
                    Button(action: { viewModel.addressBarText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .padding(.trailing, 2)
                    .transition(.scale.combined(with: .opacity))
                }

                // Integrated Favorite Button
                Button(action: { viewModel.toggleFavorite() }) {
                    Image(systemName: viewModel.isCurrentPageFavorited ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(viewModel.isCurrentPageFavorited ? .yellow : .secondary)
                }

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

  private var actionRow: some View {
       ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 24) {
      ActionButton(label: "Sites", symbol: "bookmark", tint: .green) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          viewModel.selectedDrawer = .bookmarks
        }
      }

      ActionButton(label: "History", symbol: "clock.arrow.circlepath", tint: .orange) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
          viewModel.selectedDrawer = .history
        }
      }

      ActionButton(label: "AI", symbol: "bubble.left.and.bubble.right", tint: .teal, isActive: viewModel.showAIField) {
        viewModel.toggleAIField()
      }
      
      ActionButton(label: "Tabs", symbol: "square.on.square", tint: .indigo) {
          showTabManager = true
      }
      .overlay(
        Text("\(viewModel.tabs.count)").font(.caption2.bold()).offset(x: 10, y: -10)
      )
      
      Spacer()
      
      Menu {
        Button(action: {
          withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            viewModel.selectedDrawer = .settings
          }
        }) {
          Label("Settings", systemImage: "gearshape")
        }
        
        Button(action: {
          viewModel.shareCurrentPage()
        }) {
          Label("Share", systemImage: "square.and.arrow.up")
        }
        
        Button(action: {
          viewModel.isPrivateMode.toggle()
        }) {
          Label(viewModel.isPrivateMode ? "Exit Private" : "Private", systemImage: viewModel.isPrivateMode ? "eye.slash.fill" : "eye")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.title3)
          .frame(width: 44, height: 44)
          .background(.white)
          .foregroundColor(.gray.opacity(0.6))
          .cornerRadius(12)
      }

      Spacer()
        }
      }
    }

  private var statusOverlay: some View {
    VStack {
      if viewModel.isPrivateMode {
          HStack(spacing: 4) {
              Image(systemName: "eye.slash.fill")
              Text("Private")
          }
          .font(.system(size: 10, weight: .bold))
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(Color.black.opacity(0.7))
          .foregroundColor(.white)
          .clipShape(Capsule())
          .padding(.top, 8)
      }

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
 
