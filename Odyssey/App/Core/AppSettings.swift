import Foundation
import Observation
import OdysseyKit

/// User preferences, persisted to UserDefaults. Secrets live in the Keychain (`Vault`).
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Keys.onboarded) } }
    var demoMode: Bool { didSet { defaults.set(demoMode, forKey: Keys.demo) } }
    /// nil = follow the Strava account's preference.
    var unitOverride: UnitSystem? { didSet { defaults.set(unitOverride?.rawValue, forKey: Keys.units) } }
    /// ISO weekday index: 0 = Monday, 6 = Sunday.
    var firstWeekday: Int { didSet { defaults.set(firstWeekday, forKey: Keys.firstWeekday) } }
    var clientID: String { didSet { defaults.set(clientID, forKey: Keys.clientID) } }
    var callbackDomain: String { didSet { defaults.set(callbackDomain, forKey: Keys.callbackDomain) } }
    var tokenServer: String { didSet { defaults.set(tokenServer, forKey: Keys.tokenServer) } }
    var trimRouteEnds: Bool { didSet { defaults.set(trimRouteEnds, forKey: Keys.trimRoutes) } }
    var shareCompanionNames: Bool { didSet { defaults.set(shareCompanionNames, forKey: Keys.shareNames) } }
    var shareRouteArt: Bool { didSet { defaults.set(shareRouteArt, forKey: Keys.shareRoutes) } }
    var autoAdvance: Bool { didSet { defaults.set(autoAdvance, forKey: Keys.autoAdvance) } }
    /// Detail requests per sync (each costs one of Strava's 100 reads per 15 minutes).
    var detailBudget: Int { didSet { defaults.set(detailBudget, forKey: Keys.detailBudget) } }
    var shareTheme: ShareTheme { didSet { defaults.set(shareTheme.rawValue, forKey: Keys.shareTheme) } }
    /// Whether the Keychain holds a Strava client secret. Mirrored here because
    /// Keychain reads aren't observable: "Connect" must appear as soon as one is pasted.
    private(set) var hasClientSecret = Vault.clientSecret != nil

    func saveClientSecret(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (Vault.clientSecret ?? "") else { return }
        Vault.saveClientSecret(trimmed)
        hasClientSecret = Vault.clientSecret != nil
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasOnboarded = defaults.bool(forKey: Keys.onboarded)
        demoMode = defaults.bool(forKey: Keys.demo)
        unitOverride = defaults.string(forKey: Keys.units).flatMap(UnitSystem.init(rawValue:))
        firstWeekday = defaults.object(forKey: Keys.firstWeekday) as? Int ?? AppSettings.localeFirstWeekday
        clientID = defaults.string(forKey: Keys.clientID) ?? ""
        callbackDomain = defaults.string(forKey: Keys.callbackDomain) ?? "localhost"
        tokenServer = defaults.string(forKey: Keys.tokenServer) ?? ""
        trimRouteEnds = defaults.object(forKey: Keys.trimRoutes) as? Bool ?? true
        shareCompanionNames = defaults.object(forKey: Keys.shareNames) as? Bool ?? true
        shareRouteArt = defaults.object(forKey: Keys.shareRoutes) as? Bool ?? true
        autoAdvance = defaults.object(forKey: Keys.autoAdvance) as? Bool ?? true
        detailBudget = defaults.object(forKey: Keys.detailBudget) as? Int ?? 60
        shareTheme = defaults.string(forKey: Keys.shareTheme).flatMap(ShareTheme.init(rawValue:)) ?? .sunset
    }

    /// Client ID typed in Settings, else the one baked in at build time.
    var effectiveClientID: String {
        let typed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return (Bundle.main.object(forInfoDictionaryKey: "OdysseyStravaClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Token server typed in Settings, else the build-time one. HTTPS only.
    var tokenServerURL: URL? {
        let typed = tokenServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = typed.isEmpty ? (Bundle.main.object(forInfoDictionaryKey: "OdysseyTokenServer") as? String ?? "") : typed
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host() != nil else { return nil }
        return url
    }

    var stravaConfig: StravaAppConfig {
        StravaAppConfig(clientID: effectiveClientID, callbackDomain: callbackDomain)
    }

    static var localeFirstWeekday: Int {
        // Calendar.firstWeekday: 1 = Sunday … 7 = Saturday → ISO index (0 = Monday).
        (Calendar.current.firstWeekday + 5) % 7
    }

    private enum Keys {
        static let onboarded = "onboarded"
        static let demo = "demoMode"
        static let units = "units"
        static let firstWeekday = "firstWeekday"
        static let clientID = "stravaClientID"
        static let callbackDomain = "stravaCallbackDomain"
        static let tokenServer = "tokenServer"
        static let trimRoutes = "trimRouteEnds"
        static let shareNames = "shareCompanionNames"
        static let shareRoutes = "shareRouteArt"
        static let autoAdvance = "autoAdvance"
        static let detailBudget = "detailBudget"
        static let shareTheme = "shareTheme"
    }
}

/// Colour themes for exported images.
enum ShareTheme: String, CaseIterable, Identifiable {
    case sunset, ocean, aurora, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .aurora: "Aurora"
        case .mono: "Mono"
        }
    }
}
