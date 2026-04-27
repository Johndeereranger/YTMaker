//
//  ScriptFidelityModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/18/26.
//
//  Data models for the deterministic Script Fidelity Evaluator.
//  Three layers: Baseline calibration, Hard-fail checks, Dimensional scoring.
//

import Foundation

// MARK: - Fidelity Dimensions

enum FidelityDimension: String, Codable, CaseIterable, Identifiable {
    case sentenceMechanics
    case vocabularyRegister
    case structuralShape
    case slotSignatureFidelity
    case rhythmCadence
    case contentCoverage
    case stanceTempo
    case donorSentenceSimilarity
    case slotSignatureS2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sentenceMechanics:        return "Sentence Mechanics"
        case .vocabularyRegister:       return "Vocabulary & Register"
        case .structuralShape:          return "Structural Shape"
        case .slotSignatureFidelity:    return "Slot Signature Fidelity"
        case .rhythmCadence:            return "Rhythm & Cadence"
        case .contentCoverage:          return "Content Coverage"
        case .stanceTempo:              return "Stance & Tempo"
        case .donorSentenceSimilarity:  return "Donor Similarity"
        case .slotSignatureS2:          return "Slot Signature S2"
        }
    }

    var shortLabel: String {
        switch self {
        case .sentenceMechanics:        return "Mech"
        case .vocabularyRegister:       return "Vocab"
        case .structuralShape:          return "Shape"
        case .slotSignatureFidelity:    return "Slots"
        case .rhythmCadence:            return "Rhythm"
        case .contentCoverage:          return "Cover"
        case .stanceTempo:              return "Stance"
        case .donorSentenceSimilarity:  return "Donor"
        case .slotSignatureS2:          return "S2"
        }
    }
}

// MARK: - Baseline Profile (Layer 0)

/// Per-creator distribution of scores across the 8 dimensions,
/// computed from the creator's own corpus. Every evaluation score
/// is measured relative to this baseline.
struct BaselineProfile: Codable {
    let creatorId: String
    let computedAt: Date
    let dimensionRanges: [String: DimensionRange]             // keyed by FidelityDimension.rawValue
    let sectionBaselines: [String: [String: DimensionRange]]  // moveType → dimension → range
    let sampleCount: Int                                       // total sections evaluated
}

struct DimensionRange: Codable {
    let min: Double
    let p25: Double
    let median: Double
    let p75: Double
    let max: Double
    let sampleCount: Int

    /// IQR width (interquartile range).
    var iqr: Double { p75 - p25 }

    /// Score a raw value relative to this baseline.
    /// Returns 0-100 where 100 = at median, 50 = at IQR boundary, 0 = beyond 3× IQR width.
    func score(rawValue: Double) -> Double {
        guard iqr > 0 else {
            // Degenerate case: all corpus values identical
            return rawValue == median ? 100.0 : 0.0
        }
        let distance = abs(rawValue - median)
        let normalizedDistance = distance / iqr
        // 0 distance → 100, 0.5 IQR → 75, 1.0 IQR → 50, 3.0 IQR → 0
        let score = Swift.max(0.0, 100.0 - (normalizedDistance * 50.0))
        return Swift.min(100.0, score)
    }
}

// MARK: - Hard-Fail Layer (Layer 1)

enum HardFailMetric: String, Codable, CaseIterable, Identifiable {
    case firstPersonRate
    case secondPersonRate
    case contractionRate
    case sentenceCount
    case avgSentenceLength
    case questionDensity
    case fragmentRate
    case wordCount
    case maxConsecutiveSameOpener
    case uniqueOpenerRatio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstPersonRate:            return "First-Person Rate"
        case .secondPersonRate:           return "Second-Person Rate"
        case .contractionRate:            return "Contraction Rate"
        case .sentenceCount:              return "Sentence Count"
        case .avgSentenceLength:          return "Avg Sentence Length"
        case .questionDensity:            return "Question Density"
        case .fragmentRate:               return "Fragment Rate"
        case .wordCount:                  return "Word Count"
        case .maxConsecutiveSameOpener:   return "Max Same Opener Run"
        case .uniqueOpenerRatio:          return "Unique Opener Ratio"
        }
    }
}

