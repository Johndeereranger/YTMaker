//
//  MarkovScriptModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/17/26.
//

import Foundation

// MARK: - Phase Tracking

enum MarkovScriptPhase: String, CaseIterable {
    case input = "Input"
    case opener = "Opener"
    case markovExplorer = "Markov"
    case availability = "Avail"
    case manualBuilder = "Manual"
    case chainBuilder = "Chain"
    case deadEnds = "Dead Ends"
    case gapResponse = "Gaps"
    case parameters = "Params"
    case synthesis = "Synthesis"
    case trace = "Trace"
    case scriptTrace = "Trace B"
    case structure = "Structure"
    case compare = "Compare"
    case skeletonLab = "Skel Lab"
    case atomExplorer = "Atoms"
    case proseEditor = "Editor"
    case arc = "Arc"
}

// MARK: - Session State

struct MarkovScriptSession: Codable, Identifiable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date

    // Raw input (autoloaded from GistScriptWriter or pasted fresh)
    var rawRamblingText: String
    var ramblingGists: [RamblingGist]
    var importedFromGistSession: Bool

    // Chain build run summaries (lightweight; full data stored on disk)
    var chainRuns: [ChainRunSummary]

    // Gap response tracking
    var gapResponses: [GapResponse]

    // Arc gap rambling (user responses to gap analysis questions)
    var arcGapRamblingText: String

    // Parameters
    var parameters: ChainParameters

    // Session metadata
    var sessionName: String?
    var notes: String?

    // Synthesis run history (lightweight summaries; full data stored on disk)
    var synthesisRunSummaries: [SynthesisRunSummary]

    init(
        id: UUID = UUID(),
        rawRamblingText: String = "",
        ramblingGists: [RamblingGist] = [],
        importedFromGistSession: Bool = false,
        chainRuns: [ChainRunSummary] = [],
        gapResponses: [GapResponse] = [],
        arcGapRamblingText: String = "",
        parameters: ChainParameters = ChainParameters(),
        sessionName: String? = nil,
        notes: String? = nil,
        synthesisRunSummaries: [SynthesisRunSummary] = []
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.rawRamblingText = rawRamblingText
        self.ramblingGists = ramblingGists
        self.importedFromGistSession = importedFromGistSession
        self.chainRuns = chainRuns
        self.gapResponses = gapResponses
        self.arcGapRamblingText = arcGapRamblingText
        self.parameters = parameters
        self.sessionName = sessionName
        self.notes = notes
        self.synthesisRunSummaries = synthesisRunSummaries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        rawRamblingText = try container.decode(String.self, forKey: .rawRamblingText)
        ramblingGists = try container.decode([RamblingGist].self, forKey: .ramblingGists)
        importedFromGistSession = try container.decode(Bool.self, forKey: .importedFromGistSession)
        chainRuns = try container.decodeIfPresent([ChainRunSummary].self, forKey: .chainRuns) ?? []
        gapResponses = try container.decodeIfPresent([GapResponse].self, forKey: .gapResponses) ?? []
        arcGapRamblingText = try container.decodeIfPresent(String.self, forKey: .arcGapRamblingText) ?? ""
        parameters = try container.decode(ChainParameters.self, forKey: .parameters)
        sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        synthesisRunSummaries = try container.decodeIfPresent([SynthesisRunSummary].self, forKey: .synthesisRunSummaries) ?? []
    }

    mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - Chain Run Summary (lightweight; full ChainBuildRun stored on disk)

struct ChainRunSummary: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let algorithmType: ChainAlgorithm
    let inputGistCount: Int
    let chainsAttemptedCount: Int
    let chainsCompletedCount: Int
    let bestCoverageScore: Double?
    let bestChainLength: Int?
    let starterMoveName: String?
    let deadEndCount: Int
    var hasGuidance: Bool

    init(from run: ChainBuildRun) {
        self.id = run.id
        self.createdAt = run.createdAt
        self.algorithmType = run.parameters.algorithmType
        self.inputGistCount = run.inputGistCount
        self.chainsAttemptedCount = run.chainsAttempted.count
        self.chainsCompletedCount = run.chainsCompleted.count
        self.bestCoverageScore = run.bestChain?.coverageScore
        self.bestChainLength = run.bestChain?.positions.count
        self.starterMoveName = run.bestChain?.positions.first?.moveType.displayName
        self.deadEndCount = run.deadEnds.count
        self.hasGuidance = !run.moveTypeGuidance.isEmpty
    }
}

// MARK: - Markov Matrix (wrapper around transition data)

struct MarkovMatrix {
    let transitions: [RhetoricalMoveType: MoveTransitions]
    let globalPatterns: GlobalPatternAnalysis
    let useParentLevel: Bool
    let sourceSequenceCount: Int
    let totalMoveCount: Int
    let builtAt: Date

    /// Get transition probability from one move to another (0.0 if no data)
    func probability(from source: RhetoricalMoveType, to target: RhetoricalMoveType) -> Double {
        guard let sourceData = transitions[source] else { return 0.0 }
        let totalAfter = sourceData.afterCounts.values.reduce(0, +)
        guard totalAfter > 0 else { return 0.0 }
        return Double(sourceData.afterCounts[target, default: 0]) / Double(totalAfter)
    }

    /// Get ranked next moves after a given move
    func topNextMoves(after move: RhetoricalMoveType, topK: Int = 10) -> [(move: RhetoricalMoveType, probability: Double, count: Int)] {
        guard let moveData = transitions[move] else { return [] }
        let totalAfter = moveData.afterCounts.values.reduce(0, +)
        guard totalAfter > 0 else { return [] }

        return moveData.afterCounts
            .map { (move: $0.key, probability: Double($0.value) / Double(totalAfter), count: $0.value) }
            .sorted { $0.probability > $1.probability }
            .prefix(topK)
            .map { $0 }
    }

