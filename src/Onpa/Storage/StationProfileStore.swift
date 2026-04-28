import Foundation

protocol StationProfileStore: Sendable {
    /// Returns every saved profile in user-defined order (oldest first).
    func loadProfiles() async throws -> [StationProfile]

    /// Persists the full profile list, replacing whatever was stored.
    func saveProfiles(_ profiles: [StationProfile]) async throws

    /// Identifier of the active profile, or `nil` if no profile is selected.
    func loadActiveProfileID() async throws -> UUID?

    /// Persists the active profile identifier. Pass `nil` to clear it.
    func saveActiveProfileID(_ id: UUID?) async throws
}

extension StationProfileStore {
    /// Convenience: returns the currently active profile, if any.
    func loadActiveProfile() async throws -> StationProfile? {
        guard let activeID = try await loadActiveProfileID() else {
            return nil
        }

        let profiles = try await loadProfiles()
        return profiles.first { $0.id == activeID }
    }

    /// Convenience: upserts the supplied profile and marks it active. Pass
    /// `nil` to deactivate without removing any profile from the list.
    func saveActiveProfile(_ profile: StationProfile?) async throws {
        guard let profile else {
            try await saveActiveProfileID(nil)
            return
        }

        var profiles = try await loadProfiles()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else if let sameURL = profiles.firstIndex(where: { $0.baseURL == profile.baseURL }) {
            // Reuse the existing slot for an identical URL so we don't end up
            // with duplicate entries when callers fabricate fresh UUIDs.
            profiles[sameURL] = profile
        } else {
            profiles.append(profile)
        }

        try await saveProfiles(profiles)
        try await saveActiveProfileID(profile.id)
    }
}

protocol StationCredentialStore: Sendable {
    func loadCredentials(for profile: StationProfile) async throws -> StationCredentials?
    func saveCredentials(_ credentials: StationCredentials, for profile: StationProfile) async throws
    func deleteCredentials(for profile: StationProfile) async throws
}
