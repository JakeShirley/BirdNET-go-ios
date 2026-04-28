import Foundation
import SwiftUI

@MainActor
final class SpeciesViewModel: ObservableObject {
    @Published private(set) var stationProfile: StationProfile?
    @Published private(set) var species: [SpeciesListEntry] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusKind: StatusKind = .neutral
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false
    @Published var sortMode: SortMode = .mostSeen {
        didSet {
            guard oldValue != sortMode else { return }
            species = Self.sorted(species, by: sortMode)
        }
    }

    private let recentDetectionsLimit = 100
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    var hasStation: Bool {
        stationProfile != nil
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
                species = []
                statusMessage = nil
                return
            }

            stationProfile = profile

            // Primary source: full historical species summary.
            var summaries: [SpeciesSummary] = []
            var summaryError: Error?
            do {
                summaries = try await environment.apiClient.speciesSummary(station: profile)
            } catch {
                if Self.isCancellation(error) { return }
                summaryError = error
            }

            // Optional enrichment: station catalog (rarity / thumbnails) and very-recent detections
            // (so newly-heard species appear immediately even if the analytics roll-up lags).
            var catalog: [StationSpecies] = []
            var recent: [BirdDetection] = []

            do {
                catalog = try await environment.apiClient.species(station: profile)
            } catch {
                if Self.isCancellation(error) { return }
                // Catalog is optional; ignore.
            }

            do {
                recent = try await environment.apiClient.recentDetections(station: profile, limit: recentDetectionsLimit)
            } catch {
                if Self.isCancellation(error) { return }
                // Recent detections are optional; ignore.
            }

            guard !summaries.isEmpty || !catalog.isEmpty || !recent.isEmpty else {
                if let error = summaryError {
                    await loadCachedSpeciesAfterError(error, for: profile, environment: environment)
                } else {
                    species = []
                    statusMessage = String(localized: "No detected species.")
                    statusKind = .neutral
                }
                return
            }

            species = makeEntries(summaries: summaries, catalog: catalog, recent: recent)

            if let summaryError, summaries.isEmpty {
                setMessage(String(localized: "Showing partial species list without overall stats: \(summaryError.userFacingMessage)"), kind: .warning)
            } else {
                statusMessage = species.isEmpty ? String(localized: "No detected species.") : nil
                statusKind = .neutral
            }

