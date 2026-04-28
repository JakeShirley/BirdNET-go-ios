import Foundation
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
                            if let timeOfDay = viewModel.timeOfDay.nonEmptyString {
                                Label(timeOfDay.displayTitle, systemImage: timeOfDay.timeOfDaySystemImage)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                if let weatherContext = viewModel.weatherContext, weatherContext.hasDisplayableWeather {
                    Section("Weather") {
                        WeatherContextView(context: weatherContext, timeOfDay: viewModel.timeOfDay)
                    }
                }

                Section("Details") {
                    DetailRow(title: "Date", value: detection.date)
                    DetailRow(title: "Time", value: detection.time)
                    if let timeOfDay = viewModel.timeOfDay.nonEmptyString {
                        DetailRow(title: "Time of Day", value: timeOfDay.displayTitle)
                    }
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
        .task {
            await viewModel.load(environment: appEnvironment)
        }
        .refreshable {
            await viewModel.load(environment: appEnvironment)
        }
    }
}

private struct WeatherContextView: View {
    var context: DetectionWeatherContext
    var timeOfDay: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = context.summaryText {
                Label(summary, systemImage: context.weatherSystemImage(timeOfDay: timeOfDay))
                    .font(.headline)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], alignment: .leading, spacing: 12) {
                if let temperature = context.hourly?.temperature {
                    WeatherMetricView(title: "Temperature", value: temperature.temperatureLabel, systemImage: "thermometer.medium")
                }

                if let windSpeed = context.hourly?.windSpeed {
                    WeatherMetricView(title: "Wind", value: context.windLabel(speed: windSpeed), systemImage: "wind")
                }

                if let humidity = context.hourly?.humidity {
                    WeatherMetricView(title: "Humidity", value: "\(humidity)%", systemImage: "humidity")
                }

                if let pressure = context.hourly?.pressure {
                    WeatherMetricView(title: "Pressure", value: "\(pressure) hPa", systemImage: "gauge")
                }

                if let location = context.daily?.locationLabel {
                    WeatherMetricView(title: "Location", value: location, systemImage: "location")
                }
            }

            if let sunLabel = context.daily?.sunlightLabel {
                Label(sunLabel, systemImage: "sunrise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WeatherMetricView: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
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
            Color(.secondarySystemGroupedBackground)
                .overlay {
                    switch phase {
                    case .empty:
                        ProgressView("Loading species image")
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Label("Species image unavailable", systemImage: "photo")
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if case .success = phase, let attribution, attribution.hasDisplayableCredit {
                        SpeciesImageAttributionView(attribution: attribution)
                            .padding(8)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipped()
        }
        .clipShape(DS.Shape.card)
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
        .background(DS.Overlay.darkChip, in: Capsule())
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

private extension DetectionWeatherContext {
    var hasDisplayableWeather: Bool {
        summaryText != nil || hourly?.temperature != nil || hourly?.windSpeed != nil || hourly?.humidity != nil || hourly?.pressure != nil || daily?.locationLabel != nil || daily?.sunlightLabel != nil
    }

    var summaryText: String? {
        hourly?.weatherDescription?.displayTitle ?? hourly?.weatherMain?.displayTitle
    }

    func windLabel(speed: Double) -> String {
        if let gust = hourly?.windGust, gust > speed {
            return "\(speed.oneDecimalLabel) m/s, gusts \(gust.oneDecimalLabel)"
        }

        return "\(speed.oneDecimalLabel) m/s"
    }

    func weatherSystemImage(timeOfDay: String?) -> String {
        guard let weatherIcon = hourly?.weatherIcon else {
            return timeOfDay?.timeOfDaySystemImage ?? "cloud.sun"
        }

        if weatherIcon.hasPrefix("01") {
            return timeOfDay?.lowercased() == "night" ? "moon.stars" : "sun.max"
        }

        if weatherIcon.hasPrefix("09") || weatherIcon.hasPrefix("10") {
            return "cloud.rain"
        }

        if weatherIcon.hasPrefix("11") {
            return "cloud.bolt.rain"
        }

        if weatherIcon.hasPrefix("13") {
            return "cloud.snow"
        }

        if weatherIcon.hasPrefix("50") {
            return "cloud.fog"
        }

        return "cloud"
    }
}

private extension DailyWeatherContext {
    var locationLabel: String? {
        [cityName.nonEmptyString, country.nonEmptyString].compactMap { $0 }.joined(separator: ", ").nonEmptyString
    }

    var sunlightLabel: String? {
        let sunriseLabel = sunrise.flatMap(Self.timeLabel(from:))
        let sunsetLabel = sunset.flatMap(Self.timeLabel(from:))

        switch (sunriseLabel, sunsetLabel) {
        case let (sunrise?, sunset?):
            return "Sunrise \(sunrise) / Sunset \(sunset)"
        case let (sunrise?, nil):
            return "Sunrise \(sunrise)"
        case let (nil, sunset?):
            return "Sunset \(sunset)"
        case (nil, nil):
            return nil
        }
    }

    private static func timeLabel(from value: String) -> String? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return timeFormatter.string(from: date)
        }

        return value.nonEmptyString
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private extension Double {
    var temperatureLabel: String {
        "\(oneDecimalLabel) C"
    }

    var oneDecimalLabel: String {
        String(format: "%.1f", self)
    }
}

private extension String {
    var displayTitle: String {
        replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    var nonEmptyString: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var timeOfDaySystemImage: String {
        switch lowercased() {
        case "day":
            return "sun.max"
        case "night":
            return "moon.stars"
        case "sunrise", "dawn":
            return "sunrise"
        case "sunset", "dusk":
            return "sunset"
        default:
            return "clock"
        }
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
