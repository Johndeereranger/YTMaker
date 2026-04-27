//
//  SentenceFidelityModels.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

// MARK: - Sentence Telemetry

/// Individual sentence with all tagged fields
struct SentenceTelemetry: Codable, Identifiable, Hashable {
    var id: Int { sentenceIndex }

    // Identity
    let sentenceIndex: Int
    let text: String
    let positionPercentile: Double  // 0.0 - 1.0

    // Surface structure (deterministic)
    let wordCount: Int
    let hasNumber: Bool
    let endsWithQuestion: Bool
    let endsWithExclamation: Bool

    // Lexical signals (keyword-based)
    let hasContrastMarker: Bool      // "but", "however", "yet", "actually"
    let hasTemporalMarker: Bool      // Years, dates, "then", "later"
    let hasFirstPerson: Bool         // "I", "me", "my"
    let hasSecondPerson: Bool        // "you", "your"

    // Content markers (LLM-interpreted)
    let hasStatistic: Bool           // Number with context
    let hasQuote: Bool               // Attributed speech
    let hasNamedEntity: Bool         // Specific person, company, study

    // Rhetorical markers (LLM-interpreted)
    let hasRevealLanguage: Bool      // "the truth is", "here's the thing"
    let hasPromiseLanguage: Bool     // "I'll show you", "let me explain"
    let hasChallengeLanguage: Bool   // "everyone thinks", "you've been told"

    // Stance (LLM-interpreted)
    let stance: String               // "asserting" | "questioning" | "challenging" | "neutral"

    // Perspective
    let perspective: String          // "first" | "second" | "third"

    // Structural markers
    let isTransition: Bool
    let isSponsorContent: Bool
    let isCallToAction: Bool

    // MARK: - Custom Decoding with Defaults

    enum CodingKeys: String, CodingKey {
        case sentenceIndex, text, positionPercentile
        case wordCount, hasNumber, endsWithQuestion, endsWithExclamation
        case hasContrastMarker, hasTemporalMarker, hasFirstPerson, hasSecondPerson
        case hasStatistic, hasQuote, hasNamedEntity
        case hasRevealLanguage, hasPromiseLanguage, hasChallengeLanguage
        case stance, perspective
        case isTransition, isSponsorContent, isCallToAction
        // Alternative keys Claude might use
        case index, sentence, content
        case position, position_percentile
        case word_count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // sentenceIndex - try multiple key names
        if let idx = try? container.decode(Int.self, forKey: .sentenceIndex) {
            sentenceIndex = idx
        } else if let idx = try? container.decode(Int.self, forKey: .index) {
            sentenceIndex = idx
        } else {
            // Default to -1 if not found (will be corrected by caller)
            sentenceIndex = -1
        }

        // text - try multiple key names
        if let txt = try? container.decode(String.self, forKey: .text) {
            text = txt
        } else if let txt = try? container.decode(String.self, forKey: .sentence) {
            text = txt
        } else if let txt = try? container.decode(String.self, forKey: .content) {
            text = txt
        } else {
            // Default to empty string (will be corrected by caller)
            text = ""
        }

        // Optional with defaults - try multiple key names
        if let pp = try? container.decode(Double.self, forKey: .positionPercentile) {
            positionPercentile = pp
        } else if let pp = try? container.decode(Double.self, forKey: .position) {
            positionPercentile = pp
        } else if let pp = try? container.decode(Double.self, forKey: .position_percentile) {
            positionPercentile = pp
        } else {
            positionPercentile = 0.0
        }

        if let wc = try? container.decode(Int.self, forKey: .wordCount) {
            wordCount = wc
        } else if let wc = try? container.decode(Int.self, forKey: .word_count) {
            wordCount = wc
        } else {
            wordCount = 0
        }

