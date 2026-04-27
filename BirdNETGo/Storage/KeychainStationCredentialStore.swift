import Foundation
import Security

struct KeychainStationCredentialStore: StationCredentialStore {
    private let service = "com.jakeshirley.birdnetgo.station-credentials"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadCredentials(for profile: StationProfile) async throws -> StationCredentials? {
        var query = baseQuery(for: profile)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unhandledStatus(status)
        }

        return try decoder.decode(StationCredentials.self, from: data)
    }

    func saveCredentials(_ credentials: StationCredentials, for profile: StationProfile) async throws {
        try await deleteCredentials(for: profile)

        var item = baseQuery(for: profile)
        item[kSecValueData as String] = try encoder.encode(credentials)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    func deleteCredentials(for profile: StationProfile) async throws {
        let status = SecItemDelete(baseQuery(for: profile) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(for profile: StationProfile) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profile.baseURL.absoluteString
        ]
    }
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unhandledStatus(status):
            return "Keychain operation failed with status \(status)."
        }
    }
}