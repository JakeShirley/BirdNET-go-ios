import Foundation

actor UserDefaultsStationProfileStore: StationProfileStore {
    private let key: String
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String = "station.activeProfile", userDefaults: UserDefaults = .standard) {
        self.key = key
        self.userDefaults = userDefaults
    }

    func loadActiveProfile() async throws -> StationProfile? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try decoder.decode(StationProfile.self, from: data)
    }

    func saveActiveProfile(_ profile: StationProfile?) async throws {
        guard let profile else {
            userDefaults.removeObject(forKey: key)
            return
        }

        userDefaults.set(try encoder.encode(profile), forKey: key)
    }
}
