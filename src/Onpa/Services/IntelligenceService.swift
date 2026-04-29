import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Public types

/// Generated, model-authored copy for the Daily Digest card. Validated against
/// the source `DailyDigestStats` before it ever reaches the UI.
struct DigestCopy: Equatable, Sendable {
    /// Single-sentence summary of the day. Required.
    let headline: String
    /// Optional second sentence with a notable trend or new species. Empty
    /// string means "no detail to add" — callers should treat that the same
    /// as `nil`.
    let detail: String?
}

// MARK: - Service protocol

/// Centralized entry point for any feature that wants to layer Apple's
/// on-device Foundation Models on top of structured app data. The protocol
/// is intentionally narrow — services should only ever rephrase or summarize
/// data the caller has already fetched, never generate new facts.
protocol IntelligenceService: Sendable {
    /// True when the device has Apple Intelligence available and ready.
    /// Used to gate UI affordances ahead of any actual generation attempt.
    var isAvailable: Bool { get }

    /// Generates a plain-language summary of the supplied digest stats, in
    /// the user's preferred locale.
    ///
    /// - Returns: validated `DigestCopy`, or `nil` if generation is
    ///   unavailable, the toggle is off, the model is busy, or the output
    ///   failed validation. Callers must always have a deterministic
    ///   fallback ready.
    func generateDailyDigestCopy(for stats: DailyDigestStats, dateTitle: String) async -> DigestCopy?
}

// MARK: - Disabled fallback

/// No-op implementation used when the user toggle is off or the framework
/// is unavailable at compile time. Always returns `nil` so the card renders
/// its template path.
struct DisabledIntelligenceService: IntelligenceService {
    var isAvailable: Bool { false }

    func generateDailyDigestCopy(for stats: DailyDigestStats, dateTitle: String) async -> DigestCopy? {
        nil
    }
}

// MARK: - FoundationModels-backed implementation

#if canImport(FoundationModels)

