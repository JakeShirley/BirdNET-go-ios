import Foundation

actor InMemoryStationProfileStore: StationProfileStore {
    private var profiles: [StationProfile]
    private var activeProfileID: UUID?

    init(activeProfile: StationProfile? = nil) {
        if let activeProfile {
            self.profiles = [activeProfile]
            self.activeProfileID = activeProfile.id
        } else {
            self.profiles = []
            self.activeProfileID = nil
        }
    }

    init(profiles: [StationProfile], activeProfileID: UUID? = nil) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID ?? profiles.first?.id
    }

    func loadProfiles() async throws -> [StationProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [StationProfile]) async throws {
        self.profiles = profiles
    }

    func loadActiveProfileID() async throws -> UUID? {
        activeProfileID
    }

    func saveActiveProfileID(_ id: UUID?) async throws {
        activeProfileID = id
    }
}
