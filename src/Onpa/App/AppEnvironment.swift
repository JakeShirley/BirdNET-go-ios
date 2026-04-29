import SwiftUI

struct AppEnvironment {
    let configuration: AppConfiguration
    let apiClient: any BirdNETGoAPIClient
    let stationProfileStore: any StationProfileStore
    let credentialStore: any StationCredentialStore
    let preferenceStore: any AppPreferenceStore
    let localCacheStore: any LocalCacheStore
    let diagnosticsService: any DiagnosticsService
    let intelligenceService: any IntelligenceService

    static let live: AppEnvironment = {
        AppEnvironmentMigrator.migrateIfNeeded()
        return AppEnvironment(
            configuration: .current(),
            apiClient: URLSessionBirdNETGoAPIClient(),
            stationProfileStore: UserDefaultsStationProfileStore(userDefaults: AppGroup.sharedDefaults),
            credentialStore: KeychainStationCredentialStore(),
            preferenceStore: UserDefaultsAppPreferenceStore(userDefaults: AppGroup.sharedDefaults),
            localCacheStore: FileSystemLocalCacheStore(rootDirectory: AppGroup.localCacheRootDirectory),
            diagnosticsService: FileDiagnosticsService(),
            intelligenceService: IntelligenceServiceFactory.make()
        )
    }()

    static let preview = AppEnvironment(
        configuration: .preview,
        apiClient: URLSessionBirdNETGoAPIClient(),
        stationProfileStore: InMemoryStationProfileStore(),
        credentialStore: KeychainStationCredentialStore(),
        preferenceStore: UserDefaultsAppPreferenceStore(key: "preview.preferences", userDefaults: .standard),
        localCacheStore: FileSystemLocalCacheStore(),
        diagnosticsService: FileDiagnosticsService(),
        intelligenceService: DisabledIntelligenceService()
    )
}

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.live
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}

/// One-shot migration that copies pre-App-Group state from the standard
/// `UserDefaults` and the legacy local-cache directory into the shared
/// App Group container so existing installs keep their station and
/// cached detections after the upgrade.
private enum AppEnvironmentMigrator {
    private static let migrationKey = "appgroup.migrated.v1"
    private static let keysToMigrate = [
        "station.profiles",
        "station.activeProfileID",
        "station.activeProfile",
        "app.preferences"
    ]

    static func migrateIfNeeded() {
        let shared = AppGroup.sharedDefaults
        guard shared !== UserDefaults.standard else { return }
        guard !shared.bool(forKey: migrationKey) else { return }

        let standard = UserDefaults.standard
        for key in keysToMigrate where shared.object(forKey: key) == nil {
            if let value = standard.object(forKey: key) {
                shared.set(value, forKey: key)
            }
        }

        copyLegacyCacheIfNeeded()

        shared.set(true, forKey: migrationKey)
    }

    private static func copyLegacyCacheIfNeeded() {
        let fileManager = FileManager.default
        guard let legacyRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Onpa/LocalCache", directoryHint: .isDirectory) else {
            return
        }

        let sharedRoot = AppGroup.localCacheRootDirectory
        guard legacyRoot.path != sharedRoot.path else { return }
        guard fileManager.fileExists(atPath: legacyRoot.path) else { return }

        do {
            try fileManager.createDirectory(at: sharedRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: sharedRoot.path) {
                return
            }
            try fileManager.copyItem(at: legacyRoot, to: sharedRoot)
        } catch {
            // Best-effort migration; the app will rebuild its cache on next refresh.
        }
    }
}
