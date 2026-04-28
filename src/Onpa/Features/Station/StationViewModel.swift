import Combine
import Foundation

@MainActor
final class StationViewModel: ObservableObject {
    @Published var baseURLText = ""
    @Published var username = ""
    @Published var password = ""
    @Published var rememberCredentials = true
    @Published private(set) var profiles: [StationProfile] = []
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var connectionReport: StationConnectionReport?
    @Published private(set) var authStatus: StationAuthStatus?
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusKind: StatusKind = .neutral
    @Published private(set) var diagnosticsBundleURL: URL?
    @Published private(set) var isBusy = false

    private var didLoad = false

    var activeProfile: StationProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    var canDeleteActiveProfile: Bool {
        activeProfile != nil
    }

    var canLogIn: Bool {
        connectionReport?.appConfig.security.authConfig.basicEnabled == true
    }

    var canLogOut: Bool {
        authStatus?.authenticated == true
    }

    func load(environment: AppEnvironment) async {
        guard !didLoad else { return }
        didLoad = true

        do {
            let preferences = try await environment.preferenceStore.loadPreferences()
            rememberCredentials = preferences.rememberStationCredentials

            profiles = try await environment.stationProfileStore.loadProfiles()
            activeProfileID = try await environment.stationProfileStore.loadActiveProfileID()

            let overrideProfile = environment.configuration.stationURLOverride.map(StationProfile.manual(baseURL:))

            if let overrideProfile {
                applyActiveProfile(overrideProfile)
                setMessage(String(localized: "Using debug station URL override."), kind: .neutral)
            } else if let active = activeProfile {
                applyActiveProfile(active, environment: environment)
            } else if let testProfile = environment.configuration.localNetworkTestProfile {
                applyActiveProfile(testProfile)
                setMessage(String(localized: "Loaded local test station profile."), kind: .neutral)
            }

            if let active = activeProfile,
               let credentials = try await environment.credentialStore.loadCredentials(for: active) {
                username = credentials.username ?? ""
                password = credentials.password
            }
        } catch {
            setMessage(error.userFacingMessage, kind: .warning)
        }
    }

    /// Validates the URL in `baseURLText`, persists the resulting profile,
    /// and switches the app to it. Used both for adding the very first
    /// station and for adding subsequent ones.
    func connect(environment: AppEnvironment) async {
        await performBusyOperation {
            let baseURL = try StationURLValidator.normalizedURL(from: baseURLText)
            guard StationURLValidator.tlsState(for: baseURL) != .insecurePlainHTTP else {
                throw StationConnectionError.insecurePlainHTTP
            }

            let existing = profiles.first { $0.baseURL == baseURL }
            let profile = existing ?? StationProfile.manual(baseURL: baseURL)

            let report = try await environment.apiClient.validateConnection(station: profile)

            try await upsertAndActivate(profile, environment: environment)
            connectionReport = report
            authStatus = nil
            baseURLText = baseURL.absoluteString

            if let credentials = try await environment.credentialStore.loadCredentials(for: profile) {
                username = credentials.username ?? ""
                password = credentials.password
            } else {
                username = ""
                password = ""
            }

            let message = report.requiresAuthentication
                ? String(localized: "Station connected. Login required.")
                : String(localized: "Station connected.")
            setMessage(message, kind: .success)
        }
    }

    /// Switches the active profile to an existing entry without re-validating.
    /// The dependent view models will pick the new profile up on their next
    /// load/refresh cycle.
    func switchProfile(to profile: StationProfile, environment: AppEnvironment) async {
        await performBusyOperation {
            guard profiles.contains(where: { $0.id == profile.id }) else {
                throw StationConnectionError.invalidURL
            }

            try await environment.stationProfileStore.saveActiveProfileID(profile.id)
            activeProfileID = profile.id
            connectionReport = nil
            authStatus = nil
            baseURLText = profile.baseURL.absoluteString

            if let credentials = try await environment.credentialStore.loadCredentials(for: profile) {
                username = credentials.username ?? ""
                password = credentials.password
            } else {
                username = ""
                password = ""
            }

            postActiveProfileDidChangeNotification()
            setMessage(String(localized: "Switched to \(profile.name)."), kind: .success)
        }
    }