/// On-device, Foundation-Models-backed implementation. Compile-gated so the
/// project still builds on Xcode versions without the iOS 26 SDK; runtime
/// guarded so the app never tries to generate on devices that don't support
/// Apple Intelligence.
@available(iOS 26.0, macOS 26.0, *)
struct FoundationModelsIntelligenceService: IntelligenceService {
    var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    func generateDailyDigestCopy(for stats: DailyDigestStats, dateTitle: String) async -> DigestCopy? {
        guard isAvailable else { return nil }

        let prompt = Self.makePrompt(for: stats, dateTitle: dateTitle)

        do {
            let session = LanguageModelSession(instructions: Self.systemInstructions)
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedDigestCopy.self
            )
            let copy = DigestCopy(
                headline: response.content.headline.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: response.content.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            )
            return Self.validate(copy, against: stats) ? copy : nil
        } catch {
            // Surfacing this to the user would be more confusing than just
            // showing the deterministic template, which already conveys the
            // same data.
            return nil
        }
    }

    // MARK: Prompt + schema

    /// The load-bearing system prompt. The strict, repeated "use only the
    /// JSON" framing is deliberate — it's the strongest mitigation we have
    /// against the model inventing species or behavior.
    private static let systemInstructions: String = """
    You write short, factual summaries of bird detection data from a user's BirdNET-Go station.
    Use ONLY the numbers and species names in the JSON the user supplies.
    Never invent species, locations, or behavior. Never give bird identification advice.
    Prefer concrete numbers ("38 species") over vague words ("many"). Times are in the station's local time.
    If the JSON includes a priorDayTotal or priorDayTrend, you may compare to the day before — but only using the percent in priorDayTrend, never with invented percentages.
    If timeOfDay is present (only when isToday is true), bias the opening so a morning summary feels different from an evening recap. Past days should not use phrases like "this evening" or "tonight".
    If the data is sparse or zero, say so briefly. Keep total output under 240 characters.
    Match the schema exactly. Do not include emoji.
    """

    private static func makePrompt(for stats: DailyDigestStats, dateTitle: String) -> String {
        let payload = PromptPayload(
            dateTitle: dateTitle,
            isToday: stats.isToday,
            timeOfDay: stats.timeOfDay?.rawValue,
            totalDetections: stats.totalDetections,
            uniqueSpecies: stats.uniqueSpecies,
            peakHour: stats.peakHour,
            peakHourCount: stats.peakHourCount,
            quietHoursStart: stats.quietHours?.lowerBound,
            quietHoursEnd: stats.quietHours.map { ($0.upperBound + 1) % 24 },
            topSpecies: stats.topSpecies.map { TopSpecies(commonName: $0.commonName, count: $0.count) },
            newSpeciesNames: stats.newSpeciesNames,
            priorDayTotal: stats.priorDayTotal,
            nextDayTotal: stats.nextDayTotal,
            priorDayTrend: PromptTrend(stats.priorDayTrend),
            languageTag: Locale.current.identifier
        )

        let json: String
        if let data = try? JSONEncoder().encode(payload),
           let string = String(data: data, encoding: .utf8) {
            json = string
        } else {
            json = "{}"
        }

        return """
        Summarize the day in dateTitle for this station, in language matching the locale tag in the JSON.
        Output a 1-sentence headline and an optional second sentence of detail.
        If a comparison to the day before is meaningful, mention it using the supplied trend.
        Stick strictly to the supplied JSON.

        \(json)
        """
    }

    @Generable
    fileprivate struct GeneratedDigestCopy {
        @Guide(description: "1 sentence summary of the day. Mention the total detection count and species count from the JSON. If timeOfDay is present, choose an opening that fits the part of day. No emoji. Under 140 characters.")
        let headline: String

        @Guide(description: "Optional second sentence noting peak hour, quietest stretch, new species, or a day-over-day comparison taken from priorDayTrend — only using values present in the JSON. Omit (empty string) if there is nothing notable. Under 120 characters.")
        let detail: String?
    }

    /// JSON payload sent to the model. Keeping this as an explicit type
    /// ensures we never accidentally include fields beyond what we intend.
    private struct PromptPayload: Encodable {
        let dateTitle: String
        let isToday: Bool
        let timeOfDay: String?
        let totalDetections: Int
        let uniqueSpecies: Int
        let peakHour: Int?
        let peakHourCount: Int
        let quietHoursStart: Int?
        let quietHoursEnd: Int?
        let topSpecies: [TopSpecies]
        let newSpeciesNames: [String]
        let priorDayTotal: Int?
        let nextDayTotal: Int?
        let priorDayTrend: PromptTrend?
        let languageTag: String
    }

    private struct TopSpecies: Encodable {
        let commonName: String
        let count: Int
    }

    /// Encodable mirror of `DigestTrend`. Splitting it out keeps the wire
    /// shape stable even if the in-memory enum gains more cases.
    private struct PromptTrend: Encodable {
        let direction: String  // "up" | "down" | "flat"
        let percent: Int       // 0 for "flat"

        init?(_ trend: DigestTrend?) {
            guard let trend else { return nil }
            switch trend {
            case .up(let percent):   self.direction = "up";   self.percent = percent
            case .down(let percent): self.direction = "down"; self.percent = percent
            case .flat:              self.direction = "flat"; self.percent = 0
            }
        }
    }

    // MARK: Validation

    /// Single most important guardrail in this file. Any species name the
    /// model emits MUST appear in the supplied stats; otherwise we discard
    /// the generation entirely.
    static func validate(_ copy: DigestCopy, against stats: DailyDigestStats) -> Bool {
        guard !copy.headline.isEmpty, copy.headline.count <= 240 else { return false }
        if let detail = copy.detail, detail.count > 240 { return false }

        let knownSpecies = Set(
            (stats.topSpecies.map(\.commonName) + stats.newSpeciesNames)
                .map { $0.lowercased() }
        )

        let combined = (copy.headline + " " + (copy.detail ?? "")).lowercased()

        // Build a pool of species-shaped tokens the model might have used:
        // any contiguous run of capitalized words from the original strings.
        let allText = copy.headline + " " + (copy.detail ?? "")
        let mentionedSpecies = Self.extractSpeciesCandidates(in: allText).map { $0.lowercased() }

        for candidate in mentionedSpecies {
            // Only flag candidates that look like full species names
            // (multiple capitalized words) and aren't in the known set.
            // Single-word candidates are too noisy ("Today", "Activity").
            guard candidate.split(separator: " ").count >= 2 else { continue }
            if !knownSpecies.contains(where: { $0 == candidate || candidate.contains($0) || $0.contains(candidate) }) {
                return false
            }
        }

        // Reject if the model contradicts the headline numbers wildly.
        if stats.totalDetections == 0, combined.contains("detection") == false, combined.contains("recorded") == false {
            // Empty days should at least acknowledge the absence; if the
            // model wrote something irrelevant, fall back.
            return combined.contains("no ") || combined.contains("quiet") || combined.contains("0 ")
        }

        return true
    }

    /// Cheap heuristic species-name extractor: contiguous runs of two or
    /// more capitalized words. Good enough for validation, not meant to
    /// be a real NER.
    private static func extractSpeciesCandidates(in text: String) -> [String] {
        var results: [String] = []
        var current: [String] = []

        for raw in text.split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
            let token = String(raw)
            if let first = token.first, first.isUppercase {
                current.append(token)
            } else {
                if current.count >= 2 {
                    results.append(current.joined(separator: " "))
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= 2 {
            results.append(current.joined(separator: " "))
        }
        return results
    }
}

#endif

// MARK: - Factory

enum IntelligenceServiceFactory {
    /// Returns the appropriate concrete service. Always returns a non-nil
    /// value — the disabled fallback when Foundation Models isn't compiled
    /// in or available at runtime.
    static func make() -> any IntelligenceService {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return FoundationModelsIntelligenceService()
        }
        #endif
        return DisabledIntelligenceService()
    }
}

// MARK: - Helpers

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