    /// Get ranked previous moves before a given move
    func topPreviousMoves(before move: RhetoricalMoveType, topK: Int = 10) -> [(move: RhetoricalMoveType, probability: Double, count: Int)] {
        guard let moveData = transitions[move] else { return [] }
        let totalBefore = moveData.beforeCounts.values.reduce(0, +)
        guard totalBefore > 0 else { return [] }

        return moveData.beforeCounts
            .map { (move: $0.key, probability: Double($0.value) / Double(totalBefore), count: $0.value) }
            .sorted { $0.probability > $1.probability }
            .prefix(topK)
            .map { $0 }
    }

    /// Moves that commonly start sequences, ranked
    func sequenceStarters(topK: Int = 10) -> [(move: RhetoricalMoveType, count: Int)] {
        transitions
            .filter { $0.value.startsSequenceCount > 0 }
            .map { (move: $0.key, count: $0.value.startsSequenceCount) }
            .sorted { $0.count > $1.count }
            .prefix(topK)
            .map { $0 }
    }

    /// Moves that commonly end sequences, ranked
    func sequenceEnders(topK: Int = 10) -> [(move: RhetoricalMoveType, count: Int)] {
        transitions
            .filter { $0.value.endsSequenceCount > 0 }
            .map { (move: $0.key, count: $0.value.endsSequenceCount) }
            .sorted { $0.count > $1.count }
            .prefix(topK)
            .map { $0 }
    }

    /// Total unique move types in the matrix
    var uniqueMoveCount: Int { transitions.count }

    // MARK: - Context-Aware Next Moves (Pure N-Step Corpus Lookup)

    /// Result from an N-step corpus lookup
    struct ContextAwareResult {
        let moves: [(move: RhetoricalMoveType, probability: Double, count: Int)]
        let isDeadEnd: Bool           // true when the N-step lookup returned zero results
        let historyDepthUsed: Int     // 1 through 8 — which lookup was performed
        let lookupKey: String         // the actual key used (e.g., "Hook → Hook → Hook")
    }

    /// Pure N-step corpus lookup. No blending. No fallback.
    ///
    /// `historyDepth` caps the depth. The matrix collects depths 2-8 upfront.
    /// If the lookup returns nothing, it's a dead end — the corpus doesn't have this sequence.
    func contextAwareNextMoves(
        after lastMove: RhetoricalMoveType,
        history: [RhetoricalMoveType],
        parameters: ChainParameters,
        topK: Int = 10
    ) -> ContextAwareResult {

        // Determine effective depth: min(available history, historyDepth cap)
        let effectiveDepth = min(history.count, parameters.historyDepth)

        // --- N-step lookup (depth 2+) via nStepHistories ---
        if effectiveDepth >= 2 {
            let historySlice = history.suffix(effectiveDepth)
            let key = historySlice.map { moveName($0) }.joined(separator: " → ")

            var counts: [RhetoricalMoveType: Int] = [:]
            var total = 0
            for (candidate, data) in transitions {
                let count = data.nStepHistories[effectiveDepth]?[key, default: 0] ?? 0
                if count > 0 {
                    counts[candidate] = count
                    total += count
                }
            }

            if total > 0 {
                let results = counts
                    .map { (move: $0.key, probability: Double($0.value) / Double(total), count: $0.value) }
                    .sorted { $0.probability > $1.probability }
                    .prefix(topK)
                    .map { $0 }
                return ContextAwareResult(moves: results, isDeadEnd: false, historyDepthUsed: effectiveDepth, lookupKey: key)
            } else {
                return ContextAwareResult(moves: [], isDeadEnd: true, historyDepthUsed: effectiveDepth, lookupKey: key)
            }
        }

        // --- 1-step lookup (base case) ---
        guard let moveData = transitions[lastMove] else {
            let key = moveName(lastMove)
            return ContextAwareResult(moves: [], isDeadEnd: true, historyDepthUsed: 1, lookupKey: key)
        }

        let totalAfter = moveData.afterCounts.values.reduce(0, +)
        let key = moveName(lastMove)
        guard totalAfter > 0 else {
            return ContextAwareResult(moves: [], isDeadEnd: true, historyDepthUsed: 1, lookupKey: key)
        }

        let results = moveData.afterCounts
            .map { (move: $0.key, probability: Double($0.value) / Double(totalAfter), count: $0.value) }
            .sorted { $0.probability > $1.probability }
            .prefix(topK)
            .map { $0 }

        return ContextAwareResult(moves: results, isDeadEnd: results.isEmpty, historyDepthUsed: 1, lookupKey: key)
    }

    // MARK: - Private Helpers

    /// Get the display name for a move, respecting the parent-level flag
    private func moveName(_ move: RhetoricalMoveType) -> String {
        useParentLevel ? move.category.rawValue : move.displayName
    }
}

// MARK: - Tree Walk Summary

struct TreeWalkSummary: Codable {
    let pathsExplored: Int
    let pathsCompleted: Int
    let pathsFailed: Int
    let budgetUsed: Int
    let budgetMax: Int
    let totalDeadEndsHit: Int
    let diverseChainIndices: [Int]  // Indices into chainsAttempted for top 5
    var diagnostics: TreeWalkDiagnostics?

    init(pathsExplored: Int, pathsCompleted: Int, pathsFailed: Int,
         budgetUsed: Int, budgetMax: Int, totalDeadEndsHit: Int,
         diverseChainIndices: [Int], diagnostics: TreeWalkDiagnostics? = nil) {
        self.pathsExplored = pathsExplored
        self.pathsCompleted = pathsCompleted
        self.pathsFailed = pathsFailed
        self.budgetUsed = budgetUsed
        self.budgetMax = budgetMax
        self.totalDeadEndsHit = totalDeadEndsHit
        self.diverseChainIndices = diverseChainIndices
        self.diagnostics = diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pathsExplored = try container.decode(Int.self, forKey: .pathsExplored)
        pathsCompleted = try container.decode(Int.self, forKey: .pathsCompleted)
        pathsFailed = try container.decode(Int.self, forKey: .pathsFailed)
        budgetUsed = try container.decode(Int.self, forKey: .budgetUsed)
        budgetMax = try container.decode(Int.self, forKey: .budgetMax)
        totalDeadEndsHit = try container.decode(Int.self, forKey: .totalDeadEndsHit)
        diverseChainIndices = try container.decode([Int].self, forKey: .diverseChainIndices)
        diagnostics = try container.decodeIfPresent(TreeWalkDiagnostics.self, forKey: .diagnostics)
    }
}

