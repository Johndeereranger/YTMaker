//
//  GroundTruthModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/27/26.
//

import SwiftUI

// MARK: - Boundary Method

enum BoundaryMethod: String, CaseIterable, Codable, Hashable {
    case deterministicClean = "deterministic_clean"
    case deterministicDigression = "deterministic_digression"
    case slidingWindowP1 = "sliding_window_p1"
    case slidingWindowLLM = "sliding_window_llm"
    case singleShotLLM = "single_shot_llm"

    var displayName: String {
        switch self {
        case .deterministicClean: return "Deterministic (Clean)"
        case .deterministicDigression: return "Deterministic (Digression-Excluded)"
        case .slidingWindowP1: return "Sliding Window (Pass 1)"
        case .slidingWindowLLM: return "Sliding Window (P1+P2)"
        case .singleShotLLM: return "Single-Shot LLM"
        }
    }

    var shortLabel: String {
        switch self {
        case .deterministicClean: return "R"
        case .deterministicDigression: return "RD"
        case .slidingWindowP1: return "W1"
        case .slidingWindowLLM: return "W"
        case .singleShotLLM: return "S"
        }
    }

    var color: Color {
        switch self {
        case .deterministicClean: return .blue
        case .deterministicDigression: return .cyan
        case .slidingWindowP1: return .yellow
        case .slidingWindowLLM: return .orange
        case .singleShotLLM: return .purple
        }
    }
}

// MARK: - Consensus Tier

enum ConsensusTier: Codable, Hashable {
    case definite   // all methods agree
    case probable   // all but one agree
    case contested  // split (only with 4+ methods)
    case weak       // only 1 method

    var label: String { label(totalMethods: 4) }

    func label(totalMethods: Int) -> String {
        switch self {
        case .definite: return "\(totalMethods)/\(totalMethods)"
        case .probable: return "\(totalMethods - 1)/\(totalMethods)"
        case .contested: return "\(max(1, totalMethods - 2))/\(totalMethods)"
        case .weak: return "1/\(totalMethods)"
        }
    }

    var color: Color {
        switch self {
        case .definite: return .green
        case .probable: return .yellow
        case .contested: return .orange
        case .weak: return .gray
        }
    }

    static func from(voteCount: Int) -> ConsensusTier? {
        from(voteCount: voteCount, totalMethods: 4)
    }

    static func from(voteCount: Int, totalMethods: Int) -> ConsensusTier? {
        guard voteCount > 0, totalMethods > 0 else { return nil }
        if voteCount == totalMethods { return .definite }
        if voteCount == totalMethods - 1 { return .probable }
        if totalMethods >= 4 && voteCount == totalMethods - 2 { return .contested }
        if voteCount >= 1 { return .weak }
        return nil
    }
}

// MARK: - Sentence Gap Vote

struct SentenceGapVote: Identifiable, Codable, Hashable {
    var id: Int { gapAfterSentenceIndex }

    let gapAfterSentenceIndex: Int
    let sentenceText: String
    let nextSentenceText: String
    var votes: Set<BoundaryMethod>
    var manualOverride: Bool?  // nil = not reviewed, true = confirmed, false = rejected

    var voteCount: Int { votes.count }

    var tier: ConsensusTier? {
        ConsensusTier.from(voteCount: voteCount)
    }

    var needsReview: Bool {
        manualOverride == nil && voteCount == 2
    }

    /// Override takes priority over vote threshold (3/4+)
    var isBoundary: Bool {
        if let override = manualOverride {
            return override
        }
        return voteCount >= 3
    }
}

// MARK: - Desert Region

struct DesertRegion: Identifiable, Codable, Hashable {
    var id: Int { startSentenceIndex }

    let startSentenceIndex: Int
    let endSentenceIndex: Int

    var sentenceCount: Int {
        endSentenceIndex - startSentenceIndex + 1
    }
}

// MARK: - Per-Boundary Detail

/// Detail about a single boundary from one method's perspective
struct MethodBoundaryDetail: Codable, Hashable {
    let gapIndex: Int

    // Deterministic methods: what trigger fired
    let triggerType: String?
    let triggerConfidence: String?