enum HardFailComparison: String, Codable {
    case greaterThan
    case lessThan
}

enum ThresholdMode: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case absolute
    case corpusMultiplier

    var displayName: String {
        switch self {
        case .absolute:          return "Absolute"
        case .corpusMultiplier:  return "× Corpus Rate"
        }
    }
}

enum HardFailSeverity: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case fail
    case warn

    var displayName: String {
        switch self {
        case .fail: return "Hard Fail"
        case .warn: return "Warning"
        }
    }
}

struct HardFailRule: Codable, Identifiable {
    let id: UUID
    var label: String
    var metric: HardFailMetric
    var comparison: HardFailComparison
    var threshold: Double
    var thresholdMode: ThresholdMode
    var isEnabled: Bool
    var severity: HardFailSeverity

    static func defaultRules() -> [HardFailRule] {
        [
            HardFailRule(
                id: UUID(), label: "First-person overuse",
                metric: .firstPersonRate, comparison: .greaterThan,
                threshold: 2.0, thresholdMode: .corpusMultiplier,
                isEnabled: true, severity: .fail
            ),
            HardFailRule(
                id: UUID(), label: "Second-person overuse",
                metric: .secondPersonRate, comparison: .greaterThan,
                threshold: 2.5, thresholdMode: .corpusMultiplier,
                isEnabled: true, severity: .fail
            ),
            HardFailRule(
                id: UUID(), label: "Sentence count out of range",
                metric: .sentenceCount, comparison: .greaterThan,
                threshold: 2.0, thresholdMode: .corpusMultiplier,
                isEnabled: true, severity: .fail
            ),
            HardFailRule(
                id: UUID(), label: "No opener diversity",
                metric: .uniqueOpenerRatio, comparison: .lessThan,
                threshold: 0.5, thresholdMode: .absolute,
                isEnabled: true, severity: .warn
            ),
            HardFailRule(
                id: UUID(), label: "Word count blow-up",
                metric: .wordCount, comparison: .greaterThan,
                threshold: 2.0, thresholdMode: .corpusMultiplier,
                isEnabled: true, severity: .fail
            ),
            HardFailRule(
                id: UUID(), label: "Question spam",
                metric: .questionDensity, comparison: .greaterThan,
                threshold: 3.0, thresholdMode: .corpusMultiplier,
                isEnabled: true, severity: .warn
            ),
        ]
    }
}

// MARK: - Hard-Fail Result

struct HardFailResult: Identifiable {
    let id = UUID()
    let rule: HardFailRule
    let actualValue: Double
    let corpusValue: Double
    let effectiveThreshold: Double
    let passed: Bool

    var displayMessage: String {
        let valueStr = String(format: "%.2f", actualValue)
        let corpusStr = String(format: "%.2f", corpusValue)
        let threshStr = String(format: "%.2f", effectiveThreshold)
        if passed {
            return "\(rule.label): \(valueStr) (corpus: \(corpusStr), limit: \(threshStr)) — OK"
        } else {
            return "\(rule.label): \(valueStr) (corpus: \(corpusStr), limit: \(threshStr))"
        }
    }
}

// MARK: - Dimension Scoring (Layer 2)

struct DimensionScore: Codable {
    let dimension: FidelityDimension
    let score: Double                           // 0-100, relative to baseline
    let subMetrics: [SubMetricScore]            // Breakdowns
    let baselineRange: DimensionRange?          // Creator's own range for context
}

struct SubMetricScore: Codable {
    let name: String
    let rawValue: Double
    let corpusMean: Double
    let score: Double                           // 0-100
    let tolerance: Double?                      // actual tolerance used by proximityScore (nil for non-proximity metrics)

    init(name: String, rawValue: Double, corpusMean: Double, score: Double, tolerance: Double? = nil) {
        self.name = name
        self.rawValue = rawValue
        self.corpusMean = corpusMean
        self.score = score
        self.tolerance = tolerance
    }
}

// MARK: - Section-Level Result