        // Boolean fields - decode with fallback for wrong types
        hasNumber = Self.decodeBool(container, key: .hasNumber)
        endsWithQuestion = Self.decodeBool(container, key: .endsWithQuestion)
        endsWithExclamation = Self.decodeBool(container, key: .endsWithExclamation)
        hasContrastMarker = Self.decodeBool(container, key: .hasContrastMarker)
        hasTemporalMarker = Self.decodeBool(container, key: .hasTemporalMarker)
        hasFirstPerson = Self.decodeBool(container, key: .hasFirstPerson)
        hasSecondPerson = Self.decodeBool(container, key: .hasSecondPerson)
        hasStatistic = Self.decodeBool(container, key: .hasStatistic)
        hasQuote = Self.decodeBool(container, key: .hasQuote)
        hasNamedEntity = Self.decodeBool(container, key: .hasNamedEntity)
        hasRevealLanguage = Self.decodeBool(container, key: .hasRevealLanguage)
        hasPromiseLanguage = Self.decodeBool(container, key: .hasPromiseLanguage)
        hasChallengeLanguage = Self.decodeBool(container, key: .hasChallengeLanguage)
        isTransition = Self.decodeBool(container, key: .isTransition)
        isSponsorContent = Self.decodeBool(container, key: .isSponsorContent)
        isCallToAction = Self.decodeBool(container, key: .isCallToAction)

        // String fields with defaults
        stance = try container.decodeIfPresent(String.self, forKey: .stance) ?? "neutral"
        perspective = try container.decodeIfPresent(String.self, forKey: .perspective) ?? "third"
    }

    /// Decode a boolean that might be missing, or might be an Int (0/1), or might be a Bool
    private static func decodeBool(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Bool {
        // Try Bool first
        if let value = try? container.decode(Bool.self, forKey: key) {
            return value
        }
        // Try Int (0 = false, non-zero = true)
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue != 0
        }
        // Try String ("true"/"false")
        if let strValue = try? container.decode(String.self, forKey: key) {
            return strValue.lowercased() == "true" || strValue == "1"
        }
        // Default to false if missing or undecodable
        return false
    }

    // MARK: - Custom Encoding (uses standard keys only)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sentenceIndex, forKey: .sentenceIndex)
        try container.encode(text, forKey: .text)
        try container.encode(positionPercentile, forKey: .positionPercentile)
        try container.encode(wordCount, forKey: .wordCount)
        try container.encode(hasNumber, forKey: .hasNumber)
        try container.encode(endsWithQuestion, forKey: .endsWithQuestion)
        try container.encode(endsWithExclamation, forKey: .endsWithExclamation)
        try container.encode(hasContrastMarker, forKey: .hasContrastMarker)
        try container.encode(hasTemporalMarker, forKey: .hasTemporalMarker)
        try container.encode(hasFirstPerson, forKey: .hasFirstPerson)
        try container.encode(hasSecondPerson, forKey: .hasSecondPerson)
        try container.encode(hasStatistic, forKey: .hasStatistic)
        try container.encode(hasQuote, forKey: .hasQuote)
        try container.encode(hasNamedEntity, forKey: .hasNamedEntity)
        try container.encode(hasRevealLanguage, forKey: .hasRevealLanguage)
        try container.encode(hasPromiseLanguage, forKey: .hasPromiseLanguage)
        try container.encode(hasChallengeLanguage, forKey: .hasChallengeLanguage)
        try container.encode(stance, forKey: .stance)
        try container.encode(perspective, forKey: .perspective)
        try container.encode(isTransition, forKey: .isTransition)
        try container.encode(isSponsorContent, forKey: .isSponsorContent)
        try container.encode(isCallToAction, forKey: .isCallToAction)
    }

    // Manual initializer for creating instances programmatically
    init(
        sentenceIndex: Int,
        text: String,
        positionPercentile: Double,
        wordCount: Int,
        hasNumber: Bool,
        endsWithQuestion: Bool,
        endsWithExclamation: Bool,
        hasContrastMarker: Bool,
        hasTemporalMarker: Bool,
        hasFirstPerson: Bool,
        hasSecondPerson: Bool,
        hasStatistic: Bool,
        hasQuote: Bool,
        hasNamedEntity: Bool,
        hasRevealLanguage: Bool,
        hasPromiseLanguage: Bool,
        hasChallengeLanguage: Bool,
        stance: String,
        perspective: String,
        isTransition: Bool,
        isSponsorContent: Bool,
        isCallToAction: Bool
    ) {
        self.sentenceIndex = sentenceIndex
        self.text = text
        self.positionPercentile = positionPercentile
        self.wordCount = wordCount
        self.hasNumber = hasNumber
        self.endsWithQuestion = endsWithQuestion
        self.endsWithExclamation = endsWithExclamation
        self.hasContrastMarker = hasContrastMarker
        self.hasTemporalMarker = hasTemporalMarker
        self.hasFirstPerson = hasFirstPerson
        self.hasSecondPerson = hasSecondPerson
        self.hasStatistic = hasStatistic
        self.hasQuote = hasQuote
        self.hasNamedEntity = hasNamedEntity
        self.hasRevealLanguage = hasRevealLanguage
        self.hasPromiseLanguage = hasPromiseLanguage
        self.hasChallengeLanguage = hasChallengeLanguage
        self.stance = stance
        self.perspective = perspective
        self.isTransition = isTransition
        self.isSponsorContent = isSponsorContent
        self.isCallToAction = isCallToAction
    }
}