    // Sliding window: window vote detail
    let windowVotes: Int?
    let windowsOverlapping: Int?
    let windowReasons: [String]?

    // Sliding window: pass comparison
    let inPass1: Bool?
    let inFinal: Bool?
    let passChange: String?
}

// MARK: - Method Boundary Set

struct MethodBoundarySet: Codable, Hashable {
    let method: BoundaryMethod
    let boundaryGapIndices: Set<Int>
    let runDuration: TimeInterval
    let debugSummary: String

    // LLM-specific fidelity info (nil for deterministic methods)
    let internalRunCount: Int?
    let unanimousCount: Int?
    let majorityCount: Int?

    // Per-boundary detail (nil for legacy results)
    let pass1GapIndices: Set<Int>?
    let perBoundaryDetails: [MethodBoundaryDetail]?

    /// Lookup detail for a specific gap
    func detail(forGap gapIndex: Int) -> MethodBoundaryDetail? {
        perBoundaryDetails?.first { $0.gapIndex == gapIndex }
    }
}

// MARK: - Codex Consensus Models

enum CodexComparableRunKind: Codable, Hashable {
    case deterministicClean
    case deterministicDigressionExcluded
    case slidingWindowP1Window(windowIndex: Int)
    case slidingWindowPass1
    case slidingWindowFinalWindow(windowIndex: Int)
    case slidingWindowFinal
    case singleShotInternal(runNumber: Int)
    case singleShotConsensus

    private enum CodingKeys: String, CodingKey {
        case type
        case runNumber
        case windowIndex
    }

    private enum KindType: String, Codable {
        case deterministicClean
        case deterministicDigressionExcluded
        case slidingWindowP1Window
        case slidingWindowPass1
        case slidingWindowFinalWindow
        case slidingWindowFinal
        case singleShotInternal
        case singleShotConsensus
    }

    var displayName: String {
        switch self {
        case .deterministicClean:
            return "Deterministic (Clean)"
        case .deterministicDigressionExcluded:
            return "Deterministic (Digression-Excluded)"
        case .slidingWindowP1Window(let windowIndex):
            return "P1 Window \(windowIndex)"
        case .slidingWindowPass1:
            return "Sliding Window (Pass 1)"
        case .slidingWindowFinalWindow(let windowIndex):
            return "Final Window \(windowIndex)"
        case .slidingWindowFinal:
            return "Sliding Window (P1+P2)"
        case .singleShotInternal(let runNumber):
            return "Single-Shot Run \(runNumber)"
        case .singleShotConsensus:
            return "Single-Shot Consensus"
        }
    }

    var shortLabel: String {
        switch self {
        case .deterministicClean:
            return "R"
        case .deterministicDigressionExcluded:
            return "RD"
        case .slidingWindowP1Window(let windowIndex):
            return "P1-W\(windowIndex)"
        case .slidingWindowPass1:
            return "W1"
        case .slidingWindowFinalWindow(let windowIndex):
            return "F-W\(windowIndex)"
        case .slidingWindowFinal:
            return "W"
        case .singleShotInternal(let runNumber):
            return "S\(runNumber)"
        case .singleShotConsensus:
            return "SC"
        }
    }

    var family: String {
        switch self {
        case .deterministicClean, .deterministicDigressionExcluded:
            return "Deterministic"
        case .slidingWindowP1Window, .slidingWindowPass1, .slidingWindowFinalWindow, .slidingWindowFinal:
            return "Sliding Window"
        case .singleShotInternal, .singleShotConsensus:
            return "Single Shot"
        }
    }

