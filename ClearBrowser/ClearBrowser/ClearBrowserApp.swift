//
//  ClearBrowserApp.swift
//  ClearBrowser
//
//  Created by user946737 on 4/2/26.
//

import SwiftUI

@main
struct ClearBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: HomeViewModel())
        }
    }
}
