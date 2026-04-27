import SwiftUI

struct AppEnvironment {
    let apiClient: any BirdNETGoAPIClient
    let stationProfileStore: any StationProfileStore
    let credentialStore: any StationCredentialStore

    static let live = AppEnvironment(
        apiClient: URLSessionBirdNETGoAPIClient(),
        stationProfileStore: InMemoryStationProfileStore(),
        credentialStore: KeychainStationCredentialStore()
    )

    static let preview = AppEnvironment(
        apiClient: URLSessionBirdNETGoAPIClient(),
        stationProfileStore: InMemoryStationProfileStore(),
        credentialStore: KeychainStationCredentialStore()
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
