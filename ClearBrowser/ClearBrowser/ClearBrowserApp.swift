//
//  ClearBrowserApp.swift
//  ClearBrowser
//
//  Created by user946737 on 4/2/26.
//

import SwiftUI
import FirebaseCore

@main
struct ClearBrowserApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: HomeViewModel())
        }
    }
}
