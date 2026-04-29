import SwiftUI

/// Detection counts for the days immediately before and after the selected
/// date, used by `DailyDigestStats` to build comparison phrases. Either
/// side may be `nil` (request failed, no data, or the neighbor doesn't
/// apply — e.g. "next day" when viewing today).
struct NeighborTotals: Equatable, Hashable {
    let priorDayTotal: Int?
    let nextDayTotal: Int?

    static let empty = NeighborTotals(priorDayTotal: nil, nextDayTotal: nil)
}

/// Coarse part-of-day label, derived from the device's local clock when the
/// selected day is today. Used to bias how the digest opens — a morning
/// view of today's data should sound different from an evening recap.
enum DigestTimeOfDay: String, Equatable, Hashable, Codable, Sendable {
    case earlyMorning   // 4am–7am: dawn chorus framing
    case morning        // 7am–12pm
    case afternoon      // 12pm–5pm
    case evening        // 5pm–9pm
    case night          // 9pm–4am: late, often quiet
}

/// Day-over-day trend bucket derived from the prior day's total.
enum DigestTrend: Equatable, Hashable {
    case up(percent: Int)
    case down(percent: Int)
    case flat
}

/// A deterministic, plain-language summary of the currently selected day's
/// activity. Inputs are restricted to data the dashboard already loads
/// (`dailySummary`) plus optional neighbor-day totals; the struct never
/// makes network requests of its own. Generated AI prose layered on top
/// uses this same struct as its source of truth.
struct DailyDigestStats: Equatable, Hashable {
    struct SpeciesCount: Equatable, Hashable {
        let commonName: String
        let count: Int
    }

    let totalDetections: Int
    let uniqueSpecies: Int
    let topSpecies: [SpeciesCount]
    let peakHour: Int?
    let peakHourCount: Int
    let quietHours: ClosedRange<Int>?
    let newSpeciesNames: [String]
    let isToday: Bool
    /// Detection count for the day before the selected date, when known.
    let priorDayTotal: Int?
    /// Detection count for the day after the selected date, when the
    /// selected date isn't today and the API responded.
    let nextDayTotal: Int?
    /// Day-over-day trend vs `priorDayTotal`, only populated when both
    /// totals are known and the prior day had at least one detection
    /// (so percent change is defined).
    let priorDayTrend: DigestTrend?
    /// Local time-of-day bucket for the selected date. Only meaningful
    /// when `isToday` is true; for past days this is always `nil` so the
    /// copy doesn't sound like "this evening" while looking at last week.
    let timeOfDay: DigestTimeOfDay?

    var hasData: Bool {
        totalDetections > 0
    }

    static func make(
        from summaries: [DailySpeciesSummary],
        selectedDate: Date,
        neighborTotals: NeighborTotals = .empty,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DailyDigestStats {
        let total = summaries.reduce(0) { $0 + $1.count }
        let unique = summaries.count

        let topSpecies = summaries
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { SpeciesCount(commonName: $0.commonName, count: $0.count) }

        var hourly = Array(repeating: 0, count: 24)
        for summary in summaries {
            for (hour, count) in summary.normalizedHourlyCounts.enumerated() where hour < 24 {
                hourly[hour] += count
            }
        }

        var peakHour: Int?
        var peakHourCount = 0
        for (hour, count) in hourly.enumerated() where count > peakHourCount {
            peakHour = hour
            peakHourCount = count
        }

        let quietHours = total > 0 ? Self.longestQuietRange(in: hourly) : nil

        let newSpecies = summaries
            .filter { $0.isNewSpecies == true }
            .map(\.commonName)

        let isToday = calendar.isDate(selectedDate, inSameDayAs: now)

        let priorDayTrend = Self.makeTrend(current: total, prior: neighborTotals.priorDayTotal)
        let timeOfDay: DigestTimeOfDay? = isToday ? Self.timeOfDay(for: now, calendar: calendar) : nil

        return DailyDigestStats(
            totalDetections: total,
            uniqueSpecies: unique,
            topSpecies: Array(topSpecies),
            peakHour: peakHour,
            peakHourCount: peakHourCount,
            quietHours: quietHours,
            newSpeciesNames: newSpecies,
            isToday: isToday,
            priorDayTotal: neighborTotals.priorDayTotal,
            nextDayTotal: neighborTotals.nextDayTotal,
            priorDayTrend: priorDayTrend,
            timeOfDay: timeOfDay
        )
    }

    /// Returns the longest contiguous range of hours with zero detections,
    /// only if it spans 3 hours or more (so we don't mention trivial gaps).
    private static func longestQuietRange(in hourly: [Int]) -> ClosedRange<Int>? {
        var best: ClosedRange<Int>?
        var currentStart: Int?

        for hour in 0..<24 {
            if hourly[hour] == 0 {
                if currentStart == nil {
                    currentStart = hour
                }
                if hour == 23, let start = currentStart {
                    let candidate = start...hour
                    if candidate.count > (best?.count ?? 0) {
                        best = candidate
                    }
                }
            } else if let start = currentStart {
                let candidate = start...(hour - 1)
                if candidate.count > (best?.count ?? 0) {
                    best = candidate
                }
                currentStart = nil
            }
        }

        guard let best, best.count >= 3 else {
            return nil
        }
        return best
    }

    /// Builds a coarse day-over-day trend from the prior day's total. Only
    /// emits `.up` / `.down` when the change is at least 10% (and the
    /// underlying counts are non-trivial), so we don't dramatize noise.
    private static func makeTrend(current: Int, prior: Int?) -> DigestTrend? {
        guard let prior, prior > 0 else { return nil }
        let delta = current - prior
        let percent = Int((Double(abs(delta)) / Double(prior) * 100).rounded())
        guard percent >= 10 else { return .flat }
        return delta >= 0 ? .up(percent: percent) : .down(percent: percent)
    }

    private static func timeOfDay(for date: Date, calendar: Calendar) -> DigestTimeOfDay {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<7:   return .earlyMorning
        case 7..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default:      return .night
        }
    }
}

