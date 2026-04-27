//
//  ManualSequenceBuilderViewModel.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/5/26.
//
//  State management for the Manual Sequence Builder.
//  Handles placement/removal of gists, viability computation
//  using MarkovMatrix + FrameExpansionIndex, and pool sorting.
//

import Foundation
import SwiftUI

// MARK: - Lightweight Models

struct PlacedGist: Identifiable {
    let id: UUID
    let gistId: UUID
    var positionIndex: Int
    let moveType: RhetoricalMoveType?
    let markovProbability: Double?
    let wasViable: Bool
}

struct PoolEntry: Identifiable {
    let id: UUID
    let gist: RamblingGist
    let isViable: Bool
    let matchingMoveType: RhetoricalMoveType?
    let transitionProbability: Double?
}

struct DeadEndInfo {
    let lookupKey: String
    let historyDepthUsed: Int
}

// MARK: - ViewModel

@MainActor
class ManualSequenceBuilderViewModel: ObservableObject {

    // MARK: - Dependencies

    private let coordinator: MarkovScriptWriterCoordinator

    // MARK: - Published State

    @Published var placedGists: [PlacedGist] = []
    @Published var expandedPoolIds: Set<UUID> = []
    @Published var expandedPlacedIds: Set<UUID> = []
    @Published var dropTargetActive: Bool = false

    // MARK: - Init