            await cacheIgnoringErrors(SpeciesSnapshot(summaries: summaries, catalog: catalog, recent: recent), for: profile, environment: environment)
        } catch {
            if Self.isCancellation(error) { return }
            if let profile = stationProfile {
                await loadCachedSpeciesAfterError(error, for: profile, environment: environment)
            } else {
                species = []
                setMessage(error.userFacingMessage, kind: .error)
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private func loadStationProfile(environment: AppEnvironment) async throws -> StationProfile? {
        if let overrideURL = environment.configuration.stationURLOverride {
            return StationProfile.manual(baseURL: overrideURL)
        }

        return try await environment.stationProfileStore.loadActiveProfile() ?? environment.configuration.localNetworkTestProfile
    }

    private func cache(_ snapshot: SpeciesSnapshot, for profile: StationProfile, environment: AppEnvironment) async throws {
        let data = try encoder.encode(snapshot)
        try await environment.localCacheStore.saveData(data, for: cacheKey(for: profile))
    }

    private func cacheIgnoringErrors(_ snapshot: SpeciesSnapshot, for profile: StationProfile, environment: AppEnvironment) async {
        do {
            try await cache(snapshot, for: profile, environment: environment)
        } catch {
            // Caching failures should not surface to the user or trigger the cached-fallback path.
        }
    }

    private func loadCachedSpeciesAfterError(_ error: Error, for profile: StationProfile, environment: AppEnvironment) async {
        do {
            if let data = try await environment.localCacheStore.loadData(for: cacheKey(for: profile)) {
                let snapshot = try decoder.decode(SpeciesSnapshot.self, from: data)
                species = makeEntries(summaries: snapshot.summaries, catalog: snapshot.catalog, recent: snapshot.recent)
                setMessage(String(localized: "Showing cached species."), kind: .warning)
            } else {
                species = []
                setMessage(error.userFacingMessage, kind: .error)
            }
        } catch {
            species = []
            setMessage(error.userFacingMessage, kind: .error)
        }
    }

    private func cacheKey(for profile: StationProfile) -> LocalCacheKey {
        LocalCacheKey(namespace: "species", identifier: "detected-\(profile.baseURL.absoluteString)")
    }

    private func makeEntries(summaries: [SpeciesSummary], catalog: [StationSpecies], recent: [BirdDetection]) -> [SpeciesListEntry] {
        // Build catalog lookup keyed on summaryKey for enrichment.
        var catalogByKey: [String: StationSpecies] = [:]
        for entry in catalog {
            catalogByKey[summaryKey(scientificName: entry.scientificName, commonName: entry.commonName, speciesCode: entry.speciesCode)] = entry
        }

        // Build per-species rollup from recent detections so we can include species that
        // the analytics endpoint hasn't aggregated yet (and refine top confidence / latest time).
        let recentRollups = detectionRollups(from: recent)

        var entriesByKey: [String: SpeciesListEntry] = [:]

        // Primary pass: every species from the analytics summary.
        for summary in summaries {
            let key = summaryKey(scientificName: summary.scientificName, commonName: summary.commonName, speciesCode: summary.speciesCode)
            let catalogEntry = catalogByKey[key]
            let recentRollup = recentRollups[key]

            let species = StationSpecies(
                commonName: summary.commonName,
                scientificName: summary.scientificName,
                speciesCode: summary.speciesCode ?? catalogEntry?.speciesCode,
                rarity: catalogEntry?.rarity,
                detectionCount: summary.count,
                latestDetectionTimestamp: summary.lastHeard,
                // Note: BirdNET-Go's summary endpoint returns thumbnail_url as a relative
                // path (often the SVG placeholder), which AsyncImage cannot resolve or
                // decode. Prefer the catalog's absolute thumbnail and otherwise let the
                // row fall back to apiClient.speciesImageURL(...).
                thumbnailURL: catalogEntry?.thumbnailURL
            )

            let stats = SpeciesStats(
                count: summary.count,
                firstHeardDate: parseTimestamp(summary.firstHeard),
                latestDetectionDate: latestDate(summary.lastHeard, recentRollup?.latestDetectionDate),
                topConfidence: maxConfidence(summary.maxConfidence, recentRollup?.topConfidence),
                avgConfidence: summary.avgConfidence
            )

            entriesByKey[key] = SpeciesListEntry(species: species, stats: stats)
        }

        // Enrichment pass: catalog entries the summary didn't include (e.g. configured but never detected).
        for (key, catalogEntry) in catalogByKey where entriesByKey[key] == nil {
            let recentRollup = recentRollups[key]
            let count = catalogEntry.detectionCount ?? recentRollup?.count ?? 0
            let stats = SpeciesStats(
                count: count,
                firstHeardDate: nil,
                latestDetectionDate: parseTimestamp(catalogEntry.latestDetectionTimestamp) ?? recentRollup?.latestDetectionDate,
                topConfidence: recentRollup?.topConfidence,
                avgConfidence: nil
            )
            entriesByKey[key] = SpeciesListEntry(species: catalogEntry, stats: stats)
        }

        // Defensive pass: species seen in recent detections that nothing else knew about.
        for (key, rollup) in recentRollups where entriesByKey[key] == nil {
            entriesByKey[key] = SpeciesListEntry(
                species: StationSpecies(
                    commonName: rollup.commonName,
                    scientificName: rollup.scientificName,
                    speciesCode: rollup.speciesCode
                ),
                stats: SpeciesStats(
                    count: rollup.count,
                    firstHeardDate: nil,
                    latestDetectionDate: rollup.latestDetectionDate,
                    topConfidence: rollup.topConfidence,
                    avgConfidence: nil
                )
            )
        }

        return Self.sorted(Array(entriesByKey.values), by: sortMode)
    }

    /// Bayesian smoothing constant ("phantom detections") used by the reliability sort.
    /// Higher values penalize species with few detections more aggressively.
    private static let reliabilityPriorWeight: Double = 20

    /// Default fallback prior used when no species in the current set has an avg confidence.
    /// Roughly the BirdNET-Go default minimum acceptable confidence.
    private static let reliabilityFallbackPrior: Double = 0.75

    static func sorted(_ entries: [SpeciesListEntry], by sortMode: SortMode) -> [SpeciesListEntry] {
        switch sortMode {
        case .reliability:
            let confidences = entries.compactMap { $0.stats.avgConfidence }
            let prior: Double
            if confidences.isEmpty {
                prior = reliabilityFallbackPrior
            } else {
                prior = confidences.reduce(0, +) / Double(confidences.count)
            }

            // Cache scores so the comparator stays O(1) and we don't recompute the
            // smoothed average for every pairwise comparison.
            let scored: [(entry: SpeciesListEntry, score: Double?)] = entries.map { entry in
                let score = bayesianReliabilityScore(for: entry, prior: prior)
                return (entry, score)
            }

            return scored.sorted { lhs, rhs in
                switch (lhs.score, rhs.score) {
                case let (l?, r?) where l != r:
                    return l > r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    break
                }
                return SortMode.tiebreaker(lhs.entry, rhs.entry)
            }.map(\.entry)
        case .mostSeen, .leastSeen, .mostRecent:
            return entries.sorted(by: sortMode.areInIncreasingOrder)
        }
    }

    static func bayesianReliabilityScore(for entry: SpeciesListEntry, prior: Double) -> Double? {
        guard let avg = entry.stats.avgConfidence else {
            return nil
        }
        let count = Double(entry.stats.count)
        let c = reliabilityPriorWeight
        return (count * avg + c * prior) / (count + c)
    }

    private func detectionRollups(from detections: [BirdDetection]) -> [String: DetectionRollup] {
        var rollups: [String: DetectionRollup] = [:]

        for detection in detections {
            let key = summaryKey(scientificName: detection.scientificName, commonName: detection.commonName, speciesCode: detection.speciesCode)
            var rollup = rollups[key] ?? DetectionRollup(
                commonName: detection.commonName,
                scientificName: detection.scientificName,
                speciesCode: detection.speciesCode
            )

            rollup.count += 1
            rollup.topConfidence = max(rollup.topConfidence ?? detection.confidence, detection.confidence)
            if let timestampDate = detection.timestampDate, rollup.latestDetectionDate == nil || timestampDate > rollup.latestDetectionDate! {
                rollup.latestDetectionDate = timestampDate
            }

            rollups[key] = rollup
        }

        return rollups
    }

    private func summaryKey(scientificName: String, commonName: String, speciesCode: String?) -> String {
        (scientificName.nonEmptyString ?? speciesCode?.nonEmptyString ?? commonName)
            .lowercased()
    }

    private func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }

        // BirdNET-Go's species summary endpoint formats timestamps as "yyyy-MM-dd HH:mm:ss"
        // (Go's time.DateTime). Catalog/detection timestamps tend to be ISO 8601.
        if let date = Self.iso8601WithFractional.date(from: raw) ?? Self.iso8601.date(from: raw) {
            return date
        }

        return Self.dateTimeFormatter.date(from: raw)
    }

    private func latestDate(_ raw: String?, _ other: Date?) -> Date? {
        let parsed = parseTimestamp(raw)
        switch (parsed, other) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func maxConfidence(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (a?, b?):
            return Swift.max(a, b)
        case let (a?, nil):
            return a
        case let (nil, b?):
            return b
        default:
            return nil
        }
    }

    private func setMessage(_ message: String, kind: StatusKind) {
        statusMessage = message
        statusKind = kind
    }

    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

