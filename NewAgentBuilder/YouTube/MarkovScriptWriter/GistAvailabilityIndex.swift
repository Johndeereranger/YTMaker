//
//  GistAvailabilityIndex.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/3/26.
//
//  ORPHANED — This file is no longer used by the chain builder.
//  The chain builder now uses FrameExpansionIndex.swift exclusively.
//  This file can likely be deleted.
//
//  Original purpose: Availability index mapping RamblingGists to RhetoricalMoveTypes
//  via 4-tier relevance scoring (moveLabel, frame expansion, telemetry, category fallback)
//  with 3 mapping methods (frameMatch, categoryMatch, combined).
//

import Foundation

// MARK: - GistAvailabilityIndex

struct GistAvailabilityIndex {

    /// Which gists can fill which moves, with relevance scores. Sorted by relevance descending.
    let moveToGists: [RhetoricalMoveType: [(gistId: UUID, relevance: Double)]]

    /// Which moves each gist can fill, with relevance scores. Sorted by relevance descending.
    let gistToMoves: [UUID: [(move: RhetoricalMoveType, relevance: Double)]]

    /// Category-level summary (gist IDs per category, derived from expansion moves)
    let categoryToGistIds: [RhetoricalCategory: [UUID]]

    /// How many move slots each gist can fill (lower = more constrained = assign first)
    let constraintScores: [UUID: Int]

    /// Mapping method used
    let mappingMethod: GistMappingMethod

    /// Total gist count
    let totalGists: Int

    // MARK: - Init

    init(gists: [RamblingGist], method: GistMappingMethod) {
        self.mappingMethod = method
        self.totalGists = gists.count

        var moveMap: [RhetoricalMoveType: [(gistId: UUID, relevance: Double)]] = [:]
        var gistMap: [UUID: [(move: RhetoricalMoveType, relevance: Double)]] = [:]
        var catMap: [RhetoricalCategory: Set<UUID>] = [:]
        var constraints: [UUID: Int] = [:]

        for gist in gists {
            var allMoves: [(move: RhetoricalMoveType, relevance: Double)] = []

            // Get expansion moves for this gist's frame
            let expansion = GistAvailabilityIndex.expansionMoves(for: gist.gistA.frame)

            for (idx, move) in expansion.enumerated() {
                let rawRelevance = GistAvailabilityIndex.moveRelevance(gist: gist, move: move)
                // Primary expansion move gets full weight, secondary gets 0.85x
                let weight: Double = idx == 0 ? 1.0 : 0.85
                let scaledRelevance = max(rawRelevance, 0.2) * weight
                allMoves.append((move: move, relevance: scaledRelevance))
            }

            // When using categoryMatch or combined, also check moveLabel for additional coverage
            if method == .categoryMatch || method == .combined {
                if let moveLabel = gist.moveLabel,
                   let parsedMove = RhetoricalMoveType.parse(moveLabel),
                   !allMoves.contains(where: { $0.move == parsedMove }) {
                    let rawRelevance = GistAvailabilityIndex.moveRelevance(gist: gist, move: parsedMove)
                    allMoves.append((move: parsedMove, relevance: max(rawRelevance, 0.2) * 0.6))
                }
            }

            // Populate indexes
            for entry in allMoves {
                moveMap[entry.move, default: []].append((gistId: gist.id, relevance: entry.relevance))
                // Derive category from the move itself
                catMap[entry.move.category, default: []].insert(gist.id)
            }

            // Sort by relevance descending
            allMoves.sort { $0.relevance > $1.relevance }
            gistMap[gist.id] = allMoves
            constraints[gist.id] = allMoves.count
        }

        // Sort each move's gist list by relevance descending
        for (move, gistList) in moveMap {
            moveMap[move] = gistList.sorted { $0.relevance > $1.relevance }
        }

        self.moveToGists = moveMap
        self.gistToMoves = gistMap
        self.categoryToGistIds = catMap.mapValues { Array($0) }
        self.constraintScores = constraints
    }

