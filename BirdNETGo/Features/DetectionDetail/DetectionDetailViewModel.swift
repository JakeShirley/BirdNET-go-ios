import AVFoundation
import Foundation

@MainActor
final class DetectionDetailViewModel: ObservableObject {
    @Published private(set) var detection: BirdDetection?
    @Published private(set) var stationProfile: StationProfile?
    @Published private(set) var audioURL: URL?
    @Published private(set) var autoFetchSpectrograms = AppPreferences.defaults.autoFetchSpectrograms
    @Published private(set) var speciesImageAttribution: SpeciesImageAttribution?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let detectionID: Int
    private let initialDetection: BirdDetection?

    init(detectionID: Int, initialDetection: BirdDetection? = nil) {
        self.detectionID = detectionID
        self.initialDetection = initialDetection
        self.detection = initialDetection
    }

    func load(environment: AppEnvironment) async {
        isLoading = true
        defer { isLoading = false }

        do {
            autoFetchSpectrograms = try await environment.preferenceStore.loadPreferences().autoFetchSpectrograms
        } catch {
            autoFetchSpectrograms = AppPreferences.defaults.autoFetchSpectrograms
        }

        do {
            guard let profile = try await loadStationProfile(environment: environment) else {
                stationProfile = nil
                audioURL = nil
                errorMessage = "Connect a BirdNET-Go station to load detection details."
                return
            }

            stationProfile = profile
            audioURL = environment.apiClient.audioClipURL(station: profile, detectionID: detectionID)
            let detection = try await environment.apiClient.detection(station: profile, id: detectionID)
            self.detection = detection
            speciesImageAttribution = await loadSpeciesImageAttribution(station: profile, detection: detection, environment: environment)
            errorMessage = nil
        } catch {
            if detection == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadStationProfile(environment: AppEnvironment) async throws -> StationProfile? {
        if let overrideURL = environment.configuration.stationURLOverride {
            return StationProfile.manual(baseURL: overrideURL)
        }

        return try await environment.stationProfileStore.loadActiveProfile() ?? environment.configuration.localNetworkTestProfile
    }

    private func loadSpeciesImageAttribution(station: StationProfile, detection: BirdDetection, environment: AppEnvironment) async -> SpeciesImageAttribution? {
        do {
            return try await environment.apiClient.speciesImageAttribution(station: station, scientificName: detection.scientificName)
        } catch {
            return nil
        }
    }
}