    var color: Color {
        switch self {
        case .deterministicClean:
            return .blue
        case .deterministicDigressionExcluded:
            return .cyan
        case .slidingWindowP1Window:
            return .yellow.opacity(0.7)
        case .slidingWindowPass1:
            return .yellow
        case .slidingWindowFinalWindow:
            return .orange.opacity(0.7)
        case .slidingWindowFinal:
            return .orange
        case .singleShotInternal:
            return .purple
        case .singleShotConsensus:
            return .pink
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)
        switch type {
        case .deterministicClean:
            self = .deterministicClean
        case .deterministicDigressionExcluded:
            self = .deterministicDigressionExcluded
        case .slidingWindowP1Window:
            self = .slidingWindowP1Window(windowIndex: try container.decode(Int.self, forKey: .windowIndex))
        case .slidingWindowPass1:
            self = .slidingWindowPass1
        case .slidingWindowFinalWindow:
            self = .slidingWindowFinalWindow(windowIndex: try container.decode(Int.self, forKey: .windowIndex))
        case .slidingWindowFinal:
            self = .slidingWindowFinal
        case .singleShotInternal:
            self = .singleShotInternal(runNumber: try container.decode(Int.self, forKey: .runNumber))
        case .singleShotConsensus:
            self = .singleShotConsensus
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .deterministicClean:
            try container.encode(KindType.deterministicClean, forKey: .type)
        case .deterministicDigressionExcluded:
            try container.encode(KindType.deterministicDigressionExcluded, forKey: .type)
        case .slidingWindowP1Window(let windowIndex):
            try container.encode(KindType.slidingWindowP1Window, forKey: .type)
            try container.encode(windowIndex, forKey: .windowIndex)
        case .slidingWindowPass1:
            try container.encode(KindType.slidingWindowPass1, forKey: .type)
        case .slidingWindowFinalWindow(let windowIndex):
            try container.encode(KindType.slidingWindowFinalWindow, forKey: .type)
            try container.encode(windowIndex, forKey: .windowIndex)
        case .slidingWindowFinal:
            try container.encode(KindType.slidingWindowFinal, forKey: .type)
        case .singleShotInternal(let runNumber):
            try container.encode(KindType.singleShotInternal, forKey: .type)
            try container.encode(runNumber, forKey: .runNumber)
        case .singleShotConsensus:
            try container.encode(KindType.singleShotConsensus, forKey: .type)
        }
    }
}

struct CodexComparableRunMetadata: Codable, Hashable {
    let methodDetails: [MethodBoundaryDetail]?
    let sourceRunNumber: Int?
    let sourcePassLabel: String?
    let notes: String?
}

struct CodexComparableRun: Identifiable, Codable, Hashable {
    let id: String
    let kind: CodexComparableRunKind
    let displayName: String
    let shortLabel: String
    let family: String
    let boundaryGapIndices: Set<Int>
    let runDuration: TimeInterval?
    let debugSummary: String
    let metadata: CodexComparableRunMetadata

    var color: Color { kind.color }

    func detail(forGap gapIndex: Int) -> MethodBoundaryDetail? {
        metadata.methodDetails?.first { $0.gapIndex == gapIndex }
    }
}

enum CodexConsensusTier: String, Codable, Hashable {
    case unanimous
    case strong
    case split
    case weak

    var color: Color {
        switch self {
        case .unanimous:
            return .green
        case .strong:
            return .blue
        case .split:
            return .orange
        case .weak:
            return .gray
        }
    }

    var label: String {
        switch self {
        case .unanimous:
            return "Unanimous"
        case .strong:
            return "Strong"
        case .split:
            return "Split"
        case .weak:
            return "Weak"
        }
    }

    static func from(voteCount: Int, totalRuns: Int) -> CodexConsensusTier? {
        guard voteCount > 0, totalRuns > 0 else { return nil }
        let ratio = Double(voteCount) / Double(totalRuns)
        if ratio >= 1.0 {
            return .unanimous
        }
        if ratio >= 0.75 {
            return .strong
        }
        if ratio >= 0.40 {
            return .split
        }
        return .weak
    }
}

struct CodexGapVote: Identifiable, Codable, Hashable {
    var id: Int { gapAfterSentenceIndex }

    let gapAfterSentenceIndex: Int
    let sentenceText: String
    let nextSentenceText: String
    let runIds: [String]
    let runCount: Int
    let totalRuns: Int
    let consensusTier: CodexConsensusTier
    let isBoundary: Bool
}

struct PairwiseRunComparison: Identifiable, Codable, Hashable {
    let leftRunId: String
    let rightRunId: String
    let sharedBoundaryCount: Int
    let leftOnlyCount: Int
    let rightOnlyCount: Int
    let unionCount: Int
    let jaccardSimilarity: Double
    let disagreementGapIndices: [Int]