    /// Renames a stored profile and persists the change.
    func renameProfile(_ profile: StationProfile, to newName: String, environment: AppEnvironment) async {
        await performBusyOperation {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
            profiles[index].name = trimmed
            try await environment.stationProfileStore.saveProfiles(profiles)

            if profile.id == activeProfileID {
                postActiveProfileDidChangeNotification()
            }
            setMessage(String(localized: "Renamed station to \(trimmed)."), kind: .success)
        }
    }

    /// Removes a specific profile (active or otherwise). When the active
    /// profile is removed, the next remaining profile (if any) becomes
    /// active automatically.
    func deleteProfile(_ profile: StationProfile, environment: AppEnvironment) async {
        await performBusyOperation {
            try await environment.credentialStore.deleteCredentials(for: profile)

            profiles.removeAll { $0.id == profile.id }
            try await environment.stationProfileStore.saveProfiles(profiles)

            if profile.id == activeProfileID {
                let nextActive = profiles.first
                try await environment.stationProfileStore.saveActiveProfileID(nextActive?.id)
                activeProfileID = nextActive?.id
                connectionReport = nil
                authStatus = nil
                diagnosticsBundleURL = nil

                if let nextActive {
                    baseURLText = nextActive.baseURL.absoluteString
                    if let credentials = try await environment.credentialStore.loadCredentials(for: nextActive) {
                        username = credentials.username ?? ""
                        password = credentials.password
                    } else {
                        username = ""
                        password = ""
                    }
                } else {
                    baseURLText = ""
                    username = ""
                    password = ""
                }

                postActiveProfileDidChangeNotification()
            }

            setMessage(String(localized: "Removed \(profile.name)."), kind: .success)
        }
    }

    /// Convenience wrapper that deletes the currently active profile.
    func deleteActiveProfile(environment: AppEnvironment) async {
        guard let active = activeProfile else { return }
        await deleteProfile(active, environment: environment)
    }

    /// Clears the connect form so the user can enter a new station URL.
    func prepareForNewStation() {
        baseURLText = ""
        username = ""
        password = ""
        connectionReport = nil
        authStatus = nil
    }

    func logIn(environment: AppEnvironment) async {
        await performBusyOperation {
            let report = try await ensureConnected(environment: environment)
            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let credentials = StationCredentials(username: trimmedUsername.isEmpty ? nil : trimmedUsername, password: password)
            guard !credentials.password.isEmpty else {
                throw StationConnectionError.serverRejected(statusCode: 400, message: String(localized: "Password is required."))
            }

            let response = try await environment.apiClient.login(station: report.profile, credentials: credentials, csrfToken: report.appConfig.csrfToken)
            let status = try await environment.apiClient.authStatus(station: report.profile)
            authStatus = status
            try await saveCurrentPreferences(environment: environment)

            if response.success && rememberCredentials {
                try await environment.credentialStore.saveCredentials(credentials, for: report.profile)
            }

            setMessage(status.authenticated ? String(localized: "Logged in.") : response.message, kind: response.success ? .success : .warning)
        }
    }

    func logOut(environment: AppEnvironment) async {
        await performBusyOperation {
            let report = try await ensureConnected(environment: environment)
            _ = try await environment.apiClient.logout(station: report.profile, csrfToken: report.appConfig.csrfToken)
            try await environment.credentialStore.deleteCredentials(for: report.profile)
            password = ""
            authStatus = StationAuthStatus(authenticated: false, username: nil, method: nil)
            setMessage(String(localized: "Logged out."), kind: .success)
        }
    }

    func savePreferences(environment: AppEnvironment) async {
        do {
            try await saveCurrentPreferences(environment: environment)
        } catch {
            setMessage(error.userFacingMessage, kind: .warning)
        }
    }

