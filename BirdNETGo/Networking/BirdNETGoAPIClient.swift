import Foundation

protocol BirdNETGoAPIClient: Sendable {
    func ping(station: StationProfile) async throws -> StationConnectionStatus
    func validateConnection(station: StationProfile) async throws -> StationConnectionReport
    func fetchAppConfig(station: StationProfile) async throws -> StationAppConfig
    func login(station: StationProfile, credentials: StationCredentials, csrfToken: String?) async throws -> StationAuthResponse
    func logout(station: StationProfile, csrfToken: String?) async throws -> StationAuthResponse
    func authStatus(station: StationProfile) async throws -> StationAuthStatus
    func recentDetections(station: StationProfile, limit: Int) async throws -> [BirdDetection]
    func detection(station: StationProfile, id: Int) async throws -> BirdDetection
    func species(station: StationProfile) async throws -> [StationSpecies]
    func dailySpeciesSummary(station: StationProfile, date: String, limit: Int) async throws -> [DailySpeciesSummary]
    func audioClipURL(station: StationProfile, detectionID: Int) -> URL
    func speciesImageURL(station: StationProfile, scientificName: String) -> URL
    func speciesImageAttribution(station: StationProfile, scientificName: String) async throws -> SpeciesImageAttribution
    func weatherForDetection(station: StationProfile, detectionID: Int) async throws -> DetectionWeatherContext
    func detectionTimeOfDay(station: StationProfile, detectionID: Int) async throws -> DetectionTimeOfDayContext
    func spectrogramURL(station: StationProfile, detectionID: Int, size: String, raw: Bool) -> URL
    func spectrogramStatus(station: StationProfile, detectionID: Int, size: String, raw: Bool) async throws -> SpectrogramStatusEnvelope
    func requestSpectrogramGeneration(station: StationProfile, detectionID: Int, size: String, raw: Bool, csrfToken: String?) async throws -> SpectrogramStatusEnvelope
    func detectionEvents(station: StationProfile) -> AsyncThrowingStream<BirdDetectionStreamEvent, Error>
}

struct SpeciesImageAttribution: Decodable, Equatable, Sendable {
    var authorName: String?
    var authorURL: String?
    var licenseName: String?
    var licenseURL: String?
    var sourceProvider: String?
}

struct DetectionTimeOfDayContext: Decodable, Equatable, Sendable {
    var timeOfDay: String
}

struct DetectionWeatherContext: Decodable, Equatable, Sendable {
    var daily: DailyWeatherContext?
    var hourly: HourlyWeatherContext?
    var timeOfDay: String?

    private enum CodingKeys: String, CodingKey {
        case daily
        case hourly
        case timeOfDay = "time_of_day"
    }
}

struct DailyWeatherContext: Decodable, Equatable, Sendable {
    var date: String?
    var sunrise: String?
    var sunset: String?
    var country: String?
    var cityName: String?

    private enum CodingKeys: String, CodingKey {
        case date
        case sunrise
        case sunset
        case country
        case cityName = "city_name"
    }
}

struct HourlyWeatherContext: Decodable, Equatable, Sendable {
    var time: String?
    var temperature: Double?
    var feelsLike: Double?
    var pressure: Int?
    var humidity: Int?
    var visibility: Int?
    var windSpeed: Double?
    var windDeg: Int?
    var windGust: Double?
    var clouds: Int?
    var weatherMain: String?
    var weatherDescription: String?
    var weatherIcon: String?

    private enum CodingKeys: String, CodingKey {
        case time
        case temperature
        case feelsLike = "feels_like"
        case pressure
        case humidity
        case visibility
        case windSpeed = "wind_speed"
        case windDeg = "wind_deg"
        case windGust = "wind_gust"
        case clouds
        case weatherMain = "weather_main"
        case weatherDescription = "weather_desc"
        case weatherIcon = "weather_icon"
    }
}

struct SpectrogramStatusEnvelope: Decodable, Equatable, Sendable {
    var data: SpectrogramStatusData
    var error: String
    var message: String
}

struct SpectrogramStatusData: Decodable, Equatable, Sendable {
    var status: Status
    var queuePosition: Int?
    var message: String?
    var path: String?

    enum Status: String, Decodable, Sendable {
        case notStarted = "not_started"
        case queued
        case generating
        case generated
        case failed
        case exists
    }
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
