import SwiftUI

struct FeedView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel = FeedViewModel()

    var body: some View {
        List {
            if !viewModel.hasStation {
                ContentUnavailableView(
                    "No Station Connected",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Connect a BirdNET-Go station from the Station tab to see recent detections.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .listRowBackground(Color.clear)
            } else if viewModel.isLoading && viewModel.detections.isEmpty {
                ProgressView("Loading detections")
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .listRowBackground(Color.clear)
            } else if viewModel.detections.isEmpty {
                ContentUnavailableView(
                    viewModel.statusMessage ?? "No Recent Detections",
                    systemImage: viewModel.statusKind.systemImage,
                    description: Text(viewModel.stationProfile?.name ?? "Feed")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
                .listRowBackground(Color.clear)
            } else {
                if let statusMessage = viewModel.statusMessage {
                    Label(statusMessage, systemImage: viewModel.statusKind.systemImage)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.detections) { detection in
                    DetectionRow(detection: detection)
                }
            }
        }
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh(environment: appEnvironment) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh feed")
            }
        }
        .task {
            await viewModel.load(environment: appEnvironment)
        }
        .refreshable {
            await viewModel.refresh(environment: appEnvironment)
        }
    }
}

private struct DetectionRow: View {
    var detection: BirdDetection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(detection.commonName)
                        .font(.headline)
                    Text(detection.scientificName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text("\(detection.confidencePercent)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label(detection.timeLabel, systemImage: "clock")
                if let sourceLabel = detection.sourceLabel, !sourceLabel.isEmpty {
                    Label(sourceLabel, systemImage: "waveform")
                        .lineLimit(1)
                }
                if detection.locked {
                    Label("Locked", systemImage: "lock.fill")
                }
                if detection.isNewSpecies == true {
                    Label("New", systemImage: "sparkle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
    .environment(\.appEnvironment, .preview)
}
