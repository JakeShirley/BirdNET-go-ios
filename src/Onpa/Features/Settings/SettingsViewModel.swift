import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var rememberStationCredentials = AppPreferences.defaults.rememberStationCredentials
    @Published var autoFetchSpectrograms = AppPreferences.defaults.autoFetchSpectrograms
    @Published var appearance = AppPreferences.defaults.appearance
    @Published var enableIntelligenceSummaries = AppPreferences.defaults.enableIntelligenceSummaries
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusSystemImage = "info.circle"
    @Published private(set) var isLoading = false

    private var didLoad = false

    func load(environment: AppEnvironment) async {
        guard !didLoad else {
            return
        }

        didLoad = true
        isLoading = true
        defer { isLoading = false }

        do {
            let preferences = try await environment.preferenceStore.loadPreferences()
            rememberStationCredentials = preferences.rememberStationCredentials
            autoFetchSpectrograms = preferences.autoFetchSpectrograms
            appearance = preferences.appearance
            enableIntelligenceSummaries = preferences.enableIntelligenceSummaries
            UserDefaults.standard.set(preferences.appearance.rawValue, forKey: AppearancePreference.storageKey)
        } catch {
            setMessage(error.userFacingMessage, systemImage: "exclamationmark.triangle")
        }
    }

    func save(environment: AppEnvironment) async {
        do {
            try await environment.preferenceStore.savePreferences(
                AppPreferences(
                    rememberStationCredentials: rememberStationCredentials,
                    autoFetchSpectrograms: autoFetchSpectrograms,
                    appearance: appearance,
                    enableIntelligenceSummaries: enableIntelligenceSummaries
                )
            )
            UserDefaults.standard.set(appearance.rawValue, forKey: AppearancePreference.storageKey)
            setMessage(String(localized: "Settings saved."), systemImage: "checkmark.circle")
        } catch {
            setMessage(error.userFacingMessage, systemImage: "exclamationmark.triangle")
        }
    }

    private func setMessage(_ message: String, systemImage: String) {
        statusMessage = message
        statusSystemImage = systemImage
    }
}
