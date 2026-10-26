import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@main
struct SnagApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        let container = SnagStore.makeContainer(inMemory: isUITesting)
        let settings = AppSettings(defaults: isUITesting ? (UserDefaults(suiteName: "uitesting") ?? .standard) : .standard)
        let model = AppModel(container: container, settings: settings)
        if isUITesting {
            settings.hasOnboarded = true
            DemoData.seed(into: container.mainContext, model: model)
        }
        _model = State(initialValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
                .modelContainer(model.container)
                .onOpenURL { model.handle(url: $0) }
                .task { await model.entitlements.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshWatchedPrices() }
            }
        }
        .backgroundTask(.appRefresh(PriceWatcher.refreshTaskID)) { [container = model.container] in
            await PriceWatcher.runBackgroundRefresh(container: container)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// The app's model, set at launch so system callbacks can reach it.
    static weak var model: AppModel?
    private var notificationDelegate: NotificationDelegate?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let delegate = NotificationDelegate { productID, url, buy in
            AppDelegate.model?.openFromNotification(productID: productID, url: url, buy: buy)
        }
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        Notifier.registerCategories()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AppDelegate.model?.apnsToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}