// MARK: - Tree Walk Diagnostics

struct TreeWalkDiagnostics: Codable {
    let treeExhausted: Bool                       // true = all paths explored, budget wasn't the limit
    let viableStarterCount: Int                   // starters with available gists
    let totalStartersInMatrix: Int                // starters the matrix knows about
    let positionStats: [PositionLevelStats]       // per-position branching/filtering data
    let limitingFactor: TreeWalkLimitingFactor     // what actually stopped exploration

    // Gist branching stats (nil when gist branching is off)
    let gistBranchingEnabled: Bool
    let avgGistBranchesPerPosition: Double?
    let totalGistBranches: Int?

    init(treeExhausted: Bool, viableStarterCount: Int, totalStartersInMatrix: Int,
         positionStats: [PositionLevelStats], limitingFactor: TreeWalkLimitingFactor,
         gistBranchingEnabled: Bool = false, avgGistBranchesPerPosition: Double? = nil,
         totalGistBranches: Int? = nil) {
        self.treeExhausted = treeExhausted
        self.viableStarterCount = viableStarterCount
        self.totalStartersInMatrix = totalStartersInMatrix
        self.positionStats = positionStats
        self.limitingFactor = limitingFactor
        self.gistBranchingEnabled = gistBranchingEnabled
        self.avgGistBranchesPerPosition = avgGistBranchesPerPosition
        self.totalGistBranches = totalGistBranches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        treeExhausted = try container.decode(Bool.self, forKey: .treeExhausted)
        viableStarterCount = try container.decode(Int.self, forKey: .viableStarterCount)
        totalStartersInMatrix = try container.decode(Int.self, forKey: .totalStartersInMatrix)
        positionStats = try container.decode([PositionLevelStats].self, forKey: .positionStats)
        limitingFactor = try container.decode(TreeWalkLimitingFactor.self, forKey: .limitingFactor)
        gistBranchingEnabled = try container.decodeIfPresent(Bool.self, forKey: .gistBranchingEnabled) ?? false
        avgGistBranchesPerPosition = try container.decodeIfPresent(Double.self, forKey: .avgGistBranchesPerPosition)
        totalGistBranches = try container.decodeIfPresent(Int.self, forKey: .totalGistBranches)
    }
}

struct PositionLevelStats: Codable {
    let positionIndex: Int
    let timesReached: Int                         // how many DFS paths reached this position
    let avgRawCandidates: Double                  // avg matrix-legal candidates before filtering
    let avgFilteredCandidates: Double             // avg candidates after filtering
    let filterAttribution: FilterAttribution      // what killed candidates at this level
}

struct FilterAttribution: Codable {
    var killedByThreshold: Int = 0
    var killedByObservation: Int = 0
    var killedByCategory: Int = 0
    var killedByFreqCap: Int = 0
    var killedByGistAvail: Int = 0
    var killedByBacktrack: Int = 0
    var totalKilled: Int = 0

    /// Top filter as human-readable string
    var topFilter: String {
        let filters: [(String, Int)] = [
            ("Threshold", killedByThreshold),
            ("Sparse Data", killedByObservation),
            ("Category", killedByCategory),
            ("Frequency Cap", killedByFreqCap),
            ("Gist Availability", killedByGistAvail),
            ("Backtrack", killedByBacktrack)
        ]
        return filters.max(by: { $0.1 < $1.1 })?.0 ?? "None"
    }
}

enum TreeWalkLimitingFactor: String, Codable {
    case budgetReached = "Budget Reached"
    case treeExhausted = "Tree Exhausted"
    case sparseCorpus = "Sparse Corpus"
    case gistBottleneck = "Gist Availability"
    case thresholdBottleneck = "Threshold Too High"
}

// MARK: - Chain Build Run (Debug Artifact)

struct ChainBuildRun: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let parameters: ChainParameters

    // Input
    let inputGistCount: Int

    // Results
    var chainsAttempted: [ChainAttempt]
    var chainsCompleted: [ChainAttempt] { chainsAttempted.filter { $0.status == .completed } }
    var chainsFailed: [ChainAttempt] { chainsAttempted.filter { $0.status == .failed } }

    // Dead ends across all chains
    var deadEnds: [DeadEnd]

    // Cascade analysis (computed post-tree-walk, ephemeral)
    var cascadeResults: [CascadeResult]

    // Tree walk data (nil for exhaustive runs)
    var treeWalkSummary: TreeWalkSummary?

    // Per-move-type LLM guidance (keyed by move type, not stored on individual dead ends)
    var moveTypeGuidance: [RhetoricalMoveType: MoveTypeGuidance]

    // Summary
    var bestChain: ChainAttempt? { chainsCompleted.max(by: { $0.coverageScore < $1.coverageScore }) }

    init(
        parameters: ChainParameters,
        inputGistCount: Int,
        chainsAttempted: [ChainAttempt] = [],
        deadEnds: [DeadEnd] = [],
        cascadeResults: [CascadeResult] = [],
        treeWalkSummary: TreeWalkSummary? = nil,
        moveTypeGuidance: [RhetoricalMoveType: MoveTypeGuidance] = [:]
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.parameters = parameters
        self.inputGistCount = inputGistCount
        self.chainsAttempted = chainsAttempted
        self.deadEnds = deadEnds
        self.cascadeResults = cascadeResults
        self.treeWalkSummary = treeWalkSummary
        self.moveTypeGuidance = moveTypeGuidance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        parameters = try container.decode(ChainParameters.self, forKey: .parameters)
        inputGistCount = try container.decode(Int.self, forKey: .inputGistCount)
        chainsAttempted = try container.decode([ChainAttempt].self, forKey: .chainsAttempted)
        deadEnds = try container.decode([DeadEnd].self, forKey: .deadEnds)
        cascadeResults = try container.decodeIfPresent([CascadeResult].self, forKey: .cascadeResults) ?? []
        treeWalkSummary = try container.decodeIfPresent(TreeWalkSummary.self, forKey: .treeWalkSummary)
        moveTypeGuidance = try container.decodeIfPresent([RhetoricalMoveType: MoveTypeGuidance].self, forKey: .moveTypeGuidance) ?? [:]
    }
}

