protocol StationProfileStore: Sendable {
    func loadActiveProfile() async throws -> StationProfile?
    func saveActiveProfile(_ profile: StationProfile?) async throws
}

protocol StationCredentialStore: Sendable {
    func loadCredentials(for profile: StationProfile) async throws -> StationCredentials?
    func saveCredentials(_ credentials: StationCredentials, for profile: StationProfile) async throws
    func deleteCredentials(for profile: StationProfile) async throws
}
