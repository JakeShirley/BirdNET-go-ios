import Foundation

struct URLSessionBirdNETGoAPIClient: BirdNETGoAPIClient {
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(urlSession: URLSession = URLSessionBirdNETGoAPIClient.makeDefaultSession()) {
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func ping(station: StationProfile) async throws -> StationConnectionStatus {
        let (_, response) = try await perform(request(station: station, path: "api/v2/ping"))

        return (200..<300).contains(response.statusCode) ? .reachable : .unreachable
    }

    func validateConnection(station: StationProfile) async throws -> StationConnectionReport {
        let status = try await ping(station: station)
        guard status == .reachable else {
            throw StationConnectionError.serverRejected(statusCode: 0, message: "The station did not respond to ping.")
        }

        let appConfig = try await fetchAppConfig(station: station)
        guard !appConfig.csrfToken.isEmpty else {
            throw StationConnectionError.missingBirdNETGoConfig
        }

        return StationConnectionReport(
            profile: station,
            status: status,
            tlsState: StationURLValidator.tlsState(for: station.baseURL),
            appConfig: appConfig
        )
    }

    func fetchAppConfig(station: StationProfile) async throws -> StationAppConfig {
        let (data, response) = try await perform(request(station: station, path: "api/v2/app/config"))
        try validate(response: response, data: data)

        do {
            return try decoder.decode(StationAppConfig.self, from: data)
        } catch {
            throw StationConnectionError.missingBirdNETGoConfig
        }
    }

    func login(station: StationProfile, credentials: StationCredentials, csrfToken: String?) async throws -> StationAuthResponse {
        let payload = AuthRequest(username: credentials.username ?? AuthRequest.defaultUsername, password: credentials.password, redirectURL: "/ui/", basePath: "/ui/")
        let body = try encoder.encode(payload)
        let (data, response) = try await perform(request(station: station, path: "api/v2/auth/login", method: "POST", csrfToken: csrfToken, body: body))
        try validate(response: response, data: data)
        let authResponse = try decoder.decode(StationAuthResponse.self, from: data)

        if authResponse.success, let redirectURL = authResponse.redirectURL {
            try await completeLoginRedirect(redirectURL, station: station)
        }

        return authResponse
    }

    func logout(station: StationProfile, csrfToken: String?) async throws -> StationAuthResponse {
        let (data, response) = try await perform(request(station: station, path: "api/v2/auth/logout", method: "POST", csrfToken: csrfToken))
        try validate(response: response, data: data)
        return try decoder.decode(StationAuthResponse.self, from: data)
    }

    func authStatus(station: StationProfile) async throws -> StationAuthStatus {
        let (data, response) = try await perform(request(station: station, path: "api/v2/auth/status"))
        if response.statusCode == 401 || response.statusCode == 403 {
            return StationAuthStatus(authenticated: false, username: nil, method: nil)
        }

        try validate(response: response, data: data)
        return try decoder.decode(StationAuthStatus.self, from: data)
    }

    func recentDetections(station: StationProfile, limit: Int) async throws -> [BirdDetection] {
        let queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        let (data, response) = try await perform(request(station: station, path: "api/v2/detections/recent", queryItems: queryItems))
        try validate(response: response, data: data)
        return try decoder.decode([BirdDetection].self, from: data)
    }

    private func completeLoginRedirect(_ redirectURL: String, station: StationProfile) async throws {
        let callbackURL: URL
        if let absoluteURL = URL(string: redirectURL), absoluteURL.scheme != nil {
            callbackURL = absoluteURL
        } else if let relativeURL = URL(string: redirectURL, relativeTo: station.baseURL)?.absoluteURL {
            callbackURL = relativeURL
        } else {
            throw StationConnectionError.invalidResponse
        }

        let (_, response) = try await perform(URLRequest(url: callbackURL))
        guard (200..<400).contains(response.statusCode) else {
            throw StationConnectionError.serverRejected(statusCode: response.statusCode, message: nil)
        }
    }

    private func request(station: StationProfile, path: String, method: String = "GET", queryItems: [URLQueryItem] = [], csrfToken: String? = nil, body: Data? = nil) -> URLRequest {
        let url = station.baseURL.appending(path: path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        var request = URLRequest(url: components?.url ?? url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let csrfToken, !csrfToken.isEmpty {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        }

        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StationConnectionError.invalidResponse
        }

        return (data, httpResponse)
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message = try? decoder.decode(StationAuthResponse.self, from: data).message
            throw StationConnectionError.serverRejected(statusCode: response.statusCode, message: message)
        }
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}

private struct AuthRequest: Encodable {
    static let defaultUsername = "birdnet-client"

    var username: String
    var password: String
    var redirectURL: String
    var basePath: String

    private enum CodingKeys: String, CodingKey {
        case username
        case password
        case redirectURL = "redirectUrl"
        case basePath
    }
}
