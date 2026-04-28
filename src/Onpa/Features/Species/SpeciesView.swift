import SwiftUI

struct SpeciesView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel = SpeciesViewModel()
    @State private var debugSpeciesEntry: SpeciesListEntry?

    var body: some View {
        List {
            if !viewModel.hasStation {
                ContentUnavailableView(
                    "No Station Connected",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Connect a BirdNET-Go station from the Dashboard station menu to see detected species.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .listRowBackground(Color.clear)
            } else if viewModel.isLoading && viewModel.species.isEmpty {
                ProgressView("Loading species")
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .listRowBackground(Color.clear)
            } else if viewModel.species.isEmpty {
                ContentUnavailableView(
                    viewModel.statusMessage ?? "No Species Detected",
                    systemImage: viewModel.statusKind.systemImage,
                    description: Text(viewModel.stationProfile?.name ?? "Species")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .listRowBackground(Color.clear)
            } else {
                if let statusMessage = viewModel.statusMessage {
                    Label(statusMessage, systemImage: viewModel.statusKind.systemImage)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.species) { entry in
                    NavigationLink {
                        SpeciesDetailView(entry: entry)
                    } label: {
                        SpeciesRow(entry: entry, station: viewModel.stationProfile, apiClient: appEnvironment.apiClient)
                    }
                }
            }
        }
        .navigationTitle("Species")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(environment: appEnvironment) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh species")
            }
        }
        .task {
            await viewModel.load(environment: appEnvironment)
            openDebugSpeciesDetailIfNeeded()
        }
        .refreshable {
            await viewModel.refresh(environment: appEnvironment)
            openDebugSpeciesDetailIfNeeded()
        }
        .onChange(of: viewModel.species) { _, _ in
            openDebugSpeciesDetailIfNeeded()
        }
        .navigationDestination(isPresented: debugSpeciesDetailIsPresented) {
            if let debugSpeciesEntry {
                SpeciesDetailView(entry: debugSpeciesEntry)
            }
        }
    }

    private var debugSpeciesDetailIsPresented: Binding<Bool> {
        Binding(
            get: { debugSpeciesEntry != nil },
            set: { isPresented in
                if !isPresented {
                    debugSpeciesEntry = nil
                }
            }
        )
    }

    private func openDebugSpeciesDetailIfNeeded() {
        guard debugSpeciesEntry == nil, let debugSpeciesName = appEnvironment.configuration.debugSpeciesName?.lowercased() else {
            return
        }

        debugSpeciesEntry = viewModel.species.first { entry in
            [entry.species.commonName, entry.species.scientificName, entry.species.speciesCode]
                .compactMap { $0?.lowercased() }
                .contains(debugSpeciesName)
        }
    }
}

private struct SpeciesRow: View {
    var entry: SpeciesListEntry
    var station: StationProfile?
    var apiClient: any BirdNETGoAPIClient

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SpeciesThumbnail(imageURL: imageURL, commonName: entry.species.commonName)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.species.commonName)
                            .font(.headline)
                            .lineLimit(2)
                        Text(entry.species.scientificName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if let topConfidenceLabel = entry.topConfidenceLabel {
                        Text(topConfidenceLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(entry.metadataLabel)
                    .lineLimit(2)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [entry.species.commonName]
        if let topConfidenceLabel = entry.topConfidenceLabel {
            parts.append("top confidence \(topConfidenceLabel)")
        }
        parts.append(entry.metadataLabel)
        return parts.joined(separator: ", ")
    }

    private var imageURL: URL? {
        if let thumbnailURL = entry.species.thumbnailURL {
            return thumbnailURL
        }

        guard let station else {
            return nil
        }

        return apiClient.speciesImageURL(station: station, scientificName: entry.species.scientificName)
    }
}

private struct SpeciesThumbnail: View {
    var imageURL: URL?
    var commonName: String

    var body: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "leaf")
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            DS.Shape.card
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .frame(width: 56, height: 56)
        .clipShape(DS.Shape.card)
        .accessibilityLabel("Image of \(commonName)")
    }
}

private extension SpeciesListEntry {
    var metadataLabel: String {
        let rarityOrCode = species.rarity ?? species.speciesCode?.uppercased()
        let parts = [countLabel, latestDetectionLabel, rarityOrCode].compactMap { $0 }
        return parts.isEmpty ? "No recent detections" : parts.joined(separator: " / ")
    }
}

#Preview {
    NavigationStack {
        SpeciesView()
    }
}