// MARK: - Per-Move-Type Guidance

struct MoveTypeGuidance: Codable {
    let guidance: String                      // LLM response
    let prompt: String                        // Full prompt sent to LLM (for debug)
    let representativePathSoFar: [String]     // Arc from representative dead end
    let representativePositionIndex: Int       // Position from representative dead end
    let debugTrace: String                    // Full decision trace: group formation → representative selection → data lookups → prompt assembly

    init(guidance: String, prompt: String, representativePathSoFar: [String], representativePositionIndex: Int, debugTrace: String = "") {
        self.guidance = guidance
        self.prompt = prompt
        self.representativePathSoFar = representativePathSoFar
        self.representativePositionIndex = representativePositionIndex
        self.debugTrace = debugTrace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guidance = try container.decode(String.self, forKey: .guidance)
        prompt = try container.decode(String.self, forKey: .prompt)
        representativePathSoFar = try container.decode([String].self, forKey: .representativePathSoFar)
        representativePositionIndex = try container.decode(Int.self, forKey: .representativePositionIndex)
        debugTrace = try container.decodeIfPresent(String.self, forKey: .debugTrace) ?? ""
    }
}

// MARK: - Chain Attempt

struct ChainAttempt: Codable, Identifiable {
    let id: UUID
    var positions: [ChainPosition]
    var status: ChainStatus
    var failurePoint: Int?
    var failureReason: String?
    var coverageScore: Double       // % of rambling gists used
    var gistsUsed: [UUID]
    var gistsUnused: [UUID]
    var backtrackCount: Int         // How many backtracks were used
    var starterMove: String?        // Which starter was tried (display name)
    var diversityScore: Double      // Category-arc distance from other selected chains (tree walk)

    var categoryArc: [RhetoricalCategory] {
        positions.map(\.category)
    }

    init(
        positions: [ChainPosition] = [],
        status: ChainStatus = .inProgress,
        coverageScore: Double = 0,
        gistsUsed: [UUID] = [],
        gistsUnused: [UUID] = [],
        backtrackCount: Int = 0,
        starterMove: String? = nil,
        diversityScore: Double = 0.0
    ) {
        self.id = UUID()
        self.positions = positions
        self.status = status
        self.coverageScore = coverageScore
        self.gistsUsed = gistsUsed
        self.gistsUnused = gistsUnused
        self.backtrackCount = backtrackCount
        self.starterMove = starterMove
        self.diversityScore = diversityScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        positions = try container.decode([ChainPosition].self, forKey: .positions)
        status = try container.decode(ChainStatus.self, forKey: .status)
        failurePoint = try container.decodeIfPresent(Int.self, forKey: .failurePoint)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        coverageScore = try container.decode(Double.self, forKey: .coverageScore)
        gistsUsed = try container.decode([UUID].self, forKey: .gistsUsed)
        gistsUnused = try container.decode([UUID].self, forKey: .gistsUnused)
        backtrackCount = try container.decodeIfPresent(Int.self, forKey: .backtrackCount) ?? 0
        starterMove = try container.decodeIfPresent(String.self, forKey: .starterMove)
        diversityScore = try container.decodeIfPresent(Double.self, forKey: .diversityScore) ?? 0.0
    }
}

enum ChainStatus: String, Codable {
    case inProgress
    case completed
    case failed
}

// MARK: - Chain Position

struct ChainPosition: Codable, Identifiable {
    let id: UUID
    let positionIndex: Int
    let category: RhetoricalCategory
    let moveType: RhetoricalMoveType
    let mappedGistId: UUID?             // Which rambling gist was mapped here (nil = gap)
    let markovProbability: Double       // Transition probability from previous position
    let markovContext: [String]         // History that informed this decision
    let selectionReason: String
    let alternativesConsidered: [Alternative]

    init(
        positionIndex: Int,
        category: RhetoricalCategory,
        moveType: RhetoricalMoveType,
        mappedGistId: UUID? = nil,
        markovProbability: Double,
        markovContext: [String] = [],
        selectionReason: String,
        alternativesConsidered: [Alternative] = []
    ) {
        self.id = UUID()
        self.positionIndex = positionIndex
        self.category = category
        self.moveType = moveType
        self.mappedGistId = mappedGistId
        self.markovProbability = markovProbability
        self.markovContext = markovContext
        self.selectionReason = selectionReason
        self.alternativesConsidered = alternativesConsidered
    }
}

// MARK: - Alternative (rejected candidate)

struct Alternative: Codable, Identifiable {
    let id: UUID
    let category: RhetoricalCategory
    let moveType: RhetoricalMoveType
    let probability: Double
    let rejectionReason: String

    init(
        category: RhetoricalCategory,
        moveType: RhetoricalMoveType,
        probability: Double,
        rejectionReason: String
    ) {
        self.id = UUID()
        self.category = category
        self.moveType = moveType
        self.probability = probability
        self.rejectionReason = rejectionReason
    }
}

// MARK: - Dead End

struct DeadEnd: Codable, Identifiable {
    let id: UUID
    let chainAttemptId: UUID
    let positionIndex: Int
    let pathSoFar: [String]             // Move names in order
    let deadEndType: DeadEndType
    let whatWasNeeded: String
    let whatWasMissing: String
    let suggestedUserAction: String

    // Structured diagnostic data
    var candidatesFound: Int            // Raw candidate count from matrix
    var candidateDetails: [CandidateDetail]  // Per-candidate breakdown
    var lookupDepthUsed: Int            // Which N-step depth was used
    var lookupKey: String               // The history key queried
    var wasBacktrackRetry: Bool         // True if from a retry after backtrack

