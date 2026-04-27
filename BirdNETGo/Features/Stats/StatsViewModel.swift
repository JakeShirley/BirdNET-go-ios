import Foundation
import SwiftUI

@MainActor
final class StatsViewModel: ObservableObject {
    @Published private(set) var stationProfile: StationProfile?
    @Published private(set) var dailySummary: [DailySpeciesSummary] = []
    @Published private(set) var recentDetections: [BirdDetection] = []
    @Published private(set) var selectedDate = Calendar.current.startOfDay(for: Date())
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusKind: StatusKind = .neutral
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false

    private let summaryLimit = 40
    private let recentLimit = 20
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    var hasStation: Bool {
        stationProfile != nil
    }

    var selectedDateTitle: String {
        Self.dateTitleFormatter.string(from: selectedDate)
    }

    var selectedDateValue: String {
        Self.apiDateFormatter.string(from: selectedDate)
    }

    var hourlyTotals: [Int] {
        dailySummary.reduce(into: Array(repeating: 0, count: 24)) { totals, summary in
            for (hour, count) in summary.normalizedHourlyCounts.enumerated() {
                totals[hour] += count
            }
        }
    }

    var totalDetections: Int {
        dailySummary.reduce(0) { $0 + $1.count }
    }

    var speciesCount: Int {
        dailySummary.count
    }

    var maxHourlySpeciesCount: Int {
        dailySummary
            .flatMap(\.normalizedHourlyCounts)
            .max() ?? 0
    }

    var currentlyHearing: [BirdDetection] {
        Array(recentDetections.prefix(3))
    }

    func load(environment: AppEnvironment) async {
        guard !didLoad else {
            return
        }

        didLoad = true
        await refresh(environment: environment)
    }

    func refresh(environment: AppEnvironment) async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let profile = try await loadStationProfile(environment: environment) else {
                stationProfile = nil
                dailySummary = []
                recentDetections = []
                statusMessage = nil
                return
            }

            stationProfile = profile

            var analyticsSummary: [DailySpeciesSummary] = []
            var recent: [BirdDetection] = []
            var analyticsError: Error?
            var recentError: Error?

            do {
                analyticsSummary = try await environment.apiClient.dailySpeciesSummary(station: profile, date: selectedDateValue, limit: summaryLimit)
            } catch {
                analyticsError = error
            }

            do {
                recent = try await environment.apiClient.recentDetections(station: profile, limit: recentLimit)
            } catch {
                recentError = error
            }

            if analyticsSummary.isEmpty, !recent.isEmpty {
                analyticsSummary = makeDailySummary(from: recent, date: selectedDate)
            }

            guard !analyticsSummary.isEmpty || !recent.isEmpty else {
                if let error = analyticsError ?? recentError {
                    await loadCachedDashboardAfterError(error, for: profile, environment: environment)
                } else {
                    dailySummary = []
                    recentDetections = []
                    setMessage("No activity for this day.", kind: .neutral)
                }
                return
            }

            dailySummary = analyticsSummary
            recentDetections = recent

            if analyticsError != nil, !analyticsSummary.isEmpty {
                setMessage("Showing activity from recent detections.", kind: .warning)
            } else if let recentError, recent.isEmpty {
                setMessage("Daily activity loaded, but live hearing status is unavailable: \(recentError.userFacingMessage)", kind: .warning)
            } else {
                statusMessage = analyticsSummary.isEmpty ? "No activity for this day." : nil
                statusKind = .neutral
            }