struct SpeciesListEntry: Equatable, Identifiable, Sendable {
    var species: StationSpecies
    var stats: SpeciesStats

    var id: String { species.id }

    var displayCount: Int {
        stats.count
    }

    var countLabel: String? {
        guard displayCount > 0 else {
            return nil
        }

        return displayCount == 1 ? String(localized: "1 detection") : String(localized: "\(displayCount) detections")
    }

    var latestDetectionDate: Date? {
        stats.latestDetectionDate
    }

    var latestDetectionLabel: String? {
        guard let latestDetectionDate else {
            return nil
        }

        return Self.relativeFormatter.localizedString(for: latestDetectionDate, relativeTo: Date())
    }

    var averageConfidenceLabel: String? {
        guard let avgConfidence = stats.avgConfidence else {
            return nil
        }

        return "\(Int((avgConfidence * 100).rounded()))%"
    }

    var topConfidenceLabel: String? {
        guard let topConfidence = stats.topConfidence else {
            return nil
        }

        return "\(Int((topConfidence * 100).rounded()))%"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

struct SpeciesStats: Equatable, Sendable {
    var count: Int
    var firstHeardDate: Date?
    var latestDetectionDate: Date?
    var topConfidence: Double?
    var avgConfidence: Double?
}

private struct DetectionRollup {
    var commonName: String
    var scientificName: String
    var speciesCode: String?
    var count = 0
    var latestDetectionDate: Date?
    var topConfidence: Double?
}

private struct SpeciesSnapshot: Codable {
    var summaries: [SpeciesSummary]
    var catalog: [StationSpecies]
    var recent: [BirdDetection]
}

extension SpeciesViewModel {
    enum SortMode: String, CaseIterable, Identifiable, Sendable {
        case mostSeen
        case leastSeen
        case mostRecent
        case reliability

        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .reliability: return "Reliability"
            case .mostSeen: return "Most Seen"
            case .leastSeen: return "Least Seen"
            case .mostRecent: return "Most Recent"
            }
        }

        var systemImage: String {
            switch self {
            case .reliability: return "checkmark.seal"
            case .mostSeen: return "arrow.down.circle"
            case .leastSeen: return "arrow.up.circle"
            case .mostRecent: return "clock"
            }
        }

        func areInIncreasingOrder(_ lhs: SpeciesListEntry, _ rhs: SpeciesListEntry) -> Bool {
            switch self {
            case .reliability:
                // Reliability sort is handled by SpeciesViewModel.sorted(_:by:) which
                // needs the global prior; this comparator is only a defensive fallback.
                if lhs.displayCount != rhs.displayCount {
                    return lhs.displayCount > rhs.displayCount
                }
            case .mostSeen:
                if lhs.displayCount != rhs.displayCount {
                    return lhs.displayCount > rhs.displayCount
                }
            case .leastSeen:
                if lhs.displayCount != rhs.displayCount {
                    return lhs.displayCount < rhs.displayCount
                }
            case .mostRecent:
                switch (lhs.latestDetectionDate, rhs.latestDetectionDate) {
                case let (l?, r?) where l != r:
                    return l > r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    break
                }
            }

            return Self.tiebreaker(lhs, rhs)
        }

        static func tiebreaker(_ lhs: SpeciesListEntry, _ rhs: SpeciesListEntry) -> Bool {
            if let lhsDate = lhs.latestDetectionDate, let rhsDate = rhs.latestDetectionDate, lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.species.commonName.localizedCaseInsensitiveCompare(rhs.species.commonName) == .orderedAscending
        }
    }

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

private extension BirdDetection {
    var timestampDate: Date? {
        guard let timestamp else {
            return nil
        }

        return ISO8601DateFormatter().date(from: timestamp)
    }
}

private extension Optional where Wrapped == String {
    var nonEmptyString: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}

private extension String {
    var nonEmptyString: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
