#if os(macOS)
import SwiftUI
import UserNotifications

@main
@MainActor
struct BingBotMacApp: App {
    init() { UNUserNotificationCenter.current().delegate = BingMacNotificationDelegate.shared }
    var body: some Scene {
        WindowGroup { BingBotView().frame(minWidth: 760, minHeight: 620) }
    }
}

private final class BingMacNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BingMacNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
#endif
