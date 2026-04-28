import Foundation

struct AppConfiguration: Sendable {
    var stationURLOverride: URL?
    var localNetworkTestProfile: StationProfile?
    var debugDetectionID: Int?
    var debugSpeciesName: String?
    var debugShowsStationManagement: Bool
    var debugShowsSettings: Bool
    var debugShowsChangelog: Bool
    var debugShowsDeleteStationConfirmation: Bool

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppConfiguration {
        AppConfiguration(
            stationURLOverride: stationURLOverride(arguments: arguments, environment: environment),
            localNetworkTestProfile: localNetworkTestProfile(arguments: arguments, environment: environment),
            debugDetectionID: debugDetectionID(arguments: arguments, environment: environment),
            debugSpeciesName: debugSpeciesName(arguments: arguments, environment: environment),
            debugShowsStationManagement: debugShowsStationManagement(arguments: arguments, environment: environment),
            debugShowsSettings: debugShowsSettings(arguments: arguments, environment: environment),
            debugShowsChangelog: debugShowsChangelog(arguments: arguments, environment: environment),
            debugShowsDeleteStationConfirmation: debugShowsDeleteStationConfirmation(arguments: arguments, environment: environment)
        )
    }

    static let preview = AppConfiguration(
        stationURLOverride: nil,
        localNetworkTestProfile: StationProfile(name: "Local BirdNET-Go", baseURL: URL(string: "http://localhost:8080")!),
        debugDetectionID: nil,
        debugSpeciesName: nil,
        debugShowsStationManagement: false,
        debugShowsSettings: false,
        debugShowsChangelog: false,
        debugShowsDeleteStationConfirmation: false
    )

    private static func stationURLOverride(arguments: [String], environment: [String: String]) -> URL? {
        if let argumentValue = value(after: "-stationURL", in: arguments) ?? value(after: "-debugStationURL", in: arguments),
           let url = normalizedURL(from: argumentValue) {
            return url
        }

        if let environmentValue = environment["BIRDNET_GO_STATION_URL"], let url = normalizedURL(from: environmentValue) {
            return url
        }

        return nil
    }

    private static func localNetworkTestProfile(arguments: [String], environment: [String: String]) -> StationProfile? {
        let enabled = arguments.contains("-useLocalStationProfile") || isEnabled(environment["BIRDNET_GO_USE_LOCAL_STATION_PROFILE"])
        guard enabled else {
            return nil
        }

        let urlText = value(after: "-localStationURL", in: arguments) ?? environment["BIRDNET_GO_LOCAL_STATION_URL"] ?? "http://localhost:8080"
        guard let url = normalizedURL(from: urlText) else {
            return nil
        }

        return StationProfile(name: "Local BirdNET-Go", baseURL: url)
    }

    private static func debugDetectionID(arguments: [String], environment: [String: String]) -> Int? {
        let value = value(after: "-debugDetectionID", in: arguments) ?? environment["BIRDNET_GO_DEBUG_DETECTION_ID"]
        guard let value else {
            return nil
        }

        return Int(value)
    }

    private static func debugSpeciesName(arguments: [String], environment: [String: String]) -> String? {
        (value(after: "-debugSpeciesName", in: arguments) ?? environment["BIRDNET_GO_DEBUG_SPECIES_NAME"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyString
    }

    private static func debugShowsStationManagement(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains("-debugShowStationManagement") || isEnabled(environment["BIRDNET_GO_DEBUG_SHOW_STATION_MANAGEMENT"])
    }

    private static func debugShowsSettings(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains("-debugShowSettings") || isEnabled(environment["BIRDNET_GO_DEBUG_SHOW_SETTINGS"])
    }

    private static func debugShowsChangelog(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains("-debugShowChangelog") || isEnabled(environment["BIRDNET_GO_DEBUG_SHOW_CHANGELOG"])
    }

    private static func debugShowsDeleteStationConfirmation(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains("-debugShowDeleteStationConfirmation") || isEnabled(environment["BIRDNET_GO_DEBUG_SHOW_DELETE_STATION_CONFIRMATION"])
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }

    private static func isEnabled(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        switch value.lowercased() {
        case "1", "true", "yes", "enabled":
            return true
        default:
            return false
        }
    }

    private static func normalizedURL(from text: String) -> URL? {
        try? StationURLValidator.normalizedURL(from: text)
    }
}

private extension String {
    var nonEmptyString: String? {
        isEmpty ? nil : self
    }
}
