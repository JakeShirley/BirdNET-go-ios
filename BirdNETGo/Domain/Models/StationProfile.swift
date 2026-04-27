import Foundation

struct StationProfile: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var baseURL: URL

    init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}

struct StationCredentials: Codable, Equatable, Sendable {
    var username: String?
    var password: String
}

extension StationProfile {
    static func manual(baseURL: URL) -> StationProfile {
        StationProfile(name: baseURL.host(percentEncoded: false) ?? baseURL.absoluteString, baseURL: baseURL)
    }
}
