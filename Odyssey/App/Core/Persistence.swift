import Foundation
import Security
import OdysseyKit

/// JSON files in Application Support/Odyssey. Activity data never leaves the device.
nonisolated enum LocalStore {
    static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Odyssey", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appending(path: name + ".json")) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, named name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appending(path: name + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func delete(named name: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: name + ".json"))
    }
}

/// Keychain storage for the Strava tokens and (optionally) your API app's
/// client secret. This device only; never synced.
nonisolated enum Vault {
    private static let service = "com.oftenunknown.odyssey"
    private static let tokensAccount = "strava-tokens"
    private static let secretAccount = "strava-client-secret"

    static var tokens: StravaTokens? {
        read(tokensAccount).flatMap { try? JSONDecoder().decode(StravaTokens.self, from: $0) }
    }

    static func save(_ tokens: StravaTokens) {
        if let data = try? JSONEncoder().encode(tokens) { write(data, account: tokensAccount) }
    }

    static func deleteTokens() { delete(tokensAccount) }

    static var clientSecret: String? {
        read(secretAccount).flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func saveClientSecret(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { delete(secretAccount) } else { write(Data(trimmed.utf8), account: secretAccount) }
    }

    private static func base(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private static func read(_ account: String) -> Data? {
        var query = base(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func write(_ data: Data, account: String) {
        SecItemDelete(base(account) as CFDictionary)
        var add = base(account)
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }
}
