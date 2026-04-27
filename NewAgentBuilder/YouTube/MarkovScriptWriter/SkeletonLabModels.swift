//
//  SkeletonLabModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/24/26.
//
//  Data models for the Skeleton Lab tab.
//  Defines the 6 skeleton generation paths, their shared result type,
//  the atom-level transition matrix, and configuration.
//

import SwiftUI

// MARK: - Skeleton Path Enum

enum SkeletonPath: Int, CaseIterable, Identifiable, Codable {
    case pureProbabilistic = 6
    case planFirst = 1
    case entropyHandoff = 2
    case collapseReExpand = 3
    case templateBlending = 4
    case contentTypedSubChain = 5
    case corpusSeededFirst = 7

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .pureProbabilistic:    return "Pure Probabilistic Walk"
        case .planFirst:            return "Plan First, Then Walk"
        case .entropyHandoff:       return "Entropy Handoff"
        case .collapseReExpand:     return "Collapse & Re-Expand"
        case .templateBlending:     return "Template Blending"
        case .contentTypedSubChain: return "Content-Typed Sub-Chains"
        case .corpusSeededFirst:    return "Corpus-Seeded First Sentence"
        }
    }

    var shortName: String {
        "P\(rawValue)"
    }

    var shortDescription: String {
        switch self {
        case .pureProbabilistic:    return "Null hypothesis — pure matrix walk, no content awareness"
        case .planFirst:            return "LLM plans intent sequence, matrix walks within each intent"
        case .entropyHandoff:       return "Matrix decides at rigid points, content scores at flexible points"
        case .collapseReExpand:     return "LLM writes freely, then correct atom sequence toward creator patterns"
        case .templateBlending:     return "Splice real corpus segments, validate seams with matrix"
        case .contentTypedSubChain: return "Cluster corpus by atom profile, walk the content-matched sub-matrix"
        case .corpusSeededFirst:    return "Lock sentence 1 from a real corpus opener, Markov-walk the rest"
        }
    }

    var badgeColor: Color {
        switch self {
        case .pureProbabilistic:    return .gray
        case .planFirst:            return .blue
        case .entropyHandoff:       return .orange
        case .collapseReExpand:     return .purple
        case .templateBlending:     return .green
        case .contentTypedSubChain: return .indigo
        case .corpusSeededFirst:    return .teal
        }
    }

    var requiresLLM: Bool {
        switch self {
        case .pureProbabilistic, .templateBlending, .entropyHandoff, .corpusSeededFirst: return false
        case .planFirst, .collapseReExpand, .contentTypedSubChain: return true
        }
    }

    var llmCallEstimate: String {
        switch self {
        case .pureProbabilistic:    return "0"
        case .templateBlending:     return "0"
        case .entropyHandoff:       return "0"
        case .planFirst:            return "1"
        case .contentTypedSubChain: return "1"
        case .collapseReExpand:     return "1"
        case .corpusSeededFirst:    return "0"
        }
    }

    /// Execution order: no-LLM paths first, then simplest LLM to most complex
    static var executionOrder: [SkeletonPath] {
        [.pureProbabilistic, .corpusSeededFirst, .templateBlending, .entropyHandoff,
         .planFirst, .contentTypedSubChain, .collapseReExpand]
    }
}

// MARK: - Run Status

enum SkeletonRunStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
}

// MARK: - Atom Transition Matrix

