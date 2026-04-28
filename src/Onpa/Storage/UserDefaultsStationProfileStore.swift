import Foundation

actor UserDefaultsStationProfileStore: StationProfileStore {
    private let profilesKey: String
    private let activeIDKey: String
    private let legacyActiveProfileKey: String
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var didMigrateLegacy = false

    init(
        profilesKey: String = "station.profiles",
        activeIDKey: String = "station.activeProfileID",
        legacyActiveProfileKey: String = "station.activeProfile",
        userDefaults: UserDefaults = .standard
    ) {
        self.profilesKey = profilesKey
        self.activeIDKey = activeIDKey
        self.legacyActiveProfileKey = legacyActiveProfileKey
        self.userDefaults = userDefaults
    }

    func loadProfiles() async throws -> [StationProfile] {
        try migrateLegacyIfNeeded()

        guard let data = userDefaults.data(forKey: profilesKey) else {
            return []
        }

        return try decoder.decode([StationProfile].self, from: data)
    }

    func saveProfiles(_ profiles: [StationProfile]) async throws {
        try migrateLegacyIfNeeded()
        userDefaults.set(try encoder.encode(profiles), forKey: profilesKey)
    }

    func loadActiveProfileID() async throws -> UUID? {
        try migrateLegacyIfNeeded()

        guard let raw = userDefaults.string(forKey: activeIDKey) else {
            return nil
        }

        return UUID(uuidString: raw)
    }

    func saveActiveProfileID(_ id: UUID?) async throws {
        try migrateLegacyIfNeeded()

        guard let id else {
            userDefaults.removeObject(forKey: activeIDKey)
            return
        }

        userDefaults.set(id.uuidString, forKey: activeIDKey)
    }

    /// One-shot migration: if a legacy single-profile blob exists at
    /// `station.activeProfile`, decode it, push it into the new profile list
    /// (if not already present) and mark it active. The legacy key is then
    /// removed so we don't migrate twice.
    private func migrateLegacyIfNeeded() throws {
        guard !didMigrateLegacy else { return }
        didMigrateLegacy = true

        guard let legacyData = userDefaults.data(forKey: legacyActiveProfileKey) else {
            return
        }

        defer { userDefaults.removeObject(forKey: legacyActiveProfileKey) }

        let legacyProfile = try decoder.decode(StationProfile.self, from: legacyData)

        var existing: [StationProfile] = []
        if let data = userDefaults.data(forKey: profilesKey) {
            existing = (try? decoder.decode([StationProfile].self, from: data)) ?? []
        }

        if !existing.contains(where: { $0.id == legacyProfile.id || $0.baseURL == legacyProfile.baseURL }) {
            existing.append(legacyProfile)
            userDefaults.set(try encoder.encode(existing), forKey: profilesKey)
        }

        if userDefaults.string(forKey: activeIDKey) == nil {
            userDefaults.set(legacyProfile.id.uuidString, forKey: activeIDKey)
        }
    }
}
