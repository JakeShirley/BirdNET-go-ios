import Combine
import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var stationProfile: StationProfile?
    @Published private(set) var detections: [BirdDetection] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusKind: StatusKind = .neutral
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false

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
                detections = []
                statusMessage = nil
                return
            }

            stationProfile = profile
            let recentDetections = try await environment.apiClient.recentDetections(station: profile, limit: 10)
            detections = recentDetections
            statusMessage = recentDetections.isEmpty ? "No recent detections." : nil
            try await cache(recentDetections, for: profile, environment: environment)
        } catch {
            await loadCachedDetectionsAfterError(error, environment: environment)
        }
    }

    private func loadStationProfile(environment: AppEnvironment) async throws -> StationProfile? {
        if let overrideURL = environment.configuration.stationURLOverride {
            return StationProfile.manual(baseURL: overrideURL)
        }

        return try await environment.stationProfileStore.loadActiveProfile() ?? environment.configuration.localNetworkTestProfile
    }

    private func cache(_ detections: [BirdDetection], for profile: StationProfile, environment: AppEnvironment) async throws {
        let data = try encoder.encode(detections)
        try await environment.localCacheStore.saveData(data, for: cacheKey(for: profile))
    }

    private func loadCachedDetectionsAfterError(_ error: Error, environment: AppEnvironment) async {
        guard let profile = stationProfile else {
            detections = []
            setMessage(error.localizedDescription, kind: .error)
            return
        }

        do {
            if let data = try await environment.localCacheStore.loadData(for: cacheKey(for: profile)) {
                detections = try decoder.decode([BirdDetection].self, from: data)
                setMessage("Showing cached detections.", kind: .warning)
            } else {
                detections = []
                setMessage(error.localizedDescription, kind: .error)
            }
        } catch {
            detections = []
            setMessage(error.localizedDescription, kind: .error)
        }
    }

    private func cacheKey(for profile: StationProfile) -> LocalCacheKey {
        LocalCacheKey(namespace: "detections", identifier: "recent-\(profile.baseURL.absoluteString)")
    }

    private func setMessage(_ message: String, kind: StatusKind) {
        statusMessage = message
        statusKind = kind
    }
}


extension FeedViewModel {
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