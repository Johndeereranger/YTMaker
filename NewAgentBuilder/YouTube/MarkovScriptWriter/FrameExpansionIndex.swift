//
//  FrameExpansionIndex.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/5/26.
//
//  Binary eligibility index using the 10→25 frame expansion table.
//  Each gist's frame deterministically defines which rhetorical moves it can fill.
//  No relevance tiers, no telemetry signals, no mapping method variants.
//  The chain builder uses this exclusively — Markov probability ranks,
//  frame eligibility filters.
//

import Foundation

// MARK: - FrameExpansionIndex

struct FrameExpansionIndex {

    /// Which gists are eligible for each move (binary — in the list or not)
    let moveToGists: [RhetoricalMoveType: [UUID]]

    /// Which moves each gist is eligible for
    let gistToMoves: [UUID: Set<RhetoricalMoveType>]

    /// Category-level summary (gist IDs per category, derived from expansion moves)
    let categoryToGistIds: [RhetoricalCategory: [UUID]]

    /// How many move slots each gist can fill (lower = more constrained = assign first)
    let constraintScores: [UUID: Int]

    /// Total gist count
    let totalGists: Int

    // MARK: - Init

    init(gists: [RamblingGist]) {
        self.totalGists = gists.count

        var moveMap: [RhetoricalMoveType: [UUID]] = [:]
        var gistMap: [UUID: Set<RhetoricalMoveType>] = [:]
        var catMap: [RhetoricalCategory: Set<UUID>] = [:]
        var constraints: [UUID: Int] = [:]

        for gist in gists {
            let expansion = FrameExpansionIndex.expansionMoves(for: gist.gistA.frame)
            var moveSet: Set<RhetoricalMoveType> = []

            for move in expansion {
                moveMap[move, default: []].append(gist.id)
                moveSet.insert(move)
                catMap[move.category, default: []].insert(gist.id)
            }

            gistMap[gist.id] = moveSet
            constraints[gist.id] = moveSet.count
        }

        self.moveToGists = moveMap
        self.gistToMoves = gistMap
        self.categoryToGistIds = catMap.mapValues { Array($0) }
        self.constraintScores = constraints
    }

    // MARK: - Expansion Table (10 Frames → 25 Moves)

    /// Frame → renderable moves. Deterministic. No tiers.
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

    /// Primary and secondary categories derived from the expansion table.
    static func primaryCategory(for frame: GistFrame) -> (primary: RhetoricalCategory, secondaries: [RhetoricalCategory]) {
        let moves = expansionMoves(for: frame)
        let primary = moves.first!.category
        let secondaries = Array(Set(moves.dropFirst().map(\.category)).subtracting([primary]))
        return (primary, secondaries)
    }

    // MARK: - Reverse Lookup

    /// Reverse of expansionMoves: given a move, which frames include it in their expansion?
    static func framesForMove(_ move: RhetoricalMoveType) -> [GistFrame] {
        GistFrame.allCases.filter { expansionMoves(for: $0).contains(move) }
    }

    // MARK: - Query Methods

    /// Binary eligibility check: does any unused gist's frame map to this move?
    func hasEligibleGists(for move: RhetoricalMoveType, excluding used: Set<UUID>) -> Bool {
        guard let gists = moveToGists[move] else { return false }
        return gists.contains { !used.contains($0) }
    }

    /// Get eligible gist IDs for a move, excluding already-used gists.
    func eligibleGists(for move: RhetoricalMoveType, excluding used: Set<UUID>) -> [UUID] {
        guard let gists = moveToGists[move] else { return [] }
        var seen = Set<UUID>()
        return gists.filter { !used.contains($0) && seen.insert($0).inserted }
    }

    /// Which categories still have eligible gists?
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

    /// Pick the most-constrained eligible gist for a move.
    /// Fewest alternative move slots first. Ties broken by chunk order (earliest chunk wins).
    func mostConstrainedGist(
        for move: RhetoricalMoveType,
        excluding used: Set<UUID>,
        gists: [RamblingGist]
    ) -> UUID? {
        let available = eligibleGists(for: move, excluding: used)
        guard !available.isEmpty else { return nil }

        // Build chunk index lookup for tiebreaking
        let chunkOrder: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: gists.map { ($0.id, $0.chunkIndex) }
        )

        return available.min { a, b in
            let scoreA = constraintScore(for: a)
            let scoreB = constraintScore(for: b)
            if scoreA != scoreB { return scoreA < scoreB }
            return (chunkOrder[a] ?? Int.max) < (chunkOrder[b] ?? Int.max)
        }
    }

    /// Returns all eligible gists for a move, ranked by constraint score (ascending = most constrained first).
    /// Ties broken by chunk order (earliest chunk wins). Limited to `limit` results.
    func rankedEligibleGists(
        for move: RhetoricalMoveType,
        excluding used: Set<UUID>,
        gists: [RamblingGist],
        limit: Int = Int.max
    ) -> [(gistId: UUID, constraintScore: Int)] {
        let available = eligibleGists(for: move, excluding: used)
        guard !available.isEmpty else { return [] }

        let chunkOrder: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: gists.map { ($0.id, $0.chunkIndex) }
        )

        let sorted = available.sorted { a, b in
            let scoreA = constraintScore(for: a)
            let scoreB = constraintScore(for: b)
            if scoreA != scoreB { return scoreA < scoreB }
            return (chunkOrder[a] ?? Int.max) < (chunkOrder[b] ?? Int.max)
        }

        return Array(sorted.prefix(limit)).map { ($0, constraintScore(for: $0)) }
    }

    // MARK: - Report

    /// Generate a human-readable availability report.
    func report(gists: [RamblingGist]) -> String {
        var lines: [String] = []
        lines.append("=== Frame Expansion Report ===")
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
            let constraint = constraintScore(for: gist.id)
            let moves = gistToMoves[gist.id] ?? []
            let moveNames = moves.sorted(by: { $0.displayName < $1.displayName }).map(\.displayName)
            lines.append("Chunk \(gist.chunkIndex + 1) | Frame: \(frame) | Slots: \(constraint)")
            lines.append("    Eligible: \(moveNames.joined(separator: ", "))")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
