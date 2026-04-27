//
//  MarkovTransitionService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/17/26.
//
//  Extracted from CreatorRhetoricalStyleView.swift.
//  Builds Markov transition matrices from RhetoricalSequence data.
//  Reuses existing MoveTransitions, GlobalPatternAnalysis, TrigramPattern types
//  defined at file scope in CreatorRhetoricalStyleView.swift.
//

import Foundation

struct MarkovTransitionService {

    // MARK: - Build Matrix

    /// Build a complete Markov transition matrix from rhetorical sequences.
    /// Extracted from CreatorRhetoricalStyleView.buildMatrixForLevel(useParent:)
    static func buildMatrix(
        from sequences: [String: RhetoricalSequence],
        useParentLevel: Bool
    ) -> MarkovMatrix {
        var matrix: [RhetoricalMoveType: MoveTransitions] = [:]
        var global = GlobalPatternAnalysis()
        var totalMoveCount = 0

        func getKey(_ move: RhetoricalMoveType) -> RhetoricalMoveType {
            useParentLevel ? representativeMove(for: move.category) : move
        }

        func getName(_ move: RhetoricalMoveType) -> String {
            useParentLevel ? move.category.rawValue : move.displayName
        }

        for (_, sequence) in sequences {
            let moves = sequence.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            let total = moves.count
            totalMoveCount += total

            for (index, move) in moves.enumerated() {
                let key = getKey(move.moveType)

                if matrix[key] == nil {
                    matrix[key] = MoveTransitions()
                }

                matrix[key]?.totalOccurrences += 1

                // Track normalized position (0-10 scale)
                if total > 1 {
                    let normalizedPos = Int((Double(index) / Double(total - 1)) * 10)
                    matrix[key]?.positionDistribution[normalizedPos, default: 0] += 1
                }

                // Get context moves
                let prev3: RhetoricalMoveType? = index >= 3 ? getKey(moves[index - 3].moveType) : nil
                let prev2: RhetoricalMoveType? = index >= 2 ? getKey(moves[index - 2].moveType) : nil
                let prev1: RhetoricalMoveType? = index >= 1 ? getKey(moves[index - 1].moveType) : nil
                let next: RhetoricalMoveType? = index < moves.count - 1 ? getKey(moves[index + 1].moveType) : nil

                // 1-step transitions
                if index == 0 {
                    matrix[key]?.startsSequenceCount += 1
                } else if let p1 = prev1 {
                    matrix[key]?.beforeCounts[p1, default: 0] += 1
                }

                if index == moves.count - 1 {
                    matrix[key]?.endsSequenceCount += 1
                } else if let n = next {
                    matrix[key]?.afterCounts[n, default: 0] += 1
                }

                // 2-step history (legacy, kept for display views)
                if let p2 = prev2, let p1 = prev1 {
                    let twoStepKey = "\(getName(p2)) → \(getName(p1))"
                    matrix[key]?.twoStepHistory[twoStepKey, default: 0] += 1
                }

                // 3-step history (legacy, kept for display views)
                if let p3 = prev3, let p2 = prev2, let p1 = prev1 {
                    let threeStepKey = "\(getName(p3)) → \(getName(p2)) → \(getName(p1))"
                    matrix[key]?.threeStepHistory[threeStepKey, default: 0] += 1
                }

                // Generalized N-step histories (depths 2 through 8)
                for depth in 2...8 {
                    guard index >= depth else { continue }
                    let historyMoves = (0..<depth).map { offset in
                        getName(getKey(moves[index - depth + offset].moveType))
                    }
                    let nStepKey = historyMoves.joined(separator: " → ")
                    if matrix[key]?.nStepHistories[depth] == nil {
                        matrix[key]?.nStepHistories[depth] = [:]
                    }
                    matrix[key]?.nStepHistories[depth]?[nStepKey, default: 0] += 1
                }

                // Full 5-gram context
                let p3Name = prev3 != nil ? getName(prev3!) : "⊥"
                let p2Name = prev2 != nil ? getName(prev2!) : "⊥"
                let p1Name = prev1 != nil ? getName(prev1!) : "⊥"
                let currName = getName(key)
                let nextName = next != nil ? getName(next!) : "⊥"

                let fullContext = "\(p3Name) → \(p2Name) → \(p1Name) → \(currName) → \(nextName)"
                matrix[key]?.fullContexts[fullContext, default: 0] += 1

                // Global n-grams
                if let p1 = prev1, let n = next {
                    let trigram = "\(getName(p1)) → \(currName) → \(getName(n))"
                    global.threeGrams[trigram, default: 0] += 1
                    matrix[key]?.trigramCounts[trigram, default: 0] += 1
                }

                if let p2 = prev2, let p1 = prev1, let n = next {
                    let fourGram = "\(getName(p2)) → \(getName(p1)) → \(currName) → \(getName(n))"
                    global.fourGrams[fourGram, default: 0] += 1
                }

                if let p3 = prev3, let p2 = prev2, let p1 = prev1, let n = next {
                    let fiveGram = "\(getName(p3)) → \(getName(p2)) → \(getName(p1)) → \(currName) → \(getName(n))"
                    global.fiveGrams[fiveGram, default: 0] += 1
                }
            }
        }

        // Sort trigrams per move
        for key in matrix.keys {
            let sorted = matrix[key]!.trigramCounts
                .map { TrigramPattern(pattern: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
            matrix[key]?.commonTrigrams = sorted
        }

        return MarkovMatrix(
            transitions: matrix,
            globalPatterns: global,
            useParentLevel: useParentLevel,
            sourceSequenceCount: sequences.count,
            totalMoveCount: totalMoveCount,
            builtAt: Date()
        )
    }

    // MARK: - Query Helpers

    /// Get transition probability from one move to another
    static func transitionProbability(
        from source: RhetoricalMoveType,
        to target: RhetoricalMoveType,
        in matrix: MarkovMatrix
    ) -> Double {
        matrix.probability(from: source, to: target)
    }

    /// Get ranked next moves after a given move
    static func topNextMoves(
        after move: RhetoricalMoveType,
        in matrix: MarkovMatrix,
        topK: Int = 10
    ) -> [(move: RhetoricalMoveType, probability: Double, count: Int)] {
        matrix.topNextMoves(after: move, topK: topK)
    }

    /// Get which moves commonly start sequences, ranked by frequency
    static func sequenceStartProbabilities(
        in matrix: MarkovMatrix
    ) -> [(move: RhetoricalMoveType, probability: Double)] {
        let starters = matrix.sequenceStarters(topK: matrix.uniqueMoveCount)
        let totalStarts = starters.reduce(0) { $0 + $1.count }
        guard totalStarts > 0 else { return [] }
        return starters.map { (move: $0.move, probability: Double($0.count) / Double(totalStarts)) }
    }

    // MARK: - Helpers

    /// Maps a category to its representative move type (for parent-level analysis)
    static func representativeMove(for category: RhetoricalCategory) -> RhetoricalMoveType {
        switch category {
        case .hook: return .personalStake
        case .setup: return .commonBelief
        case .tension: return .complication
        case .revelation: return .hiddenTruth
        case .evidence: return .evidenceStack
        case .closing: return .synthesis
        }
    }

    /// Build a formatted text report of the transition matrix
    static func buildReport(from matrix: MarkovMatrix) -> String {
        var lines: [String] = []
        let level = matrix.useParentLevel ? "Parent (6 categories)" : "Full (25 moves)"
        lines.append("Markov Transition Report — \(level)")
        lines.append("Sequences: \(matrix.sourceSequenceCount) | Total moves: \(matrix.totalMoveCount) | Unique: \(matrix.uniqueMoveCount)")
        lines.append(String(repeating: "═", count: 60))

        let sortedMoves = matrix.transitions.sorted { $0.value.totalOccurrences > $1.value.totalOccurrences }

        for (move, data) in sortedMoves {
            let name = matrix.useParentLevel ? move.category.rawValue : move.displayName
            lines.append("")
            lines.append("[\(name)] — \(data.totalOccurrences) occurrences")
            lines.append("  Starts sequence: \(data.startsSequenceCount) | Ends sequence: \(data.endsSequenceCount)")

            // Top successors
            let nextMoves = matrix.topNextMoves(after: move, topK: 5)
            if !nextMoves.isEmpty {
                lines.append("  Top successors:")
                for nm in nextMoves {
                    let nmName = matrix.useParentLevel ? nm.move.category.rawValue : nm.move.displayName
                    lines.append("    → \(nmName): \(String(format: "%.1f%%", nm.probability * 100)) (\(nm.count))")
                }
            }

            // Top predecessors
            let prevMoves = matrix.topPreviousMoves(before: move, topK: 5)
            if !prevMoves.isEmpty {
                lines.append("  Top predecessors:")
                for pm in prevMoves {
                    let pmName = matrix.useParentLevel ? pm.move.category.rawValue : pm.move.displayName
                    lines.append("    \(pmName) →: \(String(format: "%.1f%%", pm.probability * 100)) (\(pm.count))")
                }
            }

            // Position distribution
            if !data.positionDistribution.isEmpty {
                let posStr = (0...10).map { pos in
                    let count = data.positionDistribution[pos, default: 0]
                    return "\(pos * 10)%:\(count)"
                }.joined(separator: " ")
                lines.append("  Position: \(posStr)")
            }
        }

        // Global patterns
        lines.append("")
        lines.append(String(repeating: "═", count: 60))
        lines.append("Global Patterns")

        let top3 = matrix.globalPatterns.topThreeGrams.prefix(10)
        if !top3.isEmpty {
            lines.append("  Top 3-grams:")
            for gram in top3 {
                lines.append("    \(gram.pattern) (\(gram.count))")
            }
        }

        let top4 = matrix.globalPatterns.topFourGrams.prefix(10)
        if !top4.isEmpty {
            lines.append("  Top 4-grams:")
            for gram in top4 {
                lines.append("    \(gram.pattern) (\(gram.count))")
            }
        }

        let top5 = matrix.globalPatterns.topFiveGrams.prefix(5)
        if !top5.isEmpty {
            lines.append("  Top 5-grams:")
            for gram in top5 {
                lines.append("    \(gram.pattern) (\(gram.count))")
            }
        }

        return lines.joined(separator: "\n")
    }
}