// CHANGELOG v1→v2:
// v1: 5 properties — transitions, openerDistribution, breakProbabilities, atomCounts, totalTransitionCount.
//     All walks used sampleNext() (bigram only). No position-aware sentence breaks.
// Problem: Bigram-only walks created A→B→A bounce patterns (e.g. factual_relay → geographic_location → factual_relay).
//     Flat break probability produced 22-atom sentences because breaks had no awareness of how deep into a sentence we were.
// v2: Added trigramTransitions ("atomA|atomB" → nextAtom → count) and positionBreakRamp (hazard rate per sentence position).
//     Added sampleNextWithContext() for trigram-first sampling with bigram fallback.
// Fixes: Trigrams kill bounce patterns by conditioning on last 2 atoms. Position ramp suppresses early breaks and boosts late
//     breaks so sentences cluster around corpus-typical lengths instead of running to 22 atoms.
//
// CHANGELOG v2→v3:
// v2: positionBreakRamp used hazard-rate normalization (median position = 1.0, cap 3.0). No corpus sentence length stats.
// Problem: Ramp shape was data-driven but uncalibrated — sentences could still be 1-atom (too short) or overshoot corpus p95.
// v3: Added corpusMinSentenceLen, corpusMedianSentenceLen, corpusP95SentenceLen. positionBreakRamp now uses three-zone model:
//     Zone 1 (< min) = 0.0 (never break), Zone 2 (min..median) = linear 0→1.0, Zone 3 (median..p95) = linear 1.0→3.0.
//     applySentenceBreaks uses min as floor (skip roll) and p95 as forced break (no roll).
// Fixes: Sentences are bounded by corpus-calibrated min and p95. No more 1-atom or runaway sentences.
struct AtomTransitionMatrix {
    /// atom → atom → count
    let transitions: [String: [String: Double]]
    /// First-atom frequencies from corpus section openers
    let openerDistribution: [String: Double]
    /// P(sentence break | prevAtom, nextAtom)
    let breakProbabilities: [String: [String: Double]]
    /// Total occurrences per atom type
    let atomCounts: [String: Int]
    /// Total transitions observed
    let totalTransitionCount: Int
    /// Trigram: "atomA|atomB" → nextAtom → count
    let trigramTransitions: [String: [String: Double]]
    /// Position-in-sentence → break probability multiplier (three-zone model, v3)
    let positionBreakRamp: [Int: Double]
    /// Corpus sentence length statistics for break calibration (v3)
    let corpusMinSentenceLen: Int
    let corpusMedianSentenceLen: Int
    let corpusP95SentenceLen: Int
    /// Within-sentence-only bigram counts: "from → to" → count (no cross-boundary pairs)
    let withinSentenceBigrams: [String: Int]
    /// Within-sentence-only trigram counts: "a → b → c" → count (no cross-boundary triples)
    let withinSentenceTrigrams: [String: Int]

    func probability(from: String, to: String) -> Double {
        transitions[from]?[to] ?? 0
    }

    func sampleNext(from atom: String, using rng: inout SeededRNG) -> String? {
        guard let row = transitions[atom], !row.isEmpty else { return nil }
        let total = row.values.reduce(0, +)
        guard total > 0 else { return nil }
        var roll = Double(rng.next() % 10000) / 10000.0 * total
        for (target, prob) in row {
            roll -= prob
            if roll <= 0 { return target }
        }
        return row.keys.first
    }

    // CHANGELOG v1→v2:
    // New in v2. All paths previously used sampleNext() (bigram only).
    // Returns (atom, usedTrigram) tuple so walk traces can log whether TRIGRAM or BIGRAM decided each step.
    // Falls back to bigram when trigram row has < minObservations (default 3) entries — prevents overfitting
    // on rare trigram patterns that appeared only 1-2 times in corpus.
    /// Trigram-aware sampling: tries (prev, current) → next first,
    /// falls back to bigram if trigram has < minObservations entries.
    func sampleNextWithContext(
        from current: String,
        context prev: String?,
        minObservations: Int = 3,
        using rng: inout SeededRNG
    ) -> (atom: String, usedTrigram: Bool)? {
        if let prev = prev {
            let key = "\(prev)|\(current)"
            if let triRow = trigramTransitions[key], triRow.count >= minObservations {
                let total = triRow.values.reduce(0, +)
                if total > 0 {
                    var roll = Double(rng.next() % 10000) / 10000.0 * total
                    for (target, count) in triRow {
                        roll -= count
                        if roll <= 0 { return (atom: target, usedTrigram: true) }
                    }
                    if let first = triRow.keys.first {
                        return (atom: first, usedTrigram: true)
                    }
                }
            }
        }
        // Fallback to bigram
        if let result = sampleNext(from: current, using: &rng) {
            return (atom: result, usedTrigram: false)
        }
        return nil
    }

    func sampleOpener(using rng: inout SeededRNG) -> String? {
        guard !openerDistribution.isEmpty else { return nil }
        let total = openerDistribution.values.reduce(0, +)
        guard total > 0 else { return nil }
        var roll = Double(rng.next() % 10000) / 10000.0 * total
        for (atom, freq) in openerDistribution {
            roll -= freq
            if roll <= 0 { return atom }
        }
        return openerDistribution.keys.first
    }

