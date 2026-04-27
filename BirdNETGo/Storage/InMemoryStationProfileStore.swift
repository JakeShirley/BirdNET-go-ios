actor InMemoryStationProfileStore: StationProfileStore {
    private var activeProfile: StationProfile?

    init(activeProfile: StationProfile? = nil) {
        self.activeProfile = activeProfile
    }

    func loadActiveProfile() async throws -> StationProfile? {
        activeProfile
    }

    func saveActiveProfile(_ profile: StationProfile?) async throws {
        activeProfile = profile
    }
}
