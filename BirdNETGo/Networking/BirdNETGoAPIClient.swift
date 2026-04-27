import Foundation

protocol BirdNETGoAPIClient: Sendable {
    func ping(station: StationProfile) async throws -> StationConnectionStatus
}
