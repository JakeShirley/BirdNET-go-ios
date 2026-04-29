import SwiftUI

struct StatsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @StateObject private var viewModel = StatsViewModel()
    @State private var debugSpeciesSummary: DailySpeciesSummary?
    @State private var isStationManagementPresented = false
    @State private var stationManagementInitialMode: StationView.Mode = .manage
    @State private var isSettingsPresented = false
    @State private var didOpenDebugStationManagement = false
    @State private var didOpenDebugSettings = false

    var body: some View {
        Group {
            if viewModel.hasStation {
                dashboardContent
            } else {
                stationUnavailableView
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        stationManagementInitialMode = .manage
                        isStationManagementPresented = true
                    } label: {
                        Label(stationMenuActionTitle, systemImage: "antenna.radiowaves.left.and.right")
                    }

                    Button {
                        stationManagementInitialMode = .addStation
                        isStationManagementPresented = true
                    } label: {
                        Label("Add Station", systemImage: "plus")
                    }

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }

                    if viewModel.availableProfiles.count > 1 {
                        Section("Switch Station") {
                            ForEach(viewModel.availableProfiles) { profile in
                                let isActive = profile.id == viewModel.stationProfile?.id
                                let isConnected = isActive && viewModel.isActiveStationConnected
                                Button {
                                    Task { await viewModel.switchProfile(to: profile, environment: appEnvironment) }
                                } label: {
                                    Label(profile.name, systemImage: isActive ? "checkmark.circle.fill" : "circle")
                                }
                                .tint(isConnected ? .green : .accentColor)
                            }
                        }
                    } else if let stationProfile = viewModel.stationProfile {
                        Section("Current") {
                            Label(stationProfile.name, systemImage: "checkmark.circle")
                                .tint(viewModel.isActiveStationConnected ? .green : .accentColor)
                        }
                    }
                } label: {
                    Label("Station", systemImage: "antenna.radiowaves.left.and.right")
                }
                .accessibilityLabel("Station menu")
            }
        }
        .task {
            await viewModel.load(environment: appEnvironment)
            openDebugDestinationIfNeeded()
            openDebugSpeciesDetailIfNeeded()
        }
        .refreshable {
            await viewModel.refresh(environment: appEnvironment)
            openDebugSpeciesDetailIfNeeded()
        }
        .onChange(of: viewModel.dailySummary) { _, _ in
            openDebugSpeciesDetailIfNeeded()
        }
        .onChange(of: isStationManagementPresented) { _, isPresented in
            guard !isPresented else {
                return
            }

            // Reset to the default mode when the screen dismisses so the
            // next "Manage Station" tap doesn't accidentally land in
            // add-station mode.
            stationManagementInitialMode = .manage
            Task { await viewModel.refresh(environment: appEnvironment) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeStationProfileDidChange)) { _ in
            Task { await viewModel.refresh(environment: appEnvironment) }
        }
        .navigationDestination(isPresented: debugSpeciesDetailIsPresented) {
            if let debugSpeciesSummary {
                SpeciesDetailView(entry: debugSpeciesSummary.speciesDetailEntry)
            }
        }
        .navigationDestination(isPresented: $isStationManagementPresented) {
            StationView(initialMode: stationManagementInitialMode)
        }
        .navigationDestination(isPresented: $isSettingsPresented) {
            SettingsView()
        }
    }

    private var stationMenuActionTitle: String {
        viewModel.hasStation ? "Manage Station" : "Connect to Station"
    }

    private func openDebugDestinationIfNeeded() {
        if appEnvironment.configuration.debugShowsSettings || appEnvironment.configuration.debugShowsChangelog,
           !didOpenDebugSettings {
            didOpenDebugSettings = true
            isSettingsPresented = true
            return
        }

        guard appEnvironment.configuration.debugShowsStationManagement, !didOpenDebugStationManagement else {
            return
        }

        didOpenDebugStationManagement = true
        isStationManagementPresented = true
    }

    private var debugSpeciesDetailIsPresented: Binding<Bool> {
        Binding(
            get: { debugSpeciesSummary != nil },
            set: { isPresented in
                if !isPresented {
                    debugSpeciesSummary = nil
                }
            }
        )
    }

    private func openDebugSpeciesDetailIfNeeded() {
        guard debugSpeciesSummary == nil, let debugSpeciesName = appEnvironment.configuration.debugSpeciesName?.lowercased() else {
            return
        }

        debugSpeciesSummary = viewModel.dailySummary.first { summary in
            [summary.commonName, summary.scientificName, summary.speciesCode]
                .compactMap { $0?.lowercased() }
                .contains(debugSpeciesName)
        }
    }

    private var dashboardContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let statusMessage = viewModel.statusMessage {
                    StatusBanner(message: statusMessage, kind: viewModel.statusKind)
                }

                DateControlCard(viewModel: viewModel, environment: appEnvironment)

                KPIStrip(
                    detections: viewModel.totalDetections,
                    species: viewModel.speciesCount,
                    peakHour: peakHourLabel
                )

                DailyActivityCard(viewModel: viewModel, station: viewModel.stationProfile, apiClient: appEnvironment.apiClient)

                CurrentlyHearingCard(detections: viewModel.currentlyHearing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .overlay {
            if viewModel.isLoading && viewModel.dailySummary.isEmpty && viewModel.recentDetections.isEmpty {
                ProgressView("Loading dashboard")
                    .padding(18)
                    .background(.regularMaterial, in: DS.Shape.card)
            }
        }
        .background(DS.Surface.grouped)
    }

    private var stationUnavailableView: some View {
        List {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "No Station Connected",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Connect a BirdNET-Go station to see daily activity.")
                )

                Button {
                    isStationManagementPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Connect to Station")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .listRowBackground(Color.clear)
        }
    }

    private var peakHourLabel: String {
        guard let peak = viewModel.hourlyTotals.enumerated().max(by: { $0.element < $1.element }), peak.element > 0 else {
            return "--"
        }

        return String(format: "%02d:00", peak.offset)
    }
}

