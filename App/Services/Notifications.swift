import Foundation
import UIKit
import UserNotifications
import SnagKit

nonisolated enum NotificationIDs {
    static let priceDropCategory = "PRICE_DROP"
    static let buyAction = "BUY_NOW"
    static let viewAction = "VIEW_ITEM"
    static let productIDKey = "productID"
    static let urlKey = "url"
}

/// Local notifications for price drops and occasion reminders.
enum Notifier {
    static func registerCategories() {
        let buy = UNNotificationAction(identifier: NotificationIDs.buyAction, title: "Buy now", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "cart.fill"))
        let view = UNNotificationAction(identifier: NotificationIDs.viewAction, title: "View", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "eye"))
        let category = UNNotificationCategory(identifier: NotificationIDs.priceDropCategory, actions: [buy, view], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    static func postPriceDrop(item title: String, productID: String, price: Double, currency: String, merchant: String?, dropFraction: Double, url: URL?, reason: AlertDecision.Reason) async {
        let content = UNMutableNotificationContent()
        switch reason {
        case .allTimeLow: content.title = "Lowest price ever: \(title)"
        case .reachedTarget: content.title = "Target hit: \(title)"
        default: content.title = "Price drop: \(title)"
        }
        var body = "Now \(price.money(currency))"
        if let merchant { body += " at \(merchant)" }
        if dropFraction > 0.005 { body += " (−\(dropFraction.percentString))" }
        content.body = body + ". Tap to grab it."
        content.sound = .default
        content.categoryIdentifier = NotificationIDs.priceDropCategory
        content.threadIdentifier = "price-drops"
        content.interruptionLevel = reason == .allTimeLow ? .timeSensitive : .active
        var info: [String: String] = [NotificationIDs.productIDKey: productID]
        if let url { info[NotificationIDs.urlKey] = url.absoluteString }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: "drop-\(productID)-\(Int(price * 100))", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Reminder a week before an occasion so there's time to order.
    static func scheduleOccasionReminder(for recipient: RecipientProfile) async {
        let center = UNUserNotificationCenter.current()
        let id = "occasion-\(recipient.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let date = recipient.occasionDate,
              let remindAt = Calendar.current.date(byAdding: .day, value: -7, to: date), remindAt > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(recipient.occasion.title) for \(recipient.name) in a week"
        content.body = "Your gift ideas are ready, with today's best prices."
        content.sound = .default
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: remindAt)
        comps.hour = 10
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(request)
    }
}

/// Receives notification taps. Kept off the main actor because UserNotifications
/// may call it from any thread; it hops to the main actor to update the UI.
nonisolated final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    let onOpen: @MainActor @Sendable (_ productID: String?, _ url: URL?, _ buy: Bool) -> Void

    init(onOpen: @escaping @MainActor @Sendable (String?, URL?, Bool) -> Void) {
        self.onOpen = onOpen
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let productID = info[NotificationIDs.productIDKey] as? String
        let url = (info[NotificationIDs.urlKey] as? String).flatMap(URL.init(string:))
        let buy = response.actionIdentifier == NotificationIDs.buyAction
        await onOpen(productID, url, buy)
    }
}