    // Tree walk enrichment
    var upsideScore: Double             // Computed post-tree-walk per move-type group (0.0 default)
    var ramblingGuidance: String        // LLM-populated for top N move-type groups ("" default)
    var guidancePrompt: String          // Full prompt sent to LLM (for debug)
    var guidanceMoveType: String        // Which move type generated this guidance (for debug)
    var rawCandidateMoveTypes: [RhetoricalMoveType]  // Matrix-legal moves after depth fallback, before filtering
    var pathGistIds: [UUID?]             // Gist ID assigned at each position (parallel to pathSoFar), populated by chain builder

    init(
        chainAttemptId: UUID,
        positionIndex: Int,
        pathSoFar: [String],
        deadEndType: DeadEndType,
        whatWasNeeded: String,
        whatWasMissing: String,
        suggestedUserAction: String,
        candidatesFound: Int = 0,
        candidateDetails: [CandidateDetail] = [],
        lookupDepthUsed: Int = 0,
        lookupKey: String = "",
        wasBacktrackRetry: Bool = false,
        upsideScore: Double = 0.0,
        ramblingGuidance: String = "",
        guidancePrompt: String = "",
        guidanceMoveType: String = "",
        rawCandidateMoveTypes: [RhetoricalMoveType] = [],
        pathGistIds: [UUID?] = []
    ) {
        self.id = UUID()
        self.chainAttemptId = chainAttemptId
        self.positionIndex = positionIndex
        self.pathSoFar = pathSoFar
        self.deadEndType = deadEndType
        self.whatWasNeeded = whatWasNeeded
        self.whatWasMissing = whatWasMissing
        self.suggestedUserAction = suggestedUserAction
        self.candidatesFound = candidatesFound
        self.candidateDetails = candidateDetails
        self.lookupDepthUsed = lookupDepthUsed
        self.lookupKey = lookupKey
        self.wasBacktrackRetry = wasBacktrackRetry
        self.upsideScore = upsideScore
        self.ramblingGuidance = ramblingGuidance
        self.guidancePrompt = guidancePrompt
        self.guidanceMoveType = guidanceMoveType
        self.rawCandidateMoveTypes = rawCandidateMoveTypes
        self.pathGistIds = pathGistIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        chainAttemptId = try container.decode(UUID.self, forKey: .chainAttemptId)
        positionIndex = try container.decode(Int.self, forKey: .positionIndex)
        pathSoFar = try container.decode([String].self, forKey: .pathSoFar)
        deadEndType = try container.decode(DeadEndType.self, forKey: .deadEndType)
        whatWasNeeded = try container.decode(String.self, forKey: .whatWasNeeded)
        whatWasMissing = try container.decode(String.self, forKey: .whatWasMissing)
        suggestedUserAction = try container.decode(String.self, forKey: .suggestedUserAction)
        candidatesFound = try container.decodeIfPresent(Int.self, forKey: .candidatesFound) ?? 0
        candidateDetails = try container.decodeIfPresent([CandidateDetail].self, forKey: .candidateDetails) ?? []
        lookupDepthUsed = try container.decodeIfPresent(Int.self, forKey: .lookupDepthUsed) ?? 0
        lookupKey = try container.decodeIfPresent(String.self, forKey: .lookupKey) ?? ""
        wasBacktrackRetry = try container.decodeIfPresent(Bool.self, forKey: .wasBacktrackRetry) ?? false
        upsideScore = try container.decodeIfPresent(Double.self, forKey: .upsideScore) ?? 0.0
        ramblingGuidance = try container.decodeIfPresent(String.self, forKey: .ramblingGuidance) ?? ""
        guidancePrompt = try container.decodeIfPresent(String.self, forKey: .guidancePrompt) ?? ""
        guidanceMoveType = try container.decodeIfPresent(String.self, forKey: .guidanceMoveType) ?? ""
        rawCandidateMoveTypes = try container.decodeIfPresent([RhetoricalMoveType].self, forKey: .rawCandidateMoveTypes) ?? []
        pathGistIds = try container.decodeIfPresent([UUID?].self, forKey: .pathGistIds) ?? []
    }
}

// MARK: - Candidate Detail (structured dead end diagnostic)

struct CandidateDetail: Codable, Identifiable {
    let id: UUID
    let moveName: String
    let probability: Double
    let observationCount: Int
    let rejectionReason: String

    init(moveName: String, probability: Double, observationCount: Int, rejectionReason: String) {
        self.id = UUID()
        self.moveName = moveName
        self.probability = probability
        self.observationCount = observationCount
        self.rejectionReason = rejectionReason
    }
}

enum DeadEndType: String, Codable {
    case missingContent          // Rambling didn't provide content for this position
    case transitionImpossible    // Valid content exists but no Markov path to it
    case coverageGap             // Chain completed but too many gists unused
    case sparseData              // Transition exists but too few observations
}

// MARK: - Cascade Analysis Result (per move-type group)

struct CascadeResult: Codable, Identifiable {
    let id: UUID
    let moveType: RhetoricalMoveType
    let deadEndCount: Int

    // Level 1: what happens if we fix this move?
    let avgRunwayAfterFix: Double            // avg additional positions gained
    let completionCount: Int                 // dead ends that become completions
    let nextBlockageMove: RhetoricalMoveType? // most common next blocker
    let nextBlockageCount: Int               // paths hitting that next blocker

    // Level 2: what happens if we fix this + the next blocker? (top 5 groups only)
    let level2CompletionCount: Int
    let level2NextBlockageMove: RhetoricalMoveType?
    let level2NextBlockageCount: Int