private struct DateControlCard: View {
    @ObservedObject var viewModel: StatsViewModel
    let environment: AppEnvironment

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.moveDate(by: -1, environment: environment) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 42, height: 42)
                    .background(DS.Surface.inset, in: DS.Shape.card)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Activity")
                    .font(.headline)
                Text(viewModel.selectedDateTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.moveDate(by: 1, environment: environment) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(viewModel.canAdvanceDate ? DS.accent : Color.secondary)
                    .frame(width: 42, height: 42)
                    .background(DS.Surface.inset, in: DS.Shape.card)
                    .opacity(viewModel.canAdvanceDate ? 1.0 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canAdvanceDate)
            .accessibilityLabel("Next day")
        }
        .padding(14)
        .background(DS.Surface.card, in: DS.Shape.card)
    }
}

private struct KPIStrip: View {
    let detections: Int
    let species: Int
    let peakHour: String

    var body: some View {
        HStack(spacing: 10) {
            KPITile(title: "Detections", value: "\(detections)", systemImage: "waveform")
            KPITile(title: "Species", value: "\(species)", systemImage: "bird")
            KPITile(title: "Peak", value: peakHour, systemImage: "clock")
        }
    }
}

private struct KPITile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 28, height: 28)
                .background(DS.AccentTint.soft, in: DS.Shape.inset)
                .accessibilityHidden(true)

            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DS.Surface.card, in: DS.Shape.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(title): \(value)"))
    }
}

private struct DailyActivityCard: View {
    @ObservedObject var viewModel: StatsViewModel
    let station: StationProfile?
    let apiClient: any BirdNETGoAPIClient

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily Activity")
                        .font(.headline)
                    Text("Species detections by hour")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                }
            }

            if viewModel.dailySummary.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "chart.xyaxis.line",
                    description: Text("No detections are available for this date.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                HourlyOverview(totals: viewModel.hourlyTotals)
                HeatmapLegend()
                SpeciesHeatmap(
                    summaries: viewModel.dailySummary,
                    maximum: viewModel.maxHourlySpeciesCount,
                    station: station,
                    apiClient: apiClient
                )
            }
        }
        .padding(14)
        .background(DS.Surface.card, in: DS.Shape.card)
    }
}

private struct HourlyOverview: View {
    let totals: [Int]

    var body: some View {
        let maximum = max(totals.max() ?? 0, 1)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let count = totals[safe: hour] ?? 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(activityColor(count: count, maximum: maximum))
                        .frame(height: CGFloat(max(5, min(42, count * 42 / maximum))))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(String(format: "%02d:00", hour))
                        .accessibilityValue(count == 1 ? String(localized: "1 detection") : String(localized: "\(count) detections"))
                }
            }
            .frame(height: 46)

            HStack {
                Text("00")
                Spacer()
                Image(systemName: "sun.max")
                    .accessibilityLabel("Daylight")
                Spacer()
                Text("23")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(DS.Surface.inset, in: DS.Shape.card)
    }
}

