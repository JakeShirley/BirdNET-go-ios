struct AppPreferences: Codable, Equatable, Sendable {
    var rememberStationCredentials: Bool

    static let defaults = AppPreferences(rememberStationCredentials: true)
}

protocol AppPreferenceStore: Sendable {
    func loadPreferences() async throws -> AppPreferences
    func savePreferences(_ preferences: AppPreferences) async throws
}
