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
    @Published private(set) var isValidating = false
    @Published private(set) var lastReachableAt: Date?

    private var didLoad = false
    private var reachabilityObserver: NSObjectProtocol?

    deinit {
        if let reachabilityObserver {
            NotificationCenter.default.removeObserver(reachabilityObserver)
        }
    }

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

    /// Does the user have any saved/active station to manage? Drives whether
    /// we show "Connection" controls vs. an empty "Add your first station"
    /// state.
    var hasActiveStation: Bool {
        activeProfile != nil
    }

    /// High-level state shown at the top of the connection section. Combines
    /// the live `validateConnection` result, the most recent successful
    /// fetch from any feature view model, and the in-flight validate state.
    var liveStatus: LiveStatus {
        guard activeProfile != nil else { return .noStation }
        if isValidating && connectionReport == nil { return .checking }
        if connectionReport != nil { return .connected }
        if let lastReachableAt { return .reachable(at: lastReachableAt) }
        return .unknown
    }

    func load(environment: AppEnvironment) async {
        guard !didLoad else { return }
        didLoad = true

        installReachabilityObserverIfNeeded()

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

        // Kick off a background validation when an active profile already
        // exists, so the screen surfaces real Identity/TLS/Security info
        // instead of "Not validated yet". This is non-blocking so the UI
        // can render saved profile/credentials immediately.
        if activeProfile != nil, connectionReport == nil {
            Task { [weak self] in
                await self?.validateActiveProfileQuietly(environment: environment)
            }
        }
    }

    /// Background re-validate of the currently active profile without
    /// surfacing a status banner. Used on screen open (and could be reused
    /// by a manual "Re-validate" action that wants to stay quiet).
    func validateActiveProfileQuietly(environment: AppEnvironment) async {
        guard let active = activeProfile else { return }
        guard !isValidating else { return }

        isValidating = true
        defer { isValidating = false }

        do {
            let report = try await environment.apiClient.validateConnection(station: active)
            connectionReport = report
            lastReachableAt = Date()
        } catch {
            // Quiet failure: keep whatever state we already had. Surfacing
            // an error banner here would be noisy because the user did not
            // explicitly request a connect action.
        }
    }

    /// Forwards an explicit user-driven re-validate to the same code path
    /// `connect()` uses, but without rebuilding the profile from the URL
    /// text field. Used by the "Refresh" button when an active profile
    /// already exists.
    func revalidateActiveProfile(environment: AppEnvironment) async {
        await performBusyOperation {
            guard let active = activeProfile else {
                throw StationConnectionError.invalidURL
            }

            isValidating = true
            defer { isValidating = false }

            let report = try await environment.apiClient.validateConnection(station: active)
            connectionReport = report
            lastReachableAt = Date()
            authStatus = nil
            setMessage(String(localized: "Connection refreshed."), kind: .success)
        }
    }

    private func installReachabilityObserverIfNeeded() {
        guard reachabilityObserver == nil else { return }
        reachabilityObserver = NotificationCenter.default.addObserver(
            forName: .activeStationDidRespond,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // The closure runs on the main queue; hop onto the main actor
            // explicitly so we can mutate @Published state safely.
            Task { @MainActor in
                guard let self else { return }
                let respondingProfile = notification.object as? StationProfile
                if let respondingProfile, respondingProfile.id != self.activeProfileID {
                    return
                }
                self.lastReachableAt = Date()
            }
        }
    }

    /// Validates the URL in `baseURLText`, persists the resulting profile,
    /// and switches the app to it. Used both for adding the very first
    /// station and for adding subsequent ones.
    ///
    /// Returns `true` when the connection was validated and the new
    /// station became active. Returns `false` when validation failed (the
    /// caller can use this to decide whether to dismiss an Add Station
    /// form).
    @discardableResult
    func connect(environment: AppEnvironment) async -> Bool {
        var didSucceed = false
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
            lastReachableAt = Date()
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
            didSucceed = true
        }
        return didSucceed
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
            lastReachableAt = nil
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

        // After the busy operation completes, kick off a quiet validate so
        // the connection details refill without forcing the user to tap
        // Refresh.
        if activeProfile != nil {
            Task { [weak self] in
                await self?.validateActiveProfileQuietly(environment: environment)
            }
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
                lastReachableAt = nil

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
    /// Clears the URL/credential form so the user can enter a new station
    /// URL, without dropping the in-memory connection state for whichever
    /// profile is currently active. The Connection section continues to
    /// reflect the active station's live status while the user types into
    /// the Add Station form below it.
    func prepareForNewStation() {
        baseURLText = ""
        username = ""
        password = ""
    }

    /// Restores the URL field and Keychain-backed credentials for the
    /// currently active profile. Used to back out of an in-progress
    /// "Add Station" form without losing the user's saved login.
    func restoreActiveProfileForm(environment: AppEnvironment) async {
        guard let active = activeProfile else {
            baseURLText = ""
            username = ""
            password = ""
            return
        }

        baseURLText = active.baseURL.absoluteString

        do {
            if let credentials = try await environment.credentialStore.loadCredentials(for: active) {
                username = credentials.username ?? ""
                password = credentials.password
            } else {
                username = ""
                password = ""
            }
        } catch {
            // Failure to read Keychain shouldn't block the form reset.
            username = ""
            password = ""
        }
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

    /// Posted on the main actor whenever a feature view model successfully
    /// completes an API call against the active station. The Station screen
    /// uses this to mark the station as live without forcing a redundant
    /// `validateConnection` round-trip on every screen open.
    ///
    /// Notifications carry the responding `StationProfile` in `object` so
    /// listeners can confirm it matches the currently-active profile.
    static let activeStationDidRespond = Notification.Name("OnpaActiveStationDidRespond")
}

extension StationViewModel {
    /// High-level connection state shown at the top of the Station
    /// management screen. Combines the live `validateConnection` report,
    /// the most recent successful fetch from any feature view model, and
    /// any in-flight validate request.
    enum LiveStatus: Equatable {
        /// No active station profile has been chosen yet.
        case noStation
        /// We have a profile and a fresh `validateConnection` report.
        case connected
        /// We have a profile and a recent successful API call from another
        /// feature, but no fresh `validateConnection` report yet.
        case reachable(at: Date)
        /// We're currently running `validateConnection` against the active
        /// profile and have no prior report to fall back to.
        case checking
        /// We have a profile but no recent evidence of reachability.
        case unknown

        var displayName: String {
            switch self {
            case .noStation:
                return String(localized: "No station")
            case .connected, .reachable:
                return String(localized: "Connected")
            case .checking:
                return String(localized: "Checking…")
            case .unknown:
                return String(localized: "Unknown")
            }
        }

        var systemImage: String {
            switch self {
            case .noStation:
                return "wifi.slash"
            case .connected, .reachable:
                return "checkmark.circle.fill"
            case .checking:
                return "arrow.triangle.2.circlepath"
            case .unknown:
                return "questionmark.circle"
            }
        }
    }

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