private struct HeatmapLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Less")
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(activityColor(count: index, maximum: 4))
                    .frame(width: 18, height: 10)
            }
            Text("More")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct SpeciesHeatmap: View {
    let summaries: [DailySpeciesSummary]
    let maximum: Int
    let station: StationProfile?
    let apiClient: any BirdNETGoAPIClient

    private let labelWidth: CGFloat = 154
    private let cellSize: CGFloat = 18
    private let cellSpacing: CGFloat = 4

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: cellSpacing) {
                    Color.clear.frame(width: labelWidth, height: 1)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: cellSize)
                    }
                }

                ForEach(summaries) { summary in
                    NavigationLink {
                        SpeciesDetailView(entry: summary.speciesDetailEntry)
                    } label: {
                        HStack(spacing: cellSpacing) {
                            SpeciesHeatmapLabel(summary: summary, station: station, apiClient: apiClient)
                                .frame(width: labelWidth, alignment: .leading)

                            ForEach(Array(summary.normalizedHourlyCounts.enumerated()), id: \.offset) { _, count in
                                HeatmapCell(count: count, maximum: max(maximum, 1))
                                    .frame(width: cellSize, height: cellSize)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "\(summary.commonName), \(summary.count) detections today"))
                    .accessibilityHint("Opens species details")
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SpeciesHeatmapLabel: View {
    let summary: DailySpeciesSummary
    let station: StationProfile?
    let apiClient: any BirdNETGoAPIClient

    var body: some View {
        HStack(spacing: 8) {
            SpeciesThumbnail(primaryURL: summary.thumbnailURL, fallbackURL: fallbackThumbnailURL, name: summary.commonName)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(summary.commonName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if summary.isNewSpecies == true {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text("\(summary.count) detections")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var fallbackThumbnailURL: URL? {
        guard let station else {
            return nil
        }

        return apiClient.speciesImageURL(station: station, scientificName: summary.scientificName)
    }
}

private struct HeatmapCell: View {
    let count: Int
    let maximum: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(activityColor(count: count, maximum: maximum))

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(count > maximum / 2 ? .white : .primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 1)
            }
        }
        .accessibilityLabel(String(localized: "\(count) detections"))
    }
}

private struct CurrentlyHearingCard: View {
    let detections: [BirdDetection]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Currently Hearing")
                        .font(.headline)
                    Text("Latest station detections")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "ear.and.waveform")
                    .foregroundStyle(DS.accent)
            }

            if detections.isEmpty {
                ContentUnavailableView(
                    "Quiet Right Now",
                    systemImage: "ear",
                    description: Text("Recent detections will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ForEach(detections) { detection in
                    HearingRow(detection: detection)
                    if detection.id != detections.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .background(DS.Surface.card, in: DS.Shape.card)
    }
}

private struct HearingRow: View {
    let detection: BirdDetection

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detection.commonName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detection.scientificName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(detection.confidencePercent)%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(detection.timeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(detection.commonName), \(detection.confidencePercent) percent confidence at \(detection.timeLabel)"))
    }
}

private struct SpeciesThumbnail: View {
    let primaryURL: URL?
    let fallbackURL: URL?
    let name: String

    var body: some View {
        Group {
            if let primaryURL {
                thumbnailImage(url: primaryURL, fallbackURL: fallbackURL)
            } else if let fallbackURL {
                thumbnailImage(url: fallbackURL, fallbackURL: nil)
            } else {
                placeholder
            }
        }
        .clipShape(DS.Shape.inset)
        .accessibilityLabel(name)
    }

    @ViewBuilder
    private func thumbnailImage(url: URL, fallbackURL: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                renderedImage(image)
            case .failure:
                if let fallbackURL {
                    AsyncImage(url: fallbackURL) { fallbackPhase in
                        switch fallbackPhase {
                        case .success(let image):
                            renderedImage(image)
                        default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            default:
                placeholder
            }
        }
    }

    private func renderedImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
    }

    private var placeholder: some View {
        ZStack {
            DS.AccentTint.soft
            Image(systemName: "bird")
                .font(.caption)
                .foregroundStyle(DS.accent)
        }
    }
}

private struct StatusBanner: View {
    let message: String
    let kind: StatsViewModel.StatusKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.systemImage)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(foregroundColor)
        .padding(12)
        .background(backgroundColor, in: DS.Shape.card)
    }

    private var foregroundColor: Color {
        switch kind {
        case .neutral:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .neutral:
            return Color(.tertiarySystemGroupedBackground)
        case .warning:
            return Color.orange.opacity(0.12)
        case .error:
            return Color.red.opacity(0.12)
        }
    }
}

private func activityColor(count: Int, maximum: Int) -> Color {
    guard count > 0, maximum > 0 else {
        return Color(.systemGray5)
    }

    let ratio = Double(count) / Double(maximum)
    switch ratio {
    case ..<0.2:
        return Color.mint.opacity(0.55)
    case ..<0.4:
        return Color.green.opacity(0.68)
    case ..<0.65:
        return Color.teal.opacity(0.78)
    case ..<0.85:
        return Color.cyan.opacity(0.9)
    default:
        return Color.blue.opacity(0.95)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension DailySpeciesSummary {
    var speciesDetailEntry: SpeciesListEntry {
        SpeciesListEntry(
            species: StationSpecies(
                commonName: commonName,
                scientificName: scientificName,
                speciesCode: speciesCode,
                detectionCount: count,
                thumbnailURL: thumbnailURL
            ),
            stats: SpeciesStats(
                count: count,
                firstHeardDate: nil,
                latestDetectionDate: nil,
                topConfidence: nil,
                avgConfidence: nil
            )
        )
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
    .environment(\.appEnvironment, .preview)
}