    init(
        moveType: RhetoricalMoveType,
        deadEndCount: Int,
        avgRunwayAfterFix: Double,
        completionCount: Int,
        nextBlockageMove: RhetoricalMoveType?,
        nextBlockageCount: Int,
        level2CompletionCount: Int = 0,
        level2NextBlockageMove: RhetoricalMoveType? = nil,
        level2NextBlockageCount: Int = 0
    ) {
        self.id = UUID()
        self.moveType = moveType
        self.deadEndCount = deadEndCount
        self.avgRunwayAfterFix = avgRunwayAfterFix
        self.completionCount = completionCount
        self.nextBlockageMove = nextBlockageMove
        self.nextBlockageCount = nextBlockageCount
        self.level2CompletionCount = level2CompletionCount
        self.level2NextBlockageMove = level2NextBlockageMove
        self.level2NextBlockageCount = level2NextBlockageCount
    }
}

// MARK: - Gap Response (user rambling in response to dead end guidance)

enum GapExtractionStatus: String, Codable {
    case notStarted
    case extracting
    case completed
    case failed
}

struct GapResponse: Codable, Identifiable {
    let id: UUID
    let createdAt: Date

    // Which gap this responds to
    let targetMoveType: RhetoricalMoveType
    let guidanceQuestion: String
    let guidancePrompt: String          // Full LLM prompt context (arc, positions, move def, corpus)
    let sourceDeadEndIds: [UUID]
    let upsideScore: Double

    // User input
    var rawRamblingText: String

    // Extraction results
    var extractedGists: [RamblingGist]
    var extractionStatus: GapExtractionStatus
    var extractionDurationSeconds: Double?

    // Post-extraction analysis
    var eligibleMoves: [RhetoricalMoveType: Int]   // move → gist count from expansion
    var coversTargetMove: Bool

    init(
        id: UUID = UUID(),
        targetMoveType: RhetoricalMoveType,
        guidanceQuestion: String,
        guidancePrompt: String = "",
        sourceDeadEndIds: [UUID],
        upsideScore: Double,
        rawRamblingText: String = "",
        extractedGists: [RamblingGist] = [],
        extractionStatus: GapExtractionStatus = .notStarted,
        extractionDurationSeconds: Double? = nil,
        eligibleMoves: [RhetoricalMoveType: Int] = [:],
        coversTargetMove: Bool = false
    ) {
        self.id = id
        self.createdAt = Date()
        self.targetMoveType = targetMoveType
        self.guidanceQuestion = guidanceQuestion
        self.guidancePrompt = guidancePrompt
        self.sourceDeadEndIds = sourceDeadEndIds
        self.upsideScore = upsideScore
        self.rawRamblingText = rawRamblingText
        self.extractedGists = extractedGists
        self.extractionStatus = extractionStatus
        self.extractionDurationSeconds = extractionDurationSeconds
        self.eligibleMoves = eligibleMoves
        self.coversTargetMove = coversTargetMove
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        targetMoveType = try container.decode(RhetoricalMoveType.self, forKey: .targetMoveType)
        guidanceQuestion = try container.decode(String.self, forKey: .guidanceQuestion)
        guidancePrompt = try container.decodeIfPresent(String.self, forKey: .guidancePrompt) ?? ""
        sourceDeadEndIds = try container.decodeIfPresent([UUID].self, forKey: .sourceDeadEndIds) ?? []
        upsideScore = try container.decodeIfPresent(Double.self, forKey: .upsideScore) ?? 0
        rawRamblingText = try container.decodeIfPresent(String.self, forKey: .rawRamblingText) ?? ""
        extractedGists = try container.decodeIfPresent([RamblingGist].self, forKey: .extractedGists) ?? []
        extractionStatus = try container.decodeIfPresent(GapExtractionStatus.self, forKey: .extractionStatus) ?? .notStarted
        extractionDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .extractionDurationSeconds)
        eligibleMoves = try container.decodeIfPresent([RhetoricalMoveType: Int].self, forKey: .eligibleMoves) ?? [:]
        coversTargetMove = try container.decodeIfPresent(Bool.self, forKey: .coversTargetMove) ?? false
    }
}

// MARK: - Chain Parameters (Tunable)

struct ChainParameters: Codable {
    // Markov constraints
    var transitionThreshold: Double         // Below this, transition is dead end
    var historyDepth: Int                   // 1-step, 2-step, or 3-step context
    var minObservationCount: Int            // Transitions with fewer get flagged
    var useParentLevel: Bool                // 6-category vs 25-move level

    // Chain structure
    var coverageTarget: Double              // Min % of gists a chain should use
    var maxChainLength: Int
    var minChainLength: Int
    var allowConsecutiveSameCategory: Bool
    var maxConsecutiveSameCategory: Int

    // Position constraints
    var positionConstraintWeight: Double    // 0 = ignore, 1 = hard constraint
    var positionConstraintZones: PositionConstraintZone

    // Algorithm
    var algorithmType: ChainAlgorithm
    var monteCarloSimulations: Int          // Also used as path budget for tree walk
    var monteCarloTemperature: Double

    // Tree walk guidance
    var maxGuidanceGaps: Int               // Top N move-type groups that get LLM guidance (3-10)
    var upsideFrequencyWeight: Double      // How much dead end count matters (more dead ends = bigger bottleneck)
    var upsideDepthWeight: Double          // How much late-chain position matters (deeper = closer to completion)
    var upsideDiversityWeight: Double      // How many distinct starters are blocked (systemic bottleneck)

    // Diversity (tree walk only, budget >= 1000)
    var maxMoveTypeShare: Double           // Max fraction of chain any single move type can occupy (0.35 = 35%, 1.0 = disabled)

    // Gist branching (tree walk only)
    var enableGistBranching: Bool          // Also branch on gist assignments, not just moves
    var maxGistBranchesPerMove: Int        // Max alternative gists to explore per move (most constrained first)