// MARK: - Fidelity Test Result

/// A single test run storing all sentence telemetry
struct SentenceFidelityTest: Codable, Identifiable, Hashable {
    let id: String
    let videoId: String
    let channelId: String
    let videoTitle: String
    let createdAt: Date

    // Test metadata
    let runNumber: Int
    let promptVersion: String
    let modelUsed: String
    let temperature: Double?
    let taggingMode: String?  // "Bulk", "Per-Sentence", "Batched (10)"

    // Results
    let totalSentences: Int
    let sentences: [SentenceTelemetry]

    // Comparison (populated when comparing to another run)
    var comparedToRunId: String?
    var stabilityScore: Double?
    var fieldStability: [String: Double]?

    // Computed
    var durationSeconds: Double?

    // Hashable conformance (hash by id only)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SentenceFidelityTest, rhs: SentenceFidelityTest) -> Bool {
        lhs.id == rhs.id
    }

}

// MARK: - Comparison Result

/// Result of comparing two fidelity test runs
struct FidelityComparisonResult: Identifiable {
    let id = UUID()
    let run1: SentenceFidelityTest
    let run2: SentenceFidelityTest

    let overallStability: Double
    let fieldStability: [String: Double]
    let disagreements: [SentenceDisagreement]

    var unstableFields: [String] {
        fieldStability.filter { $0.value < 0.8 }.keys.sorted()
    }

    var stableFields: [String] {
        fieldStability.filter { $0.value >= 0.8 }.keys.sorted()
    }
}

/// A specific disagreement between two runs
struct SentenceDisagreement: Identifiable {
    var id: String { "\(sentenceIndex)_\(fieldName)" }
    let sentenceIndex: Int
    let sentenceText: String
    let fieldName: String
    let run1Value: String
    let run2Value: String
}

// MARK: - Field Definitions (for comparison)

enum SentenceTelemetryField: String, CaseIterable {
    // Booleans
    case hasNumber
    case endsWithQuestion
    case endsWithExclamation
    case hasContrastMarker
    case hasTemporalMarker
    case hasFirstPerson
    case hasSecondPerson
    case hasStatistic
    case hasQuote
    case hasNamedEntity
    case hasRevealLanguage
    case hasPromiseLanguage
    case hasChallengeLanguage
    case isTransition
    case isSponsorContent
    case isCallToAction

    // Enums
    case stance
    case perspective