    var id: String {
        [leftRunId, rightRunId].sorted().joined(separator: "::")
    }
}

// MARK: - Alignment Run (lightweight, for alignment tab)

struct AlignmentRun: Identifiable, Hashable {
    let id: String
    let label: String
    let color: Color
    let boundaryGapIndices: Set<Int>
    let detail: String?

    private enum CodingKeys: String, CodingKey {
        case id, label, boundaryGapIndices, detail
    }
}

// MARK: - Ground Truth Result

struct GroundTruthResult: Codable {
    let videoId: String
    let totalSentences: Int
    let totalMethods: Int
    let methodResults: [MethodBoundarySet]
    var gapVotes: [SentenceGapVote]
    let deserts: [DesertRegion]
    let pass1WindowResults: [WindowSplitResult]?
    let mergedWindowResults: [WindowSplitResult]?
    let slidingWindowRuns: [SectionSplitterRunResult]?
    let codexRuns: [CodexComparableRun]?
    let codexGapVotes: [CodexGapVote]?
    let codexPairwiseComparisons: [PairwiseRunComparison]?
    let createdAt: Date

    /// Majority threshold: 3 for 4 methods, 2 for 3 methods
    var boundaryThreshold: Int { (totalMethods / 2) + 1 }

    var codexBoundaryThreshold: Int {
        let totalRuns = codexRuns?.count ?? 0
        guard totalRuns > 0 else { return 0 }
        return Int(ceil(Double(totalRuns) / 2.0))
    }

    /// Which methods were actually used
    var activeMethods: [BoundaryMethod] { methodResults.map { $0.method } }

    /// All full-pass runs for the alignment tab — 1 column per complete pass
    var allAlignmentRuns: [AlignmentRun] {
        var runs: [AlignmentRun] = []

        // Deterministic methods — always 1 column each
        for m in methodResults {
            switch m.method {
            case .deterministicClean:
                runs.append(AlignmentRun(id: "R", label: "R", color: .blue, boundaryGapIndices: m.boundaryGapIndices, detail: nil))
            case .deterministicDigression:
                runs.append(AlignmentRun(id: "RD", label: "RD", color: .cyan, boundaryGapIndices: m.boundaryGapIndices, detail: nil))
            default:
                break
            }
        }

        // Sliding window runs — 2 columns per run (W1-N, W-N)
        if let swRuns = slidingWindowRuns, !swRuns.isEmpty {
            for (i, run) in swRuns.enumerated() {
                let runNum = i + 1
                let suffix = swRuns.count == 1 ? "" : "-\(runNum)"

                // W1: Pass 1 consensus
                let pass1Gaps = Self.gapIndices(from: run.pass1Boundaries)
                runs.append(AlignmentRun(
                    id: "W1\(suffix)",
                    label: "W1\(suffix)",
                    color: .yellow,
                    boundaryGapIndices: pass1Gaps,
                    detail: "Pass 1 consensus (run \(runNum))"
                ))

                // W: Final consensus (pass 1+2)
                let finalGaps = Self.gapIndices(from: run.boundaries)
                runs.append(AlignmentRun(
                    id: "W\(suffix)",
                    label: "W\(suffix)",
                    color: .orange,
                    boundaryGapIndices: finalGaps,
                    detail: "P1+P2 consensus (run \(runNum))"
                ))
            }
        } else {
            // Fallback for legacy data — use methodResults
            for m in methodResults {
                switch m.method {
                case .slidingWindowP1:
                    runs.append(AlignmentRun(id: "W1", label: "W1", color: .yellow, boundaryGapIndices: m.boundaryGapIndices, detail: "Pass 1 consensus"))
                case .slidingWindowLLM:
                    runs.append(AlignmentRun(id: "W", label: "W", color: .orange, boundaryGapIndices: m.boundaryGapIndices, detail: "P1+P2 consensus"))
                default:
                    break
                }
            }
        }

        // Single-shot (if present)
        for m in methodResults where m.method == .singleShotLLM {
            runs.append(AlignmentRun(id: "S", label: "S", color: .purple, boundaryGapIndices: m.boundaryGapIndices, detail: nil))
        }

        return runs
    }