    init(
        transitionThreshold: Double = 0.05,
        historyDepth: Int = 3,
        minObservationCount: Int = 2,
        useParentLevel: Bool = false,
        coverageTarget: Double = 1.0,
        maxChainLength: Int = 50,
        minChainLength: Int = 3,
        allowConsecutiveSameCategory: Bool = true,
        maxConsecutiveSameCategory: Int = 3,
        positionConstraintWeight: Double = 0.3,
        positionConstraintZones: PositionConstraintZone = .startAndEnd,
        algorithmType: ChainAlgorithm = .exhaustive,
        monteCarloSimulations: Int = 1000,
        monteCarloTemperature: Double = 1.0,
        maxGuidanceGaps: Int = 5,
        upsideFrequencyWeight: Double = 0.4,
        upsideDepthWeight: Double = 0.3,
        upsideDiversityWeight: Double = 0.3,
        maxMoveTypeShare: Double = 1.0,
        enableGistBranching: Bool = false,
        maxGistBranchesPerMove: Int = 3
    ) {
        self.transitionThreshold = transitionThreshold
        self.historyDepth = historyDepth
        self.minObservationCount = minObservationCount
        self.useParentLevel = useParentLevel
        self.coverageTarget = coverageTarget
        self.maxChainLength = maxChainLength
        self.minChainLength = minChainLength
        self.allowConsecutiveSameCategory = allowConsecutiveSameCategory
        self.maxConsecutiveSameCategory = maxConsecutiveSameCategory
        self.positionConstraintWeight = positionConstraintWeight
        self.positionConstraintZones = positionConstraintZones
        self.algorithmType = algorithmType
        self.monteCarloSimulations = monteCarloSimulations
        self.monteCarloTemperature = monteCarloTemperature
        self.maxGuidanceGaps = maxGuidanceGaps
        self.upsideFrequencyWeight = upsideFrequencyWeight
        self.upsideDepthWeight = upsideDepthWeight
        self.upsideDiversityWeight = upsideDiversityWeight
        self.maxMoveTypeShare = maxMoveTypeShare
        self.enableGistBranching = enableGistBranching
        self.maxGistBranchesPerMove = maxGistBranchesPerMove
    }

    // Migration key for decoding old property names
    private struct MigrationKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transitionThreshold = try container.decode(Double.self, forKey: .transitionThreshold)
        historyDepth = try container.decode(Int.self, forKey: .historyDepth)
        minObservationCount = try container.decode(Int.self, forKey: .minObservationCount)
        useParentLevel = try container.decode(Bool.self, forKey: .useParentLevel)
        let decodedCoverage = try container.decodeIfPresent(Double.self, forKey: .coverageTarget) ?? 1.0
        coverageTarget = decodedCoverage <= 0.80 ? 1.0 : decodedCoverage  // Migrate old 80% default → 100%
        let decodedMaxChain = try container.decodeIfPresent(Int.self, forKey: .maxChainLength) ?? 50
        maxChainLength = decodedMaxChain <= 15 ? 50 : decodedMaxChain  // Migrate old 15-cap default → 50
        minChainLength = try container.decode(Int.self, forKey: .minChainLength)
        allowConsecutiveSameCategory = try container.decode(Bool.self, forKey: .allowConsecutiveSameCategory)
        maxConsecutiveSameCategory = try container.decode(Int.self, forKey: .maxConsecutiveSameCategory)
        positionConstraintWeight = try container.decode(Double.self, forKey: .positionConstraintWeight)
        positionConstraintZones = try container.decode(PositionConstraintZone.self, forKey: .positionConstraintZones)
        algorithmType = try container.decode(ChainAlgorithm.self, forKey: .algorithmType)
        monteCarloSimulations = try container.decode(Int.self, forKey: .monteCarloSimulations)
        monteCarloTemperature = try container.decode(Double.self, forKey: .monteCarloTemperature)
        maxGuidanceGaps = try container.decodeIfPresent(Int.self, forKey: .maxGuidanceGaps) ?? 5
        // Migrate renamed upside weights: try new key, fall back to old key name
        let migrationContainer = try decoder.container(keyedBy: MigrationKey.self)
        upsideFrequencyWeight = try container.decodeIfPresent(Double.self, forKey: .upsideFrequencyWeight)
            ?? (try? migrationContainer.decodeIfPresent(Double.self, forKey: MigrationKey(stringValue: "upsideProgressWeight")!)) ?? 0.4
        upsideDepthWeight = try container.decodeIfPresent(Double.self, forKey: .upsideDepthWeight)
            ?? (try? migrationContainer.decodeIfPresent(Double.self, forKey: MigrationKey(stringValue: "upsideCoverageWeight")!)) ?? 0.3
        upsideDiversityWeight = try container.decodeIfPresent(Double.self, forKey: .upsideDiversityWeight) ?? 0.3
        maxMoveTypeShare = try container.decodeIfPresent(Double.self, forKey: .maxMoveTypeShare) ?? 1.0
        enableGistBranching = try container.decodeIfPresent(Bool.self, forKey: .enableGistBranching) ?? false
        maxGistBranchesPerMove = try container.decodeIfPresent(Int.self, forKey: .maxGistBranchesPerMove) ?? 3
    }
}

enum PositionConstraintZone: String, Codable, CaseIterable {
    case startOnly = "Start Only"
    case endOnly = "End Only"
    case startAndEnd = "Start + End"
    case all = "All Positions"
    case none = "None"
}

enum ChainAlgorithm: String, Codable, CaseIterable {
    case exhaustive = "Exhaustive"
    case treeWalk = "Tree Walk"
    case monteCarlo = "Monte Carlo"
    case regimeSwitching = "Regime Switching"
    case hybrid = "Hybrid"
}

// ORPHANED — GistMappingMethod was used by the old GistAvailabilityIndex.
// The chain builder now uses FrameExpansionIndex exclusively.
// This enum can likely be deleted along with GistAvailabilityIndex.swift.
enum GistMappingMethod: String, Codable, CaseIterable {
    case frameMatch = "Frame Match"
    case categoryMatch = "Category Match"
    case combined = "Combined"
}

// MARK: - Chain Trace Explorer (Ephemeral — computed on demand, not persisted)

/// Source for a trace replay — either a dead end or a completed chain
enum TraceSource: Identifiable {
    case deadEnd(DeadEnd)
    case chainAttempt(ChainAttempt)

