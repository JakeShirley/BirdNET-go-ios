import Foundation

struct BirdDetection: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var date: String
    var time: String
    var timestamp: String?
    var source: DetectionSourceInfo?
    var beginTime: String?
    var endTime: String?
    var speciesCode: String?
    var scientificName: String
    var commonName: String
    var confidence: Double
    var verified: String?
    var locked: Bool
    var isNewSpecies: Bool?
    var timeOfDay: String?

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }

    var timeLabel: String {
        if let timestamp, let date = Self.dateFormatter.date(from: timestamp) {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        }

        if !time.isEmpty {
            return time
        }

        return date.isEmpty ? "Unknown time" : date
    }

    var sourceLabel: String? {
        source?.displayName ?? source?.id
    }

    private static let dateFormatter = ISO8601DateFormatter()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}


struct DetectionSourceInfo: Codable, Equatable, Sendable {
    var id: String?
    var type: String?
    var displayName: String?

    init(id: String? = nil, type: String? = nil, displayName: String? = nil) {
        self.id = id
        self.type = type
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self.init(id: stringValue, displayName: stringValue)
            return
        }

        let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try keyedContainer.decodeIfPresent(String.self, forKey: .id),
            type: try keyedContainer.decodeIfPresent(String.self, forKey: .type),
            displayName: try keyedContainer.decodeIfPresent(String.self, forKey: .displayName)
        )
    }
}