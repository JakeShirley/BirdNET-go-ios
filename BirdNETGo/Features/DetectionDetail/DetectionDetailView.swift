import SwiftUI

struct DetectionDetailView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel: DetectionDetailViewModel

    init(detectionID: Int, initialDetection: BirdDetection? = nil) {
        _viewModel = StateObject(wrappedValue: DetectionDetailViewModel(detectionID: detectionID, initialDetection: initialDetection))
    }

    var body: some View {
        List {
            if viewModel.isLoading, viewModel.detection == nil {
                ProgressView("Loading detection")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .listRowBackground(Color.clear)
            } else if let detection = viewModel.detection {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if let station = viewModel.stationProfile {
                            SpeciesImageView(
                                imageURL: appEnvironment.apiClient.speciesImageURL(station: station, scientificName: detection.scientificName),
                                commonName: detection.commonName,
                                attribution: viewModel.speciesImageAttribution
                            )
                        }

                        Text(detection.commonName)
                            .font(.title2.weight(.semibold))
                        Text(detection.scientificName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Label("\(detection.confidencePercent)%", systemImage: "checkmark.seal")
                            Label(detection.timeLabel, systemImage: "clock")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Audio") {
                    SpectrogramView(
                        station: viewModel.stationProfile,
                        detectionID: detection.id,
                        audioURL: viewModel.audioURL,
                        title: detection.commonName,
                        autoFetchSpectrograms: viewModel.autoFetchSpectrograms,
                        apiClient: appEnvironment.apiClient
                    )
                }

                Section("Details") {
                    DetailRow(title: "Date", value: detection.date)
                    DetailRow(title: "Time", value: detection.time)
                    if let sourceLabel = detection.sourceLabel {
                        DetailRow(title: "Source", value: sourceLabel)
                    }
                    if let speciesCode = detection.speciesCode {
                        DetailRow(title: "Species Code", value: speciesCode)
                    }
                    if let clipName = detection.clipName, !clipName.isEmpty {
                        DetailRow(title: "Clip", value: clipName)
                    }
                    if let interval = detection.recordedIntervalLabel {
                        DetailRow(title: "Recording", value: interval)
                    }
                    DetailRow(title: "Review", value: detection.verified ?? "Unverified")
                    if detection.locked {
                        Label("Locked", systemImage: "lock.fill")
                    }
                    if detection.isNewSpecies == true {
                        Label("New species", systemImage: "sparkle")
                    }
                }
            } else {
                ContentUnavailableView(
                    viewModel.errorMessage ?? "Detection Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Try again from the Feed tab.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Detection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.load(environment: appEnvironment)
        }
        .refreshable {
            await viewModel.load(environment: appEnvironment)
        }
    }
}

private struct DetailRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SpeciesImageView: View {
    var imageURL: URL
    var commonName: String
    var attribution: SpeciesImageAttribution?

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .empty:
                ProgressView("Loading species image")
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)
            case .success(let image):
                ZStack(alignment: .bottomTrailing) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4 / 3, contentMode: .fill)
                        .clipped()

                    if let attribution, attribution.hasDisplayableCredit {
                        SpeciesImageAttributionView(attribution: attribution)
                            .padding(8)
                    }
                }
            case .failure:
                Label("Species image unavailable", systemImage: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)
            @unknown default:
                EmptyView()
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Image of \(commonName)")
    }
}

private struct SpeciesImageAttributionView: View {
    var attribution: SpeciesImageAttribution

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "camera")
            Text(attribution.displayText)
                .truncationMode(.tail)
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.62), in: Capsule())
        .accessibilityLabel(attribution.accessibilityLabel)
    }
}

private extension SpeciesImageAttribution {
    var hasDisplayableCredit: Bool {
        authorName.nonEmptyString != nil || licenseName.nonEmptyString != nil || sourceProvider.nonEmptyString != nil
    }

    var displayText: String {
        let primaryCredit = authorName.nonEmptyString ?? sourceProvider.nonEmptyString
        return [primaryCredit, licenseName.nonEmptyString].compactMap { $0 }.joined(separator: " / ")
    }

    var accessibilityLabel: String {
        let parts = [authorName.nonEmptyString, licenseName.nonEmptyString, sourceProvider.nonEmptyString].compactMap { $0 }
        return "Image credit: \(parts.joined(separator: ", "))"
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

#Preview {
    NavigationStack {
        DetectionDetailView(detectionID: 1)
    }
    .environment(\.appEnvironment, .preview)
}