struct SectionFidelityResult: Identifiable {
    let id = UUID()
    let sectionIndex: Int
    let sectionText: String
    let sentenceCount: Int
    let wordCount: Int
    let dimensionScores: [FidelityDimension: DimensionScore]
    let hardFailResults: [HardFailResult]
    let compositeScore: Double

    var hasHardFail: Bool {
        hardFailResults.contains { !$0.passed && $0.rule.severity == .fail }
    }

    var hasWarning: Bool {
        hardFailResults.contains { !$0.passed && $0.rule.severity == .warn }
    }

    var failedRules: [HardFailResult] {
        hardFailResults.filter { !$0.passed && $0.rule.severity == .fail }
    }

    var warningRules: [HardFailResult] {
        hardFailResults.filter { !$0.passed && $0.rule.severity == .warn }
    }
}

// MARK: - Full Evaluation Result

struct FidelityScore: Codable, Identifiable {
    let id: UUID
    let evaluatedAt: Date
    let compositeScore: Double                  // Weighted average of dimension scores
    let dimensionScores: [String: DimensionScore]  // keyed by FidelityDimension.rawValue
    let hardFailCount: Int
    let warningCount: Int
    let weightProfileName: String

    init(
        compositeScore: Double,
        dimensionScores: [FidelityDimension: DimensionScore],
        hardFailCount: Int,
        warningCount: Int,
        weightProfileName: String
    ) {
        self.id = UUID()
        self.evaluatedAt = Date()
        self.compositeScore = compositeScore
        self.dimensionScores = Dictionary(uniqueKeysWithValues:
            dimensionScores.map { ($0.key.rawValue, $0.value) }
        )
        self.hardFailCount = hardFailCount
        self.warningCount = warningCount
        self.weightProfileName = weightProfileName
    }

    func score(for dimension: FidelityDimension) -> DimensionScore? {
        dimensionScores[dimension.rawValue]
    }
}

// MARK: - Weight Profile

struct FidelityWeightProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var dimensionWeights: [String: Double]       // keyed by FidelityDimension.rawValue, must sum to 1.0
    var hardFailRules: [HardFailRule]
    var createdAt: Date
    var notes: String

    init(
        name: String,
        dimensionWeights: [FidelityDimension: Double]? = nil,
        hardFailRules: [HardFailRule]? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.notes = notes
        self.hardFailRules = hardFailRules ?? HardFailRule.defaultRules()

        if let weights = dimensionWeights {
            self.dimensionWeights = Dictionary(uniqueKeysWithValues:
                weights.map { ($0.key.rawValue, $0.value) }
            )
        } else {
            // Equal weights
            let equalWeight = 1.0 / Double(FidelityDimension.allCases.count)
            self.dimensionWeights = Dictionary(uniqueKeysWithValues:
                FidelityDimension.allCases.map { ($0.rawValue, equalWeight) }
            )
        }
    }

    func weight(for dimension: FidelityDimension) -> Double {
        dimensionWeights[dimension.rawValue] ?? 0.0
    }

    mutating func setWeight(_ value: Double, for dimension: FidelityDimension) {
        dimensionWeights[dimension.rawValue] = value
    }

    /// Normalize weights to sum to 1.0, preserving ratios.
    mutating func normalizeWeights() {
        let total = dimensionWeights.values.reduce(0.0, +)
        guard total > 0 else { return }
        for key in dimensionWeights.keys {
            dimensionWeights[key]! /= total
        }
    }

    static func equalWeights() -> FidelityWeightProfile {
        FidelityWeightProfile(name: "Equal Weights")
    }
}

// MARK: - Metric Range (for rangeScore-based metrics)

/// Distribution range for a corpus metric, used by rangeScore().
/// Codable-safe. Computed once from per-section arrays in buildCorpusStats().
struct MetricRange: Codable {
    let min: Double
    let p25: Double
    let p75: Double
    let max: Double
    var iqr: Double { p75 - p25 }
}

// MARK: - Corpus Stats (computed from CreatorSentences, persisted in FidelityCorpusCache)