    var id: String {
        switch self {
        case .deadEnd(let de): return "de-\(de.id)"
        case .chainAttempt(let ca): return "ca-\(ca.id)"
        }
    }

    var pathMoves: [RhetoricalMoveType] {
        switch self {
        case .deadEnd(let de):
            return de.pathSoFar.compactMap { RhetoricalMoveType.parse($0) }
        case .chainAttempt(let ca):
            return ca.positions.map(\.moveType)
        }
    }

    var label: String {
        switch self {
        case .deadEnd(let de):
            return "Dead end at P\(de.positionIndex): \(de.pathSoFar.last ?? "?")"
        case .chainAttempt(let ca):
            return "\(ca.status.rawValue) chain (\(ca.positions.count) pos)"
        }
    }
}

/// One position in a replayed chain trace.
struct TracePosition: Identifiable {
    let id = UUID()
    let positionIndex: Int
    let moveType: RhetoricalMoveType
    let assignedGistId: UUID?
    let assignedGistChunkIndex: Int?
    let assignedGistFrame: GistFrame?
    let rawCandidateCount: Int
    let filteredCandidateCount: Int
    let lookupDepthUsed: Int
    let lookupKey: String
    let candidates: [TraceCandidateStatus]
    let gistsConsumedSoFar: Int
    let totalGists: Int
    let isOverridden: Bool              // true if user changed this via what-if
}

/// Status of one candidate at a trace position.
struct TraceCandidateStatus: Identifiable {
    let id = UUID()
    let moveType: RhetoricalMoveType
    let probability: Double
    let observationCount: Int
    let totalGistsForMove: Int
    let availableGists: Int
    let consumedGists: Int
    let passesFilter: Bool
    let rejectionReason: String?
    let wasSelected: Bool
}

// MARK: - Opener Matcher Models

/// Result of a single opener match run — 3 strategies × 2 matches each.
/// `selectedVideoId` feeds downstream: synthesis Pass 1 uses the selected opener's
/// corpus sections as the execution model for positions 0-1.
struct OpenerMatchResult: Codable {
    let id: UUID
    let ramblingProfile: RamblingProfile
    let strategies: [OpenerStrategy]
    let antiMatches: [OpenerAntiMatch]
    let promptVersion: String
    let analyzedAt: Date
    let corpusVideoCount: Int
    let inputTokenEstimate: Int
    let promptSent: String
    let systemPromptSent: String
    let rawResponse: String
    let telemetry: SectionTelemetry?
    var selectedVideoId: String?
}

/// LLM's 5-dimension structural read of the user's rambling.
/// First thing to check when a match feels wrong.
struct RamblingProfile: Codable {
    let entryEnergy: String
    let emotionalTrajectory: String
    let stakesShape: String
    let complexityLoad: String
    let speakerPosture: String
}

struct OpenerStrategy: Codable, Identifiable {
    let id: UUID
    let strategyId: String
    let strategyName: String
    let strategyDescription: String
    let matches: [OpenerRankedMatch]
    let patternLabel: String?           // nil for old (pre-pattern) runs
}

struct OpenerRankedMatch: Codable, Identifiable {
    let id: UUID
    let rank: Int
    let videoId: String
    let videoTitle: String
    let matchReasoning: String
    let openingStrategySummary: String
}

struct OpenerAntiMatch: Codable, Identifiable {
    let id: UUID
    let videoId: String
    let videoTitle: String
    let reasoning: String
}

// MARK: - Opener Gist Filter Models (Step 2)

/// Result of deterministic + LLM gist filtering.
/// Stores 2 matched gist IDs per strategy (one per opening position).
struct OpenerGistFilterResult: Codable {
    let id: UUID
    let strategyFilters: [OpenerStrategyFilter]
    let filteredAt: Date
}

/// Per-strategy gist filter: deterministic narrowing + LLM selection for 2 positions.
struct OpenerStrategyFilter: Codable, Identifiable {
    let id: UUID
    let strategyId: String          // "A", "B", "C"
    let strategyName: String
    let positions: [OpenerFilterPosition]
    let systemPromptSent: String
    let userPromptSent: String
    let rawResponse: String
    let telemetry: SectionTelemetry?
}

/// One opening position's filtering pipeline.
struct OpenerFilterPosition: Codable, Identifiable {
    let id: UUID
    let positionIndex: Int          // 0 or 1

    // Corpus reference
    let corpusMoveLabel: String
    let corpusMoveCategory: String
    let corpusSectionText: String

    // Deterministic filter results
    let eligibleFrames: [GistFrame]
    let candidateGistIds: [UUID]
    let candidateCount: Int

    // LLM selection
    let selectedGistId: UUID?
    let selectionReasoning: String
}

// MARK: - Opener Draft Models (Step 3)

/// Container for 3 drafted openings (one per strategy) from a single Step 3 run.
struct OpenerDraftResult: Codable {
    let id: UUID
    let drafts: [OpenerDraft]
    let draftedAt: Date
}

/// One LLM-drafted opening following a strategy's structural template (Step 3).
struct OpenerDraft: Codable, Identifiable {
    let id: UUID
    let strategyId: String
    let strategyName: String
    let draftText: String
    let systemPromptSent: String
    let userPromptSent: String
    let rawResponse: String
    let telemetry: SectionTelemetry?
}

// MARK: - Opener Rewrite Models (Step 4)

/// Container for 3 voice-corrected rewrites (one per strategy) from a single Step 3 run.
struct OpenerRewriteResult: Codable {
    let id: UUID
    let rewrites: [OpenerRewrite]
    let rewrittenAt: Date
}

/// One voice-corrected rewrite of a Step 2 draft.
struct OpenerRewrite: Codable, Identifiable {
    let id: UUID
    let strategyId: String
    let strategyName: String
    let rewriteText: String
    let voiceAnalysis: String
    let originalDraftText: String
    let systemPromptSent: String
    let userPromptSent: String
    let rawResponse: String
    let telemetry: SectionTelemetry?
}
