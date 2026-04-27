//
//  SignatureRollupService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/17/26.
//
//  Pure-function service for coarsening pipe-delimited slot signatures
//  into fewer categories ("rollup") to reduce sparsity in bigram walks.
//  Four strategies: dominant-slot, slot-set, lead+complexity, slot-family.
//  Also provides map-back from coarse → full signatures.
//

import Foundation

// MARK: - Rollup Strategy Enum

enum RollupStrategy: String, CaseIterable, Identifiable {
    case none = "None (Raw)"
    case dominantSlot = "Dominant Slot"
    case slotSet = "Slot Set"
    case leadPlusComplexity = "Lead + Complexity"
    case slotFamily = "Slot Family"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .none: return "Raw"
        case .dominantSlot: return "Dominant"
        case .slotSet: return "Set"
        case .leadPlusComplexity: return "Lead+Cx"
        case .slotFamily: return "Family"
        }
    }
}

// MARK: - Rollup Diagnostic

struct RollupDiagnostic: Identifiable {
    let id: String
    let strategy: RollupStrategy
    let uniqueCountBefore: Int
    let uniqueCountAfter: Int
    let compressionRatio: Double
    let bucket1x: Int
    let bucket2to3: Int
    let bucket4to9: Int
    let bucket10plus: Int
    let topFrequencies: [(rolledUp: String, count: Int)]
    let allFrequencies: [(rolledUp: String, count: Int)]
}

// MARK: - SignatureRollupService

struct SignatureRollupService {

    // MARK: - Strategy A: Dominant-Slot Rollup

    /// Priority ranking for slot types. Lower = more "important".
    /// Content-carrying slots rank higher than structural/connector slots.
    static let slotPriority: [String: Int] = [
        "narrative_action": 1,
        "evaluative_claim": 2,
        "factual_relay": 3,
        "contradiction": 4,
        "comparison": 5,
        "rhetorical_question": 6,
        "direct_address": 7,
        "quantitative_claim": 8,
        "actor_reference": 9,
        "reaction_beat": 10,
        "visual_detail": 11,
        "sensory_detail": 12,
        "visual_anchor": 13,
        "geographic_location": 14,
        "abstract_framing": 15,
        "pivot_phrase": 16,
        "temporal_marker": 17,
        "empty_connector": 18,
        "other": 19,
    ]

    static func rollupDominantSlot(_ signature: String) -> String {
        let slots = signature.components(separatedBy: "|")
        guard !slots.isEmpty else { return signature }
        let best = slots.min { (slotPriority[$0] ?? 99) < (slotPriority[$1] ?? 99) }
        return best ?? signature
    }

    // MARK: - Strategy B: Slot-Set Rollup (Unordered)

    static func rollupSlotSet(_ signature: String) -> String {
        let slots = signature.components(separatedBy: "|")
        let unique = Set(slots).sorted()
        return "{" + unique.joined(separator: ",") + "}"
    }

    // MARK: - Strategy C: Lead-Slot + Complexity Class

    static func rollupLeadPlusComplexity(_ signature: String) -> String {
        let slots = signature.components(separatedBy: "|")
        let lead = slots.first ?? "other"
        let complexity: String
        switch slots.count {
        case 1...2: complexity = "simple"
        case 3...4: complexity = "moderate"
        default:    complexity = "complex"
        }
        return "\(lead):\(complexity)"
    }

    // MARK: - Strategy D: Slot-Family Grouping

    /// Maps each of the 19 slot types to one of 6 families.
    static let slotToFamily: [String: String] = [
        "narrative_action": "narrative",
        "actor_reference": "narrative",
        "reaction_beat": "narrative",
        "visual_detail": "descriptive",
        "sensory_detail": "descriptive",
        "visual_anchor": "descriptive",
        "geographic_location": "descriptive",
        "evaluative_claim": "analytical",
        "quantitative_claim": "analytical",
        "factual_relay": "analytical",
        "comparison": "analytical",
        "pivot_phrase": "structural",
        "contradiction": "structural",
        "empty_connector": "structural",
        "temporal_marker": "structural",
        "abstract_framing": "structural",
        "direct_address": "interactive",
        "rhetorical_question": "interactive",
        "other": "other",
    ]

