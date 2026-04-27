protocol StationProfileStore: Sendable {
    func loadActiveProfile() async throws -> StationProfile?
    func saveActiveProfile(_ profile: StationProfile?) async throws
}
