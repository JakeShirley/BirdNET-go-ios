import SafariServices
import SwiftUI

struct SpeciesDetailView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel: SpeciesDetailViewModel
    @State private var inAppBrowserURL: IdentifiedURL?

    init(entry: SpeciesListEntry) {
        _viewModel = StateObject(wrappedValue: SpeciesDetailViewModel(entry: entry))
    }

    var body: some View {
        List {
            heroSection

            if let statusMessage = viewModel.statusMessage {
                Section {
                    Label(statusMessage, systemImage: viewModel.statusKind.systemImage)
                        .foregroundStyle(viewModel.statusKind == .error ? .red : .secondary)
                }
            }

            if !viewModel.audioSamples.isEmpty {
                Section("Audio Samples") {
                    ForEach(viewModel.audioSamples) { detection in
                        AudioClipPlayerView(
                            audioURL: viewModel.audioURL(for: detection, environment: appEnvironment),
                            title: detection.audioSampleTitle
                        )
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Recent Detections") {
                if viewModel.isLoading && viewModel.detections.isEmpty {
                    ProgressView("Loading detections")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if viewModel.detections.isEmpty {
                    ContentUnavailableView(
                        "No Recent Detections",
                        systemImage: "waveform.slash",
                        description: Text("New detections for this species will appear here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(viewModel.detections) { detection in
                        NavigationLink {
                            DetectionDetailView(detectionID: detection.id, initialDetection: detection)
                        } label: {
                            SpeciesDetectionRow(detection: detection)
                        }
                    }
                }
            }

            Section("Details") {
                DetailRow(title: "Common Name", value: viewModel.species.commonName)
                DetailRow(title: "Scientific Name", value: viewModel.species.scientificName)
                if let speciesCode = viewModel.species.speciesCode {
                    DetailRow(title: "Species Code", value: speciesCode.uppercased())
                }
                if let rarity = viewModel.species.rarity {
                    DetailRow(title: "Rarity", value: rarity)
                }
            }
        }
        .navigationTitle(viewModel.species.commonName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(environment: appEnvironment) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh species detail")
            }
        }
        .task {
            await viewModel.load(environment: appEnvironment)
        }
        .refreshable {
            await viewModel.refresh(environment: appEnvironment)
        }
        .sheet(item: $inAppBrowserURL) { item in
            SafariBrowserView(url: item.url)
                .ignoresSafeArea()
        }
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                SpeciesDetailImageView(
                    primaryURL: primaryImageURL,
                    fallbackURL: fallbackImageURL,
                    commonName: viewModel.species.commonName,
                    attribution: viewModel.speciesImageAttribution
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.species.commonName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    Text(viewModel.species.scientificName)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let wikipediaURL {
                    WikipediaLinkChip(url: wikipediaURL, commonName: viewModel.species.commonName) {
                        inAppBrowserURL = IdentifiedURL(url: wikipediaURL)
                    }
                }

                HStack(spacing: 10) {
                    SpeciesMetricTile(title: "Detections", value: "\(viewModel.totalDetections)", systemImage: "waveform")
                    SpeciesMetricTile(title: "Samples", value: "\(viewModel.audioSamples.count)", systemImage: "play.circle")
                    SpeciesMetricTile(title: "Latest", value: latestDetectionLabel, systemImage: "clock")
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var latestDetectionLabel: String {
        viewModel.detections.first?.timeLabel ?? viewModel.entry.latestDetectionLabel ?? "--"
    }

    private var primaryImageURL: URL? {
        guard let station = viewModel.stationProfile else {
            return viewModel.species.thumbnailURL
        }

        return appEnvironment.apiClient.speciesImageURL(station: station, scientificName: viewModel.species.scientificName)
    }

    private var fallbackImageURL: URL? {
        guard viewModel.stationProfile != nil else {
            return nil
        }

        return viewModel.species.thumbnailURL
    }

    private var wikipediaURL: URL? {
        let trimmedScientific = viewModel.species.scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommon = viewModel.species.commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedScientific.isEmpty ? trimmedCommon : trimmedScientific
        guard !title.isEmpty,
              let encoded = title.replacingOccurrences(of: " ", with: "_")
                  .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        return URL(string: "https://en.wikipedia.org/wiki/\(encoded)")
    }
}

private struct SpeciesDetailImageView: View {
    let primaryURL: URL?
    let fallbackURL: URL?
    let commonName: String
    let attribution: SpeciesImageAttribution?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DS.Surface.card
                .overlay {
                    if let primaryURL {
                        asyncImage(url: primaryURL, fallbackURL: fallbackURL)
                    } else {
                        imageUnavailableLabel
                    }
                }

            if let attribution, attribution.hasDisplayableCredit {
                SpeciesImageCreditView(attribution: attribution)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(DS.Shape.card)
        .accessibilityLabel("Image of \(commonName)")
    }

    private var imageUnavailableLabel: some View {
        Label("Species image unavailable", systemImage: "photo")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func asyncImage(url: URL, fallbackURL: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView("Loading species image")
            case .success(let image):
                renderedImage(image)
            case .failure:
                if let fallbackURL {
                    AsyncImage(url: fallbackURL) { fallbackPhase in
                        switch fallbackPhase {
                        case .empty:
                            ProgressView("Loading species image")
                        case .success(let image):
                            renderedImage(image)
                        default:
                            imageUnavailableLabel
                        }
                    }
                } else {
                    imageUnavailableLabel
                }
            @unknown default:
                EmptyView()
            }
        }
    }

    private func renderedImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
    }
}

private struct SpeciesImageCreditView: View {
    let attribution: SpeciesImageAttribution

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
        .background(DS.Overlay.darkChip, in: Capsule())
        .accessibilityLabel(attribution.accessibilityLabel)
    }
}

private struct SpeciesMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.accent)
            Text(value)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DS.Surface.card, in: DS.Shape.card)
    }
}

private struct SpeciesDetectionRow: View {
    let detection: BirdDetection

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detection.timeLabel)
                    .font(.headline)
                Text(detection.recordedIntervalLabel ?? detection.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(detection.confidencePercent)%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let sourceLabel = detection.sourceLabel {
                    Text(sourceLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

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

private struct WikipediaLinkChip: View {
    let url: URL
    let commonName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .font(.subheadline.weight(.semibold))
                Text("Read on Wikipedia")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [DS.AccentTint.medium, DS.AccentTint.soft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: DS.Shape.large
            )
            .overlay(
                DS.Shape.large
                    .stroke(DS.AccentTint.strong, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read about \(commonName) on Wikipedia")
        .accessibilityHint("Opens an in-app browser")
    }
}

private struct SafariBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor.systemTeal
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
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

private extension BirdDetection {
    var audioSampleTitle: String {
        "\(timeLabel) / \(confidencePercent)%"
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