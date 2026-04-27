import Foundation

struct URLSessionBirdNETGoAPIClient: BirdNETGoAPIClient {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func ping(station: StationProfile) async throws -> StationConnectionStatus {
        let request = URLRequest(url: station.baseURL.appending(path: "api/v2/ping"))
        let response = try await urlSession.data(for: request).1

        guard let httpResponse = response as? HTTPURLResponse else {
            return .unknown
        }

        return (200..<300).contains(httpResponse.statusCode) ? .reachable : .unreachable
    }
}