    /// Per-window detail columns for a specific run — for the Window Detail view
    func windowDetailAlignmentRuns(forRunIndex runIndex: Int) -> [AlignmentRun] {
        guard let swRuns = slidingWindowRuns, runIndex < swRuns.count else { return [] }
        let run = swRuns[runIndex]
        var runs: [AlignmentRun] = []

        // Pass 1 individual windows
        for w in run.pass1Results {
            let gaps: Set<Int>
            if let split = w.splitAfterSentence, split - 1 >= 0 {
                gaps = Set([split - 1])
            } else {
                gaps = Set()
            }
            runs.append(AlignmentRun(
                id: "P1-W\(w.windowIndex)",
                label: "P1-W\(w.windowIndex)",
                color: .yellow.opacity(0.7),
                boundaryGapIndices: gaps,
                detail: "[\(w.startSentence)-\(w.endSentence)] \(w.reason ?? "")"
            ))
        }

        // Pass 1 consensus
        let pass1Gaps = Self.gapIndices(from: run.pass1Boundaries)
        runs.append(AlignmentRun(id: "W1", label: "W1", color: .yellow, boundaryGapIndices: pass1Gaps, detail: "Pass 1 consensus"))

        // Final/merged individual windows
        for w in run.mergedResults {
            let gaps: Set<Int>
            if let split = w.splitAfterSentence, split - 1 >= 0 {
                gaps = Set([split - 1])
            } else {
                gaps = Set()
            }
            runs.append(AlignmentRun(
                id: "F-W\(w.windowIndex)",
                label: "F-W\(w.windowIndex)",
                color: .orange.opacity(0.7),
                boundaryGapIndices: gaps,
                detail: "[\(w.startSentence)-\(w.endSentence)] \(w.reason ?? "")"
            ))
        }

        // Final consensus
        let finalGaps = Self.gapIndices(from: run.boundaries)
        runs.append(AlignmentRun(id: "W", label: "W", color: .orange, boundaryGapIndices: finalGaps, detail: "P1+P2 consensus"))

        return runs
    }

    /// Convert SectionBoundary array to 0-indexed gap indices
    private static func gapIndices(from boundaries: [SectionBoundary]) -> Set<Int> {
        Set(boundaries.compactMap { b in
            let gap = b.sentenceNumber - 1
            return gap >= 0 ? gap : nil
        })
    }

    var codexActiveRuns: [CodexComparableRun] { codexRuns ?? [] }
    var codexActiveVotes: [CodexGapVote] { codexGapVotes ?? [] }
    var codexActivePairwiseComparisons: [PairwiseRunComparison] { codexPairwiseComparisons ?? [] }

    /// Tier-based counts using actual method count
    var definiteCount: Int { gapVotes.filter { ConsensusTier.from(voteCount: $0.voteCount, totalMethods: totalMethods) == .definite }.count }
    var probableCount: Int { gapVotes.filter { ConsensusTier.from(voteCount: $0.voteCount, totalMethods: totalMethods) == .probable }.count }
    var contestedCount: Int { gapVotes.filter { ConsensusTier.from(voteCount: $0.voteCount, totalMethods: totalMethods) == .contested }.count }
    var weakCount: Int { gapVotes.filter { ConsensusTier.from(voteCount: $0.voteCount, totalMethods: totalMethods) == .weak }.count }
    var pendingReviewCount: Int { gapVotes.filter { $0.voteCount > 0 && $0.voteCount < boundaryThreshold && $0.manualOverride == nil }.count }
    var totalBoundaries: Int { gapVotes.filter { $0.voteCount > 0 }.count }

    /// Is this gap a boundary? Uses dynamic threshold based on method count
    func isBoundary(_ vote: SentenceGapVote) -> Bool {
        if let override = vote.manualOverride { return override }
        return vote.voteCount >= boundaryThreshold
    }

    /// Tier for a vote using actual method count
    func tier(for vote: SentenceGapVote) -> ConsensusTier? {
        ConsensusTier.from(voteCount: vote.voteCount, totalMethods: totalMethods)
    }

