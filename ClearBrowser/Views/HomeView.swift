import SwiftUI
import UIKit
import PhotosUI
import AudioToolbox

struct HomeView: View {
  @StateObject var viewModel: HomeViewModel
  @StateObject private var reloCalcModel = ReloCalcModel()
  @State private var isKeyboardVisible = false
  @FocusState private var isAddressBarFocused: Bool

  @State private var showTabManager = false
  @State private var isShowingApps = false
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

        if viewModel.selectedDrawer != nil {
          drawerOverlay
        }



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

        if viewModel.showAIField {
          GeometryReader { proxy in
            Color.black.opacity(0.28)
              .ignoresSafeArea()
              .contentShape(Rectangle())
              .onTapGesture {
                dismissAI()
              }

            VStack {
              AIResponseView(
                query: $viewModel.aiQuery,
                response: viewModel.aiResponse,
                isWorking: viewModel.isAIWorking,
                onSubmit: viewModel.fetchAIResponse,
                onDismiss: dismissAI
              )
              .frame(maxHeight: min(600, proxy.size.height * 0.75))
              .padding()
              .padding(.top)
            }
            .ignoresSafeArea(edges: .bottom)
          }
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(2)
        }

        
        if (isShowingApps) {
          AppsView(onClose: { isShowingApps = false }, model: reloCalcModel)
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
    .alert("Send text to server?", isPresented: Binding<Bool>(
      get: { viewModel.pendingTextConfirmation != nil },
      set: { if !$0 { viewModel.pendingTextConfirmation = nil } }
    )) {
      if let confirmation = viewModel.pendingTextConfirmation {
        Button("Cancel", role: .cancel) {
          viewModel.pendingTextConfirmation = nil
        }
        Button("Send") {
          viewModel.proceedWithReadAloud(text: confirmation.text)
        }
      } else {
        Button("OK", role: .cancel) { }
      }
    } message: {
      if let confirmation = viewModel.pendingTextConfirmation {
        Text("Send \(confirmation.size) of text to the server for audio generation?")
      } else {
        Text("Confirm text send")
      }
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
    // Vibrate when showing toast message
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()

    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      toastMessage = message
    }
    // Show toast for longer duration (5 seconds) to give users more time to read
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
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
      
      BrowserControlsView(viewModel: viewModel, onDismiss: {})
         .padding(.horizontal, Theme.Spacing.lg)
         .padding(.top, 4)
         .padding(.bottom, Theme.Spacing.md-2)
         .background(Theme.secondary.opacity(0.95))
    }
  }

  private func dismissAI() {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      viewModel.showAIField = false
    }
  }

 


  private var searchBar: some View {
           ZStack(alignment: .bottom) {
            HStack(spacing: Theme.Spacing.sm) {
               //Move the home button here to the left of the address bar
                Button(action: { viewModel.goHome() }) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }

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
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
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

                    if viewModel.hasConfiguredAIKey {
                        ActionButton(label: "AI",
                                     symbol: "bubble.left.and.bubble.right",
                                     tint: .teal,
                                     isActive: viewModel.showAIField) {
                            viewModel.toggleAIField()
                        }
                    }

                    ActionButton(label: "Tabs", symbol: "square.on.square", tint: .indigo) {
                        showTabManager = true
                    }
                    .overlay(
                        Text("\(viewModel.tabs.count)")
                            .font(.caption2.bold())
                            .offset(x: 10, y: -10)
                    )

                    ActionButton(label: "Share", symbol: "square.and.arrow.up", tint: .blue) {
                        viewModel.shareCurrentPage()
                    }

                    ActionButton(label: "Settings", symbol: "gearshape", tint: .gray) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.selectedDrawer = .settings
                        }
                    }

                    Menu {
                        Button {
                            isShowingApps = true
                        } label: {
                            Label("Apps", systemImage: "square.grid.2x2")
                        }

                        Button {
                            viewModel.isPrivateMode.toggle()
                        } label: {
                            Label(viewModel.isPrivateMode ? "Exit Private" : "Private",
                                  systemImage: viewModel.isPrivateMode ? "eye.slash.fill" : "eye")
                        }
                    } label: {
                        ActionButton(label: "More", symbol: "ellipsis", tint: .gray) { }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity).frame(height: 44)   // 🔥 THIS FIXES THE HEIGHT
        }
        .padding(.horizontal)

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
 