    func sampleBreak(prev: String, next: String, using rng: inout SeededRNG) -> Bool {
        let prob = breakProbabilities[prev]?[next] ?? 0.3
        let roll = Double(rng.next() % 10000) / 10000.0
        return roll < prob
    }

    func entropy(from atom: String) -> Double {
        guard let row = transitions[atom], !row.isEmpty else { return 0 }
        let total = row.values.reduce(0, +)
        guard total > 0 else { return 0 }
        return -row.values.reduce(0.0) { sum, count in
            let p = count / total
            return p > 0 ? sum + p * log2(p) : sum
        }
    }

    func normalizedEntropy(from atom: String) -> Double {
        guard let row = transitions[atom], row.count > 1 else { return 0 }
        let maxH = log2(Double(row.count))
        return maxH > 0 ? entropy(from: atom) / maxH : 0
    }

    func validNextAtoms(from atom: String, minProbability: Double = 0.05) -> [(atom: String, probability: Double)] {
        guard let row = transitions[atom] else { return [] }
        let total = row.values.reduce(0, +)
        guard total > 0 else { return [] }
        return row.compactMap { target, count in
            let p = count / total
            return p >= minProbability ? (atom: target, probability: p) : nil
        }.sorted { $0.probability > $1.probability }
    }

    // MARK: - Explorer Query Methods

    /// Ranked next atoms (no minimum probability filter, includes count)
    func topNextAtoms(after atom: String, topK: Int = 10) -> [(atom: String, probability: Double, count: Int)] {
        guard let row = transitions[atom], !row.isEmpty else { return [] }
        let total = row.values.reduce(0, +)
        guard total > 0 else { return [] }
        return row
            .map { (atom: $0.key, probability: $0.value / total, count: Int($0.value)) }
            .sorted { $0.probability > $1.probability }
            .prefix(topK)
            .map { $0 }
    }

    /// Reverse lookup: what atoms precede this one, ranked by frequency
    func topPreviousAtoms(before atom: String, topK: Int = 10) -> [(atom: String, probability: Double, count: Int)] {
        var reverseCounts: [String: Double] = [:]
        for (from, row) in transitions {
            if let count = row[atom] {
                reverseCounts[from] = count
            }
        }
        let total = reverseCounts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return reverseCounts
            .map { (atom: $0.key, probability: $0.value / total, count: Int($0.value)) }
            .sorted { $0.probability > $1.probability }
            .prefix(topK)
            .map { $0 }
    }

    /// Ranked opener atoms from openerDistribution
    func topOpeners(topK: Int = 10) -> [(atom: String, probability: Double, count: Int)] {
        let total = openerDistribution.values.reduce(0, +)
        guard total > 0 else { return [] }
        return openerDistribution
            .map { (atom: $0.key, probability: $0.value / total, count: Int($0.value)) }
            .sorted { $0.probability > $1.probability }
            .prefix(topK)
            .map { $0 }
    }

    /// Trigram-context ranked next atoms: given (prev, current), return ranked successors
    func trigramNextAtoms(prev: String, current: String, topK: Int = 10) -> [(atom: String, probability: Double, count: Int)] {
        let key = "\(prev)|\(current)"
        guard let row = trigramTransitions[key], !row.isEmpty else { return [] }
        let total = row.values.reduce(0, +)
        guard total > 0 else { return [] }
        return row
            .map { (atom: $0.key, probability: $0.value / total, count: Int($0.value)) }
            .sorted { $0.probability > $1.probability }
            .prefix(topK)
            .map { $0 }
    }

    /// All atom types sorted by total occurrences descending
    func atomsByFrequency() -> [(atom: String, count: Int)] {
        atomCounts.sorted { $0.value > $1.value }.map { (atom: $0.key, count: $0.value) }
    }

    /// Top bigram patterns (within-sentence only — no cross-boundary inflation)
    func globalAtomBigrams(topK: Int = 30) -> [(pattern: String, count: Int)] {
        withinSentenceBigrams
            .sorted { $0.value > $1.value }
            .prefix(topK)
            .map { ($0.key, $0.value) }
    }

    /// Top trigram patterns (within-sentence only — no cross-boundary inflation)
    func globalAtomTrigrams(topK: Int = 30) -> [(pattern: String, count: Int)] {
        withinSentenceTrigrams
            .sorted { $0.value > $1.value }
            .prefix(topK)
            .map { ($0.key, $0.value) }
    }
}

// MARK: - Skeleton Result

