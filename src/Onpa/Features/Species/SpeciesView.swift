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
                Menu {
                    Picker(selection: $viewModel.sortMode) {
                        ForEach(SpeciesViewModel.SortMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    } label: {
                        Text("Sort By")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort species")
            }

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
        .onReceive(NotificationCenter.default.publisher(for: .activeStationProfileDidChange)) { _ in
            Task { await viewModel.refresh(environment: appEnvironment) }
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
            SpeciesThumbnail(primaryURL: primaryImageURL, fallbackURL: fallbackImageURL, commonName: entry.species.commonName)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.species.commonName)
                        .font(.headline)
                        .lineLimit(2)
                    Text(entry.species.scientificName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
        [entry.species.commonName, entry.metadataLabel].joined(separator: ", ")
    }

    private var primaryImageURL: URL? {
        // Prefer the station's media endpoint (returns a PNG we can decode) over
        // any catalog-supplied thumbnail, which may be a relative path or SVG
        // placeholder that AsyncImage cannot load.
        if let station {
            return apiClient.speciesImageURL(station: station, scientificName: entry.species.scientificName)
        }

        return entry.species.thumbnailURL
    }

    private var fallbackImageURL: URL? {
        guard station != nil, let thumbnailURL = entry.species.thumbnailURL, thumbnailURL.scheme != nil else {
            return nil
        }

        return thumbnailURL
    }
}

private struct SpeciesThumbnail: View {
    var primaryURL: URL?
    var fallbackURL: URL?
    var commonName: String

    var body: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)

            if let primaryURL {
                thumbnailImage(url: primaryURL, fallbackURL: fallbackURL)
            } else if let fallbackURL {
                thumbnailImage(url: fallbackURL, fallbackURL: nil)
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
        .accessibilityLabel(String(localized: "Image of \(commonName)"))
    }

    @ViewBuilder
    private func thumbnailImage(url: URL, fallbackURL: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                if let fallbackURL {
                    AsyncImage(url: fallbackURL) { fallbackPhase in
                        switch fallbackPhase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            @unknown default:
                EmptyView()
            }
        }
    }
}

private extension SpeciesListEntry {
    var metadataLabel: String {
        let rarityOrCode = species.rarity ?? species.speciesCode?.uppercased()
        let parts = [countLabel, latestDetectionLabel, rarityOrCode].compactMap { $0 }
        return parts.isEmpty ? String(localized: "No recent detections") : parts.joined(separator: " / ")
    }
}

#Preview {
    NavigationStack {
        SpeciesView()
    }
}