/// Pre-aggregated corpus statistics needed by the evaluator.
/// Computed once from the creator's sentence corpus and persisted.
/// All fields are Codable-safe (no Set<String> — use [String] and convert at call site).
// WARNING: Adding/removing/renaming fields here invalidates all saved FidelityCorpusCache
// files on disk. After changing this struct, users must re-run "Compute Fidelity Baseline"
// in the Structure Workbench. The stale file is auto-deleted on decode failure —
// see FidelityStorage.loadCorpusCache / saveCorpusCache for the persistence counterpart.
struct CorpusStats: Codable {
    let creatorId: String

    // Per-sentence aggregates
    let avgSentenceLength: Double               // words per sentence
    let sentenceLengthVariance: Double
    let avgClauseCount: Double
    let questionRate: Double                     // questions / total sentences
    let fragmentRate: Double                     // fragments / total sentences

    // Word frequency rates
    let firstPersonRate: Double                  // first-person words per sentence
    let secondPersonRate: Double                 // second-person words per sentence
    let contractionRate: Double                  // contractions per sentence

    // Opener patterns
    let openerDistribution: [String: Double]     // first word → frequency
    let uniqueOpenerRatio: Double                // distinct openers / total sentences

    // Per-moveType sentence counts
    let sentencesPerMove: [String: Double]       // moveType → median sentence count

    // Word count per section
    let avgWordCountPerSection: Double
    let wordCountPerMove: [String: Double]       // moveType → median word count

    // Donor n-grams (precomputed from CreatorSentence corpus)
    let trigramIndex: [String: Int]              // trigram → count across corpus

    // Direct address rate
    let directAddressRate: Double                // sentences with direct address / total

    // Sentence hint distributions
    let hintRates: [String: Double]              // hint name → rate (e.g. "hasTemporalMarker" → 0.15)

    // Casual markers (as array for Codable)
    let casualMarkers: [String]                  // known casual markers from corpus

    // Per-section aggregates (computed from real section groupings)
    let vocabularyDensity: Double                // median unique-words/total-words per section
    let corpusEngagement: Double                 // median engagement score per section

    // Pre-aggregated slot/donor data (eliminates need for raw donor sentences at eval time)
    let slotSignaturesByMove: [String: [String]]       // moveType → known slot signatures
    let openerSlotSignaturesByMove: [String: [String]]  // moveType → signatures at sentence index 0
    let slotBigramsByMove: [String: [String]]           // moveType → "sig1→sig2" bigram strings
    let openingPatternSet: [String]                     // all known first-word patterns from corpus

    // Per-section distribution quartiles (for IQR-based scorer tolerances)
    let sentenceCountP25: Double
    let sentenceCountP75: Double
    let wordCountPerSectionP25: Double
    let wordCountPerSectionP75: Double
    let lengthVarianceP25: Double
    let lengthVarianceP75: Double

    // Closing slot signatures (heuristic-extracted, matches opener extraction)
    let closerSlotSignaturesByMove: [String: [String]]  // moveType → signatures at last sentence

    // Corpus-derived bigram match rate (median across sections)
    let corpusBigramMatchRate: Double

    // Precomputed per-section sub-metric distributions (for size-independent tolerances)
    let corpusOpenerOverlapMedian: Double       // D2: median opener overlap rate across sections
    let corpusOpenerOverlapSD: Double           // D2: SD of opener overlap rate across sections
    let corpusOpenerPatternMatchMedian: Double  // D8: median opener pattern hit rate across sections
    let corpusOpenerPatternMatchSD: Double      // D8: SD of opener pattern hit rate across sections
    let corpusHintDiffMedian: Double            // D8: median avg hint rate diff across sections
    let corpusHintDiffSD: Double                // D8: SD of avg hint rate diff across sections

