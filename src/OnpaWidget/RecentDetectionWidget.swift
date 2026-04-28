import SwiftUI
import WidgetKit

struct RecentDetectionEntry: TimelineEntry {
    let date: Date
    let snapshot: RecentDetectionSnapshot
}

struct RecentDetectionProvider: TimelineProvider {
    private let loader = RecentDetectionLoader()

    func placeholder(in context: Context) -> RecentDetectionEntry {
        RecentDetectionEntry(date: Date(), snapshot: RecentDetectionSnapshot.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentDetectionEntry) -> Void) {
        let snapshot = context.isPreview ? RecentDetectionSnapshot.placeholder : loader.loadSnapshot()
        completion(RecentDetectionEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentDetectionEntry>) -> Void) {
        let now = Date()
        let entry = RecentDetectionEntry(date: now, snapshot: loader.loadSnapshot())
        // Refresh every 15 minutes; the main app pushes new data into the
        // shared cache whenever it runs, so a relatively coarse refresh
        // keeps the widget in sync without burning the system budget.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension RecentDetectionSnapshot {
    static var placeholder: RecentDetectionSnapshot {
        RecentDetectionSnapshot(
            profile: StationProfile(name: "BirdNET-Go", baseURL: URL(string: "http://birdnet-go.local")!),
            detection: BirdDetection(
                id: 0,
                date: "2026-04-28",
                time: "08:42:11",
                timestamp: nil,
                source: DetectionSourceInfo(id: "porch", displayName: "Porch Mic"),
                beginTime: nil,
                endTime: nil,
                speciesCode: "amerob",
                clipName: nil,
                latitude: nil,
                longitude: nil,
                scientificName: "Turdus migratorius",
                commonName: "American Robin",
                confidence: 0.94,
                verified: nil,
                locked: false,
                isNewSpecies: nil,
                timeOfDay: nil
            )
        )
    }
}

struct RecentDetectionWidget: Widget {
    static let kind = "org.odinseye.onpa.widget.recent-detection"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RecentDetectionProvider()) { entry in
            RecentDetectionWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    RecentDetectionBackground()
                }
        }
        .configurationDisplayName("Recent Detection")
        .description("Shows the latest bird detected by your BirdNET-Go station.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct RecentDetectionBackground: View {
    var body: some View {
        LinearGradient(
            colors: [DS.accent.opacity(0.18), DS.accent.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct RecentDetectionWidgetView: View {
    var entry: RecentDetectionEntry

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var content: some View {
        if let detection = entry.snapshot.detection {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "bird.fill")
                        .font(.caption)
                        .foregroundStyle(DS.accent)
                        .accessibilityHidden(true)
                    Text(stationLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(detection.commonName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(detection.scientificName)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Label("\(detection.confidencePercent)%", systemImage: "waveform")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.accent)
                        .labelStyle(.titleAndIcon)

                    Spacer(minLength: 0)

                    Text(detection.timeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title3)
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                Text("No Recent Detections")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(emptyStateSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Open Onpa")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.accent)
            }
        }
    }

    private var stationLabel: String {
        entry.snapshot.profile?.name ?? String(localized: "BirdNET-Go")
    }

    private var emptyStateSubtitle: String {
        if entry.snapshot.profile == nil {
            return String(localized: "Connect a station to start tracking detections.")
        }
        return String(localized: "Your station hasn't reported anything yet.")
    }

    private var accessibilitySummary: String {
        if let detection = entry.snapshot.detection {
            return String(
                localized:
                    "Recent detection from \(stationLabel): \(detection.commonName), \(detection.scientificName), \(detection.confidencePercent) percent confidence, \(detection.timeLabel)."
            )
        }
        return String(localized: "Onpa widget: \(emptyStateSubtitle)")
    }
}

#Preview(as: .systemSmall) {
    RecentDetectionWidget()
} timeline: {
    RecentDetectionEntry(date: .now, snapshot: .placeholder)
    RecentDetectionEntry(date: .now, snapshot: RecentDetectionSnapshot(profile: nil, detection: nil))
}
