import SwiftUI
import WebKit
import Foundation
import UIKit

struct ContentView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        ZStack {
            NavigationView {
                Group {
                    if appState.showHome {
                        HomeView()
                            .environmentObject(appState)
                    } else {
                        BrowserView()
                            .environmentObject(appState)
                    }
                }
                .navigationViewStyle(.stack)
            }
            
            // Drawer overlay
            if appState.activeDrawer != nil {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        appState.closeDrawer()
                    }
                
                DrawerView(drawer: appState.activeDrawer ?? .bookmarks)
                    .environmentObject(appState)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.activeDrawer)
    }
}

#Preview {
    ContentView()
}