    // Per-section SD for every proximityScore tolerance (precomputed from ~77 sections)
    let corpusAvgSentenceLengthSD: Double       // D1 + D7: SD of per-section avg sentence length
    let corpusQuestionDensitySD: Double         // D1: SD of per-section question density
    let corpusFragmentRateSD: Double            // D1: SD of per-section fragment rate
    let corpusFirstPersonRateSD: Double         // D2: SD of per-section first-person rate (binary)
    let corpusContractionRateSD: Double         // D2: SD of per-section contraction rate (binary)
    let corpusDirectAddressRateSD: Double       // D2: SD of per-section direct address rate
    let corpusBigramRateSD: Double              // D4: SD of per-section bigram match rate
    let corpusWordCountSD: Double               // D3 + D6: SD of per-section word count
    let corpusVocabularyDensitySD: Double       // D6: SD of per-section vocabulary density
    let corpusEngagementSD: Double              // D7: SD of per-section engagement score
    let corpusAlternationSD: Double             // D5: SD of per-section alternation rate

    // Per-section median + SD for sub-metrics that previously used hardcoded corpusMean values
    let corpusCasualMarkerMedian: Double        // D2: median casual marker count per section
    let corpusCasualMarkerSD: Double            // D2: SD of casual marker count per section
    let corpusSignatureMatchMedian: Double      // D4: median heuristic sig match rate per section
    let corpusSignatureMatchSD: Double          // D4: SD of sig match rate per section
    let corpusWordCountInRangeMedian: Double    // D5: median word-count-in-range rate per section
    let corpusWordCountInRangeSD: Double        // D5: SD of word-count-in-range rate per section
    let corpusTypeMatchMedian: Double           // D5: median sentence type match rate per section
    let corpusTypeMatchSD: Double               // D5: SD of type match rate per section
    let corpusAlternationMedian: Double         // D5: median alternation rate (replaces hardcoded 0.5)
    let corpusTrigramOverlapMedian: Double      // D8: median trigram overlap rate per section
    let corpusTrigramOverlapSD: Double          // D8: SD of trigram overlap rate per section

    // D3: opener/closer signature overlap rates across sections
    let corpusOpenerSigOverlapMedian: Double    // D3: median opener sig overlap rate
    let corpusOpenerSigOverlapSD: Double        // D3: SD of opener sig overlap rate
    let corpusCloserSigOverlapMedian: Double    // D3: median closer sig overlap rate
    let corpusCloserSigOverlapSD: Double        // D3: SD of closer sig overlap rate

    // S2: Raw (unrolled) slot signature aggregate stats for S2 dimension
    let corpusRawSignatureMatchMedian: Double   // S2: median raw sig match rate per section
    let corpusRawSignatureMatchSD: Double       // S2: SD of raw sig match rate per section
    let corpusRawBigramMatchRate: Double        // S2: median raw bigram match rate across sections
    let corpusRawBigramRateSD: Double           // S2: SD of raw bigram match rate per section

    // S2: Per-move frequency distributions (slotType → proportion of total sentences)
    let rawSlotDistributionByMove: [String: [String: Double]]    // moveType → {slotType: fraction}
    let rawBigramDistributionByMove: [String: [String: Double]]  // moveType → {"sig→sig": fraction}
    let rawOpenerDistributionByMove: [String: [String: Double]]  // moveType → {openerSlot: fraction}

    // S2: Corpus baseline cosine similarity stats (for proximityScore tolerance)
    let corpusSlotDistCosinMedian: Double    // median per-section cosine sim vs corpus distribution
    let corpusSlotDistCosinSD: Double        // SD of per-section cosine sim
    let corpusBigramDistCosinMedian: Double  // median per-section bigram cosine sim
    let corpusBigramDistCosinSD: Double      // SD of per-section bigram cosine sim

    // Rolled-up slot data (dominant-slot rollup of LLM-assigned signatures)
    let rolledSlotSignaturesByMove: [String: [String]]
    let rolledOpenerSlotSignaturesByMove: [String: [String]]
    let rolledCloserSlotSignaturesByMove: [String: [String]]
    let rolledSlotBigramsByMove: [String: [String]]

    // Frequency distribution: moveType → rolledSig → fraction of sections using that sig
    // Used for D3 Opening/Closing Sig Match — frequency-weighted instead of binary set-membership
    let rolledOpenerSigFreqByMove: [String: [String: Double]]
    let rolledCloserSigFreqByMove: [String: [String: Double]]