            try await cache(DailySpeciesDashboard(date: selectedDateValue, summaries: analyticsSummary, recentDetections: recent), for: profile, environment: environment)
        } catch {
            if let profile = stationProfile {
                await loadCachedDashboardAfterError(error, for: profile, environment: environment)
            } else {
                dailySummary = []
                recentDetections = []
                setMessage(error.userFacingMessage, kind: .error)
            }
        }
    }

    func moveDate(by days: Int, environment: AppEnvironment) async {
        guard let date = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else {
            return
        }

        selectedDate = Calendar.current.startOfDay(for: date)
        await refresh(environment: environment)
    }

    private func loadStationProfile(environment: AppEnvironment) async throws -> StationProfile? {
        if let overrideURL = environment.configuration.stationURLOverride {
            return StationProfile.manual(baseURL: overrideURL)
        }

        return try await environment.stationProfileStore.loadActiveProfile() ?? environment.configuration.localNetworkTestProfile
    }

    private func makeDailySummary(from detections: [BirdDetection], date: Date) -> [DailySpeciesSummary] {
        var summaries: [String: DailySummaryAccumulator] = [:]
        let calendar = Calendar.current

        for detection in detections {
            guard let detectionDate = detection.dashboardDate else {
                continue
            }

            guard calendar.isDate(detectionDate, inSameDayAs: date) else {
                continue
            }

            let key = (detection.speciesCode ?? detection.scientificName).lowercased()
            var accumulator = summaries[key] ?? DailySummaryAccumulator(
                scientificName: detection.scientificName,
                commonName: detection.commonName,
                speciesCode: detection.speciesCode
            )

            let hour = calendar.component(.hour, from: detectionDate)
            if accumulator.hourlyCounts.indices.contains(hour) {
                accumulator.hourlyCounts[hour] += 1
            }

            accumulator.count += 1
            accumulator.highConfidence = accumulator.highConfidence || detection.confidence >= 0.7
            accumulator.latestDate = max(accumulator.latestDate ?? detectionDate, detectionDate)
            accumulator.firstDate = min(accumulator.firstDate ?? detectionDate, detectionDate)
            accumulator.thumbnailURL = accumulator.thumbnailURL ?? nil
            summaries[key] = accumulator
        }

        return summaries.values
            .map { $0.summary }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }

                return (lhs.latestHeard ?? "") > (rhs.latestHeard ?? "")
            }
    }

    private func cache(_ dashboard: DailySpeciesDashboard, for profile: StationProfile, environment: AppEnvironment) async throws {
        let data = try encoder.encode(dashboard)
        try await environment.localCacheStore.saveData(data, for: cacheKey(for: profile))
    }

    private func loadCachedDashboardAfterError(_ error: Error, for profile: StationProfile, environment: AppEnvironment) async {
        do {
            if let data = try await environment.localCacheStore.loadData(for: cacheKey(for: profile)) {
                let dashboard = try decoder.decode(DailySpeciesDashboard.self, from: data)
                dailySummary = dashboard.summaries
                recentDetections = dashboard.recentDetections
                setMessage("Showing cached dashboard.", kind: .warning)
            } else {
                dailySummary = []
                recentDetections = []
                setMessage(error.userFacingMessage, kind: .error)
            }
        } catch {
            dailySummary = []
            recentDetections = []
            setMessage(error.userFacingMessage, kind: .error)
        }
    }

    private func cacheKey(for profile: StationProfile) -> LocalCacheKey {
        LocalCacheKey(namespace: "stats", identifier: "daily-dashboard-\(profile.baseURL.absoluteString)-\(selectedDateValue)")
    }

    private func setMessage(_ message: String, kind: StatusKind) {
        statusMessage = message
        statusKind = kind
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

extension StatsViewModel {
    enum StatusKind {
        case neutral
        case warning
        case error

        var systemImage: String {
            switch self {
            case .neutral:
                return "info.circle"
            case .warning:
                return "exclamationmark.triangle"
            case .error:
                return "xmark.octagon"
            }
        }
    }
}

private struct DailySummaryAccumulator {
    var scientificName: String
    var commonName: String
    var speciesCode: String?
    var count = 0
    var hourlyCounts = Array(repeating: 0, count: 24)
    var highConfidence = false
    var firstDate: Date?
    var latestDate: Date?
    var thumbnailURL: URL?

    var summary: DailySpeciesSummary {
        DailySpeciesSummary(
            scientificName: scientificName,
            commonName: commonName,
            speciesCode: speciesCode,
            count: count,
            hourlyCounts: hourlyCounts,
            highConfidence: highConfidence,
            firstHeard: firstDate.map(Self.timeFormatter.string(from:)),
            latestHeard: latestDate.map(Self.timeFormatter.string(from:)),
            thumbnailURL: thumbnailURL
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}

private extension BirdDetection {
    var dashboardDate: Date? {
        if let timestamp, let date = ISO8601DateFormatter().date(from: timestamp) {
            return date
        }

        let combined = "\(date)T\(time)"
        return Self.fallbackDateFormatter.date(from: combined)
    }

    private static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}