    func codexTierCount(_ tier: CodexConsensusTier) -> Int {
        codexActiveVotes.filter { $0.consensusTier == tier }.count
    }

    func codexRun(withId id: String) -> CodexComparableRun? {
        codexRuns?.first { $0.id == id }
    }

    func codexPairwiseComparison(leftRunId: String, rightRunId: String) -> PairwiseRunComparison? {
        codexPairwiseComparisons?.first {
            ($0.leftRunId == leftRunId && $0.rightRunId == rightRunId) ||
            ($0.leftRunId == rightRunId && $0.rightRunId == leftRunId)
        }
    }

    // Custom Codable for backward compat (totalMethods defaults to 4)
    enum CodingKeys: String, CodingKey {
        case videoId, totalSentences, totalMethods, methodResults, gapVotes, deserts
        case pass1WindowResults, mergedWindowResults, slidingWindowRuns
        case codexRuns, codexGapVotes, codexPairwiseComparisons, createdAt
    }

    init(
        videoId: String,
        totalSentences: Int,
        totalMethods: Int,
        methodResults: [MethodBoundarySet],
        gapVotes: [SentenceGapVote],
        deserts: [DesertRegion],
        pass1WindowResults: [WindowSplitResult]? = nil,
        mergedWindowResults: [WindowSplitResult]? = nil,
        slidingWindowRuns: [SectionSplitterRunResult]? = nil,
        codexRuns: [CodexComparableRun]? = nil,
        codexGapVotes: [CodexGapVote]? = nil,
        codexPairwiseComparisons: [PairwiseRunComparison]? = nil,
        createdAt: Date
    ) {
        self.videoId = videoId
        self.totalSentences = totalSentences
        self.totalMethods = totalMethods
        self.methodResults = methodResults
        self.gapVotes = gapVotes
        self.deserts = deserts
        self.pass1WindowResults = pass1WindowResults
        self.mergedWindowResults = mergedWindowResults
        self.slidingWindowRuns = slidingWindowRuns
        self.codexRuns = codexRuns
        self.codexGapVotes = codexGapVotes
        self.codexPairwiseComparisons = codexPairwiseComparisons
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try c.decode(String.self, forKey: .videoId)
        totalSentences = try c.decode(Int.self, forKey: .totalSentences)
        totalMethods = try c.decodeIfPresent(Int.self, forKey: .totalMethods) ?? 4
        methodResults = try c.decode([MethodBoundarySet].self, forKey: .methodResults)
        gapVotes = try c.decode([SentenceGapVote].self, forKey: .gapVotes)
        deserts = try c.decode([DesertRegion].self, forKey: .deserts)
        pass1WindowResults = try c.decodeIfPresent([WindowSplitResult].self, forKey: .pass1WindowResults)
        mergedWindowResults = try c.decodeIfPresent([WindowSplitResult].self, forKey: .mergedWindowResults)
        slidingWindowRuns = try c.decodeIfPresent([SectionSplitterRunResult].self, forKey: .slidingWindowRuns)
        codexRuns = try c.decodeIfPresent([CodexComparableRun].self, forKey: .codexRuns)
        codexGapVotes = try c.decodeIfPresent([CodexGapVote].self, forKey: .codexGapVotes)
        codexPairwiseComparisons = try c.decodeIfPresent([PairwiseRunComparison].self, forKey: .codexPairwiseComparisons)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

// MARK: - Ground Truth Storage (UserDefaults)

struct GroundTruthStorage {
    static func key(for videoId: String) -> String {
        "ground_truth_\(videoId)"
    }

    static func save(_ result: GroundTruthResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        UserDefaults.standard.set(data, forKey: key(for: result.videoId))
    }

    static func load(videoId: String) -> GroundTruthResult? {
        guard let data = UserDefaults.standard.data(forKey: key(for: videoId)) else { return nil }
        return try? JSONDecoder().decode(GroundTruthResult.self, from: data)
    }

    static func delete(videoId: String) {
        UserDefaults.standard.removeObject(forKey: key(for: videoId))
    }
}