    // D3: Sentence length tertile boundaries (derived from all corpus sentence lengths)
    // Sentences with wordCount <= shortSentenceMax are "short"; >= longSentenceMin are "long"
    let shortSentenceMax: Int
    let longSentenceMin: Int

    // D5: Cadence transition matrix — transition probabilities between length buckets
    // Keys: "short→short", "short→medium", "short→long", "medium→short", etc.
    let cadenceTransitionMatrix: [String: Double]

    // Per-metric distribution ranges for rangeScore() (replaces proximityScore for range metrics)
    // Keys: "firstPersonRate", "contractionRate", "casualMarkers", "directAddressRate",
    //        "sentenceCount", "wordCount", "alternation", "engagement",
    //        "shortPct", "mediumPct", "longPct", "cadenceFit"
    let rangeDistributions: [String: MetricRange]

    // MARK: Computed IQR Helpers

    var sentenceCountIQR: Double { sentenceCountP75 - sentenceCountP25 }
    var wordCountIQR: Double { wordCountPerSectionP75 - wordCountPerSectionP25 }
    var lengthVarianceIQR: Double { lengthVarianceP75 - lengthVarianceP25 }

    /// Convenience: get casual markers as Set for matching.
    var casualMarkerSet: Set<String> { Set(casualMarkers) }

    /// Convenience: get slot signatures as Set for a move type.
    func slotSignatures(forMove move: String) -> Set<String> {
        Set(slotSignaturesByMove[move] ?? [])
    }

    func openerSlotSignatures(forMove move: String) -> Set<String> {
        Set(openerSlotSignaturesByMove[move] ?? [])
    }

    func slotBigrams(forMove move: String) -> Set<String> {
        Set(slotBigramsByMove[move] ?? [])
    }

    func closerSlotSignatures(forMove move: String) -> Set<String> {
        Set(closerSlotSignaturesByMove[move] ?? [])
    }

    var openingPatterns: Set<String> { Set(openingPatternSet) }

    func rolledSlotSignatures(forMove move: String) -> Set<String> {
        Set(rolledSlotSignaturesByMove[move] ?? [])
    }

    func rolledOpenerSlotSignatures(forMove move: String) -> Set<String> {
        Set(rolledOpenerSlotSignaturesByMove[move] ?? [])
    }

    func rolledCloserSlotSignatures(forMove move: String) -> Set<String> {
        Set(rolledCloserSlotSignaturesByMove[move] ?? [])
    }

    func rolledSlotBigrams(forMove move: String) -> Set<String> {
        Set(rolledSlotBigramsByMove[move] ?? [])
    }

    /// Frequency of a specific rolled opener sig among corpus sections of the same move type.
    /// Returns 0.0 if the sig was never seen in the corpus.
    func openerSigFrequency(forMove move: String, sig: String) -> Double {
        rolledOpenerSigFreqByMove[move]?[sig] ?? 0.0
    }

    /// Frequency of a specific rolled closer sig among corpus sections of the same move type.
    func closerSigFrequency(forMove move: String, sig: String) -> Double {
        rolledCloserSigFreqByMove[move]?[sig] ?? 0.0
    }

    /// S2: Raw slot frequency distribution for a move type (slotType → proportion).
    func rawSlotDistribution(forMove move: String) -> [String: Double] {
        rawSlotDistributionByMove[move] ?? [:]
    }

    /// S2: Raw bigram frequency distribution for a move type ("sig→sig" → proportion).
    func rawBigramDistribution(forMove move: String) -> [String: Double] {
        rawBigramDistributionByMove[move] ?? [:]
    }

    /// S2: Raw opener slot frequency distribution for a move type (slotType → proportion).
    func rawOpenerDistribution(forMove move: String) -> [String: Double] {
        rawOpenerDistributionByMove[move] ?? [:]
    }

    /// Get the precomputed distribution range for a named metric (used by rangeScore).
    /// Returns nil if the metric wasn't computed (should not happen for known metrics).
    func metricRange(_ name: String) -> MetricRange? {
        rangeDistributions[name]
    }
}