// MARK: - Card

struct DailyDigestCard: View {
    let stats: DailyDigestStats
    let dateTitle: String
    let intelligenceEnabled: Bool
    let intelligenceService: any IntelligenceService

    @State private var generatedCopy: DigestCopy?
    @State private var isGenerating = false

    init(
        stats: DailyDigestStats,
        dateTitle: String,
        intelligenceEnabled: Bool = false,
        intelligenceService: any IntelligenceService = DisabledIntelligenceService()
    ) {
        self.stats = stats
        self.dateTitle = dateTitle
        self.intelligenceEnabled = intelligenceEnabled
        self.intelligenceService = intelligenceService
    }

    private var shouldAttemptGeneration: Bool {
        intelligenceEnabled && intelligenceService.isAvailable && stats.hasData
    }

    private var displayingGeneratedCopy: Bool {
        generatedCopy != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if stats.hasData {
                Text(displayedHeadline)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = displayedDetail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !stats.topSpecies.isEmpty {
                    topSpeciesChips
                }
            } else {
                Text("No detections recorded for this day yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card, in: DS.Shape.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        // Re-generate when stats, date, or toggle change. Generation is
        // best-effort: a nil result silently keeps the deterministic copy.
        .task(id: GenerationKey(stats: stats, dateTitle: dateTitle, enabled: shouldAttemptGeneration)) {
            await regenerateIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 28, height: 28)
                .background(DS.AccentTint.soft, in: DS.Shape.inset)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Digest")
                    .font(.headline)
                Text(dateTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else if displayingGeneratedCopy {
                aiBadge
            }
        }
    }

    private var aiBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
                .font(.caption2.weight(.semibold))
            Text("AI summary")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(DS.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DS.AccentTint.soft, in: Capsule())
        .accessibilityLabel("AI generated summary")
    }

    private var topSpeciesChips: some View {
        HStack(spacing: 8) {
            ForEach(stats.topSpecies, id: \.commonName) { species in
                HStack(spacing: 4) {
                    Text(species.commonName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text("\(species.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DS.AccentTint.soft, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Copy

    /// Headline shown in the UI: prefer the validated, model-generated copy
    /// when present; fall back to the deterministic template otherwise.
    private var displayedHeadline: String {
        generatedCopy?.headline ?? headlineText
    }

    /// Detail line shown in the UI: prefer the model's optional second
    /// sentence; otherwise use the deterministic detail (which itself can
    /// be nil when there's nothing notable to add).
    private var displayedDetail: String? {
        if let detail = generatedCopy?.detail, !detail.isEmpty {
            return detail
        }
        return detailText
    }

    private func regenerateIfNeeded() async {
        // Always reset on any task-id change so a previously generated
        // string never lingers when the inputs change underneath us.
        generatedCopy = nil

        guard shouldAttemptGeneration else {
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        let copy = await intelligenceService.generateDailyDigestCopy(
            for: stats,
            dateTitle: dateTitle
        )

        // Only adopt the generation if the inputs haven't changed under us.
        // SwiftUI's `.task(id:)` already cancels and restarts on change, but
        // we still guard against a late delivery from a now-stale task.
        if !Task.isCancelled, let copy {
            generatedCopy = copy
        }
    }

    private var headlineText: String {
        let detections = pluralizedDetections(stats.totalDetections)
        let species = pluralizedSpecies(stats.uniqueSpecies)
        let dayWord = headlineDayWord
        return String(localized: "\(dayWord) your station has recorded \(detections) across \(species).")
    }

    /// Lead phrase for the headline. Today's view biases on the local
    /// clock so a morning glance feels different from an evening recap;
    /// past days always use the static "On this day," frame so we don't
    /// claim "this evening" while the user is paging through last week.
    private var headlineDayWord: String {
        guard stats.isToday else {
            return String(localized: "On this day,")
        }
        switch stats.timeOfDay {
        case .earlyMorning?: return String(localized: "So far this morning,")
        case .morning?:      return String(localized: "This morning,")
        case .afternoon?:    return String(localized: "This afternoon,")
        case .evening?:      return String(localized: "This evening,")
        case .night?:        return String(localized: "Tonight,")
        case nil:            return String(localized: "Today,")
        }
    }

    private var detailText: String? {
        var parts: [String] = []

        if let comparison = comparisonSentence {
            parts.append(comparison)
        }

        if let peakHour = stats.peakHour, stats.peakHourCount > 0 {
            let label = Self.hourLabel(peakHour)
            parts.append(String(localized: "Activity peaked around \(label)."))
        }

        if let quiet = stats.quietHours {
            let start = Self.hourLabel(quiet.lowerBound)
            let end = Self.hourLabel((quiet.upperBound + 1) % 24)
            parts.append(String(localized: "Quietest stretch was \(start)–\(end)."))
        }

        if !stats.newSpeciesNames.isEmpty {
            let names = ListFormatter.localizedString(byJoining: stats.newSpeciesNames)
            if stats.newSpeciesNames.count == 1 {
                parts.append(String(localized: "New today: \(names)."))
            } else {
                parts.append(String(localized: "New today: \(names)."))
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Optional day-over-day comparison phrase. Prefers the prior-day trend
    /// (which is what the user usually wants) and falls back to "more/less
    /// than the next day" when reviewing a past day with no prior-day
    /// signal but with a known next-day total.
    private var comparisonSentence: String? {
        if let trend = stats.priorDayTrend {
            switch trend {
            case .up(let percent):
                return String(localized: "That's \(percent)% more than the day before.")
            case .down(let percent):
                return String(localized: "That's \(percent)% less than the day before.")
            case .flat:
                return String(localized: "About on pace with the day before.")
            }
        }

        // Fallback: when the prior day didn't fire (no data, or no API
        // result), we can still anchor against the next day for past dates.
        if !stats.isToday,
           let next = stats.nextDayTotal,
           stats.totalDetections > 0 || next > 0 {
            if next > stats.totalDetections {
                return String(localized: "Quieter than the next day.")
            } else if next < stats.totalDetections {
                return String(localized: "Busier than the next day.")
            }
        }

        return nil
    }


    private var accessibilityLabel: String {
        let prefix = String(localized: "Daily digest for \(dateTitle).")
        guard stats.hasData else {
            return prefix + " " + String(localized: "No detections recorded for this day yet.")
        }
        let aiPrefix = displayingGeneratedCopy ? String(localized: "AI generated summary.") + " " : ""
        var text = prefix + " " + aiPrefix + displayedHeadline
        if let detail = displayedDetail {
            text += " " + detail
        }
        if !stats.topSpecies.isEmpty {
            let parts = stats.topSpecies.map { species in
                String(localized: "\(species.commonName), \(species.count) detections")
            }
            text += " " + String(localized: "Top species:") + " " + parts.joined(separator: ", ") + "."
        }
        return text
    }

    private func pluralizedDetections(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 detection")
            : String(localized: "\(count) detections")
    }

    private func pluralizedSpecies(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 species")
            : String(localized: "\(count) species")
    }

    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? Date()
        return Self.hourFormatter.string(from: date)
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter
    }()
}

/// Composite identity used to drive the card's `.task(id:)` so that
/// generation re-runs whenever the underlying inputs change.
private struct GenerationKey: Hashable {
    let stats: DailyDigestStats
    let dateTitle: String
    let enabled: Bool
}

#Preview("With data") {
    let summaries = [
        DailySpeciesSummary(
            scientificName: "Cardinalis cardinalis",
            commonName: "Northern Cardinal",
            count: 42,
            hourlyCounts: [0,0,0,0,0,1,8,12,9,5,2,1,0,0,0,1,2,1,0,0,0,0,0,0],
            isNewSpecies: false
        ),
        DailySpeciesSummary(
            scientificName: "Thryothorus ludovicianus",
            commonName: "Carolina Wren",
            count: 28,
            hourlyCounts: [0,0,0,0,0,0,5,8,6,4,2,1,1,0,0,0,1,0,0,0,0,0,0,0]
        ),
        DailySpeciesSummary(
            scientificName: "Baeolophus bicolor",
            commonName: "Tufted Titmouse",
            count: 19,
            hourlyCounts: Array(repeating: 1, count: 24),
            isNewSpecies: true
        )
    ]
    let stats = DailyDigestStats.make(from: summaries, selectedDate: Date())
    return DailyDigestCard(stats: stats, dateTitle: "Today")
        .padding()
        .background(DS.Surface.grouped)
}

#Preview("Empty") {
    DailyDigestCard(stats: DailyDigestStats.make(from: [], selectedDate: Date()), dateTitle: "Today")
        .padding()
        .background(DS.Surface.grouped)
}
