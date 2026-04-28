import AVFoundation
import SwiftUI

struct SpectrogramView: View {
    var station: StationProfile?
    var detectionID: Int
    var audioURL: URL?
    var title: String
    var autoFetchSpectrograms: Bool
    var apiClient: any BirdNETGoAPIClient

    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var playbackProgress = 0.0
    @State private var playbackDuration = 0.0
    @State private var isPlaying = false
    @State private var playbackMessage = "Ready to play"
    @State private var imageURL: URL?
    @State private var message = "Checking spectrogram"
    @State private var isLoading = false
    @State private var generationStatus: SpectrogramStatusData.Status?

    private let size = "lg"
    private let raw = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView("Loading spectrogram")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    case .success(let image):
                        spectrogramImage(image)
                    case .failure:
                        spectrogramStatusLabel("Spectrogram image is unavailable.", systemImage: "waveform.path.ecg")
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
            } else if isLoading {
                ProgressView(message)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                spectrogramStatusLabel(message, systemImage: "waveform.path.ecg")
            }

            if let generationStatus, imageURL == nil {
                Label(generationStatusLabel(for: generationStatus), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if canRequestGeneration {
                Button {
                    Task {
                        await generateSpectrogram()
                    }
                } label: {
                    Label("Generate", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }

            playbackControls
        }
        .onAppear(perform: preparePlayer)
        .onChange(of: audioURL) { _, _ in
            preparePlayer()
        }
        .onDisappear(perform: stopPlayer)
        .task(id: loadTaskID) {
            await loadSpectrogram()
        }
    }

    private var loadTaskID: String {
        "\(station?.id.uuidString ?? "no-station")-\(detectionID)-\(autoFetchSpectrograms)"
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .disabled(audioURL == nil)
            .accessibilityLabel(isPlaying ? "Pause audio clip" : "Play audio clip")

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(playbackMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(playbackTimeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var canRequestGeneration: Bool {
        guard station != nil, imageURL == nil, !isLoading else {
            return false
        }

        return generationStatus == .notStarted || generationStatus == .failed
    }

    private var playbackTimeLabel: String {
        guard playbackDuration.isFinite, playbackDuration > 0 else {
            return "0:00"
        }

        return "\(timeLabel(for: playbackProgress * playbackDuration)) / \(timeLabel(for: playbackDuration))"
    }

    private func spectrogramImage(_ image: Image) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 5)
                    .offset(x: playheadOffset(in: proxy.size.width))

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .offset(x: playheadOffset(in: proxy.size.width) + 1.5)

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: max(0, proxy.size.width * playbackProgress))
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .clipShape(DS.Shape.card)
        .accessibilityLabel("Detection spectrogram with playback position")
    }

    private func playheadOffset(in width: Double) -> Double {
        max(0, min(width - 5, width * playbackProgress))
    }

    private func spectrogramStatusLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private func preparePlayer() {
        stopPlayer()
        playbackProgress = 0
        playbackDuration = 0

        guard let audioURL else {
            playbackMessage = "No audio clip URL available."
            return
        }

        let player = AVPlayer(url: audioURL)
        self.player = player
        playbackMessage = "Ready to play"
        addPeriodicTimeObserver(to: player)
    }

    private func stopPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }

        timeObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
    }

    private func togglePlayback() {
        guard let player else {
            return
        }

        if isPlaying {
            player.pause()
            playbackMessage = "Paused"
        } else {
            player.play()
            playbackMessage = "Playing"
        }

        isPlaying.toggle()
    }

    private func addPeriodicTimeObserver(to player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { time in
            updatePlaybackProgress(currentTime: time)
        }
    }

    private func updatePlaybackProgress(currentTime: CMTime) {
        guard let player else {
            playbackProgress = 0
            playbackDuration = 0
            return
        }

        let duration = player.currentItem?.duration.seconds ?? 0
        guard duration.isFinite, duration > 0 else {
            playbackProgress = 0
            playbackDuration = 0
            return
        }

        let current = max(0, currentTime.seconds)
        playbackDuration = duration
        playbackProgress = min(1, current / duration)

        if playbackProgress >= 0.999, isPlaying {
            player.seek(to: .zero)
            player.pause()
            playbackProgress = 0
            isPlaying = false
            playbackMessage = "Ready to replay"
        }
    }

    private func timeLabel(for seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func loadSpectrogram() async {
        guard let station else {
            message = "Connect a station to load the spectrogram."
            imageURL = nil
            return
        }

        imageURL = nil
        generationStatus = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let statusEnvelope = try await apiClient.spectrogramStatus(station: station, detectionID: detectionID, size: size, raw: raw)
            generationStatus = statusEnvelope.data.status

            switch statusEnvelope.data.status {
            case .exists, .generated:
                imageURL = apiClient.spectrogramURL(station: station, detectionID: detectionID, size: size, raw: raw)
                message = statusEnvelope.data.message ?? "Spectrogram ready"
            case .notStarted, .failed:
                if autoFetchSpectrograms {
                    try await requestGenerationAndPoll(station: station)
                } else {
                    message = statusEnvelope.data.message ?? "Spectrogram has not been generated."
                }
            case .queued, .generating:
                try await pollUntilReady(station: station)
            }
        } catch {
            message = error.localizedDescription
            imageURL = nil
        }
    }

    private func generateSpectrogram() async {
        guard let station else {
            message = "Connect a station to load the spectrogram."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await requestGenerationAndPoll(station: station)
        } catch {
            message = error.localizedDescription
            imageURL = nil
        }
    }

    private func requestGenerationAndPoll(station: StationProfile) async throws {
        let appConfig = try await apiClient.fetchAppConfig(station: station)
        let envelope = try await apiClient.requestSpectrogramGeneration(station: station, detectionID: detectionID, size: size, raw: raw, csrfToken: appConfig.csrfToken)
        generationStatus = envelope.data.status
        message = envelope.data.message ?? "Generating spectrogram"

        if envelope.data.status == .exists || envelope.data.status == .generated {
            imageURL = apiClient.spectrogramURL(station: station, detectionID: detectionID, size: size, raw: raw)
            return
        }

        try await pollUntilReady(station: station)
    }

    private func pollUntilReady(station: StationProfile) async throws {
        for _ in 0..<12 {
            try await Task.sleep(for: .seconds(1))
            let envelope = try await apiClient.spectrogramStatus(station: station, detectionID: detectionID, size: size, raw: raw)
            generationStatus = envelope.data.status
            message = envelope.data.message ?? generationStatusLabel(for: envelope.data.status)

            switch envelope.data.status {
            case .exists, .generated:
                imageURL = apiClient.spectrogramURL(station: station, detectionID: detectionID, size: size, raw: raw)
                return
            case .failed:
                throw StationConnectionError.serverRejected(statusCode: 0, message: envelope.data.message ?? "Spectrogram generation failed.")
            case .notStarted, .queued, .generating:
                break
            }
        }

        throw StationConnectionError.serverRejected(statusCode: 0, message: "Spectrogram is still being generated.")
    }

    private func generationStatusLabel(for status: SpectrogramStatusData.Status) -> String {
        switch status {
        case .notStarted:
            return "Spectrogram not generated"
        case .queued:
            return "Spectrogram queued"
        case .generating:
            return "Spectrogram generating"
        case .generated, .exists:
            return "Spectrogram ready"
        case .failed:
            return "Spectrogram generation failed"
        }
    }
}
