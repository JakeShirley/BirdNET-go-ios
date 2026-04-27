import Foundation

actor UserDefaultsAppPreferenceStore: AppPreferenceStore {
    private let key: String
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String = "app.preferences", userDefaults: UserDefaults = .standard) {
        self.key = key
        self.userDefaults = userDefaults
    }

    func loadPreferences() async throws -> AppPreferences {
        guard let data = userDefaults.data(forKey: key) else {
            return .defaults
        }

        return try decoder.decode(AppPreferences.self, from: data)
    }

    func savePreferences(_ preferences: AppPreferences) async throws {
        userDefaults.set(try encoder.encode(preferences), forKey: key)
    }
}
