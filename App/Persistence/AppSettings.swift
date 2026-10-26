import Foundation
import Observation
import SnagKit

/// User preferences, persisted to UserDefaults. Small and synchronous.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var region: Region { didSet { defaults.set(region.rawValue, forKey: Keys.region) } }
    var eligibilities: Set<Eligibility> { didSet { defaults.set(eligibilities.map(\.rawValue), forKey: Keys.eligibilities) } }
    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Keys.onboarded) } }
    var includeUsed: Bool { didSet { defaults.set(includeUsed, forKey: Keys.includeUsed) } }
    var autoApplyCodes: Bool { didSet { defaults.set(autoApplyCodes, forKey: Keys.autoApply) } }
    var backendURLString: String { didSet { defaults.set(backendURLString, forKey: Keys.backend) } }
    var upcItemDBKey: String { didSet { defaults.set(upcItemDBKey, forKey: Keys.upcKey) } }
    /// TestFlight/Xcode builds only: unlock premium without a purchase.
    var testerPremium: Bool { didSet { defaults.set(testerPremium, forKey: Keys.testerPremium) } }
    var knownMerchants: Set<String> { didSet { defaults.set(Array(knownMerchants), forKey: Keys.knownMerchants) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        region = defaults.string(forKey: Keys.region).flatMap(Region.init(rawValue:))
            ?? Region(regionIdentifier: Locale.current.region?.identifier)
        eligibilities = Set((defaults.stringArray(forKey: Keys.eligibilities) ?? [Eligibility.newCustomer.rawValue]).compactMap(Eligibility.init(rawValue:)))
        hasOnboarded = defaults.bool(forKey: Keys.onboarded)
        includeUsed = defaults.bool(forKey: Keys.includeUsed)
        autoApplyCodes = defaults.object(forKey: Keys.autoApply) as? Bool ?? true
        backendURLString = defaults.string(forKey: Keys.backend) ?? ""
        upcItemDBKey = defaults.string(forKey: Keys.upcKey) ?? ""
        testerPremium = defaults.bool(forKey: Keys.testerPremium)
        knownMerchants = Set(defaults.stringArray(forKey: Keys.knownMerchants) ?? [])
    }

    var currency: String { region.currencyCode }

    var backendURL: URL? {
        let trimmed = backendURLString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme == "https" else { return nil }
        return url
    }

    var deviceID: String {
        if let id = defaults.string(forKey: Keys.deviceID) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Keys.deviceID)
        return id
    }

    private enum Keys {
        static let region = "region"
        static let eligibilities = "eligibilities"
        static let onboarded = "onboarded"
        static let includeUsed = "includeUsed"
        static let autoApply = "autoApplyCodes"
        static let backend = "backendURL"
        static let upcKey = "upcItemDBKey"
        static let testerPremium = "testerPremium"
        static let knownMerchants = "knownMerchants"
        static let deviceID = "deviceID"
    }
}

/// Persona and saved codes live as JSON in Application Support.
enum LocalStore {
    static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Snag", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        Blob.decode(type, from: try? Data(contentsOf: directory.appending(path: name + ".json")))
    }

    static func save<T: Encodable>(_ value: T, named name: String) {
        try? Blob.encode(value).write(to: directory.appending(path: name + ".json"), options: [.atomic, .completeFileProtection])
    }

    static var avatarURL: URL { directory.appending(path: "avatar.png") }
}