    init(coordinator: MarkovScriptWriterCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Convenience Accessors

    var allGists: [RamblingGist] {
        coordinator.session.ramblingGists
    }

    var matrix: MarkovMatrix? {
        coordinator.markovMatrix
    }

    var expansionIndex: FrameExpansionIndex? {
        coordinator.expansionIndex
    }

    var parameters: ChainParameters {
        coordinator.session.parameters
    }

    // MARK: - Derived State

    var placedGistIds: Set<UUID> {
        Set(placedGists.map(\.gistId))
    }

    var unplacedGists: [RamblingGist] {
        allGists.filter { !placedGistIds.contains($0.id) }
    }

    var placedMoveHistory: [RhetoricalMoveType] {
        placedGists.compactMap(\.moveType)
    }

    var coveragePercent: Double {
        guard !allGists.isEmpty else { return 0 }
        return Double(placedGists.count) / Double(allGists.count)
    }

    var hasMatrix: Bool {
        matrix != nil
    }

    var hasGists: Bool {
        !allGists.isEmpty
    }

    // MARK: - Dead End Detection

    var deadEndInfo: DeadEndInfo? {
        guard let matrix = matrix, !placedGists.isEmpty else { return nil }
        let history = placedMoveHistory
        guard let lastMove = history.last else { return nil }

        let result = matrix.contextAwareNextMoves(
            after: lastMove,
            history: history,
            parameters: parameters,
            topK: 25
        )

        if result.isDeadEnd {
            return DeadEndInfo(
                lookupKey: result.lookupKey,
                historyDepthUsed: result.historyDepthUsed
            )
        }
        return nil
    }

    // MARK: - Pool Sorting (core viability computation)

    var sortedPoolEntries: [PoolEntry] {
        let unplaced = unplacedGists
        guard let matrix = matrix else {
            return unplaced.map {
                PoolEntry(id: $0.id, gist: $0, isViable: false,
                          matchingMoveType: nil, transitionProbability: nil)
            }
        }

        // Determine suggested moves for the next position
        let suggestedMoves: [(move: RhetoricalMoveType, probability: Double)]

        if placedGists.isEmpty {
            // Initial state: use sequence starters
            let starters = matrix.sequenceStarters(topK: 25)
            let totalStartCount = starters.reduce(0) { $0 + $1.count }
            guard totalStartCount > 0 else {
                return unplaced.map {
                    PoolEntry(id: $0.id, gist: $0, isViable: false,
                              matchingMoveType: nil, transitionProbability: nil)
                }
            }
            suggestedMoves = starters.map {
                ($0.move, Double($0.count) / Double(totalStartCount))
            }
        } else {
            // After placements: use context-aware next moves
            let history = placedMoveHistory
            guard let lastMove = history.last else {
                return unplaced.map {
                    PoolEntry(id: $0.id, gist: $0, isViable: false,
                              matchingMoveType: nil, transitionProbability: nil)
                }
            }
            let result = matrix.contextAwareNextMoves(
                after: lastMove,
                history: history,
                parameters: parameters,
                topK: 25
            )
            suggestedMoves = result.moves.map { ($0.move, $0.probability) }
        }

        // Score each unplaced gist
        var viable: [PoolEntry] = []
        var nonViable: [PoolEntry] = []

        for gist in unplaced {
            let bestMatch = findBestMatch(for: gist, in: suggestedMoves)

            if let match = bestMatch {
                viable.append(PoolEntry(
                    id: gist.id, gist: gist, isViable: true,
                    matchingMoveType: match.move,
                    transitionProbability: match.probability
                ))
            } else {
                nonViable.append(PoolEntry(
                    id: gist.id, gist: gist, isViable: false,
                    matchingMoveType: nil, transitionProbability: nil
                ))
            }
        }

        // Sort viable by probability desc
        viable.sort {
            let probA = $0.transitionProbability ?? 0
            let probB = $1.transitionProbability ?? 0
            return probA > probB
        }

        // Sort non-viable by chunk index (original order)
        nonViable.sort { $0.gist.chunkIndex < $1.gist.chunkIndex }

        return viable + nonViable
    }

    // MARK: - Match Finding

    /// Binary eligibility: does the gist's frame expansion include any of the suggested moves?
    /// Returns the highest-probability match. No relevance scoring.
    private func findBestMatch(
        for gist: RamblingGist,
        in suggestedMoves: [(move: RhetoricalMoveType, probability: Double)]
    ) -> (move: RhetoricalMoveType, probability: Double)? {

        if let index = expansionIndex {
            // Use expansion index for binary eligibility
            let eligibleMoves = index.gistToMoves[gist.id] ?? []
            var bestMatch: (move: RhetoricalMoveType, probability: Double)?

            for (move, prob) in suggestedMoves {
                if eligibleMoves.contains(move) {
                    if bestMatch == nil || prob > bestMatch!.probability {
                        bestMatch = (move, prob)
                    }
                }
            }
            return bestMatch
        } else {
            // Fallback: direct moveLabel match only
            if let moveLabel = gist.moveLabel,
               let gistMove = RhetoricalMoveType.parse(moveLabel) {
                for (move, prob) in suggestedMoves where move == gistMove {
                    return (move, prob)
                }
            }
            return nil
        }
    }

    // MARK: - Placement Actions

    func placeGist(_ gistId: UUID) {
        guard !placedGistIds.contains(gistId) else { return }
        guard let gist = allGists.first(where: { $0.id == gistId }) else { return }

        let moveType = gist.moveLabel.flatMap { RhetoricalMoveType.parse($0) }
        let history = placedMoveHistory

        // Calculate transition probability at moment of placement
        var probability: Double?
        var wasViable = false

        if let matrix = matrix, let moveType = moveType {
            if placedGists.isEmpty {
                let starters = matrix.sequenceStarters(topK: 25)
                let total = starters.reduce(0) { $0 + $1.count }
                if total > 0, let starter = starters.first(where: { $0.move == moveType }) {
                    probability = Double(starter.count) / Double(total)
                    wasViable = true
                }
            } else if let lastMove = history.last {
                let result = matrix.contextAwareNextMoves(
                    after: lastMove, history: history,
                    parameters: parameters, topK: 25
                )
                if let match = result.moves.first(where: { $0.move == moveType }) {
                    probability = match.probability
                    wasViable = true
                }
            }
        }

        let placed = PlacedGist(
            id: UUID(),
            gistId: gistId,
            positionIndex: placedGists.count,
            moveType: moveType,
            markovProbability: probability,
            wasViable: wasViable
        )

        withAnimation(.easeInOut(duration: 0.25)) {
            placedGists.append(placed)
        }
    }

    func removeGist(at positionIndex: Int) {
        guard positionIndex < placedGists.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            placedGists.remove(at: positionIndex)
            // Re-index remaining positions
            for i in placedGists.indices {
                placedGists[i].positionIndex = i
            }
        }
    }

    func clearAll() {
        withAnimation(.easeInOut(duration: 0.25)) {
            placedGists.removeAll()
        }
    }

    // MARK: - Expand/Collapse

    func togglePoolExpansion(_ gistId: UUID) {
        if expandedPoolIds.contains(gistId) {
            expandedPoolIds.remove(gistId)
        } else {
            expandedPoolIds.insert(gistId)
        }
    }

    func togglePlacedExpansion(_ gistId: UUID) {
        if expandedPlacedIds.contains(gistId) {
            expandedPlacedIds.remove(gistId)
        } else {
            expandedPlacedIds.insert(gistId)
        }
    }

    // MARK: - Helpers

    func gist(for gistId: UUID) -> RamblingGist? {
        allGists.first(where: { $0.id == gistId })
    }

    func categoryColor(_ category: RhetoricalCategory) -> Color {
        switch category {
        case .hook: return .blue
        case .setup: return .green
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .gray
        case .closing: return .red
        }
    }

    func ensureExpansionIndex() {
        if expansionIndex == nil {
            coordinator.rebuildExpansionIndex()
        }
    }
}