    // MARK: - Expansion Table (Static)

    /// Frame → renderable moves. First move is primary (Tier 2a: 0.9), rest are secondary (Tier 2b: 0.7).
    /// Each gist is scored against its own frame's expansion — no cross-frame lookup.
    static func expansionMoves(for frame: GistFrame) -> [RhetoricalMoveType] {
        switch frame {
        case .personalNarrative: return [.sceneSet, .personalStake, .historicalContext, .commonBelief, .complication, .caseStudy]
        case .factualClaim:      return [.shockingFact, .dataPresent, .evidenceStack, .authorityCite, .commonBelief, .hiddenTruth]
        case .wondering:         return [.questionHook, .mysteryRaise, .complication]
        case .problemStatement:  return [.complication, .counterargument, .contradiction, .stakesEstablishment, .mysteryRaise]
        case .explanation:       return [.defineFrame, .rootCause, .hiddenTruth, .reframe, .dataPresent]
        case .comparison:        return [.analogy, .caseStudy, .reframe, .connectionReveal]
        case .stakesDeclaration: return [.stakesEstablishment, .personalStake, .shockingFact, .implication, .viewerAddress]
        case .patternNotice:     return [.connectionReveal, .rootCause, .reframe, .hiddenTruth, .synthesis]
        case .correction:        return [.reframe, .hiddenTruth, .counterargument, .contradiction, .commonBelief]
        case .takeaway:          return [.synthesis, .implication, .futureProject, .viewerAddress]
        }
    }

    /// Derives primary category from first expansion move, secondary categories from rest.
    /// Used by views for display badges.
    static func primaryCategory(for frame: GistFrame) -> (primary: RhetoricalCategory, secondaries: [RhetoricalCategory]) {
        let moves = expansionMoves(for: frame)
        let primary = moves.first!.category
        let secondaries = Array(Set(moves.dropFirst().map(\.category)).subtracting([primary]))
        return (primary, secondaries)
    }

    // MARK: - Move Relevance Scoring

    /// Compute how well a gist fits a specific rhetorical move (0.0-1.0).
    /// Four tiers:
    ///   1. Direct moveLabel match → 1.0
    ///   2. Frame expansion match → 0.9 (primary) / 0.7 (secondary)
    ///   3. Telemetry signal match → 0.3-0.6
    ///   4. Category fallback → 0.2
    static func moveRelevance(gist: RamblingGist, move: RhetoricalMoveType) -> Double {
        // Tier 1: Direct moveLabel match
        if let moveLabel = gist.moveLabel,
           let parsedMove = RhetoricalMoveType.parse(moveLabel),
           parsedMove == move {
            return 1.0
        }

        // Tier 2: Frame expansion match
        let expansion = expansionMoves(for: gist.gistA.frame)
        if let idx = expansion.firstIndex(of: move) {
            return idx == 0 ? 0.9 : 0.7  // Primary = 0.9, secondary = 0.7
        }

        // Tier 3: Telemetry signal match
        if let telemetry = gist.telemetry {
            let telemetryScore = telemetryRelevance(telemetry: telemetry, move: move)
            if telemetryScore > 0.0 {
                return telemetryScore
            }
        }

        // Tier 4: Category fallback
        return 0.2
    }

    /// Telemetry-based relevance signals (0.3-0.6).
    private static func telemetryRelevance(telemetry: ChunkTelemetry, move: RhetoricalMoveType) -> Double {
        switch move {
        case .questionHook, .mysteryRaise:
            if telemetry.questionCount >= 2 { return 0.6 }
            if telemetry.questionCount >= 1 { return 0.4 }
        case .contradiction, .counterargument:
            if telemetry.contrastCount >= 2 { return 0.6 }
            if telemetry.contrastCount >= 1 { return 0.4 }
        case .dataPresent:
            if telemetry.numberCount >= 3 { return 0.6 }
            if telemetry.numberCount >= 1 { return 0.4 }
        case .personalStake:
            if telemetry.firstPersonCount >= 3 { return 0.5 }
        case .viewerAddress:
            if telemetry.secondPersonCount >= 2 { return 0.5 }
        case .historicalContext:
            if telemetry.temporalCount >= 2 { return 0.5 }
        case .authorityCite:
            if telemetry.quoteCount >= 1 { return 0.5 }
        case .analogy:
            if telemetry.spatialCount >= 1 { return 0.3 }
        default:
            break
        }
        return 0.0
    }

