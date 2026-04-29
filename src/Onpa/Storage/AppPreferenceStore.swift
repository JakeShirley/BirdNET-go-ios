import SwiftUI

enum AppearancePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "app.preferences.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var rememberStationCredentials: Bool
    var autoFetchSpectrograms: Bool
    var appearance: AppearancePreference
    /// When true, the app may use Apple's on-device Foundation Models to
    /// rewrite deterministic summaries (e.g. the dashboard Daily Digest)
    /// in plain language. Generation only runs on devices that support
    /// Apple Intelligence; the deterministic template is always the
    /// fallback. Defaults off until the feature has been dogfooded.
    var enableIntelligenceSummaries: Bool

    static let defaults = AppPreferences(
        rememberStationCredentials: true,
        autoFetchSpectrograms: true,
        appearance: .system,
        enableIntelligenceSummaries: false
    )

    init(
        rememberStationCredentials: Bool,
        autoFetchSpectrograms: Bool,
        appearance: AppearancePreference = .system,
        enableIntelligenceSummaries: Bool = false
    ) {
        self.rememberStationCredentials = rememberStationCredentials
        self.autoFetchSpectrograms = autoFetchSpectrograms
        self.appearance = appearance
        self.enableIntelligenceSummaries = enableIntelligenceSummaries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rememberStationCredentials = try container.decodeIfPresent(Bool.self, forKey: .rememberStationCredentials) ?? Self.defaults.rememberStationCredentials
        autoFetchSpectrograms = try container.decodeIfPresent(Bool.self, forKey: .autoFetchSpectrograms) ?? Self.defaults.autoFetchSpectrograms
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? Self.defaults.appearance
        enableIntelligenceSummaries = try container.decodeIfPresent(Bool.self, forKey: .enableIntelligenceSummaries) ?? Self.defaults.enableIntelligenceSummaries
    }
}

protocol AppPreferenceStore: Sendable {
    func loadPreferences() async throws -> AppPreferences
    func savePreferences(_ preferences: AppPreferences) async throws
}