    func generateDiagnostics(environment: AppEnvironment) async {
        await performBusyOperation {
            let preferences = try? await environment.preferenceStore.loadPreferences()
            let active = activeProfile
            diagnosticsBundleURL = try await environment.diagnosticsService.makeDiagnosticsBundle(
                snapshot: DiagnosticsSnapshot(
                    configuration: environment.configuration,
                    activeProfile: active,
                    preferences: preferences,
                    connectionReport: connectionReport,
                    authStatus: authStatus,
                    statusMessage: statusMessage
                )
            )
            setMessage(String(localized: "Diagnostics bundle ready to share."), kind: .success)
        }
    }

    func refreshAuthStatus(environment: AppEnvironment) async {
        await performBusyOperation {
            let report = try await ensureConnected(environment: environment)
            authStatus = try await environment.apiClient.authStatus(station: report.profile)
            setMessage(
                authStatus?.authenticated == true ? String(localized: "Authenticated.") : String(localized: "Not authenticated."),
                kind: .neutral
            )
        }
    }

    // MARK: - Helpers

    private func applyActiveProfile(_ profile: StationProfile, environment: AppEnvironment? = nil) {
        if !profiles.contains(where: { $0.id == profile.id }) {
            profiles.append(profile)
        }
        activeProfileID = profile.id
        baseURLText = profile.baseURL.absoluteString
    }

    private func upsertAndActivate(_ profile: StationProfile, environment: AppEnvironment) async throws {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else if let index = profiles.firstIndex(where: { $0.baseURL == profile.baseURL }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        try await environment.stationProfileStore.saveProfiles(profiles)
        try await environment.stationProfileStore.saveActiveProfileID(profile.id)
        activeProfileID = profile.id
        postActiveProfileDidChangeNotification()
    }

    private func ensureConnected(environment: AppEnvironment) async throws -> StationConnectionReport {
        if let connectionReport {
            return connectionReport
        }

        let baseURL = try StationURLValidator.normalizedURL(from: baseURLText)
        guard StationURLValidator.tlsState(for: baseURL) != .insecurePlainHTTP else {
            throw StationConnectionError.insecurePlainHTTP
        }

        let existing = profiles.first { $0.baseURL == baseURL }
        let profile = existing ?? StationProfile.manual(baseURL: baseURL)
        let report = try await environment.apiClient.validateConnection(station: profile)
        try await upsertAndActivate(profile, environment: environment)
        connectionReport = report
        baseURLText = baseURL.absoluteString
        return report
    }

    private func performBusyOperation(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await operation()
        } catch {
            setMessage(error.userFacingMessage, kind: .error)
        }
    }

    private func setMessage(_ message: String, kind: StatusKind) {
        statusMessage = message
        statusKind = kind
    }

    private func saveCurrentPreferences(environment: AppEnvironment) async throws {
        var preferences = try await environment.preferenceStore.loadPreferences()
        preferences.rememberStationCredentials = rememberCredentials
        try await environment.preferenceStore.savePreferences(preferences)
    }

    private func postActiveProfileDidChangeNotification() {
        NotificationCenter.default.post(name: .activeStationProfileDidChange, object: nil)
    }
}

extension Notification.Name {
    /// Posted on the main actor whenever the active station profile changes
    /// (switch, rename, delete, or new connection). Feature view models
    /// listen for this so they can drop cached state and reload against the
    /// new profile.
    static let activeStationProfileDidChange = Notification.Name("OnpaActiveStationProfileDidChange")
}

extension StationViewModel {
    enum StatusKind {
        case neutral
        case success
        case warning
        case error

        var systemImage: String {
            switch self {
            case .neutral:
                return "info.circle"
            case .success:
                return "checkmark.circle"
            case .warning:
                return "exclamationmark.triangle"
            case .error:
                return "xmark.octagon"
            }
        }
    }
}