    // MARK: - Query Methods

    /// Get available gists for a move, excluding already-used gists. Sorted by relevance descending.
    func availableGists(for move: RhetoricalMoveType, excluding used: Set<UUID>) -> [(gistId: UUID, relevance: Double)] {
        guard let gists = moveToGists[move] else { return [] }
        return gists.filter { !used.contains($0.gistId) }
    }

    /// Check if any gists are available for a move (fast path).
    func hasAvailableGists(for move: RhetoricalMoveType, excluding used: Set<UUID>) -> Bool {
        guard let gists = moveToGists[move] else { return false }
        return gists.contains { !used.contains($0.gistId) }
    }

    /// Which categories still have available gists?
    func coverableCategories(excluding used: Set<UUID>) -> Set<RhetoricalCategory> {
        var result: Set<RhetoricalCategory> = []
        for (category, gistIds) in categoryToGistIds {
            if gistIds.contains(where: { !used.contains($0) }) {
                result.insert(category)
            }
        }
        return result
    }

    /// How many move slots this gist can fill (lower = more constrained = assign first).
    func constraintScore(for gistId: UUID) -> Int {
        constraintScores[gistId] ?? 0
    }

    /// Best relevance score for a gist at a specific move.
    func relevance(gistId: UUID, for move: RhetoricalMoveType) -> Double {
        guard let moves = gistToMoves[gistId] else { return 0.0 }
        return moves.first(where: { $0.move == move })?.relevance ?? 0.0
    }

    /// Pick the most-constrained available gist for a move (fewest alternative positions).
    /// Ties broken by highest relevance.
    func mostConstrainedGist(for move: RhetoricalMoveType, excluding used: Set<UUID>) -> (gistId: UUID, relevance: Double)? {
        let available = availableGists(for: move, excluding: used)
        guard !available.isEmpty else { return nil }

        return available.min { a, b in
            let scoreA = constraintScore(for: a.gistId)
            let scoreB = constraintScore(for: b.gistId)
            if scoreA != scoreB { return scoreA < scoreB }
            return a.relevance > b.relevance
        }
    }

    // MARK: - Report

    /// Generate a human-readable availability report for copy/export.
    func report(gists: [RamblingGist]) -> String {
        var lines: [String] = []
        lines.append("=== Gist Availability Report ===")
        lines.append("Method: \(mappingMethod.rawValue)")
        lines.append("Total Gists: \(totalGists)")
        lines.append("")

        // Category coverage
        lines.append("--- Category Coverage ---")
        for category in RhetoricalCategory.allCases {
            let count = categoryToGistIds[category]?.count ?? 0
            let status = count == 0 ? "EMPTY" : "\(count) gists"
            lines.append("  \(category.rawValue): \(status)")
        }
        lines.append("")

        // Per-gist breakdown
        lines.append("--- Per-Gist Mapping ---")
        for gist in gists {
            let frame = gist.gistA.frame.displayName
            let moveLabel = gist.moveLabel ?? "none"
            let constraint = constraintScore(for: gist.id)
            lines.append("Chunk \(gist.chunkIndex + 1) | Frame: \(frame) | Move: \(moveLabel) | Slots: \(constraint)")

            if let moves = gistToMoves[gist.id] {
                for entry in moves.prefix(8) {
                    let relevanceStr = String(format: "%.2f", entry.relevance)
                    lines.append("    \(entry.move.displayName) (\(entry.move.category.rawValue)) -> \(relevanceStr)")
                }
                if moves.count > 8 {
                    lines.append("    ... and \(moves.count - 8) more")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
