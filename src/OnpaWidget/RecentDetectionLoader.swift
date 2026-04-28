import Foundation

/// Lightweight reader that pulls the most recently cached detection out of
/// the shared App Group container. The widget never talks to BirdNET-Go
/// directly — it relies on the main app to keep
/// `LocalCacheStore[detections / recent-<url>]` fresh while it runs.
struct RecentDetectionLoader {
    private let containerURL: URL
    private let profilesKey: String
    private let activeProfileIDKey: String
    private let userDefaults: UserDefaults
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = AppGroup.sharedDefaults,
        containerURL: URL = AppGroup.localCacheRootDirectory,
        profilesKey: String = "station.profiles",
        activeProfileIDKey: String = "station.activeProfileID"
    ) {
        self.userDefaults = userDefaults
        self.containerURL = containerURL
        self.profilesKey = profilesKey
        self.activeProfileIDKey = activeProfileIDKey
        self.decoder = JSONDecoder()
    }

    /// Returns the active station profile and the most recent cached
    /// detection. Either may be `nil` if the app hasn't been opened yet,
    /// no station is connected, or the cache is empty.
    func loadSnapshot() -> RecentDetectionSnapshot {
        let profile = activeProfile()
        let detection = profile.flatMap { mostRecentDetection(for: $0) }
        return RecentDetectionSnapshot(profile: profile, detection: detection)
    }

    private func activeProfile() -> StationProfile? {
        guard
            let profilesData = userDefaults.data(forKey: profilesKey),
            let profiles = try? decoder.decode([StationProfile].self, from: profilesData)
        else {
            return nil
        }

        if
            let activeIDString = userDefaults.string(forKey: activeProfileIDKey),
            let activeID = UUID(uuidString: activeIDString),
            let match = profiles.first(where: { $0.id == activeID })
        {
            return match
        }

        return profiles.first
    }

    private func mostRecentDetection(for profile: StationProfile) -> BirdDetection? {
        let cacheURL = containerURL
            .appending(path: sanitizedComponent("detections"), directoryHint: .isDirectory)
            .appending(path: sanitizedComponent("recent-\(profile.baseURL.absoluteString)"), directoryHint: .notDirectory)
            .appendingPathExtension("json")

        guard
            FileManager.default.fileExists(atPath: cacheURL.path),
            let data = try? Data(contentsOf: cacheURL),
            let detections = try? decoder.decode([BirdDetection].self, from: data)
        else {
            return nil
        }

        return detections.first
    }

    /// Mirrors `FileSystemLocalCacheStore.sanitizedPathComponent` so the
    /// widget reads the same on-disk location the main app writes to.
    private func sanitizedComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "default" : sanitized
    }
}

struct RecentDetectionSnapshot {
    var profile: StationProfile?
    var detection: BirdDetection?
}
