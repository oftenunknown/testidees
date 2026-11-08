import SwiftUI
import OdysseyKit

@main
struct OdysseyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel

    init() {
        let launch = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        let settings = AppSettings(defaults: launch.isUITesting ? LaunchOptions.testDefaults() : .standard)
        if launch.isUITesting {
            settings.demoMode = true
            settings.hasOnboarded = true
        }
        _model = State(initialValue: AppModel(settings: settings, launch: launch))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
                .onOpenURL { model.handle(url: $0) }
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.syncIfStale() }
            }
        }
    }
}

/// Command-line switches for UI tests and screenshots.
struct LaunchOptions {
    var isUITesting = false
    var openStory = false
    var storyPage: Int?
    var tab: AppTab?

    init(arguments: [String]) {
        isUITesting = arguments.contains("-uiTesting")
        openStory = arguments.contains("-openStory")
        if let i = arguments.firstIndex(of: "-storyPage"), i + 1 < arguments.count { storyPage = Int(arguments[i + 1]) }
        if let i = arguments.firstIndex(of: "-tab"), i + 1 < arguments.count { tab = AppTab(rawValue: arguments[i + 1]) }
    }

    /// A fresh, throwaway defaults domain so test runs never see real data.
    static func testDefaults() -> UserDefaults {
        let name = "odyssey.uitesting"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }
}