    var isBoolean: Bool {
        switch self {
        case .stance, .perspective:
            return false
        default:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .hasNumber: return "Has Number"
        case .endsWithQuestion: return "Ends With ?"
        case .endsWithExclamation: return "Ends With !"
        case .hasContrastMarker: return "Contrast Marker"
        case .hasTemporalMarker: return "Temporal Marker"
        case .hasFirstPerson: return "First Person"
        case .hasSecondPerson: return "Second Person"
        case .hasStatistic: return "Has Statistic"
        case .hasQuote: return "Has Quote"
        case .hasNamedEntity: return "Named Entity"
        case .hasRevealLanguage: return "Reveal Language"
        case .hasPromiseLanguage: return "Promise Language"
        case .hasChallengeLanguage: return "Challenge Language"
        case .isTransition: return "Is Transition"
        case .isSponsorContent: return "Sponsor Content"
        case .isCallToAction: return "Call To Action"
        case .stance: return "Stance"
        case .perspective: return "Perspective"
        }
    }

    var category: FieldCategory {
        switch self {
        case .hasNumber, .endsWithQuestion, .endsWithExclamation:
            return .surface
        case .hasContrastMarker, .hasTemporalMarker, .hasFirstPerson, .hasSecondPerson:
            return .lexical
        case .hasStatistic, .hasQuote, .hasNamedEntity:
            return .content
        case .hasRevealLanguage, .hasPromiseLanguage, .hasChallengeLanguage:
            return .rhetorical
        case .stance, .perspective:
            return .interpretive
        case .isTransition, .isSponsorContent, .isCallToAction:
            return .structural
        }
    }

    enum FieldCategory: String, CaseIterable {
        case surface = "Surface"
        case lexical = "Lexical"
        case content = "Content"
        case rhetorical = "Rhetorical"
        case interpretive = "Interpretive"
        case structural = "Structural"
    }
}

// MARK: - Helper to extract field values

extension SentenceTelemetry {
    func value(for field: SentenceTelemetryField) -> String {
        switch field {
        case .hasNumber: return String(hasNumber)
        case .endsWithQuestion: return String(endsWithQuestion)
        case .endsWithExclamation: return String(endsWithExclamation)
        case .hasContrastMarker: return String(hasContrastMarker)
        case .hasTemporalMarker: return String(hasTemporalMarker)
        case .hasFirstPerson: return String(hasFirstPerson)
        case .hasSecondPerson: return String(hasSecondPerson)
        case .hasStatistic: return String(hasStatistic)
        case .hasQuote: return String(hasQuote)
        case .hasNamedEntity: return String(hasNamedEntity)
        case .hasRevealLanguage: return String(hasRevealLanguage)
        case .hasPromiseLanguage: return String(hasPromiseLanguage)
        case .hasChallengeLanguage: return String(hasChallengeLanguage)
        case .isTransition: return String(isTransition)
        case .isSponsorContent: return String(isSponsorContent)
        case .isCallToAction: return String(isCallToAction)
        case .stance: return stance
        case .perspective: return perspective
        }
    }
}

// MARK: - Aggregate Stability Analysis (Multiple Runs)

/// Aggregates stability data across ALL runs for a video
struct SentenceFidelityAggregateSummary {
    let videoId: String
    let videoTitle: String
    let runs: [SentenceFidelityTest]
    let sentenceCount: Int

    // Per-field stability across all runs (0.0 - 1.0)
    var fieldStability: [SentenceTelemetryField: Double] {
        var stability: [SentenceTelemetryField: Double] = [:]
        for field in SentenceTelemetryField.allCases {
            stability[field] = calculateFieldStability(for: field)
        }
        return stability
    }

    // Overall stability (average of all field stabilities)
    var overallStability: Double {
        let stabilities = fieldStability.values
        guard !stabilities.isEmpty else { return 0 }
        return stabilities.reduce(0, +) / Double(stabilities.count)
    }

    // Per-sentence stability (how stable is each sentence across runs)
    var sentenceStability: [Int: Double] {
        var stability: [Int: Double] = [:]
        for i in 0..<sentenceCount {
            stability[i] = calculateSentenceStability(at: i)
        }
        return stability
    }