// MARK: - Fidelity Corpus Cache (persisted per creator)

/// Self-contained evaluation cache computed in the Structure Workbench.
/// Includes everything the compare tab needs to evaluate scripts
/// without loading anything from Firebase.
struct FidelityCorpusCache: Codable {
    let creatorId: String
    let computedAt: Date
    let corpusStats: CorpusStats
    let baseline: BaselineProfile
    let sectionProfiles: [SectionProfile]
    let rhythmTemplates: [RhythmTemplate]
    let sentenceCount: Int                       // for display (how many sentences fed baseline)
}

// MARK: - Parsed Section (intermediate representation for scoring)

/// A generated script section parsed into sentence-level metrics for scoring.
struct ParsedSection {
    let index: Int
    let rawText: String
    let sentences: [ParsedSentence]
    let moveType: String?                        // if known from chain position

    var sentenceCount: Int { sentences.count }
    var wordCount: Int { sentences.map(\.wordCount).reduce(0, +) }
    var avgSentenceLength: Double {
        guard !sentences.isEmpty else { return 0 }
        return Double(wordCount) / Double(sentences.count)
    }
}

struct ParsedSentence {
    let index: Int
    let text: String
    let words: [String]
    let wordCount: Int
    let isQuestion: Bool
    let isFragment: Bool
    let hasDirectAddress: Bool
    let firstWord: String
    let firstPersonCount: Int                    // "I", "me", "my", "we", "us", "our"
    let secondPersonCount: Int                   // "you", "your", "yours"
    let contractionCount: Int
    let trigrams: [String]                       // 3-word sequences for donor matching
    let deterministicHints: Set<String>          // from SentenceHints-style regex checks
}

// MARK: - S2 Annotation Cache (persisted per section text)

/// Cached result of an LLM slot annotation call for a section of text.
/// Keyed by SHA-256 hash of the section text so identical text reuses the same annotations.
struct S2CacheEntry: Codable {
    let textHash: String
    let sectionText: String
    let s2Signatures: [String]
    let annotations: [CachedSlotAnnotation]
    let timestamp: Date
    let modelUsed: String
}

struct CachedSlotAnnotation: Codable {
    let sentenceText: String
    let slotSequence: [String]
    let sentenceFunction: String
}

// MARK: - Slot Debugger Data

struct SlotDebugData {
    struct SentenceSlotDebug: Identifiable {
        let id: Int
        let text: String
        let wordCount: Int
        let hints: [String]
        let heuristicSig: String
        let rolledSig: String
        let d4Matched: Bool
        let s2Source: String           // "LLM" or "hint"
        let s2Sig: String
        let s2Matched: Bool

        // Prompt spec (what was ASKED for)
        let targetSig: String?
        let targetWordRange: String?       // e.g. "10-20"
        let targetSentenceType: String?    // "statement" / "question" / "fragment"
        let targetTopic: String?           // donor/gist text sent in prompt
    }

    struct BigramDebug: Identifiable {
        var id: String { "\(from)→\(to)" }
        let from: String
        let to: String
        let matched: Bool
    }

    let sentences: [SentenceSlotDebug]
    let d4Bigrams: [BigramDebug]
    let s2Bigrams: [BigramDebug]
    let corpusRolledSigs: [(sig: String, count: Int)]
    let corpusRawSigs: [(sig: String, count: Int)]
    let corpusRolledOpeners: [String]
    let corpusRawOpeners: [String]
    let corpusRolledBigrams: [(bigram: String, count: Int)]
    let corpusRawBigrams: [(bigram: String, count: Int)]
    let d4ScoreExplanation: String
    let s2ScoreExplanation: String

    // S2 distribution comparison data (additive — existing fields above stay)
    let corpusSlotDistribution: [(sig: String, fraction: Double)]     // corpus dist sorted desc
    let generatedSlotDistribution: [(sig: String, fraction: Double)]  // generated dist sorted desc
    let slotDistCosine: Double
    let bigramDistCosine: Double
    let openerSlotFrequency: Double   // how common the opener slot is in corpus
}

