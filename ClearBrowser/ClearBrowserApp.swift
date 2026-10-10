//
//  ClearBrowserApp.swift
//  ClearBrowser
//
//  Created by user946737 on 4/2/26.
//

import SwiftUI
import FirebaseCore
import UserNotifications

@main
struct ClearBrowserApp: App {
    init() {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = ClearBrowserNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: HomeViewModel())
        }
    }
}


// Keep a strong reference: UNUserNotificationCenter holds its delegate weakly.
final class ClearBrowserNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ClearBrowserNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
