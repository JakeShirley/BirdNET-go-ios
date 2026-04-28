import SwiftUI

struct FeedView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel = FeedViewModel()
    @State private var debugDetectionID: Int?

    var body: some View {
        List {
            if viewModel.hasStation, let streamStatusMessage = viewModel.streamStatusMessage {
                Label(streamStatusMessage, systemImage: viewModel.streamStatusKind.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.hasStation {
                ContentUnavailableView(
                    "No Station Connected",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Connect a BirdNET-Go station from the Dashboard station menu to see recent detections.")
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
                    NavigationLink {
                        DetectionDetailView(detectionID: detection.id, initialDetection: detection)
                    } label: {
                        DetectionRow(detection: detection, isLiveInserted: detection.id == viewModel.liveInsertedDetectionID)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
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
            if let detectionID = appEnvironment.configuration.debugDetectionID {
                debugDetectionID = detectionID
            }
            await viewModel.load(environment: appEnvironment)
            await viewModel.runLiveStream(environment: appEnvironment)
        }
        .navigationDestination(
            isPresented: Binding(
                get: { debugDetectionID != nil },
                set: { isPresented in
                    if !isPresented {
                        debugDetectionID = nil
                    }
                }
            )
        ) {
            if let debugDetectionID {
                DetectionDetailView(detectionID: debugDetectionID)
            }
        }
        .refreshable {
            await viewModel.refresh(environment: appEnvironment)
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeStationProfileDidChange)) { _ in
            Task { await viewModel.refresh(environment: appEnvironment) }
        }
    }
}

private struct DetectionRow: View {
    var detection: BirdDetection
    var isLiveInserted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimatingLiveInsertion = false

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
                    .layoutPriority(1)
                if let sourceLabel = detection.sourceLabel, !sourceLabel.isEmpty {
                    Label(sourceLabel, systemImage: "waveform")
                        .lineLimit(1)
                }
                if detection.locked {
                    Label("Locked", systemImage: "lock.fill")
                        .labelStyle(.iconOnly)
                }
                if detection.isNewSpecies == true {
                    Label("New", systemImage: "sparkle")
                        .labelStyle(.iconOnly)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
        .background {
            DS.Shape.card
                .fill(Color.accentColor.opacity(isAnimatingLiveInsertion ? 0.14 : 0))
        }
        .opacity(isAnimatingLiveInsertion ? 0.9 : 1)
        .offset(y: isAnimatingLiveInsertion ? -6 : 0)
        .onAppear {
            guard isLiveInserted, !reduceMotion else {
                return
            }

            isAnimatingLiveInsertion = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeOut(duration: 1.1)) {
                    isAnimatingLiveInsertion = false
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(detection.isNewSpecies == true ? .isHeader : [])
    }

    private var accessibilityLabel: String {
        var parts: [String] = [
            detection.commonName,
            String(localized: "\(detection.confidencePercent) percent confidence"),
            String(localized: "at \(detection.timeLabel)")
        ]
        if detection.isNewSpecies == true { parts.append(String(localized: "new species")) }
        if detection.locked { parts.append(String(localized: "locked")) }
        if let source = detection.sourceLabel, !source.isEmpty { parts.append(source) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
    .environment(\.appEnvironment, .preview)
}
