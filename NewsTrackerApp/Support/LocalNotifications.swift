import NewsCore
import UIKit
import UserNotifications

/// Local notifications for price alerts – free, no server needed.
/// Delivered when the app checks prices (foreground, pull-to-refresh or background refresh).
struct LocalNotifier: PriceAlertNotifier {
    static let urlKey = "url"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func deliver(_ alerts: [PriceAlert]) async throws {
        let center = UNUserNotificationCenter.current()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = PriceAlertFormatter.title(for: alert)
            content.body = PriceAlertFormatter.body(for: alert)
            content.sound = .default
            content.threadIdentifier = alert.asset.id
            if let url = alert.asset.quoteURL {
                content.userInfo = [Self.urlKey: url.absoluteString]
            }
            try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
        }
    }

    func sendTest() async throws {
        let content = UNMutableNotificationContent()
        content.title = "News Tracker"
        content.body = "Powiadomienia o zmianach cen działają."
        content.sound = .default
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

/// Shows notifications while the app is open and opens the quote page on tap.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let string = response.notification.request.content.userInfo[LocalNotifier.urlKey] as? String,
              let url = URL(string: string)
        else { return }
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
}
