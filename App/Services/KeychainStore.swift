import Foundation
import Security
import SnagKit

/// Login details for discount programs (UNiDAYS, Blue Light Card, ID.me…),
/// kept in the Keychain, this device only, and only filled on that program's
/// own website.
struct ProgramCredential: Codable, Hashable, Identifiable {
    var programID: String
    var username: String
    var password: String
    var domain: String

    var id: String { programID }
}

enum KeychainStore {
    private static let service = "com.oftenunknown.snag.programs"

    static func save(_ credential: ProgramCredential) {
        let data = Blob.encode(credential)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: credential.programID,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrLabel] = "Snag – \(credential.programID)"
        SecItemAdd(add as CFDictionary, nil)
    }

    static func credential(for programID: String) -> ProgramCredential? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: programID,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return Blob.decode(ProgramCredential.self, from: data)
    }

    static func delete(programID: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: programID,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func connectedProgramIDs(among programs: [DiscountProgram]) -> Set<String> {
        Set(programs.filter { credential(for: $0.id) != nil }.map(\.id))
    }
}