struct SkeletonResult: Identifiable, Codable {
    let id: UUID
    let path: SkeletonPath
    let createdAt: Date

    let atoms: [String]
    let sentenceBreaks: Set<Int>
    var status: SkeletonRunStatus

    let durationMs: Int
    let llmCallCount: Int
    let promptTokensTotal: Int
    let completionTokensTotal: Int
    let estimatedCost: Double

    var intermediateOutputs: [String: String]
    var llmCalls: [SkeletonLLMCall]

    /// S5 prose generation result (populated after "Run S5" on this skeleton)
    var s5ProseResult: SkeletonS5Runner.S5ProseResult?

    /// S6 adaptive prose generation result (populated after "Run S6" on this skeleton)
    var s6ProseResult: SkeletonS6Runner.S6ProseResult?

    /// S7 phrase-library prose generation result (populated after "Run S7" on this skeleton)
    var s7ProseResult: SkeletonS7Runner.S7ProseResult?

    var sentenceCount: Int { sentenceBreaks.count + 1 }
    var atomCount: Int { atoms.count }

    /// Split atoms into per-sentence groups
    var sentences: [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for (i, atom) in atoms.enumerated() {
            if sentenceBreaks.contains(i) && !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(atom)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Compute transition quality for each adjacent pair
    func transitionQuality(matrix: AtomTransitionMatrix) -> [(from: String, to: String, probability: Double, isCrossBoundary: Bool)] {
        guard atoms.count > 1 else { return [] }
        var pairs: [(from: String, to: String, probability: Double, isCrossBoundary: Bool)] = []
        for i in 0..<(atoms.count - 1) {
            let prob = matrix.probability(from: atoms[i], to: atoms[i + 1])
            let isBoundary = sentenceBreaks.contains(i + 1)
            pairs.append((from: atoms[i], to: atoms[i + 1], probability: prob, isCrossBoundary: isBoundary))
        }
        return pairs
    }
}

// MARK: - LLM Call Record

struct SkeletonLLMCall: Identifiable, Codable {
    let id: UUID
    let callIndex: Int
    let callLabel: String
    let systemPrompt: String
    let userPrompt: String
    let rawResponse: String
    let durationMs: Int
    let promptTokens: Int
    let completionTokens: Int

    init(callIndex: Int, callLabel: String, systemPrompt: String, userPrompt: String,
         rawResponse: String, durationMs: Int, promptTokens: Int = 0, completionTokens: Int = 0) {
        self.id = UUID()
        self.callIndex = callIndex
        self.callLabel = callLabel
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.rawResponse = rawResponse
        self.durationMs = durationMs
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

// MARK: - Configuration

struct SkeletonLabConfig {
    var moveType: String = ""
    var contentInput: String = ""
    var targetSentenceCount: Int = 7
    var enabledPaths: Set<SkeletonPath> = Set(SkeletonPath.allCases)
    var seed: UInt64 = 42

    // Path 2: Entropy Handoff
    var entropyThreshold: Double = 0.7

    // Path 5: Content-Typed Sub-Chains
    var clusterCount: Int = 4

    // Path 3: Collapse & Re-Expand
    var collapseTemperature: Double = 0.8
}

// MARK: - Intent Categories (Path 1)

enum IntentCategory: String, CaseIterable, Codable {
    case ground = "Ground"
    case introduce = "Introduce"
    case claim = "Claim"
    case pivot = "Pivot"
    case connect = "Connect"
    case frame = "Frame"

    var atomTypes: Set<String> {
        switch self {
        case .ground:    return ["geographic_location", "temporal_marker", "visual_detail"]
        case .introduce: return ["actor_reference", "narrative_action"]
        case .claim:     return ["quantitative_claim", "factual_relay", "evaluative_claim"]
        case .pivot:     return ["contradiction", "pivot_phrase", "rhetorical_question"]
        case .connect:   return ["direct_address", "empty_connector", "reaction_beat"]
        case .frame:     return ["abstract_framing", "comparison", "sensory_detail", "visual_anchor"]
        }
    }

    var description: String {
        switch self {
        case .ground:    return "Orient the viewer in place/time"
        case .introduce: return "Bring a person or group into the story"
        case .claim:     return "Assert something with evidence or judgment"
        case .pivot:     return "Change direction or challenge"
        case .connect:   return "Engage the viewer or bridge segments"
        case .frame:     return "Provide conceptual scaffolding"
        }
    }
}
