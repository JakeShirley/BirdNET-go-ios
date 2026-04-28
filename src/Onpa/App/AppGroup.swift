import Foundation

/// Shared App Group identifier used to share preferences and cached data
/// between the main `Onpa` app and its `OnpaWidget` extension.
///
/// Both targets list this group in their entitlements and read/write the
/// same `UserDefaults(suiteName:)` and container directory.
enum AppGroup {
    static let identifier = "group.org.odinseye.onpa"

    /// Shared `UserDefaults` for cross-target preferences. Falls back to
    /// `.standard` if the group isn't provisioned (e.g. simulator without
    /// the entitlement applied yet) so the main app keeps working.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Shared container URL for cache files. Falls back to a per-process
    /// Application Support directory if the group container isn't
    /// available.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport
        }

        return FileManager.default.temporaryDirectory
    }

    /// Root directory used by `FileSystemLocalCacheStore` — placed inside
    /// the shared container so the widget can read cached detections.
    static var localCacheRootDirectory: URL {
        containerURL.appending(path: "Onpa/LocalCache", directoryHint: .isDirectory)
    }
}
