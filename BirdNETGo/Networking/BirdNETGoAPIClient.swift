import Foundation

protocol BirdNETGoAPIClient: Sendable {
    func ping(station: StationProfile) async throws -> StationConnectionStatus
    func validateConnection(station: StationProfile) async throws -> StationConnectionReport
    func fetchAppConfig(station: StationProfile) async throws -> StationAppConfig
    func login(station: StationProfile, credentials: StationCredentials, csrfToken: String?) async throws -> StationAuthResponse
    func logout(station: StationProfile, csrfToken: String?) async throws -> StationAuthResponse
    func authStatus(station: StationProfile) async throws -> StationAuthStatus
    func recentDetections(station: StationProfile, limit: Int) async throws -> [BirdDetection]
    func detectionEvents(station: StationProfile) -> AsyncThrowingStream<BirdDetectionStreamEvent, Error>
}

struct StationAppConfig: Decodable, Equatable, Sendable {
    var csrfToken: String
    var security: Security
    var version: String
    var basePath: String

    struct Security: Decodable, Equatable, Sendable {
        var enabled: Bool
        var accessAllowed: Bool
        var authConfig: AuthConfig
        var publicAccess: PublicAccess
    }

    struct AuthConfig: Decodable, Equatable, Sendable {
        var basicEnabled: Bool
        var enabledProviders: [String]
    }

    struct PublicAccess: Decodable, Equatable, Sendable {
        var liveAudio: Bool
    }
}

struct StationAuthResponse: Decodable, Equatable, Sendable {
    var success: Bool
    var message: String
    var username: String?
    var redirectURL: String?
    var errorKey: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case message
        case username
        case redirectURL = "redirectUrl"
        case errorKey = "error_key"
    }
}

struct StationAuthStatus: Decodable, Equatable, Sendable {
    var authenticated: Bool
    var username: String?
    var method: String?

    private enum CodingKeys: String, CodingKey {
        case authenticated
        case username
        case method = "auth_method"
    }
}

enum StationConnectionError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedScheme
    case missingHost
    case invalidResponse
    case serverRejected(statusCode: Int, message: String?)
    case missingBirdNETGoConfig
    case insecurePlainHTTP

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid station URL."
        case .unsupportedScheme:
            return "Station URLs must use HTTP or HTTPS."
        case .missingHost:
            return "Station URL must include a host."
        case .invalidResponse:
            return "The station returned an invalid response."
        case let .serverRejected(statusCode, message):
            return message ?? "The station returned HTTP \(statusCode)."
        case .missingBirdNETGoConfig:
            return "The server did not look like a BirdNET-Go station."
        case .insecurePlainHTTP:
            return "Use HTTPS for remote stations. Plain HTTP is only supported for localhost, private IPs, and .local stations."
        }
    }
}
