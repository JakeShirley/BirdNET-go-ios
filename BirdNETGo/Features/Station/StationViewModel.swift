import Combine
import Foundation

@MainActor
final class StationViewModel: ObservableObject {
    @Published var baseURLText = ""
    @Published var username = ""
    @Published var password = ""
    @Published var rememberCredentials = true
    @Published private(set) var connectionReport: StationConnectionReport?
    @Published private(set) var authStatus: StationAuthStatus?
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusKind: StatusKind = .neutral
    @Published private(set) var isBusy = false

    private var didLoad = false

    var canLogIn: Bool {
        connectionReport?.appConfig.security.authConfig.basicEnabled == true
    }

    var canLogOut: Bool {
        authStatus?.authenticated == true
    }

    func load(environment: AppEnvironment) async {
        guard !didLoad else {
            return
        }

        didLoad = true

        do {
            guard let profile = try await environment.stationProfileStore.loadActiveProfile() else {
                return
            }

            baseURLText = profile.baseURL.absoluteString
            if let credentials = try await environment.credentialStore.loadCredentials(for: profile) {
                username = credentials.username ?? ""
                password = credentials.password
            }
        } catch {
            setMessage(error.localizedDescription, kind: .warning)
        }
    }

    func connect(environment: AppEnvironment) async {
        await performBusyOperation {
            let baseURL = try StationURLValidator.normalizedURL(from: baseURLText)
            guard StationURLValidator.tlsState(for: baseURL) != .insecurePlainHTTP else {
                throw StationConnectionError.insecurePlainHTTP
            }

            let profile = StationProfile.manual(baseURL: baseURL)
            let report = try await environment.apiClient.validateConnection(station: profile)
            try await environment.stationProfileStore.saveActiveProfile(profile)

            connectionReport = report
            authStatus = nil
            baseURLText = baseURL.absoluteString

            if let credentials = try await environment.credentialStore.loadCredentials(for: profile) {
                username = credentials.username ?? ""
                password = credentials.password
            }

            let message = report.requiresAuthentication ? "Station connected. Login required." : "Station connected."
            setMessage(message, kind: .success)
        }
    }

    func logIn(environment: AppEnvironment) async {
        await performBusyOperation {
            let report = try await ensureConnected(environment: environment)
            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let credentials = StationCredentials(username: trimmedUsername.isEmpty ? nil : trimmedUsername, password: password)
            guard !credentials.password.isEmpty else {
                throw StationConnectionError.serverRejected(statusCode: 400, message: "Password is required.")
            }

            let response = try await environment.apiClient.login(station: report.profile, credentials: credentials, csrfToken: report.appConfig.csrfToken)
            let status = try await environment.apiClient.authStatus(station: report.profile)
            authStatus = status

            if response.success && rememberCredentials {
                try await environment.credentialStore.saveCredentials(credentials, for: report.profile)
            }

            setMessage(status.authenticated ? "Logged in." : response.message, kind: response.success ? .success : .warning)
        }
    }

    func logOut(environment: AppEnvironment) async {
        await performBusyOperation {
            let report = try await ensureConnected(environment: environment)
            _ = try await environment.apiClient.logout(station: report.profile, csrfToken: report.appConfig.csrfToken)
            try await environment.credentialStore.deleteCredentials(for: report.profile)
            password = ""
            authStatus = StationAuthStatus(authenticated: false, username: nil, method: nil)
            setMessage("Logged out.", kind: .success)
        }
    }

    func refreshAuthStatus(environment: AppEnvironment) async {
        await performBusyOperation {
            let report = try await ensureConnected(environment: environment)
            authStatus = try await environment.apiClient.authStatus(station: report.profile)
            setMessage(authStatus?.authenticated == true ? "Authenticated." : "Not authenticated.", kind: .neutral)
        }
    }

    private func ensureConnected(environment: AppEnvironment) async throws -> StationConnectionReport {
        if let connectionReport {
            return connectionReport
        }

        let baseURL = try StationURLValidator.normalizedURL(from: baseURLText)
        guard StationURLValidator.tlsState(for: baseURL) != .insecurePlainHTTP else {
            throw StationConnectionError.insecurePlainHTTP
        }

        let profile = StationProfile.manual(baseURL: baseURL)
        let report = try await environment.apiClient.validateConnection(station: profile)
        try await environment.stationProfileStore.saveActiveProfile(profile)
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
            setMessage(error.localizedDescription, kind: .error)
        }
    }

    private func setMessage(_ message: String, kind: StatusKind) {
        statusMessage = message
        statusKind = kind
    }
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