    static func rollupSlotFamily(_ signature: String) -> String {
        let slots = signature.components(separatedBy: "|")
        let families = slots.map { slotToFamily[$0] ?? "other" }
        return families.joined(separator: "|")
    }

    // MARK: - Unified Rollup Dispatch

    static func rollup(_ signature: String, strategy: RollupStrategy) -> String {
        switch strategy {
        case .none: return signature
        case .dominantSlot: return rollupDominantSlot(signature)
        case .slotSet: return rollupSlotSet(signature)
        case .leadPlusComplexity: return rollupLeadPlusComplexity(signature)
        case .slotFamily: return rollupSlotFamily(signature)
        }
    }

    // MARK: - Diagnostic Builder

    static func buildDiagnostic(
        strategy: RollupStrategy,
        signatures: [(signature: String, count: Int)]
    ) -> RollupDiagnostic {
        // Apply rollup to each signature, summing its occurrence count into the coarse bucket
        var rolledUpCounts: [String: Int] = [:]
        for item in signatures {
            let rolled = rollup(item.signature, strategy: strategy)
            rolledUpCounts[rolled, default: 0] += item.count
        }

        let sorted = rolledUpCounts.sorted { $0.value > $1.value }
            .map { (rolledUp: $0.key, count: $0.value) }

        let uniqueBefore = signatures.count
        let uniqueAfter = sorted.count

        let b1x = sorted.filter { $0.count == 1 }.count
        let b2to3 = sorted.filter { $0.count >= 2 && $0.count <= 3 }.count
        let b4to9 = sorted.filter { $0.count >= 4 && $0.count <= 9 }.count
        let b10p = sorted.filter { $0.count >= 10 }.count

        return RollupDiagnostic(
            id: strategy.rawValue,
            strategy: strategy,
            uniqueCountBefore: uniqueBefore,
            uniqueCountAfter: uniqueAfter,
            compressionRatio: uniqueAfter > 0 ? Double(uniqueBefore) / Double(uniqueAfter) : 0,
            bucket1x: b1x,
            bucket2to3: b2to3,
            bucket4to9: b4to9,
            bucket10plus: b10p,
            topFrequencies: Array(sorted.prefix(10)),
            allFrequencies: sorted
        )
    }

    // MARK: - Map-Back: Coarse → Full Signature

    /// Given a coarse (rolled-up) signature and the corpus of full signatures
    /// with their counts, return a full signature that maps to this coarse category.
    ///
    /// - Parameters:
    ///   - coarseSignature: The rolled-up signature from the walk
    ///   - strategy: Which rollup was used
    ///   - corpus: Full signature frequencies (sorted by count desc)
    ///   - useWeightedRandom: If false, picks most frequent; if true, samples proportionally
    ///   - rng: Seeded RNG for reproducibility
    /// - Returns: A full signature string
    static func mapBack(
        coarseSignature: String,
        strategy: RollupStrategy,
        corpus: [(signature: String, count: Int)],
        useWeightedRandom: Bool = false,
        rng: inout SeededRNG
    ) -> String {
        guard strategy != .none else { return coarseSignature }

        // Find all full signatures that roll up to this coarse signature
        let candidates = corpus.filter { rollup($0.signature, strategy: strategy) == coarseSignature }

        guard !candidates.isEmpty else { return coarseSignature }

        if useWeightedRandom {
            let totalCount = candidates.reduce(0) { $0 + $1.count }
            guard totalCount > 0 else { return candidates[0].signature }
            var roll = Int.random(in: 0..<totalCount, using: &rng)
            for candidate in candidates {
                roll -= candidate.count
                if roll < 0 { return candidate.signature }
            }
        }

        // Default: most frequent full signature in this category
        return candidates[0].signature
    }

    /// Count how many full signatures map to a given coarse signature.
    static func mapBackCandidateCount(
        coarseSignature: String,
        strategy: RollupStrategy,
        corpus: [(signature: String, count: Int)]
    ) -> Int {
        guard strategy != .none else { return 1 }
        return corpus.filter { rollup($0.signature, strategy: strategy) == coarseSignature }.count
    }
}
