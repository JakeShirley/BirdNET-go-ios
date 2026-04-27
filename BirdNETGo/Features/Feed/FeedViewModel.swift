import Combine
import Foundation
import SwiftUI

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var stationProfile: StationProfile?
    @Published private(set) var detections: [BirdDetection] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusKind: StatusKind = .neutral
    @Published private(set) var streamStatus: StreamStatus = .idle
    @Published private(set) var liveInsertedDetectionID: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false

    private let detectionLimit = 10
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    var hasStation: Bool {
        stationProfile != nil
    }

    var streamStatusMessage: String? {
        streamStatus.message
    }

    var streamStatusKind: StatusKind {
        streamStatus.statusKind
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
                streamStatus = .idle
                return
            }

            stationProfile = profile
            let recentDetections = try await environment.apiClient.recentDetections(station: profile, limit: detectionLimit)
            applyRecentDetections(recentDetections)
            statusMessage = recentDetections.isEmpty ? "No recent detections." : nil
            try await cache(recentDetections, for: profile, environment: environment)
        } catch {
            await loadCachedDetectionsAfterError(error, environment: environment)
        }
    }

    func runLiveStream(environment: AppEnvironment) async {
        var reconnectDelay: Duration = .seconds(1)

        while !Task.isCancelled {
            do {
                guard let profile = try await loadStationProfile(environment: environment) else {
                    streamStatus = .idle
                    return
                }

                stationProfile = profile
                streamStatus = .connecting

                for try await event in environment.apiClient.detectionEvents(station: profile) {
                    try Task.checkCancellation()
                    switch event {
                    case .connected:
                        reconnectDelay = .seconds(1)
                        streamStatus = .connected
                    case .detection(let detection):
                        reconnectDelay = .seconds(1)
                        streamStatus = .connected
                        insertLiveDetection(detection)
                        try await cache(detections, for: profile, environment: environment)
                    case .heartbeat:
                        streamStatus = .connected
                    case .pending:
                        break
                    }
                }

                throw URLError(.networkConnectionLost)
            } catch is CancellationError {
                streamStatus = .idle
                return
            } catch {
                streamStatus = .reconnecting
                do {
                    try await Task.sleep(for: reconnectDelay)
                } catch {
                    streamStatus = .idle
                    return
                }
                reconnectDelay = min(reconnectDelay * 2, .seconds(30))
            }
        }

        streamStatus = .idle
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
                applyRecentDetections(try decoder.decode([BirdDetection].self, from: data))
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

    private func applyRecentDetections(_ recentDetections: [BirdDetection]) {
        var seenIDs = Set<Int>()
        liveInsertedDetectionID = nil
        detections = recentDetections.filter { detection in
            seenIDs.insert(detection.id).inserted
        }.prefix(detectionLimit).map { $0 }
    }

    private func insertLiveDetection(_ detection: BirdDetection) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            detections.removeAll { $0.id == detection.id }
            detections.insert(detection, at: 0)

            if detections.count > detectionLimit {
                detections.removeLast(detections.count - detectionLimit)
            }

            liveInsertedDetectionID = detection.id
        }

        if statusMessage == "No recent detections." {
            statusMessage = nil
        }
    }

    private func setMessage(_ message: String, kind: StatusKind) {
        statusMessage = message
        statusKind = kind
    }
}

extension FeedViewModel {
    enum StreamStatus {
        case idle
        case connecting
        case connected
        case reconnecting

        var message: String? {
            switch self {
            case .idle:
                return nil
            case .connecting:
                return "Connecting live feed"
            case .connected:
                return "Live feed connected"
            case .reconnecting:
                return "Live feed reconnecting"
            }
        }

        var statusKind: StatusKind {
            switch self {
            case .idle, .connected:
                return .neutral
            case .connecting, .reconnecting:
                return .warning
            }
        }
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