    // Least stable sentences (for debugging)
    var leastStableSentences: [(index: Int, stability: Double, text: String)] {
        sentenceStability
            .sorted { $0.value < $1.value }
            .prefix(10)
            .compactMap { (index, stability) -> (Int, Double, String)? in
                guard let firstRun = runs.first,
                      index < firstRun.sentences.count else { return nil }
                return (index, stability, String(firstRun.sentences[index].text.prefix(80)))
            }
    }

    // Least stable fields
    var leastStableFields: [(field: SentenceTelemetryField, stability: Double)] {
        fieldStability
            .sorted { $0.value < $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }
    }

    // Most stable fields
    var mostStableFields: [(field: SentenceTelemetryField, stability: Double)] {
        fieldStability
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }
    }

    // Calculate stability for a specific field across all runs
    private func calculateFieldStability(for field: SentenceTelemetryField) -> Double {
        guard runs.count > 1 else { return 1.0 }

        var totalAgreements = 0
        var totalComparisons = 0

        for sentenceIndex in 0..<sentenceCount {
            // Get values for this sentence across all runs
            let values = runs.compactMap { run -> String? in
                guard sentenceIndex < run.sentences.count else { return nil }
                return run.sentences[sentenceIndex].value(for: field)
            }

            guard values.count > 1 else { continue }

            // Calculate mode agreement (what % agree with most common value)
            let modePct = modeAgreementPercentage(values)
            totalAgreements += Int(modePct * Double(values.count))
            totalComparisons += values.count
        }

        guard totalComparisons > 0 else { return 1.0 }
        return Double(totalAgreements) / Double(totalComparisons)
    }

    // Calculate stability for a specific sentence across all fields
    private func calculateSentenceStability(at index: Int) -> Double {
        guard runs.count > 1 else { return 1.0 }

        var fieldAgreements = 0
        var fieldCount = 0

        for field in SentenceTelemetryField.allCases {
            let values = runs.compactMap { run -> String? in
                guard index < run.sentences.count else { return nil }
                return run.sentences[index].value(for: field)
            }

            guard values.count > 1 else { continue }

            let modePct = modeAgreementPercentage(values)
            if modePct >= 0.5 { // Majority agreement
                fieldAgreements += 1
            }
            fieldCount += 1
        }

        guard fieldCount > 0 else { return 1.0 }
        return Double(fieldAgreements) / Double(fieldCount)
    }

    // Helper: calculate what % of values agree with the mode
    private func modeAgreementPercentage(_ values: [String]) -> Double {
        guard !values.isEmpty else { return 0 }
        var freq: [String: Int] = [:]
        for v in values { freq[v, default: 0] += 1 }
        let maxFreq = freq.values.max() ?? 0
        return Double(maxFreq) / Double(values.count)
    }

    // Get value distribution for a field at a sentence index
    func getDistribution(for field: SentenceTelemetryField, at sentenceIndex: Int) -> [String: Int] {
        var freq: [String: Int] = [:]
        for run in runs {
            guard sentenceIndex < run.sentences.count else { continue }
            let value = run.sentences[sentenceIndex].value(for: field)
            freq[value, default: 0] += 1
        }
        return freq
    }

    // Get overall distribution for a field across all sentences
    func getOverallDistribution(for field: SentenceTelemetryField) -> [String: Int] {
        var freq: [String: Int] = [:]
        for run in runs {
            for sentence in run.sentences {
                let value = sentence.value(for: field)
                freq[value, default: 0] += 1
            }
        }
        return freq
    }
}

/// Per-sentence stability detail for display
struct SentenceStabilityDetail: Identifiable {
    let id: Int  // sentence index
    let text: String
    let overallStability: Double
    let fieldStability: [SentenceTelemetryField: Double]
    let fieldDistributions: [SentenceTelemetryField: [String: Int]]

    var unstableFields: [SentenceTelemetryField] {
        fieldStability.filter { $0.value < 0.8 }.keys.sorted { $0.rawValue < $1.rawValue }
    }
}
