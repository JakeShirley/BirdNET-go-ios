import Foundation

struct DailySpeciesSummary: Codable, Equatable, Identifiable, Sendable {
    var scientificName: String
    var commonName: String
    var speciesCode: String?
    var count: Int
    var hourlyCounts: [Int]
    var highConfidence: Bool
    var firstHeard: String?
    var latestHeard: String?
    var thumbnailURL: URL?
    var isNewSpecies: Bool?

    var id: String {
        (speciesCode ?? scientificName).lowercased()
    }

    var normalizedHourlyCounts: [Int] {
        Array((hourlyCounts + Array(repeating: 0, count: 24)).prefix(24))
    }

    init(
        scientificName: String,
        commonName: String,
        speciesCode: String? = nil,
        count: Int,
        hourlyCounts: [Int],
        highConfidence: Bool = false,
        firstHeard: String? = nil,
        latestHeard: String? = nil,
        thumbnailURL: URL? = nil,
        isNewSpecies: Bool? = nil
    ) {
        self.scientificName = scientificName
        self.commonName = commonName
        self.speciesCode = speciesCode
        self.count = count
        self.hourlyCounts = hourlyCounts
        self.highConfidence = highConfidence
        self.firstHeard = firstHeard
        self.latestHeard = latestHeard
        self.thumbnailURL = thumbnailURL
        self.isNewSpecies = isNewSpecies
    }

    private enum CodingKeys: String, CodingKey {
        case scientificName = "scientific_name"
        case commonName = "common_name"
        case speciesCode = "species_code"
        case count
        case hourlyCounts = "hourly_counts"
        case highConfidence = "high_confidence"
        case firstHeard = "first_heard"
        case latestHeard = "latest_heard"
        case thumbnailURL = "thumbnail_url"
        case isNewSpecies = "is_new_species"
    }
}

struct DailySpeciesDashboard: Codable, Equatable, Sendable {
    var date: String
    var summaries: [DailySpeciesSummary]
    var recentDetections: [BirdDetection]
}