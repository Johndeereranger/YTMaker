//
//  ChainBuildingService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/3/26.
//
//  Greedy chain builder with bounded local backtracking.
//  Takes immutable inputs (matrix, availability index, gists, parameters),
//  returns a ChainBuildRun with one attempt per viable sequence starter.
//

import Foundation

struct ChainBuildingService {

    // MARK: - Public Entry Point

    /// Build a full run: dispatches to exhaustive or tree walk based on algorithm type.
    static func buildRun(
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters
    ) -> ChainBuildRun {
        switch parameters.algorithmType {
        case .treeWalk:
            return buildTreeWalkRun(
                matrix: matrix,
                expansionIndex: expansionIndex,
                gists: gists,
                parameters: parameters
            )
        default:
            return buildExhaustiveRun(
                matrix: matrix,
                expansionIndex: expansionIndex,
                gists: gists,
                parameters: parameters
            )
        }
    }

    /// Exhaustive: one attempt per viable sequence starter, keep all.
    /// Best chain = highest coverage score.
    private static func buildExhaustiveRun(
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters
    ) -> ChainBuildRun {
        var run = ChainBuildRun(parameters: parameters, inputGistCount: gists.count)

        // Find all viable starters (have available gists)
        let allStarters = MarkovTransitionService.sequenceStartProbabilities(in: matrix)
        let viableStarters = allStarters.filter { starter in
            expansionIndex.hasEligibleGists(for: starter.move, excluding: [])
        }

        if viableStarters.isEmpty {
            let attempt = makeFailedAttempt(
                reason: "No viable sequence starter",
                gistCount: gists.count,
                deadEndType: .missingContent,
                whatWasNeeded: "A sequence starter move with available gist content",
                whatWasMissing: "No sequence starters in the matrix had available gists",
                suggestion: "Add more rambling content covering hook/opening moves"
            )
            run.chainsAttempted.append(attempt.chain)
            run.deadEnds.append(contentsOf: attempt.deadEnds)
            return run
        }

        // Try each viable starter (up to 8)
        for starter in viableStarters.prefix(8) {
            let result = buildSingleAttempt(
                starterMove: starter.move,
                starterProbability: starter.probability,
                matrix: matrix,
                expansionIndex: expansionIndex,
                gists: gists,
                parameters: parameters,
                allStarters: allStarters
            )
            run.chainsAttempted.append(result.chain)
            run.deadEnds.append(contentsOf: result.deadEnds)
        }

        return run
    }

    // MARK: - Single Attempt

    private struct AttemptResult {
        let chain: ChainAttempt
        let deadEnds: [DeadEnd]
    }

    private static func buildSingleAttempt(
        starterMove: RhetoricalMoveType,
        starterProbability: Double,
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters,
        allStarters: [(move: RhetoricalMoveType, probability: Double)]
    ) -> AttemptResult {
        var attempt = ChainAttempt()
        var usedGistIds: Set<UUID> = []
        var history: [RhetoricalMoveType] = []
        var deadEnds: [DeadEnd] = []
        var backtrackCount = 0
        let maxBacktracks = 3

        // Build alternatives list for the starter
        let starterAlternatives = allStarters
            .filter { $0.move != starterMove && expansionIndex.hasEligibleGists(for: $0.move, excluding: []) }
            .prefix(5)
            .map { Alternative(
                category: $0.move.category,
                moveType: $0.move,
                probability: $0.probability,
                rejectionReason: "Alternative starter (trying \(starterMove.displayName) first)"
            )}

        // Position 0: assign the starter
        guard let starterGistId = expansionIndex.mostConstrainedGist(for: starterMove, excluding: usedGistIds, gists: gists) else {
            return makeFailedAttempt(
                reason: "No gist available for starter \(starterMove.displayName)",
                gistCount: gists.count,
                deadEndType: .missingContent,
                whatWasNeeded: "A gist compatible with \(starterMove.displayName)",
                whatWasMissing: "No gists mapped to this move",
                suggestion: "Add more rambling content covering this move type"
            )
        }

        usedGistIds.insert(starterGistId)
        let pos0 = ChainPosition(
            positionIndex: 0,
            category: starterMove.category,
            moveType: starterMove,
            mappedGistId: starterGistId,
            markovProbability: starterProbability,
            markovContext: ["sequence_starter"],
            selectionReason: "Sequence starter (\(pct(starterProbability)))",
            alternativesConsidered: Array(starterAlternatives)
        )
        attempt.positions.append(pos0)
        history.append(starterMove)

        // Extension loop (while loop so we control posIndex explicitly)
        var posIndex = 1
        var positionExclusions: [Int: Set<RhetoricalMoveType>] = [:]
        let effectiveMaxLength = max(parameters.maxChainLength, gists.count + 5)

        while posIndex < effectiveMaxLength {
            let exclusions = positionExclusions[posIndex] ?? []

            let result = extendChain(
                history: history,
                positionIndex: posIndex,
                matrix: matrix,
                expansionIndex: expansionIndex,
                gists: gists,
                parameters: parameters,
                usedGistIds: usedGistIds,
                attemptId: attempt.id,
                effectiveMaxLength: effectiveMaxLength,
                excludedMoves: exclusions
            )

            switch result {
            case .extended(let position):
                if let gid = position.mappedGistId {
                    usedGistIds.insert(gid)
                }
                attempt.positions.append(position)
                history.append(position.moveType)
                posIndex += 1  // Only increment on success

            case .deadEnd(var deadEnd):
                // Attach actual gist assignments from the chain so far
                deadEnd.pathGistIds = attempt.positions.map(\.mappedGistId)
                deadEnds.append(deadEnd)

                // Try backtracking
                if backtrackCount < maxBacktracks && attempt.positions.count > 1 {
                    backtrackCount += 1

                    // Pop the last successful position
                    let popped = attempt.positions.removeLast()
                    history.removeLast()
                    if let gid = popped.mappedGistId {
                        usedGistIds.remove(gid)
                    }

                    // Clear exclusions for positions ahead (stale from a different path)
                    positionExclusions[posIndex] = nil
                    for key in positionExclusions.keys where key > posIndex {
                        positionExclusions.removeValue(forKey: key)
                    }

                    // Go back to the position we just popped and exclude the move that was there
                    posIndex = attempt.positions.count
                    positionExclusions[posIndex, default: []].insert(popped.moveType)

                    continue  // Retry this position with the exclusion
                }

                attempt.status = .failed
                attempt.failurePoint = posIndex
                attempt.failureReason = deadEnd.whatWasMissing
                break
            }

            if attempt.status == .failed { break }

            // Coverage check: stop early if we've placed enough gists
            if attempt.positions.count >= parameters.minChainLength {
                let coverage = Double(usedGistIds.count) / Double(max(gists.count, 1))
                if coverage >= parameters.coverageTarget {
                    break
                }
            }
        }

        // Finalize
        if attempt.status != .failed {
            attempt.status = .completed
        }
        attempt.backtrackCount = backtrackCount
        attempt.starterMove = starterMove.displayName
        let allGistIds = Set(gists.map(\.id))
        attempt.gistsUsed = Array(usedGistIds)
        attempt.gistsUnused = Array(allGistIds.subtracting(usedGistIds))
        attempt.coverageScore = Double(usedGistIds.count) / Double(max(gists.count, 1))

        // Coverage gap dead end
        if attempt.status == .completed && attempt.coverageScore < parameters.coverageTarget {
            deadEnds.append(DeadEnd(
                chainAttemptId: attempt.id,
                positionIndex: attempt.positions.count,
                pathSoFar: attempt.positions.map { $0.moveType.displayName },
                deadEndType: .coverageGap,
                whatWasNeeded: "Coverage target of \(pct(parameters.coverageTarget))",
                whatWasMissing: "Only \(pct(attempt.coverageScore)) of gists used (\(usedGistIds.count)/\(gists.count))",
                suggestedUserAction: "Increase maxChainLength or lower coverageTarget",
                pathGistIds: attempt.positions.map(\.mappedGistId)
            ))
        }

        return AttemptResult(chain: attempt, deadEnds: deadEnds)
    }

    // MARK: - Chain Extension

    private enum ExtensionResult {
        case extended(ChainPosition)
        case deadEnd(DeadEnd)
    }

    private static func extendChain(
        history: [RhetoricalMoveType],
        positionIndex: Int,
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters,
        usedGistIds: Set<UUID>,
        attemptId: UUID,
        effectiveMaxLength: Int,
        excludedMoves: Set<RhetoricalMoveType> = []
    ) -> ExtensionResult {

        let lookup = getFilteredCandidates(
            history: history,
            positionIndex: positionIndex,
            matrix: matrix,
            expansionIndex: expansionIndex,
            parameters: parameters,
            usedGistIds: usedGistIds,
            excludedMoves: excludedMoves
        )

        let isBacktrackRetry = !excludedMoves.isEmpty

        // No candidates at any depth
        if lookup.raw.isEmpty {
            let maxDepth = min(history.count, parameters.historyDepth)
            return .deadEnd(DeadEnd(
                chainAttemptId: attemptId,
                positionIndex: positionIndex,
                pathSoFar: history.map(\.displayName),
                deadEndType: .transitionImpossible,
                whatWasNeeded: "A valid next move after \(history.last!.displayName)",
                whatWasMissing: "Matrix returned no transitions at any depth (1-\(maxDepth))",
                suggestedUserAction: "Build matrix with more corpus data, or lower historyDepth",
                candidatesFound: 0,
                candidateDetails: [],
                lookupDepthUsed: lookup.depthUsed,
                lookupKey: lookup.lookupKey,
                wasBacktrackRetry: isBacktrackRetry
            ))
        }

        // All candidates filtered out — build structured diagnostic data
        if lookup.filtered.isEmpty {
            let deadEndType = classifyDeadEnd(
                candidates: lookup.raw,
                expansionIndex: expansionIndex,
                usedGistIds: usedGistIds,
                parameters: parameters
            )

            let details = lookup.raw.map { candidate -> CandidateDetail in
                let reason = lookup.alternatives.first(where: { $0.moveType == candidate.move })?.rejectionReason
                    ?? "Filtered by constraints"
                return CandidateDetail(
                    moveName: candidate.move.displayName,
                    probability: candidate.probability,
                    observationCount: candidate.count,
                    rejectionReason: reason
                )
            }

            return .deadEnd(DeadEnd(
                chainAttemptId: attemptId,
                positionIndex: positionIndex,
                pathSoFar: history.map(\.displayName),
                deadEndType: deadEndType.type,
                whatWasNeeded: "A valid next move after \(history.last!.displayName) at position \(positionIndex)",
                whatWasMissing: deadEndType.missing,
                suggestedUserAction: deadEndType.suggestion,
                candidatesFound: lookup.raw.count,
                candidateDetails: details,
                lookupDepthUsed: lookup.depthUsed,
                lookupKey: lookup.lookupKey,
                wasBacktrackRetry: isBacktrackRetry,
                rawCandidateMoveTypes: lookup.raw.map(\.move)
            ))
        }

        // Score candidates: (markovProb × 0.7) + (positionFit × weight × 0.3)
        // Frame eligibility is binary — already filtered by hasEligibleGists above.
        var alternatives = lookup.alternatives
        let scored = lookup.filtered.map { candidate -> (move: RhetoricalMoveType, probability: Double, count: Int, score: Double) in
            let positionFit = positionFitScore(
                move: candidate.move,
                positionIndex: positionIndex,
                maxLength: effectiveMaxLength
            )
            let score = (candidate.probability * 0.7)
                + (positionFit * parameters.positionConstraintWeight * 0.3)
            return (candidate.move, candidate.probability, candidate.count, score)
        }.sorted { $0.score > $1.score }

        let best = scored[0]

        for runner in scored.dropFirst() {
            alternatives.append(Alternative(
                category: runner.move.category, moveType: runner.move,
                probability: runner.probability,
                rejectionReason: "Lower score (\(fmt2(runner.score)) vs \(fmt2(best.score)))"
            ))
        }

        let assignedGistId = expansionIndex.mostConstrainedGist(for: best.move, excluding: usedGistIds, gists: gists)

        let position = ChainPosition(
            positionIndex: positionIndex,
            category: best.move.category,
            moveType: best.move,
            mappedGistId: assignedGistId,
            markovProbability: best.probability,
            markovContext: ["\(lookup.depthUsed)-step", lookup.lookupKey],
            selectionReason: "Score \(fmt2(best.score)): prob \(pct(best.probability)), \(best.count) obs",
            alternativesConsidered: alternatives
        )

        return .extended(position)
    }

    // MARK: - Dead End Classification

    private struct DeadEndClassification {
        let type: DeadEndType
        let missing: String
        let suggestion: String
    }

    private static func classifyDeadEnd(
        candidates: [(move: RhetoricalMoveType, probability: Double, count: Int)],
        expansionIndex: FrameExpansionIndex,
        usedGistIds: Set<UUID>,
        parameters: ChainParameters
    ) -> DeadEndClassification {
        let allGistFiltered = candidates.allSatisfy {
            !expansionIndex.hasEligibleGists(for: $0.move, excluding: usedGistIds)
        }
        let allSparse = candidates.allSatisfy { $0.count < parameters.minObservationCount }
        let allBelowThreshold = candidates.allSatisfy { $0.probability < parameters.transitionThreshold }

        if allGistFiltered {
            return DeadEndClassification(
                type: .missingContent,
                missing: "All \(candidates.count) candidates had no available gists",
                suggestion: "Add more rambling content covering this move type"
            )
        } else if allSparse {
            return DeadEndClassification(
                type: .sparseData,
                missing: "All candidates had fewer than \(parameters.minObservationCount) observations",
                suggestion: "Lower minObservationCount or build matrix with more corpus data"
            )
        } else if allBelowThreshold {
            return DeadEndClassification(
                type: .transitionImpossible,
                missing: "All candidates below \(pct(parameters.transitionThreshold)) threshold",
                suggestion: "Lower the transitionThreshold parameter"
            )
        } else {
            return DeadEndClassification(
                type: .transitionImpossible,
                missing: "All candidates filtered by various constraints",
                suggestion: "Relax constraints: lower threshold, allow consecutive categories, or increase gist coverage"
            )
        }
    }

    // MARK: - Position Fit Scoring

    private static func positionFitScore(move: RhetoricalMoveType, positionIndex: Int, maxLength: Int) -> Double {
        let normalizedPos = Double(positionIndex) / Double(max(maxLength - 1, 1))
        switch move.category {
        case .hook:       return normalizedPos < 0.2 ? 1.0 : max(0, 1.0 - normalizedPos * 2)
        case .setup:      return (normalizedPos >= 0.05 && normalizedPos <= 0.35) ? 1.0 : 0.3
        case .tension:    return (normalizedPos >= 0.2 && normalizedPos <= 0.6) ? 1.0 : 0.3
        case .revelation: return (normalizedPos >= 0.4 && normalizedPos <= 0.75) ? 1.0 : 0.3
        case .evidence:   return (normalizedPos >= 0.3 && normalizedPos <= 0.85) ? 1.0 : 0.3
        case .closing:    return normalizedPos > 0.7 ? 1.0 : max(0, normalizedPos - 0.3)
        }
    }

    // MARK: - Failed Attempt Helper

    private static func makeFailedAttempt(
        reason: String,
        gistCount: Int,
        deadEndType: DeadEndType,
        whatWasNeeded: String,
        whatWasMissing: String,
        suggestion: String
    ) -> AttemptResult {
        var attempt = ChainAttempt()
        attempt.status = .failed
        attempt.failurePoint = 0
        attempt.failureReason = reason
        attempt.gistsUnused = []  // can't compute without allGistIds here
        let deadEnd = DeadEnd(
            chainAttemptId: attempt.id,
            positionIndex: 0,
            pathSoFar: [],
            deadEndType: deadEndType,
            whatWasNeeded: whatWasNeeded,
            whatWasMissing: whatWasMissing,
            suggestedUserAction: suggestion
        )
        return AttemptResult(chain: attempt, deadEnds: [deadEnd])
    }

    // MARK: - Candidate Lookup (shared by exhaustive + tree walk)

    struct CandidateLookupResult {
        let raw: [(move: RhetoricalMoveType, probability: Double, count: Int)]
        let filtered: [(move: RhetoricalMoveType, probability: Double, count: Int)]
        let alternatives: [Alternative]
        let lookupKey: String
        let depthUsed: Int
    }

    /// Get candidates from the matrix with depth fallback, then filter by all constraints.
    /// Returns both raw (pre-filter) and filtered (post-filter) candidates.
    static func getFilteredCandidates(
        history: [RhetoricalMoveType],
        positionIndex: Int,
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        parameters: ChainParameters,
        usedGistIds: Set<UUID>,
        excludedMoves: Set<RhetoricalMoveType> = []
    ) -> CandidateLookupResult {
        // Depth fallback: try from max depth down to 1.
        // Filtering happens INSIDE the loop — if all candidates at a given depth
        // are killed by filters (gist availability, threshold, category rules),
        // we fall back to shallower depths that may surface more options.
        let maxDepth = min(history.count, parameters.historyDepth)
        var rawCandidates: [(move: RhetoricalMoveType, probability: Double, count: Int)] = []
        var lookupKey = ""
        var depthUsed = 1
        var alternatives: [Alternative] = []
        var filtered: [(move: RhetoricalMoveType, probability: Double, count: Int)] = []
        let recentCategories = history.suffix(parameters.maxConsecutiveSameCategory).map(\.category)

        for depth in stride(from: maxDepth, through: 1, by: -1) {
            let params = ChainParameters(
                transitionThreshold: parameters.transitionThreshold,
                historyDepth: depth,
                minObservationCount: parameters.minObservationCount,
                useParentLevel: parameters.useParentLevel
            )
            let result = matrix.contextAwareNextMoves(
                after: history.last!,
                history: history,
                parameters: params,
                topK: 25
            )
            if result.moves.isEmpty { continue }

            // Filter candidates at this depth
            var depthFiltered: [(move: RhetoricalMoveType, probability: Double, count: Int)] = []
            var depthAlternatives: [Alternative] = []

            for candidate in result.moves {
                if excludedMoves.contains(candidate.move) {
                    depthAlternatives.append(Alternative(
                        category: candidate.move.category, moveType: candidate.move,
                        probability: candidate.probability,
                        rejectionReason: "Excluded by backtrack (already tried, hit dead end)"
                    ))
                    continue
                }

                if candidate.probability < parameters.transitionThreshold {
                    depthAlternatives.append(Alternative(
                        category: candidate.move.category, moveType: candidate.move,
                        probability: candidate.probability,
                        rejectionReason: "Below threshold (\(pct(candidate.probability)) < \(pct(parameters.transitionThreshold)))"
                    ))
                    continue
                }

                if candidate.count < parameters.minObservationCount {
                    depthAlternatives.append(Alternative(
                        category: candidate.move.category, moveType: candidate.move,
                        probability: candidate.probability,
                        rejectionReason: "Sparse data (\(candidate.count) obs < \(parameters.minObservationCount) min)"
                    ))
                    continue
                }

                if !parameters.allowConsecutiveSameCategory {
                    if let lastCat = recentCategories.last, lastCat == candidate.move.category {
                        depthAlternatives.append(Alternative(
                            category: candidate.move.category, moveType: candidate.move,
                            probability: candidate.probability,
                            rejectionReason: "Consecutive same category not allowed"
                        ))
                        continue
                    }
                } else if parameters.maxConsecutiveSameCategory > 0 {
                    let consecutiveCount = recentCategories.reversed()
                        .prefix(while: { $0 == candidate.move.category }).count
                    if consecutiveCount >= parameters.maxConsecutiveSameCategory {
                        depthAlternatives.append(Alternative(
                            category: candidate.move.category, moveType: candidate.move,
                            probability: candidate.probability,
                            rejectionReason: "Exceeds max consecutive same category (\(parameters.maxConsecutiveSameCategory))"
                        ))
                        continue
                    }
                }

                // Move-type frequency cap (prevents degenerate arcs where one move dominates)
                if parameters.maxMoveTypeShare < 1.0 && history.count >= 8 {
                    let moveCount = history.filter { $0 == candidate.move }.count
                    let currentShare = Double(moveCount) / Double(history.count)
                    if currentShare >= parameters.maxMoveTypeShare {
                        depthAlternatives.append(Alternative(
                            category: candidate.move.category, moveType: candidate.move,
                            probability: candidate.probability,
                            rejectionReason: "Move type frequency cap (\(Int(currentShare * 100))% >= \(Int(parameters.maxMoveTypeShare * 100))% max)"
                        ))
                        continue
                    }
                }

                if !expansionIndex.hasEligibleGists(for: candidate.move, excluding: usedGistIds) {
                    depthAlternatives.append(Alternative(
                        category: candidate.move.category, moveType: candidate.move,
                        probability: candidate.probability,
                        rejectionReason: "No available gist (all used or none mapped)"
                    ))
                    continue
                }

                depthFiltered.append(candidate)
            }

            // Keep the deepest depth's raw + alternatives for diagnostics
            if rawCandidates.isEmpty {
                rawCandidates = result.moves
                lookupKey = result.lookupKey
                depthUsed = result.historyDepthUsed
                alternatives = depthAlternatives
            }

            if !depthFiltered.isEmpty {
                rawCandidates = result.moves
                lookupKey = result.lookupKey
                depthUsed = result.historyDepthUsed
                filtered = depthFiltered
                alternatives = depthAlternatives
                break
            }
        }

        return CandidateLookupResult(raw: rawCandidates, filtered: filtered, alternatives: alternatives, lookupKey: lookupKey, depthUsed: depthUsed)
    }

    // MARK: - Tree Walk Diagnostics Collector

    /// Mutable reference-type collector passed through recursive DFS to record
    /// per-position branching stats and filter attribution without copying overhead.
    class TreeWalkCollector {
        var positionReachCounts: [Int: Int] = [:]
        var positionRawCounts: [Int: [Int]] = [:]
        var positionFilteredCounts: [Int: [Int]] = [:]
        var positionFilterAttribution: [Int: FilterAttribution] = [:]
        var positionGistBranchCounts: [Int: [Int]] = [:]
        var totalGistBranches: Int = 0

        func recordGistBranching(positionIndex: Int, branchCount: Int) {
            positionGistBranchCounts[positionIndex, default: []].append(branchCount)
            totalGistBranches += branchCount
        }

        func recordVisit(positionIndex: Int, lookup: CandidateLookupResult) {
            positionReachCounts[positionIndex, default: 0] += 1
            positionRawCounts[positionIndex, default: []].append(lookup.raw.count)
            positionFilteredCounts[positionIndex, default: []].append(lookup.filtered.count)

            // Attribute filtered candidates by rejection reason
            var attr = positionFilterAttribution[positionIndex] ?? FilterAttribution()
            for alt in lookup.alternatives {
                let reason = alt.rejectionReason
                if reason.contains("frequency cap") {
                    attr.killedByFreqCap += 1
                } else if reason.contains("Below threshold") {
                    attr.killedByThreshold += 1
                } else if reason.contains("Sparse data") {
                    attr.killedByObservation += 1
                } else if reason.contains("consecutive") || reason.contains("Consecutive") {
                    attr.killedByCategory += 1
                } else if reason.contains("No available gist") {
                    attr.killedByGistAvail += 1
                } else if reason.contains("Excluded by backtrack") {
                    attr.killedByBacktrack += 1
                }
                attr.totalKilled += 1
            }
            positionFilterAttribution[positionIndex] = attr
        }

        func buildDiagnostics(
            treeExhausted: Bool,
            viableStarterCount: Int,
            totalStartersInMatrix: Int
        ) -> TreeWalkDiagnostics {
            let allPositions = Set(positionReachCounts.keys)
                .union(positionRawCounts.keys)
                .union(positionFilteredCounts.keys)
                .sorted()

            let positionStats: [PositionLevelStats] = allPositions.map { pos in
                let reached = positionReachCounts[pos] ?? 0
                let rawCounts = positionRawCounts[pos] ?? []
                let filteredCounts = positionFilteredCounts[pos] ?? []
                let avgRaw = rawCounts.isEmpty ? 0.0 : Double(rawCounts.reduce(0, +)) / Double(rawCounts.count)
                let avgFiltered = filteredCounts.isEmpty ? 0.0 : Double(filteredCounts.reduce(0, +)) / Double(filteredCounts.count)
                let attribution = positionFilterAttribution[pos] ?? FilterAttribution()

                return PositionLevelStats(
                    positionIndex: pos,
                    timesReached: reached,
                    avgRawCandidates: avgRaw,
                    avgFilteredCandidates: avgFiltered,
                    filterAttribution: attribution
                )
            }

            // Determine limiting factor
            let limitingFactor: TreeWalkLimitingFactor
            if !treeExhausted {
                limitingFactor = .budgetReached
            } else {
                // Tree was exhausted — find root cause
                let avgBranching = positionStats.isEmpty ? 0.0 :
                    positionStats.map(\.avgFilteredCandidates).reduce(0, +) / Double(positionStats.count)

                // Sum all filter attribution across positions
                let totalAttr = positionStats.reduce(into: FilterAttribution()) { result, stat in
                    result.killedByThreshold += stat.filterAttribution.killedByThreshold
                    result.killedByObservation += stat.filterAttribution.killedByObservation
                    result.killedByCategory += stat.filterAttribution.killedByCategory
                    result.killedByFreqCap += stat.filterAttribution.killedByFreqCap
                    result.killedByGistAvail += stat.filterAttribution.killedByGistAvail
                    result.killedByBacktrack += stat.filterAttribution.killedByBacktrack
                    result.totalKilled += stat.filterAttribution.totalKilled
                }

                if avgBranching < 2.0 && totalAttr.totalKilled == 0 {
                    // Low branching but nothing filtered — corpus itself is sparse
                    limitingFactor = .sparseCorpus
                } else if totalAttr.totalKilled > 0 {
                    // Something is filtering — find the top killer
                    let topKillerCount = max(
                        totalAttr.killedByThreshold,
                        totalAttr.killedByObservation,
                        totalAttr.killedByCategory,
                        totalAttr.killedByFreqCap,
                        totalAttr.killedByGistAvail,
                        totalAttr.killedByBacktrack
                    )
                    if topKillerCount == totalAttr.killedByGistAvail {
                        limitingFactor = .gistBottleneck
                    } else if topKillerCount == totalAttr.killedByThreshold {
                        limitingFactor = .thresholdBottleneck
                    } else {
                        limitingFactor = .sparseCorpus
                    }
                } else {
                    limitingFactor = .treeExhausted
                }
            }

            // Gist branching stats
            let gistBranchingOn = !positionGistBranchCounts.isEmpty
            let allGistCounts = positionGistBranchCounts.values.flatMap { $0 }
            let avgGistBranches: Double? = gistBranchingOn && !allGistCounts.isEmpty
                ? Double(allGistCounts.reduce(0, +)) / Double(allGistCounts.count)
                : nil

            return TreeWalkDiagnostics(
                treeExhausted: treeExhausted,
                viableStarterCount: viableStarterCount,
                totalStartersInMatrix: totalStartersInMatrix,
                positionStats: positionStats,
                limitingFactor: limitingFactor,
                gistBranchingEnabled: gistBranchingOn,
                avgGistBranchesPerPosition: avgGistBranches,
                totalGistBranches: gistBranchingOn ? totalGistBranches : nil
            )
        }
    }

    // MARK: - Tree Walk DFS Engine

    /// Build a tree walk run: bounded DFS exploring all branches from each starter.
    /// Returns completed chains + all dead ends hit during exploration.
    private static func buildTreeWalkRun(
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters
    ) -> ChainBuildRun {
        let budget = parameters.monteCarloSimulations  // reuse as path budget
        let effectiveMaxLength = max(parameters.maxChainLength, gists.count + 5)

        // Auto-enable diversity cap for large tree walks if not already set
        var parameters = parameters
        if budget >= 1000 && parameters.maxMoveTypeShare >= 1.0 {
            parameters.maxMoveTypeShare = 0.35
        }

        var pathsExplored = 0
        var deadEnds: [DeadEnd] = []
        var completedChains: [ChainAttempt] = []
        var totalDeadEnds = 0
        let collector = TreeWalkCollector()

        let allStarters = MarkovTransitionService.sequenceStartProbabilities(in: matrix)
        let viableStarters = allStarters.filter { starter in
            expansionIndex.hasEligibleGists(for: starter.move, excluding: [])
        }

        if viableStarters.isEmpty {
            var run = ChainBuildRun(parameters: parameters, inputGistCount: gists.count)
            let attempt = makeFailedAttempt(
                reason: "No viable sequence starter",
                gistCount: gists.count,
                deadEndType: .missingContent,
                whatWasNeeded: "A sequence starter move with available gist content",
                whatWasMissing: "No sequence starters in the matrix had available gists",
                suggestion: "Add more rambling content covering hook/opening moves"
            )
            run.chainsAttempted.append(attempt.chain)
            run.deadEnds.append(contentsOf: attempt.deadEnds)
            return run
        }

        for starter in viableStarters {
            if pathsExplored >= budget { break }

            // Determine starter gist assignments to explore
            let starterGistIds: [UUID]
            if parameters.enableGistBranching {
                let ranked = expansionIndex.rankedEligibleGists(
                    for: starter.move, excluding: [], gists: gists,
                    limit: parameters.maxGistBranchesPerMove
                ).filter { $0.constraintScore <= 5 }
                starterGistIds = ranked.isEmpty
                    ? expansionIndex.rankedEligibleGists(for: starter.move, excluding: [], gists: gists, limit: 1).map(\.gistId)
                    : ranked.map(\.gistId)
                collector.recordGistBranching(positionIndex: 0, branchCount: starterGistIds.count)
            } else {
                guard let gid = expansionIndex.mostConstrainedGist(for: starter.move, excluding: [], gists: gists) else {
                    continue
                }
                starterGistIds = [gid]
            }

            for starterGistId in starterGistIds {
                if pathsExplored >= budget { break }

                let pos0 = ChainPosition(
                    positionIndex: 0,
                    category: starter.move.category,
                    moveType: starter.move,
                    mappedGistId: starterGistId,
                    markovProbability: starter.probability,
                    markovContext: [],
                    selectionReason: "",
                    alternativesConsidered: []
                )

                dfsExplore(
                    history: [starter.move],
                    positions: [pos0],
                    usedGistIds: [starterGistId],
                    positionIndex: 1,
                    matrix: matrix,
                    expansionIndex: expansionIndex,
                    gists: gists,
                    parameters: parameters,
                    effectiveMaxLength: effectiveMaxLength,
                    budget: budget,
                    pathsExplored: &pathsExplored,
                    completedChains: &completedChains,
                    deadEnds: &deadEnds,
                    totalDeadEnds: &totalDeadEnds,
                    collector: collector
                )
            }
        }

        // Diversity selection: pick top 5 from completed chains
        let diverse = selectDiverseChains(from: completedChains, count: 5)

        // Build diagnostics from collector
        let treeExhausted = pathsExplored < budget
        let diagnostics = collector.buildDiagnostics(
            treeExhausted: treeExhausted,
            viableStarterCount: viableStarters.count,
            totalStartersInMatrix: allStarters.count
        )

        let run = ChainBuildRun(
            parameters: parameters,
            inputGistCount: gists.count,
            chainsAttempted: diverse,
            deadEnds: deadEnds,
            treeWalkSummary: TreeWalkSummary(
                pathsExplored: pathsExplored,
                pathsCompleted: completedChains.count,
                pathsFailed: pathsExplored - completedChains.count,
                budgetUsed: pathsExplored,
                budgetMax: budget,
                totalDeadEndsHit: totalDeadEnds,
                diverseChainIndices: Array(0..<diverse.count),
                diagnostics: diagnostics
            )
        )

        return run
    }

    /// Recursive DFS: at each position, get ALL filtered candidates and recurse into each one.
    private static func dfsExplore(
        history: [RhetoricalMoveType],
        positions: [ChainPosition],
        usedGistIds: Set<UUID>,
        positionIndex: Int,
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters,
        effectiveMaxLength: Int,
        budget: Int,
        pathsExplored: inout Int,
        completedChains: inout [ChainAttempt],
        deadEnds: inout [DeadEnd],
        totalDeadEnds: inout Int,
        collector: TreeWalkCollector
    ) {
        if pathsExplored >= budget { return }

        let lookup = getFilteredCandidates(
            history: history,
            positionIndex: positionIndex,
            matrix: matrix,
            expansionIndex: expansionIndex,
            parameters: parameters,
            usedGistIds: usedGistIds
        )

        // Record visit for diagnostics
        collector.recordVisit(positionIndex: positionIndex, lookup: lookup)

        if lookup.filtered.isEmpty {
            // Dead end — create real DeadEnd object (lightweight: skip candidateDetails)
            pathsExplored += 1
            totalDeadEnds += 1

            let classification = lookup.raw.isEmpty
                ? DeadEndClassification(
                    type: .transitionImpossible,
                    missing: "Matrix returned no transitions at any depth",
                    suggestion: "Build matrix with more corpus data, or lower historyDepth"
                )
                : classifyDeadEnd(
                    candidates: lookup.raw,
                    expansionIndex: expansionIndex,
                    usedGistIds: usedGistIds,
                    parameters: parameters
                )

            let de = DeadEnd(
                chainAttemptId: UUID(),
                positionIndex: positionIndex,
                pathSoFar: history.map(\.displayName),
                deadEndType: classification.type,
                whatWasNeeded: "A valid next move after \(history.last!.displayName) at position \(positionIndex)",
                whatWasMissing: classification.missing,
                suggestedUserAction: classification.suggestion,
                candidatesFound: lookup.raw.count,
                candidateDetails: [],  // Skip for memory during tree walk
                lookupDepthUsed: lookup.depthUsed,
                lookupKey: lookup.lookupKey,
                wasBacktrackRetry: false,
                rawCandidateMoveTypes: lookup.raw.map(\.move),
                pathGistIds: positions.map(\.mappedGistId)
            )
            deadEnds.append(de)
            return
        }

        // Branch: recurse into EACH candidate
        for candidate in lookup.filtered {
            if pathsExplored >= budget { return }

            // Determine gist assignments to explore for this move
            let gistIdsToExplore: [UUID?]
            if parameters.enableGistBranching {
                let ranked = expansionIndex.rankedEligibleGists(
                    for: candidate.move, excluding: usedGistIds, gists: gists,
                    limit: parameters.maxGistBranchesPerMove
                )
                // Prune: only branch on constrained gists (score <= 5); flexible ones don't cause dead-ends
                let pruned = ranked.filter { $0.constraintScore <= 5 }
                let finalList = pruned.isEmpty ? Array(ranked.prefix(1)) : pruned
                gistIdsToExplore = finalList.map { $0.gistId as UUID? }
                collector.recordGistBranching(positionIndex: positionIndex, branchCount: finalList.count)
            } else {
                let gistId = expansionIndex.mostConstrainedGist(for: candidate.move, excluding: usedGistIds, gists: gists)
                gistIdsToExplore = [gistId]
            }

            for gistId in gistIdsToExplore {
                if pathsExplored >= budget { return }

                // Safety: skip if this gist was already used in this path
                if let gid = gistId, usedGistIds.contains(gid) { continue }

                let lightweightPosition = ChainPosition(
                    positionIndex: positionIndex,
                    category: candidate.move.category,
                    moveType: candidate.move,
                    mappedGistId: gistId,
                    markovProbability: candidate.probability,
                    markovContext: [],
                    selectionReason: "",
                    alternativesConsidered: []
                )

                let newPositions = positions + [lightweightPosition]
                let newHistory = history + [candidate.move]
                var newUsedGists = usedGistIds
                if let gid = gistId { newUsedGists.insert(gid) }

                // Check coverage — if sufficient, record completed chain
                if newPositions.count >= parameters.minChainLength {
                    let coverage = Double(newUsedGists.count) / Double(max(gists.count, 1))
                    if coverage >= parameters.coverageTarget {
                        pathsExplored += 1
                        let attempt = ChainAttempt(
                            positions: newPositions,
                            status: .completed,
                            coverageScore: coverage,
                            gistsUsed: Array(newUsedGists),
                            gistsUnused: Array(Set(gists.map(\.id)).subtracting(newUsedGists)),
                            starterMove: newPositions.first?.moveType.displayName
                        )
                        completedChains.append(attempt)
                        continue  // Don't recurse further — this path completed
                    }
                }

                // Not yet complete and not at max length — recurse deeper
                if newPositions.count < effectiveMaxLength {
                    dfsExplore(
                        history: newHistory,
                        positions: newPositions,
                        usedGistIds: newUsedGists,
                        positionIndex: positionIndex + 1,
                        matrix: matrix,
                        expansionIndex: expansionIndex,
                        gists: gists,
                        parameters: parameters,
                        effectiveMaxLength: effectiveMaxLength,
                        budget: budget,
                        pathsExplored: &pathsExplored,
                        completedChains: &completedChains,
                        deadEnds: &deadEnds,
                        totalDeadEnds: &totalDeadEnds,
                        collector: collector
                    )
                } else {
                    // Hit max length without coverage — still a completed path
                    pathsExplored += 1
                    let coverage = Double(newUsedGists.count) / Double(max(gists.count, 1))
                    let attempt = ChainAttempt(
                        positions: newPositions,
                        status: .completed,
                        coverageScore: coverage,
                        gistsUsed: Array(newUsedGists),
                        gistsUnused: Array(Set(gists.map(\.id)).subtracting(newUsedGists)),
                        starterMove: newPositions.first?.moveType.displayName
                    )
                    completedChains.append(attempt)
                }
            }
        }
    }

    // MARK: - Diverse Chain Selection

    /// Select top N chains by category-arc diversity. First pick = highest coverage,
    /// then greedily pick most different from already-selected.
    private static func selectDiverseChains(
        from completed: [ChainAttempt],
        count: Int = 5
    ) -> [ChainAttempt] {
        guard !completed.isEmpty else { return [] }

        var pool = completed.sorted { $0.coverageScore > $1.coverageScore }
        var selected: [ChainAttempt] = []

        // Pick first (highest coverage)
        selected.append(pool.removeFirst())

        while selected.count < count && !pool.isEmpty {
            let best = pool.enumerated().max { a, b in
                minArcDistance(a.element, to: selected) < minArcDistance(b.element, to: selected)
            }
            if let best = best {
                var chain = pool.remove(at: best.offset)
                chain.diversityScore = minArcDistance(chain, to: selected)
                selected.append(chain)
            }
        }

        return selected
    }

    /// Category-arc distance between two chains
    private static func arcDistance(_ a: ChainAttempt, _ b: ChainAttempt) -> Double {
        let arcA = a.categoryArc
        let arcB = b.categoryArc
        let maxLen = max(arcA.count, arcB.count)
        guard maxLen > 0 else { return 0 }
        var diffs = 0
        for i in 0..<maxLen {
            let catA = i < arcA.count ? arcA[i] : nil
            let catB = i < arcB.count ? arcB[i] : nil
            if catA != catB { diffs += 1 }
        }
        return Double(diffs) / Double(maxLen)
    }

    /// Minimum arc distance from a chain to any chain in a set
    private static func minArcDistance(_ chain: ChainAttempt, to selected: [ChainAttempt]) -> Double {
        selected.map { arcDistance(chain, $0) }.min() ?? 0
    }

    // MARK: - Upside Scoring (Post-Tree-Walk)

    /// Groups dead ends by rawCandidateMoveTypes, computes upside per move-type group,
    /// writes the score back to each dead end.
    ///
    /// Three signals:
    /// - Frequency: what fraction of all dead ends does this group represent?
    /// - Depth: average position as fraction of target length (deeper = more valuable to fix)
    /// - Diversity: how many distinct starters' paths are blocked (systemic bottleneck)?
    static func computeDeadEndUpside(
        deadEnds: inout [DeadEnd],
        parameters: ChainParameters,
        effectiveMaxLength: Int,
        totalStarters: Int
    ) {
        let totalDeadEnds = deadEnds.count
        guard totalDeadEnds > 0 else { return }

        // Build per-move-type aggregation
        var moveGroups: [RhetoricalMoveType: [Int]] = [:]
        for (idx, de) in deadEnds.enumerated() {
            for move in de.rawCandidateMoveTypes {
                moveGroups[move, default: []].append(idx)
            }
        }

        // Distinct starters across ALL dead ends (for diversity denominator)
        let allDistinctStarters = Set(deadEnds.compactMap { $0.pathSoFar.first })
        let totalDistinctStarters = max(allDistinctStarters.count, 1)

        for (_, indices) in moveGroups {
            let group = indices.map { deadEnds[$0] }

            // Frequency: what fraction of all dead ends does this group represent?
            let frequency = Double(group.count) / Double(totalDeadEnds)

            // Depth: average position as fraction of target length (deeper = closer to completion)
            let avgDepth = group.map { Double($0.positionIndex) / Double(max(effectiveMaxLength, 1)) }
                .reduce(0, +) / Double(max(group.count, 1))

            // Diversity: how many distinct starters' paths are blocked by this move?
            let distinctStartersBlocked = Set(group.compactMap { $0.pathSoFar.first }).count
            let diversityRatio = min(Double(distinctStartersBlocked) / Double(totalDistinctStarters), 1.0)

            let upside = (frequency * parameters.upsideFrequencyWeight)
                + (avgDepth * parameters.upsideDepthWeight)
                + (diversityRatio * parameters.upsideDiversityWeight)

            for idx in indices {
                deadEnds[idx].upsideScore = upside
            }
        }
    }

    // MARK: - Cascade Simulation (Post-Tree-Walk)

    /// For each dead end group (by move type), simulates what happens if a phantom gist
    /// were available for that move. Walks forward from the dead end position to measure
    /// runway (additional positions gained), completions, and next blockages.
    ///
    /// Level 2: For top N groups, also simulates fixing the most common next blocker.
    static func computeCascadeAnalysis(
        deadEnds: [DeadEnd],
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters,
        effectiveMaxLength: Int,
        maxLevel2Groups: Int = 5
    ) -> [CascadeResult] {
        // Group dead ends by move type (same grouping as upside)
        var moveGroups: [RhetoricalMoveType: [DeadEnd]] = [:]
        for de in deadEnds {
            for move in de.rawCandidateMoveTypes {
                moveGroups[move, default: []].append(de)
            }
        }

        // Sort by upside score for level-2 prioritization
        let rankedGroups = moveGroups.sorted { a, b in
            let upsideA = a.value.map(\.upsideScore).max() ?? 0
            let upsideB = b.value.map(\.upsideScore).max() ?? 0
            return upsideA > upsideB
        }

        var results: [CascadeResult] = []

        for (rank, (moveType, groupDeadEnds)) in rankedGroups.enumerated() {
            var totalRunway: Double = 0
            var completions = 0
            var nextBlockages: [RhetoricalMoveType: Int] = [:]

            for de in groupDeadEnds {
                let (runway, completed, blocker) = simulateForwardFromDeadEnd(
                    de, phantomMoves: [moveType],
                    matrix: matrix, expansionIndex: expansionIndex,
                    gists: gists, parameters: parameters,
                    effectiveMaxLength: effectiveMaxLength
                )
                totalRunway += Double(runway)
                if completed { completions += 1 }
                if let b = blocker { nextBlockages[b, default: 0] += 1 }
            }

            let avgRunway = groupDeadEnds.isEmpty ? 0 : totalRunway / Double(groupDeadEnds.count)
            let topNextBlockage = nextBlockages.max { $0.value < $1.value }

            // Level 2: for top N groups, simulate fixing both this move AND the top next blockage
            var level2Completions = 0
            var level2NextBlockage: RhetoricalMoveType? = nil
            var level2NextBlockageCount = 0

            if rank < maxLevel2Groups, let nextBlocker = topNextBlockage?.key {
                var l2NextBlockages: [RhetoricalMoveType: Int] = [:]

                for de in groupDeadEnds {
                    let (_, completed, blocker) = simulateForwardFromDeadEnd(
                        de, phantomMoves: [moveType, nextBlocker],
                        matrix: matrix, expansionIndex: expansionIndex,
                        gists: gists, parameters: parameters,
                        effectiveMaxLength: effectiveMaxLength
                    )
                    if completed { level2Completions += 1 }
                    if let b = blocker { l2NextBlockages[b, default: 0] += 1 }
                }

                let l2Top = l2NextBlockages.max { $0.value < $1.value }
                level2NextBlockage = l2Top?.key
                level2NextBlockageCount = l2Top?.value ?? 0
            }

            results.append(CascadeResult(
                moveType: moveType,
                deadEndCount: groupDeadEnds.count,
                avgRunwayAfterFix: avgRunway,
                completionCount: completions,
                nextBlockageMove: topNextBlockage?.key,
                nextBlockageCount: topNextBlockage?.value ?? 0,
                level2CompletionCount: level2Completions,
                level2NextBlockageMove: level2NextBlockage,
                level2NextBlockageCount: level2NextBlockageCount
            ))
        }

        return results
    }

    /// Simulates walking forward from a dead end position, pretending phantom gists
    /// exist for the specified move types. Returns (runway, completed, nextBlockerMove).
    private static func simulateForwardFromDeadEnd(
        _ de: DeadEnd,
        phantomMoves: [RhetoricalMoveType],
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters,
        effectiveMaxLength: Int
    ) -> (runway: Int, completed: Bool, nextBlocker: RhetoricalMoveType?) {
        let phantomSet = Set(phantomMoves)

        // Reconstruct usedGistIds from the chain builder's actual gist assignments
        let pathMoves = de.pathSoFar.compactMap { RhetoricalMoveType.parse($0) }
        var usedGistIds: Set<UUID> = []
        for (idx, move) in pathMoves.enumerated() {
            if idx < de.pathGistIds.count, let gid = de.pathGistIds[idx] {
                usedGistIds.insert(gid)
            } else {
                // Fallback for old data or gap positions
                if let gistId = expansionIndex.mostConstrainedGist(
                    for: move, excluding: usedGistIds, gists: gists
                ) {
                    usedGistIds.insert(gistId)
                }
            }
        }

        // Start walking from the dead end position
        // The phantom fix: append the blocking move to history without consuming a real gist
        var history = pathMoves
        history.append(phantomMoves[0])  // Primary phantom fix at the dead end position

        var posIdx = de.positionIndex + 1
        var runway = 0

        while posIdx < effectiveMaxLength {
            let lookup = getFilteredCandidates(
                history: history,
                positionIndex: posIdx,
                matrix: matrix,
                expansionIndex: expansionIndex,
                parameters: parameters,
                usedGistIds: usedGistIds
            )

            if lookup.filtered.isEmpty {
                // Another dead end — check if it's a phantom-fixable move
                let rawMoves = Set(lookup.raw.map(\.move))
                let fixableBlocker = phantomSet.intersection(rawMoves).first
                if let fixable = fixableBlocker {
                    // Phantom fix this too — skip without consuming a gist
                    history.append(fixable)
                    posIdx += 1
                    runway += 1
                    continue
                }
                // Genuine dead end — record the blocker
                let blocker = lookup.raw.first?.move
                return (runway, false, blocker)
            }

            // Pick best candidate (highest probability, same as chain builder)
            let best = lookup.filtered.max { $0.probability < $1.probability }!
            if let gistId = expansionIndex.mostConstrainedGist(
                for: best.move, excluding: usedGistIds, gists: gists
            ) {
                usedGistIds.insert(gistId)
            }
            history.append(best.move)
            posIdx += 1
            runway += 1

            // Check completion
            if posIdx >= parameters.minChainLength {
                let coverage = Double(usedGistIds.count) / Double(max(gists.count, 1))
                if coverage >= parameters.coverageTarget {
                    return (runway, true, nil)
                }
            }
        }

        // Hit max length without completing
        return (runway, false, nil)
    }

    // MARK: - LLM Guidance Enrichment (Async)

    /// Corpus example for LLM prompt context
    struct CorpusExample {
        let move: RhetoricalMove
        let videoId: String
        let chunkIndex: Int
        let compositeScore: Double
        let selectionReason: String
    }

    /// Enriches top N dead end groups with LLM-generated rambling guidance.
    /// Returns per-move-type guidance dict (primary storage).
    /// Also writes to individual dead ends for backward compat.
    static func enrichDeadEndsWithGuidance(
        deadEnds: inout [DeadEnd],
        gists: [RamblingGist],
        corpusSequences: [String: RhetoricalSequence],
        johnnyGists: [JohnnyGist],
        maxToEnrich: Int
    ) async -> [RhetoricalMoveType: MoveTypeGuidance] {
        var guidanceResult: [RhetoricalMoveType: MoveTypeGuidance] = [:]

        // Build lookup: videoId → chunkIndex → JohnnyGist for fullChunkText retrieval
        var johnnyLookup: [String: [Int: JohnnyGist]] = [:]
        for jg in johnnyGists {
            johnnyLookup[jg.videoId, default: [:]][jg.chunkIndex] = jg
        }

        // Group by rawCandidateMoveTypes
        var moveTypeDeadEnds: [RhetoricalMoveType: [Int]] = [:]
        for (idx, de) in deadEnds.enumerated() {
            for move in de.rawCandidateMoveTypes {
                moveTypeDeadEnds[move, default: []].append(idx)
            }
        }

        // Rank by upside (use max upside within each group)
        let ranked = moveTypeDeadEnds
            .map { (move: $0.key, indices: $0.value, upside: $0.value.map { deadEnds[$0].upsideScore }.max() ?? 0) }
            .sorted { $0.upside > $1.upside }

        // Gist lookup by ID for displaying content — reads actual assignments from pathGistIds
        let gistById: [UUID: RamblingGist] = Dictionary(uniqueKeysWithValues: gists.map { ($0.id, $0) })

        // --- Phase 1: Build all prompts (CPU-only, no LLM calls) ---

        struct GuidanceRequest: Sendable {
            let move: RhetoricalMoveType
            let indices: [Int]
            let userPrompt: String
            let systemPrompt: String
            let representativePathSoFar: [String]
            let representativePositionIndex: Int
            let debugTrace: String
        }

        let systemPrompt = "You help content creators identify what's missing from their rambling to complete a rhetorical narrative chain. Output ONLY the question — no preamble, no labels."

        // Pre-compute per-dead-end overlap counts (how many groups each DE appears in)
        var deGroupCounts: [Int: Int] = [:]
        for (idx, de) in deadEnds.enumerated() {
            deGroupCounts[idx] = de.rawCandidateMoveTypes.count
        }

        var requests: [GuidanceRequest] = []

        for group in ranked.prefix(maxToEnrich) {
            var trace: [String] = []
            trace.append("═══════════════════════════════════════════════")
            trace.append("GUIDANCE DEBUG TRACE: \(group.move.displayName)")
            trace.append("═══════════════════════════════════════════════")

            // ── Step 1: Group Formation ──
            trace.append("")
            trace.append("── STEP 1: GROUP FORMATION ──")
            trace.append("Target move type: \(group.move.displayName) [\(group.move.category.rawValue)]")
            trace.append("Dead ends in this group: \(group.indices.count)")
            trace.append("Grouping key: rawCandidateMoveTypes (every DE whose raw candidate list contains \(group.move.displayName))")

            // Show overlap: how many groups does each DE in this group also appear in?
            let overlapCounts = group.indices.map { deGroupCounts[$0] ?? 0 }
            let avgOverlap = overlapCounts.isEmpty ? 0.0 : Double(overlapCounts.reduce(0, +)) / Double(overlapCounts.count)
            let maxOverlap = overlapCounts.max() ?? 0
            trace.append("Overlap: each DE in this group appears in avg \(String(format: "%.1f", avgOverlap)) groups (max \(maxOverlap))")
            trace.append("WHY: A DE with rawCandidateMoveTypes [A, B, C, D] appears in ALL 4 groups. This means groups are NOT disjoint.")

            // Show position distribution
            let positions = group.indices.map { deadEnds[$0].positionIndex }
            let positionCounts = Dictionary(grouping: positions, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key }
            let positionStr = positionCounts.map { "pos \($0.key): \($0.value)x" }.joined(separator: ", ")
            trace.append("Position distribution: \(positionStr)")

            // Show deadEndType distribution
            let typeCounts = Dictionary(grouping: group.indices.map { deadEnds[$0].deadEndType }, by: { $0 }).mapValues(\.count)
            let typeStr = typeCounts.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", ")
            trace.append("Dead end type distribution: \(typeStr)")

            // Show arc fingerprint diversity
            let arcFingerprints = Set(group.indices.map { deadEnds[$0].pathSoFar.joined(separator: "→") })
            trace.append("Distinct arc fingerprints: \(arcFingerprints.count) out of \(group.indices.count) dead ends")
            if arcFingerprints.count <= 5 {
                for arc in arcFingerprints.prefix(5) {
                    trace.append("  arc: \(arc)")
                }
            } else {
                // Show a sample
                for arc in arcFingerprints.prefix(3) {
                    trace.append("  arc: \(arc)")
                }
                trace.append("  ... and \(arcFingerprints.count - 3) more")
            }

            // ── Step 2: Representative Selection ──
            trace.append("")
            trace.append("── STEP 2: REPRESENTATIVE SELECTION ──")
            trace.append("Selection method: promptQualityScore() = (recentCoverage × 0.50) + (depthScore × 0.30) + (totalCoverage × 0.20)")

            let scoredCandidates = group.indices.map { idx -> (idx: Int, de: DeadEnd, score: Double) in
                let de = deadEnds[idx]
                return (idx, de, promptQualityScore(de))
            }.sorted { $0.score > $1.score }

            // Show top 5 candidates with full score breakdown
            for (rank, entry) in scoredCandidates.prefix(5).enumerated() {
                let de = entry.de
                let recent = Array(de.pathGistIds.suffix(5))
                let recentCovered = recent.filter { $0 != nil }.count
                let recentCoverage = Double(recentCovered) / Double(max(recent.count, 1))
                let totalCovered = de.pathGistIds.filter { $0 != nil }.count
                let totalCoverage = Double(totalCovered) / Double(max(de.pathGistIds.count, 1))
                let depthScore = min(Double(de.positionIndex) / 20.0, 1.0)

                let marker = rank == 0 ? " ◀ WINNER" : ""
                trace.append("  #\(rank + 1) (DE idx \(entry.idx)) pos=\(de.positionIndex), score=\(String(format: "%.3f", entry.score))\(marker)")
                trace.append("       recentCoverage=\(String(format: "%.2f", recentCoverage)) (\(recentCovered)/\(recent.count) of last 5 have gists)")
                trace.append("       depthScore=\(String(format: "%.2f", depthScore)) (pos \(de.positionIndex) / 20)")
                trace.append("       totalCoverage=\(String(format: "%.2f", totalCoverage)) (\(totalCovered)/\(de.pathGistIds.count) total)")
                trace.append("       deadEndType=\(de.deadEndType.rawValue)")
                trace.append("       rawCandidateMoveTypes=[\(de.rawCandidateMoveTypes.map(\.displayName).joined(separator: ", "))]")
            }
            if scoredCandidates.count > 5 {
                trace.append("  ... and \(scoredCandidates.count - 5) more candidates not shown")
            }

            // Pick representative
            let representative = scoredCandidates[0].de

            trace.append("")
            trace.append("SELECTED REPRESENTATIVE:")
            trace.append("  Position: \(representative.positionIndex)")
            trace.append("  Dead end type: \(representative.deadEndType.rawValue)")
            trace.append("  Path length: \(representative.pathSoFar.count)")
            trace.append("  pathGistIds count: \(representative.pathGistIds.count)")

            // ── Step 3: Arc Context Building ──
            trace.append("")
            trace.append("── STEP 3: ARC CONTEXT BUILDING ──")

            let pathMoves = representative.pathSoFar.compactMap { RhetoricalMoveType.parse($0) }

            // Full arc
            let arcStr = representative.pathSoFar.joined(separator: " → ")
            trace.append("Full arc (\(pathMoves.count) moves): \(arcStr)")

            // Context window
            let contextWindow = 5
            var contextLines: [String] = []
            var lastEstablished: String? = nil
            let startIdx = max(0, pathMoves.count - contextWindow)

            // Find most recent factual_claim gist in full arc
            var anchorGist: RamblingGist? = nil
            for i in stride(from: pathMoves.count - 1, through: 0, by: -1) {
                let gistId = i < representative.pathGistIds.count ? representative.pathGistIds[i] : nil
                if let gid = gistId, let gist = gistById[gid], gist.gistA.frame == .factualClaim {
                    anchorGist = gist
                    break
                }
            }

            trace.append("Context window: positions \(startIdx)..\(pathMoves.count - 1) (last \(min(contextWindow, pathMoves.count)) of \(pathMoves.count))")
            trace.append("Anchor gist (most recent factual_claim): \(anchorGist.map { "chunk \($0.chunkIndex + 1) — \"\($0.gistA.premise)\"" } ?? "NONE found in arc")")
            trace.append("")

            for i in startIdx..<pathMoves.count {
                let move = pathMoves[i]
                let gistId = i < representative.pathGistIds.count ? representative.pathGistIds[i] : nil

                if let gid = gistId, let gist = gistById[gid] {
                    let premise = gist.gistA.premise
                    contextLines.append("- Position \(i) (\(move.displayName)): \"\(premise)\"")
                    lastEstablished = premise
                    trace.append("  Position \(i): move=\(move.displayName), gistId=\(gid.uuidString.prefix(8))..., FOUND gist")
                    trace.append("    premise: \"\(premise.prefix(100))\(premise.count > 100 ? "..." : "")\"")
                } else {
                    contextLines.append("- Position \(i) (\(move.displayName)): (no gist assigned)")
                    if let gid = gistId {
                        trace.append("  Position \(i): move=\(move.displayName), gistId=\(gid.uuidString.prefix(8))..., NOT FOUND in gistById lookup")
                    } else {
                        trace.append("  Position \(i): move=\(move.displayName), gistId=nil (no gist was assigned by chain builder)")
                    }
                }
            }

            contextLines.append("- Position \(representative.positionIndex) (???): MISSING — this is the gap.")

            let contextStr = contextLines.joined(separator: "\n")

            // Last established
            let lastEstablishedStr: String
            if let last = lastEstablished, let lastMove = pathMoves.last {
                lastEstablishedStr = "\nThe last thing established (\(lastMove.displayName)): \"\(last)\"\n"
                trace.append("")
                trace.append("Last established content: \(lastMove.displayName)")
                trace.append("  \"\(last.prefix(120))\(last.count > 120 ? "..." : "")\"")
            } else {
                lastEstablishedStr = ""
                trace.append("")
                trace.append("Last established content: NONE (no gist found in context window)")
            }

            // ── Step 4: Move Definition ──
            trace.append("")
            trace.append("── STEP 4: MOVE DEFINITION ──")
            trace.append("Target move: \(group.move.displayName)")
            trace.append("Category: \(group.move.category.rawValue)")
            trace.append("Definition: \(group.move.rhetoricalDefinition)")
            trace.append("Example phrase: \"\(group.move.examplePhrase)\"")

            let moveDefStr = """
            The chain needs a [\(group.move.displayName)] next — a move that \(group.move.rhetoricalDefinition.lowercased()).
            Example: "\(group.move.examplePhrase)"
            """

            // ── Step 5: Cross-Category Transition ──
            trace.append("")
            trace.append("── STEP 5: CROSS-CATEGORY TRANSITION CHECK ──")

            let transitionStr: String
            if let lastMove = pathMoves.last {
                trace.append("Last move in arc: \(lastMove.displayName) [\(lastMove.category.rawValue)]")
                trace.append("Target move: \(group.move.displayName) [\(group.move.category.rawValue)]")

                if lastMove.category != group.move.category {
                    if let note = RhetoricalCategory.transitionNote(from: lastMove.category, to: group.move.category) {
                        transitionStr = "\nSTRUCTURAL NOTE: The previous move was \(lastMove.displayName) [\(lastMove.category.rawValue)], and the next move is \(group.move.displayName) [\(group.move.category.rawValue)]. \(note)\n"
                        trace.append("Cross-category: YES (\(lastMove.category.rawValue) → \(group.move.category.rawValue))")
                        trace.append("Transition note: \(note)")
                    } else {
                        transitionStr = ""
                        trace.append("Cross-category: YES but no transition note defined for \(lastMove.category.rawValue) → \(group.move.category.rawValue)")
                    }
                } else {
                    transitionStr = ""
                    trace.append("Cross-category: NO (same category: \(lastMove.category.rawValue))")
                }
            } else {
                transitionStr = ""
                trace.append("No last move in arc (empty pathMoves)")
            }

            // ── Step 6: Corpus Examples ──
            trace.append("")
            trace.append("── STEP 6: CORPUS EXAMPLES ──")

            let categoryArc = pathMoves.map(\.category)
            let posRatio = Double(representative.positionIndex) / Double(max(15, 1))
            trace.append("Search params: moveType=\(group.move.displayName), positionRatio=\(String(format: "%.2f", posRatio)), arcLength=\(categoryArc.count)")

            let corpusExamples = findCorpusExamples(
                for: group.move,
                in: corpusSequences,
                deadEndPositionRatio: posRatio,
                categoryArc: categoryArc
            )

            trace.append("Corpus examples found: \(corpusExamples.count)")

            let examplesSection: String
            if corpusExamples.count >= 2 {
                let formatted = corpusExamples.map { ex in
                    let creatorText: String
                    if let jg = johnnyLookup[ex.videoId]?[ex.chunkIndex] {
                        let raw = jg.fullChunkText
                        creatorText = raw.count > 800
                            ? String(raw.prefix(800)) + "..."
                            : raw
                    } else {
                        var fallback = ex.move.briefDescription
                        if let expanded = ex.move.expandedDescription {
                            fallback += " — \(expanded)"
                        }
                        creatorText = fallback
                    }
                    return "- \"\(creatorText)\"\n  [Structural match: \(ex.selectionReason)]"
                }.joined(separator: "\n")
                examplesSection = "\nHere is how creators actually execute this move (raw script text):\n\(formatted)\n"

                for (i, ex) in corpusExamples.enumerated() {
                    let hasJohnny = johnnyLookup[ex.videoId]?[ex.chunkIndex] != nil
                    trace.append("  Example \(i + 1): video=\(ex.videoId.prefix(12))..., chunk=\(ex.chunkIndex), score=\(String(format: "%.3f", ex.compositeScore))")
                    trace.append("    scoring: \(ex.selectionReason)")
                    trace.append("    source: \(hasJohnny ? "JohnnyGist fullChunkText" : "fallback briefDescription")")
                }
            } else {
                examplesSection = ""
                trace.append("Not enough examples (need ≥2, got \(corpusExamples.count)) — section omitted from prompt")
            }

            // ── Step 7: MISMATCH CHECK ──
            trace.append("")
            trace.append("── STEP 7: MISMATCH CHECK ──")

            // Check: does the representative's deadEndType badge match the group's move type?
            trace.append("Group move type (what prompt asks for): \(group.move.displayName) [\(group.move.category.rawValue)]")
            trace.append("Representative's deadEndType badge: \(representative.deadEndType.rawValue)")
            if let lastMove = pathMoves.last {
                trace.append("Last move in representative's arc: \(lastMove.displayName) [\(lastMove.category.rawValue)]")
                if lastMove.category == group.move.category && lastMove != group.move {
                    trace.append("⚠️  SAME CATEGORY: last arc move (\(lastMove.displayName)) and target (\(group.move.displayName)) are both [\(group.move.category.rawValue)]")
                }
            }
            let repRawMoves = representative.rawCandidateMoveTypes.map(\.displayName).joined(separator: ", ")
            trace.append("Representative's rawCandidateMoveTypes: [\(repRawMoves)]")
            if !representative.rawCandidateMoveTypes.contains(where: { $0 == group.move }) {
                trace.append("🚨 CRITICAL MISMATCH: group.move (\(group.move.displayName)) is NOT in representative's rawCandidateMoveTypes!")
            }

            // Check what the representative's candidateDetails say about rejection
            if !representative.candidateDetails.isEmpty {
                trace.append("Representative's candidate details (rejection reasons):")
                for cd in representative.candidateDetails {
                    trace.append("  \(cd.moveName): prob=\(String(format: "%.1f%%", cd.probability * 100)), obs=\(cd.observationCount), reason=\"\(cd.rejectionReason)\"")
                }
            } else {
                trace.append("Representative has no candidateDetails (tree walk skips these for memory)")
            }

            // ── Step 8: Final Prompt Assembly ──
            trace.append("")
            trace.append("── STEP 8: PROMPT ASSEMBLY ──")
            trace.append("System prompt: \"\(systemPrompt)\"")
            trace.append("Chains blocked by this gap: \(group.indices.count)")

            let userPrompt = """
            A rhetorical chain was building this arc (\(representative.positionIndex) positions):
            \(arcStr)

            Recent context (user's rambling content):
            \(contextStr)
            \(lastEstablishedStr)
            \(moveDefStr)
            \(transitionStr)
            \(anchorGist.map { "Most recent unanchored factual claim: \"\($0.gistA.premise)\" — the question should ask the user to provide support specifically for this claim." } ?? "")
            This gap blocked \(group.indices.count) chains across the tree walk.
            \(examplesSection)
            Based on the story arc so far and what the last beat established, write one specific \
            question that tells the user exactly what they need to go ramble about to fill this gap.
            """

            trace.append("Prompt length: \(userPrompt.count) chars")
            trace.append("═══════════════════════════════════════════════")

            requests.append(GuidanceRequest(
                move: group.move,
                indices: group.indices,
                userPrompt: userPrompt,
                systemPrompt: systemPrompt,
                representativePathSoFar: representative.pathSoFar,
                representativePositionIndex: representative.positionIndex,
                debugTrace: trace.joined(separator: "\n")
            ))
        }

        // --- Phase 2: Fire all LLM calls in parallel ---

        // Build lookup from move → debugTrace for Phase 3
        var traceByMove: [RhetoricalMoveType: String] = [:]
        for request in requests {
            traceByMove[request.move] = request.debugTrace
        }

        let results = await withTaskGroup(
            of: (RhetoricalMoveType, [Int], String, String, [String], Int).self
        ) { taskGroup in
            for request in requests {
                taskGroup.addTask {
                    let adapter = ClaudeModelAdapter(model: .claude4Sonnet)
                    let response = await adapter.generate_response(
                        prompt: request.userPrompt,
                        promptBackgroundInfo: request.systemPrompt,
                        params: ["temperature": 0.3, "max_tokens": 300]
                    )
                    let guidance = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (request.move, request.indices, guidance, request.userPrompt,
                            request.representativePathSoFar, request.representativePositionIndex)
                }
            }

            var collected: [(RhetoricalMoveType, [Int], String, String, [String], Int)] = []
            for await result in taskGroup {
                collected.append(result)
            }
            return collected
        }

        // --- Phase 3: Apply results (sequential, mutates inout deadEnds) ---

        for (move, indices, guidance, prompt, pathSoFar, positionIndex) in results {
            // Append LLM response to the debug trace
            let trace = traceByMove[move] ?? ""
            let fullTrace = trace + "\n\n── LLM RESPONSE ──\n\(guidance)\n"

            // Store in per-move-type dictionary (primary storage — no collision possible)
            guidanceResult[move] = MoveTypeGuidance(
                guidance: guidance,
                prompt: prompt,
                representativePathSoFar: pathSoFar,
                representativePositionIndex: positionIndex,
                debugTrace: fullTrace
            )

            // Backward compat: also write to individual dead ends
            for idx in indices {
                deadEnds[idx].ramblingGuidance = guidance
                deadEnds[idx].guidancePrompt = prompt
                deadEnds[idx].guidanceMoveType = move.displayName
            }
        }

        return guidanceResult
    }

    // MARK: - Prompt Quality Scoring

    /// Scores a dead end for how good a prompt it would produce.
    /// Uses pathGistIds (actual chain builder assignments) to count coverage.
    /// A chain at position 10 with gist content at every position produces
    /// a far better LLM prompt than a chain at position 5 with holes.
    private static func promptQualityScore(_ de: DeadEnd) -> Double {
        guard !de.pathSoFar.isEmpty else { return 0 }

        // Recent positions (last 5 — what the prompt window actually shows)
        let recent = Array(de.pathGistIds.suffix(5))
        let recentCovered = recent.filter { $0 != nil }.count
        let recentCoverage = Double(recentCovered) / Double(max(recent.count, 1))

        // Overall chain coverage
        let totalCovered = de.pathGistIds.filter { $0 != nil }.count
        let totalCoverage = Double(totalCovered) / Double(max(de.pathGistIds.count, 1))

        // Depth — longer chains give more structural context (normalize to ~20 positions)
        let depthScore = min(Double(de.positionIndex) / 20.0, 1.0)

        // Weight: recent coverage matters most (LLM sees it), then depth, then overall
        return (recentCoverage * 0.50) + (depthScore * 0.30) + (totalCoverage * 0.20)
    }

    // MARK: - Corpus Example Retrieval (Multi-Signal)

    /// Find corpus examples of a move type with multi-signal structural scoring:
    /// arc distance (50%), position ratio (20%), stack depth (15%), tension direction (15%).
    private static func findCorpusExamples(
        for moveType: RhetoricalMoveType,
        in sequences: [String: RhetoricalSequence],
        deadEndPositionRatio: Double,
        categoryArc: [RhetoricalCategory],
        maxExamples: Int = 3
    ) -> [CorpusExample] {
        var candidates: [CorpusExample] = []

        for (videoId, seq) in sequences {
            let seqMoves = seq.moves.sorted { $0.chunkIndex < $1.chunkIndex }
            let seqArc = seq.parentSequence

            for (moveIdx, move) in seqMoves.enumerated() where move.moveType == moveType {
                // 1. Arc distance (50%)
                let arcDist = categoryArcDistance(seqArc, categoryArc)
                let arcScore = 1.0 - min(arcDist, 1.0)

                // 2. Position ratio proximity (20%)
                let examplePosRatio = Double(moveIdx) / Double(max(seqMoves.count - 1, 1))
                let posScore = 1.0 - abs(examplePosRatio - deadEndPositionRatio)

                // 3. Stack depth match (15%)
                let exampleStackDepth = consecutiveSameCategoryBefore(seqMoves, at: moveIdx)
                let deadEndStackDepth = consecutiveSameCategoryCount(categoryArc)
                let stackScore = exampleStackDepth == deadEndStackDepth ? 1.0
                    : 1.0 / (1.0 + Double(abs(exampleStackDepth - deadEndStackDepth)))

                // 4. Tension direction (15%)
                let exampleDirection = tensionDirection(seqMoves, at: moveIdx)
                let deadEndDirection = tensionDirectionFromArc(categoryArc)
                let tensionScore: Double = exampleDirection == deadEndDirection ? 1.0 : 0.3

                let composite = (arcScore * 0.50) + (posScore * 0.20) + (stackScore * 0.15) + (tensionScore * 0.15)

                let reason = "arc \(fmt2(arcScore)), pos \(fmt2(posScore)), stack \(exampleStackDepth)/\(deadEndStackDepth), \(exampleDirection.rawValue)"

                candidates.append(CorpusExample(move: move, videoId: videoId, chunkIndex: move.chunkIndex, compositeScore: composite, selectionReason: reason))
            }
        }

        return candidates.sorted { $0.compositeScore > $1.compositeScore }
            .prefix(maxExamples)
            .map { $0 }
    }

    // MARK: - Corpus Example Helpers

    private enum TensionDirection: String {
        case resolving, escalating, neutral
    }

    /// Normalized edit distance between two category arcs (0 = identical, 1 = completely different)
    private static func categoryArcDistance(_ a: [RhetoricalCategory], _ b: [RhetoricalCategory]) -> Double {
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 0 }
        var diffs = 0
        for i in 0..<maxLen {
            let catA = i < a.count ? a[i] : nil
            let catB = i < b.count ? b[i] : nil
            if catA != catB { diffs += 1 }
        }
        return Double(diffs) / Double(maxLen)
    }

    /// Count consecutive same-category moves before a given index
    private static func consecutiveSameCategoryBefore(_ moves: [RhetoricalMove], at index: Int) -> Int {
        guard index > 0 && index < moves.count else { return 0 }
        let targetCat = moves[index].moveType.category
        var count = 0
        for i in stride(from: index - 1, through: 0, by: -1) {
            if moves[i].moveType.category == targetCat {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Count consecutive same-category at the end of an arc
    private static func consecutiveSameCategoryCount(_ arc: [RhetoricalCategory]) -> Int {
        guard let last = arc.last else { return 0 }
        var count = 0
        for cat in arc.reversed() {
            if cat == last {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Determine if the narrative tension is resolving or escalating at a given position
    private static func tensionDirection(_ moves: [RhetoricalMove], at index: Int) -> TensionDirection {
        guard index > 0 else { return .neutral }
        let current = moves[index].moveType.category
        let previous = moves[index - 1].moveType.category
        let resolvingTransitions: Set<[RhetoricalCategory]> = [
            [.tension, .revelation], [.tension, .evidence], [.revelation, .closing], [.evidence, .closing]
        ]
        let escalatingTransitions: Set<[RhetoricalCategory]> = [
            [.hook, .tension], [.setup, .tension], [.evidence, .tension], [.revelation, .tension]
        ]
        if resolvingTransitions.contains([previous, current]) { return .resolving }
        if escalatingTransitions.contains([previous, current]) { return .escalating }
        return .neutral
    }

    /// Infer tension direction from the tail of a category arc
    private static func tensionDirectionFromArc(_ arc: [RhetoricalCategory]) -> TensionDirection {
        guard arc.count >= 2 else { return .neutral }
        let previous = arc[arc.count - 2]
        let current = arc[arc.count - 1]
        let resolvingTransitions: Set<[RhetoricalCategory]> = [
            [.tension, .revelation], [.tension, .evidence], [.revelation, .closing], [.evidence, .closing]
        ]
        let escalatingTransitions: Set<[RhetoricalCategory]> = [
            [.hook, .tension], [.setup, .tension], [.evidence, .tension], [.revelation, .tension]
        ]
        if resolvingTransitions.contains([previous, current]) { return .resolving }
        if escalatingTransitions.contains([previous, current]) { return .escalating }
        return .neutral
    }

    // MARK: - Chain Convergence Diagnostic

    /// Generates a convergence diagnostic for the selected diverse chains.
    /// Cross-chain summary shows where chains converge/diverge, then per-chain detail
    /// replays getFilteredCandidates at every position to show what was available,
    /// what was killed, and why — proving whether lack of diversity is a filter issue or data issue.
    static func generateConvergenceDiagnostic(
        chains: [ChainAttempt],
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters,
        treeWalkDiagnostics: TreeWalkDiagnostics? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("═══════════════════════════════════════════════")
        lines.append("  CHAIN CONVERGENCE DIAGNOSTIC")
        lines.append("  \(chains.count) chains, \(chains.first?.positions.count ?? 0) positions")
        lines.append("═══════════════════════════════════════════════")
        lines.append("")

        // ── Cross-chain convergence summary ──
        let maxPos = chains.map(\.positions.count).max() ?? 0
        var convergencePoint: Int? = nil
        var lockedCount = 0

        lines.append("── CROSS-CHAIN CONVERGENCE ──")
        lines.append("")

        // Build reach count lookup from tree walk collector data
        let reachLookup: [Int: PositionLevelStats] = (treeWalkDiagnostics?.positionStats ?? [])
            .reduce(into: [:]) { $0[$1.positionIndex] = $1 }

        for posIdx in 0..<maxPos {
            let movesAtPos = chains.compactMap { chain -> RhetoricalMoveType? in
                guard posIdx < chain.positions.count else { return nil }
                return chain.positions[posIdx].moveType
            }
            let distinct = Dictionary(grouping: movesAtPos, by: { $0 }).sorted { $0.value.count > $1.value.count }
            let isConverged = distinct.count <= 1

            // DFS reach info from collector (shows actual exploration vs. theoretical availability)
            let dfsTag: String
            if let stat = reachLookup[posIdx] {
                dfsTag = "  [DFS: \(stat.timesReached)x, \(String(format: "%.1f", stat.avgFilteredCandidates)) avg cand]"
            } else {
                dfsTag = ""
            }

            if isConverged {
                let move = distinct.first?.key.displayName ?? "?"
                lines.append("  Pos \(String(format: "%2d", posIdx)):  \u{2713} \(move) (\(movesAtPos.count)/\(chains.count))\(dfsTag)")
                lockedCount += 1
            } else {
                if convergencePoint == nil { convergencePoint = posIdx }
                let breakdown = distinct.map { "\($0.key.displayName) (\($0.value.count))" }.joined(separator: ", ")
                lines.append("  Pos \(String(format: "%2d", posIdx)):  \u{2717} \(distinct.count) distinct [\(breakdown)]\(dfsTag)")
            }
        }

        lines.append("")
        if let cp = convergencePoint {
            lines.append("First divergence: position \(cp)")
            lines.append("Locked prefix: \(cp) positions (\(String(format: "%.0f", Double(cp) / Double(max(maxPos, 1)) * 100))% of chain)")
        } else {
            lines.append("ALL positions converged — every chain is identical")
        }
        lines.append("")

        // ── Per-chain detail ──
        for (chainIdx, chain) in chains.enumerated() {
            let divStr = chainIdx == 0 ? "—" : String(format: "%.2f", chain.diversityScore)
            lines.append("══════════════════════════════════════════════")
            lines.append("  CHAIN \(chainIdx + 1): \(chain.positions.first?.moveType.displayName ?? "?") (coverage \(String(format: "%.0f", chain.coverageScore * 100))%, diversity \(divStr))")
            lines.append("══════════════════════════════════════════════")
            lines.append("")

            // Reconstruct history and usedGistIds incrementally
            var history: [RhetoricalMoveType] = []
            var usedGistIds: Set<UUID> = []

            for pos in chain.positions {
                let posIdx = pos.positionIndex

                if posIdx == 0 {
                    // Starter — no filter replay
                    lines.append("Position \(posIdx): \(pos.moveType.displayName) [\(pos.category.rawValue)]  \u{2190} STARTER")
                    if let gid = pos.mappedGistId {
                        lines.append("  Gist: \(gid.uuidString.prefix(8))")
                    }
                    lines.append("")
                    history.append(pos.moveType)
                    if let gid = pos.mappedGistId { usedGistIds.insert(gid) }
                    continue
                }

                // Replay getFilteredCandidates at this position
                let lookup = getFilteredCandidates(
                    history: history,
                    positionIndex: posIdx,
                    matrix: matrix,
                    expansionIndex: expansionIndex,
                    parameters: parameters,
                    usedGistIds: usedGistIds
                )

                let rawCount = lookup.raw.count
                let filteredCount = lookup.filtered.count
                let isLocked = filteredCount == 1
                let isBranching = filteredCount > 1
                let isDead = filteredCount == 0

                let statusTag: String
                if isDead {
                    statusTag = "DEAD END (0 of \(rawCount) raw survived)"
                } else if isLocked {
                    statusTag = "LOCKED (1 of \(rawCount) raw survived)"
                } else {
                    statusTag = "BRANCHING (\(filteredCount) of \(rawCount) raw survived)"
                }

                lines.append("Position \(posIdx): \(pos.moveType.displayName) [\(pos.category.rawValue)]  \u{2190} \(statusTag)")
                lines.append("  Lookup: depth \(lookup.depthUsed), key: \(lookup.lookupKey)")

                // Raw candidates
                let rawStr = lookup.raw.prefix(10).map { "\($0.move.displayName) (\(String(format: "%.0f", $0.probability * 100))%, \($0.count) obs)" }.joined(separator: ", ")
                lines.append("  Raw (\(rawCount)): \(rawStr)")

                // Group alternatives by rejection reason category
                var killedByThreshold: [String] = []
                var killedBySparse: [String] = []
                var killedByCategory: [String] = []
                var killedByFreqCap: [String] = []
                var killedByGistAvail: [String] = []
                var killedByBacktrack: [String] = []

                for alt in lookup.alternatives {
                    let label = "\(alt.moveType.displayName) (\(String(format: "%.0f", alt.probability * 100))%)"
                    let reason = alt.rejectionReason.lowercased()
                    if reason.contains("threshold") {
                        killedByThreshold.append(label)
                    } else if reason.contains("sparse") {
                        killedBySparse.append(label)
                    } else if reason.contains("category") || reason.contains("consecutive") {
                        killedByCategory.append(label)
                    } else if reason.contains("frequency") {
                        killedByFreqCap.append(label)
                    } else if reason.contains("gist") || reason.contains("no available") {
                        killedByGistAvail.append(label)
                    } else if reason.contains("backtrack") || reason.contains("excluded") {
                        killedByBacktrack.append(label)
                    }
                }

                if !killedByThreshold.isEmpty {
                    lines.append("  Killed by threshold: \(killedByThreshold.count) [\(killedByThreshold.joined(separator: ", "))]")
                }
                if !killedBySparse.isEmpty {
                    lines.append("  Killed by sparse data: \(killedBySparse.count) [\(killedBySparse.joined(separator: ", "))]")
                }
                if !killedByCategory.isEmpty {
                    lines.append("  Killed by category: \(killedByCategory.count) [\(killedByCategory.joined(separator: ", "))]")
                }
                if !killedByFreqCap.isEmpty {
                    lines.append("  Killed by freq cap: \(killedByFreqCap.count) [\(killedByFreqCap.joined(separator: ", "))]")
                }
                if !killedByGistAvail.isEmpty {
                    lines.append("  Killed by gist avail: \(killedByGistAvail.count) [\(killedByGistAvail.joined(separator: ", "))]")
                }
                if !killedByBacktrack.isEmpty {
                    lines.append("  Killed by backtrack: \(killedByBacktrack.count) [\(killedByBacktrack.joined(separator: ", "))]")
                }

                // Survivors
                let survivorStr = lookup.filtered.map { "\($0.move.displayName) (\(String(format: "%.0f", $0.probability * 100))%, \($0.count) obs)" }.joined(separator: ", ")
                if !survivorStr.isEmpty {
                    let onlyTag = isLocked ? " \u{2190} ONLY SURVIVOR" : ""
                    lines.append("  Survived (\(filteredCount)): \(survivorStr)\(onlyTag)")
                }

                // WHY analysis
                let totalKilled = lookup.alternatives.count
                if isLocked && totalKilled > 0 {
                    // Determine primary killer
                    let gistKills = killedByGistAvail.count
                    let threshKills = killedByThreshold.count
                    let sparseKills = killedBySparse.count
                    let topKiller: String
                    if gistKills >= threshKills && gistKills >= sparseKills {
                        topKiller = "Gist exhaustion — \(gistKills) of \(totalKilled) candidates had no eligible gists left (all consumed by positions 0-\(posIdx - 1))"
                    } else if threshKills >= sparseKills {
                        topKiller = "Threshold filter — \(threshKills) of \(totalKilled) candidates below \(String(format: "%.0f", parameters.transitionThreshold * 100))% threshold"
                    } else {
                        topKiller = "Sparse data — \(sparseKills) of \(totalKilled) candidates had < \(parameters.minObservationCount) observations"
                    }
                    lines.append("  WHY: \(topKiller)")
                } else if isBranching {
                    lines.append("  WHY: \(filteredCount) candidates survived filtering — alternative paths exist here")
                }

                // Show gist info for this position
                if let gid = pos.mappedGistId {
                    lines.append("  Gist used: \(gid.uuidString.prefix(8)) | Pool remaining: \(gists.count - usedGistIds.count - 1)")
                } else {
                    lines.append("  Gist: NONE (gap) | Pool remaining: \(gists.count - usedGistIds.count)")
                }

                lines.append("")

                // Advance state
                history.append(pos.moveType)
                if let gid = pos.mappedGistId { usedGistIds.insert(gid) }
            }

            // Chain summary
            let lockedPositions = chain.positions.count  // will be counted properly below
            lines.append("")
        }

        // Final summary
        lines.append("═══════════════════════════════════════════════")
        lines.append("  SUMMARY")
        lines.append("═══════════════════════════════════════════════")
        if let cp = convergencePoint {
            lines.append("Chains diverge at position \(cp) of \(maxPos)")
            lines.append("The first \(cp) positions are deterministic — filters leave exactly 1 candidate")
            lines.append("")
            lines.append("To increase diversity, consider:")
            lines.append("  - Lower transition threshold (currently \(String(format: "%.0f", parameters.transitionThreshold * 100))%) to admit more candidates")
            lines.append("  - Lower min observation count (currently \(parameters.minObservationCount)) to keep sparse transitions")
            lines.append("  - Reduce history depth (currently \(parameters.historyDepth)) for broader matrix lookups")
            lines.append("  - Add more rambling gists to expand gist pool")
        } else {
            lines.append("All chains are identical — no diversity achieved")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Filter Impact Proof

    /// Standalone proof: replays Chain 1 with relaxed filters to show exactly
    /// which locked positions would unlock and how many new candidates appear.
    static func generateFilterImpactProof(
        chain: ChainAttempt,
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        parameters: ChainParameters,
        treeWalkDiagnostics: TreeWalkDiagnostics? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("═══════════════════════════════════════════════")
        lines.append("  FILTER IMPACT PROOF")
        lines.append("═══════════════════════════════════════════════")
        lines.append("")
        lines.append("Current:   minObservationCount=\(parameters.minObservationCount), threshold=\(pct(parameters.transitionThreshold))")
        lines.append("What-if A: minObservationCount=1 (keep threshold)")
        lines.append("What-if B: threshold=2% (keep minObs)")
        lines.append("What-if C: both relaxed")
        lines.append("")

        // Build reach count lookup from tree walk collector
        let reachLookup: [Int: PositionLevelStats] = (treeWalkDiagnostics?.positionStats ?? [])
            .reduce(into: [:]) { $0[$1.positionIndex] = $1 }

        var whatIfHistory: [RhetoricalMoveType] = []
        var whatIfUsedGists: Set<UUID> = []

        var totalLocked = 0
        var unlockedByMinObs = 0
        var unlockedByThreshold = 0
        var unlockedByBoth = 0
        var totalNewCandidates = 0
        var hardLocks = 0

        var minObsParams = parameters
        minObsParams.minObservationCount = 1

        var threshParams = parameters
        threshParams.transitionThreshold = 0.02

        var bothParams = parameters
        bothParams.minObservationCount = 1
        bothParams.transitionThreshold = 0.02

        lines.append("── PER-POSITION ANALYSIS ──")
        lines.append("")

        for pos in chain.positions {
            let posIdx = pos.positionIndex

            if posIdx == 0 {
                let dfsTag: String
                if let stat = reachLookup[posIdx] {
                    dfsTag = " [DFS: \(stat.timesReached)x]"
                } else { dfsTag = "" }
                lines.append("Pos  0: \(pos.moveType.displayName) ← STARTER\(dfsTag)")
                whatIfHistory.append(pos.moveType)
                if let gid = pos.mappedGistId { whatIfUsedGists.insert(gid) }
                continue
            }

            let current = getFilteredCandidates(
                history: whatIfHistory, positionIndex: posIdx,
                matrix: matrix, expansionIndex: expansionIndex,
                parameters: parameters, usedGistIds: whatIfUsedGists
            )

            let dfsTag: String
            if let stat = reachLookup[posIdx] {
                dfsTag = " [DFS: \(stat.timesReached)x]"
            } else { dfsTag = "" }

            if current.filtered.count <= 1 {
                totalLocked += 1

                let variantA = getFilteredCandidates(
                    history: whatIfHistory, positionIndex: posIdx,
                    matrix: matrix, expansionIndex: expansionIndex,
                    parameters: minObsParams, usedGistIds: whatIfUsedGists
                )
                let variantB = getFilteredCandidates(
                    history: whatIfHistory, positionIndex: posIdx,
                    matrix: matrix, expansionIndex: expansionIndex,
                    parameters: threshParams, usedGistIds: whatIfUsedGists
                )
                let variantC = getFilteredCandidates(
                    history: whatIfHistory, positionIndex: posIdx,
                    matrix: matrix, expansionIndex: expansionIndex,
                    parameters: bothParams, usedGistIds: whatIfUsedGists
                )

                let countCurrent = current.filtered.count
                let countA = variantA.filtered.count
                let countB = variantB.filtered.count
                let countC = variantC.filtered.count

                if countA > countCurrent { unlockedByMinObs += 1 }
                if countB > countCurrent { unlockedByThreshold += 1 }
                if countC > countCurrent {
                    unlockedByBoth += 1
                    totalNewCandidates += countC - countCurrent
                } else {
                    hardLocks += 1
                }

                let isDead = countCurrent == 0
                let tag = isDead ? "DEAD" : "LOCKED"

                lines.append("Pos \(String(format: "%2d", posIdx)): \(pos.moveType.displayName) ← \(tag) (\(countCurrent))\(dfsTag)")
                lines.append("  Current: \(countCurrent) | A(minObs=1): \(countA) | B(thresh=2%): \(countB) | C(both): \(countC)")

                // Show which specific candidates the relaxed filters would unlock
                let newInC = variantC.filtered.filter { relaxed in
                    !current.filtered.contains { $0.move == relaxed.move }
                }
                if !newInC.isEmpty {
                    let newStr = newInC.map {
                        "\($0.move.displayName) (\(pct($0.probability)), \($0.count) obs)"
                    }.joined(separator: ", ")
                    lines.append("  Unlocked by C: \(newStr)")
                }

                // Show which filter was the primary killer
                let sparseKills = current.alternatives.filter { $0.rejectionReason.contains("Sparse") }.count
                let threshKills = current.alternatives.filter { $0.rejectionReason.contains("threshold") }.count
                let gistKills = current.alternatives.filter { $0.rejectionReason.contains("gist") || $0.rejectionReason.contains("No available") }.count
                let catKills = current.alternatives.filter { $0.rejectionReason.contains("consecutive") || $0.rejectionReason.contains("Consecutive") }.count
                let freqKills = current.alternatives.filter { $0.rejectionReason.contains("frequency") }.count

                var causes: [String] = []
                if sparseKills > 0 { causes.append("sparse: \(sparseKills)") }
                if threshKills > 0 { causes.append("threshold: \(threshKills)") }
                if gistKills > 0 { causes.append("gist: \(gistKills)") }
                if catKills > 0 { causes.append("category: \(catKills)") }
                if freqKills > 0 { causes.append("freq cap: \(freqKills)") }
                if !causes.isEmpty {
                    lines.append("  Killed by: \(causes.joined(separator: ", "))")
                }
                lines.append("")
            } else {
                lines.append("Pos \(String(format: "%2d", posIdx)): \(pos.moveType.displayName) ← OK (\(current.filtered.count) candidates)\(dfsTag)")
            }

            whatIfHistory.append(pos.moveType)
            if let gid = pos.mappedGistId { whatIfUsedGists.insert(gid) }
        }

        // Proof summary
        lines.append("")
        lines.append("═══════════════════════════════════════════════")
        lines.append("  PROOF SUMMARY")
        lines.append("═══════════════════════════════════════════════")
        lines.append("")
        let chainLen = chain.positions.count - 1  // exclude starter
        lines.append("Total positions (excl. starter): \(chainLen)")
        lines.append("Locked/dead positions (0-1 candidate): \(totalLocked)")
        lines.append("")
        lines.append("A) Relax minObservationCount (\(parameters.minObservationCount) → 1):")
        lines.append("   Positions unlocked: \(unlockedByMinObs) of \(totalLocked)")
        lines.append("")
        lines.append("B) Relax transitionThreshold (\(pct(parameters.transitionThreshold)) → 2%):")
        lines.append("   Positions unlocked: \(unlockedByThreshold) of \(totalLocked)")
        lines.append("")
        lines.append("C) Relax BOTH:")
        lines.append("   Positions unlocked: \(unlockedByBoth) of \(totalLocked)")
        lines.append("   New candidates added: +\(totalNewCandidates)")
        lines.append("   Hard locks remaining: \(hardLocks) (genuinely 1 viable transition)")
        lines.append("")

        if totalLocked > 0 {
            let filterPct = unlockedByBoth * 100 / totalLocked
            lines.append("VERDICT: \(filterPct)% of locked positions are caused by filter strictness.")
            if filterPct >= 50 {
                lines.append("The filters ARE the primary bottleneck for chain diversity.")
            } else if filterPct > 0 {
                lines.append("Filters contribute but are not the sole bottleneck.")
            } else {
                lines.append("Filters are NOT the cause — all locks are genuine corpus/gist constraints.")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Generates a convergence diagnostic for a single chain.
    /// Replays getFilteredCandidates at every position to show what was available,
    /// what was killed, and why.
    static func generateSingleChainDiagnostic(
        chain: ChainAttempt,
        chainIndex: Int,
        matrix: MarkovMatrix,
        expansionIndex: FrameExpansionIndex,
        gists: [RamblingGist],
        parameters: ChainParameters
    ) -> String {
        var lines: [String] = []
        let divStr = chainIndex == 0 ? "—" : String(format: "%.2f", chain.diversityScore)
        lines.append("══════════════════════════════════════════════")
        lines.append("  CHAIN \(chainIndex + 1): \(chain.positions.first?.moveType.displayName ?? "?") (coverage \(String(format: "%.0f", chain.coverageScore * 100))%, diversity \(divStr))")
        lines.append("══════════════════════════════════════════════")
        lines.append("")

        var history: [RhetoricalMoveType] = []
        var usedGistIds: Set<UUID> = []

        for pos in chain.positions {
            let posIdx = pos.positionIndex

            if posIdx == 0 {
                lines.append("Position \(posIdx): \(pos.moveType.displayName) [\(pos.category.rawValue)]  \u{2190} STARTER")
                if let gid = pos.mappedGistId {
                    lines.append("  Gist: \(gid.uuidString.prefix(8))")
                }
                lines.append("")
                history.append(pos.moveType)
                if let gid = pos.mappedGistId { usedGistIds.insert(gid) }
                continue
            }

            let lookup = getFilteredCandidates(
                history: history,
                positionIndex: posIdx,
                matrix: matrix,
                expansionIndex: expansionIndex,
                parameters: parameters,
                usedGistIds: usedGistIds
            )

            let rawCount = lookup.raw.count
            let filteredCount = lookup.filtered.count
            let isLocked = filteredCount == 1
            let isBranching = filteredCount > 1
            let isDead = filteredCount == 0

            let statusTag: String
            if isDead {
                statusTag = "DEAD END (0 of \(rawCount) raw survived)"
            } else if isLocked {
                statusTag = "LOCKED (1 of \(rawCount) raw survived)"
            } else {
                statusTag = "BRANCHING (\(filteredCount) of \(rawCount) raw survived)"
            }

            lines.append("Position \(posIdx): \(pos.moveType.displayName) [\(pos.category.rawValue)]  \u{2190} \(statusTag)")
            lines.append("  Lookup: depth \(lookup.depthUsed), key: \(lookup.lookupKey)")

            let rawStr = lookup.raw.prefix(10).map { "\($0.move.displayName) (\(String(format: "%.0f", $0.probability * 100))%, \($0.count) obs)" }.joined(separator: ", ")
            lines.append("  Raw (\(rawCount)): \(rawStr)")

            var killedByThreshold: [String] = []
            var killedBySparse: [String] = []
            var killedByCategory: [String] = []
            var killedByFreqCap: [String] = []
            var killedByGistAvail: [String] = []
            var killedByBacktrack: [String] = []

            for alt in lookup.alternatives {
                let label = "\(alt.moveType.displayName) (\(String(format: "%.0f", alt.probability * 100))%)"
                let reason = alt.rejectionReason.lowercased()
                if reason.contains("threshold") {
                    killedByThreshold.append(label)
                } else if reason.contains("sparse") {
                    killedBySparse.append(label)
                } else if reason.contains("category") || reason.contains("consecutive") {
                    killedByCategory.append(label)
                } else if reason.contains("frequency") {
                    killedByFreqCap.append(label)
                } else if reason.contains("gist") || reason.contains("no available") {
                    killedByGistAvail.append(label)
                } else if reason.contains("backtrack") || reason.contains("excluded") {
                    killedByBacktrack.append(label)
                }
            }

            if !killedByThreshold.isEmpty {
                lines.append("  Killed by threshold: \(killedByThreshold.count) [\(killedByThreshold.joined(separator: ", "))]")
            }
            if !killedBySparse.isEmpty {
                lines.append("  Killed by sparse data: \(killedBySparse.count) [\(killedBySparse.joined(separator: ", "))]")
            }
            if !killedByCategory.isEmpty {
                lines.append("  Killed by category: \(killedByCategory.count) [\(killedByCategory.joined(separator: ", "))]")
            }
            if !killedByFreqCap.isEmpty {
                lines.append("  Killed by freq cap: \(killedByFreqCap.count) [\(killedByFreqCap.joined(separator: ", "))]")
            }
            if !killedByGistAvail.isEmpty {
                lines.append("  Killed by gist avail: \(killedByGistAvail.count) [\(killedByGistAvail.joined(separator: ", "))]")
            }
            if !killedByBacktrack.isEmpty {
                lines.append("  Killed by backtrack: \(killedByBacktrack.count) [\(killedByBacktrack.joined(separator: ", "))]")
            }

            let survivorStr = lookup.filtered.map { "\($0.move.displayName) (\(String(format: "%.0f", $0.probability * 100))%, \($0.count) obs)" }.joined(separator: ", ")
            if !survivorStr.isEmpty {
                let onlyTag = isLocked ? " \u{2190} ONLY SURVIVOR" : ""
                lines.append("  Survived (\(filteredCount)): \(survivorStr)\(onlyTag)")
            }

            let totalKilled = lookup.alternatives.count
            if isLocked && totalKilled > 0 {
                let gistKills = killedByGistAvail.count
                let threshKills = killedByThreshold.count
                let sparseKills = killedBySparse.count
                let topKiller: String
                if gistKills >= threshKills && gistKills >= sparseKills {
                    topKiller = "Gist exhaustion — \(gistKills) of \(totalKilled) candidates had no eligible gists left (all consumed by positions 0-\(posIdx - 1))"
                } else if threshKills >= sparseKills {
                    topKiller = "Threshold filter — \(threshKills) of \(totalKilled) candidates below \(String(format: "%.0f", parameters.transitionThreshold * 100))% threshold"
                } else {
                    topKiller = "Sparse data — \(sparseKills) of \(totalKilled) candidates had < \(parameters.minObservationCount) observations"
                }
                lines.append("  WHY: \(topKiller)")
            } else if isBranching {
                lines.append("  WHY: \(filteredCount) candidates survived filtering — alternative paths exist here")
            }

            if let gid = pos.mappedGistId {
                lines.append("  Gist used: \(gid.uuidString.prefix(8)) | Pool remaining: \(gists.count - usedGistIds.count - 1)")
            } else {
                lines.append("  Gist: NONE (gap) | Pool remaining: \(gists.count - usedGistIds.count)")
            }

            lines.append("")

            history.append(pos.moveType)
            if let gid = pos.mappedGistId { usedGistIds.insert(gid) }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Dead End Integrity Report

    /// Traces the full pipeline for specific dead ends: matrix → depth fallback → each filter → dead end.
    /// For each traced dead end, re-runs getFilteredCandidates at the dead-end position AND the position
    /// before it, showing exactly what the matrix returned, what each filter killed, and why nothing survived.
    /// Also traces the gist supply — how many gists exist for each candidate move vs how many are already used.
    static func generateDeadEndIntegrityReport(
        deadEnds: [DeadEnd],
        gists: [RamblingGist],
        expansionIndex: FrameExpansionIndex,
        matrix: MarkovMatrix,
        parameters: ChainParameters,
        effectiveMaxLength: Int
    ) -> String {
        var lines: [String] = []
        lines.append("═══════════════════════════════════════════════")
        lines.append("  DEAD END PIPELINE TRACE")
        lines.append("═══════════════════════════════════════════════")
        lines.append("")

        // ─── Section 1: Gist Supply Overview ───

        lines.append("── SECTION 1: Gist Supply vs Demand ──")
        lines.append("")
        lines.append("Total gists: \(gists.count)")
        lines.append("")

        // Show how many gists can serve each move type
        let allMoveTypes = RhetoricalMoveType.allCases
        var moveSupply: [(move: RhetoricalMoveType, total: Int)] = []
        for move in allMoveTypes {
            let eligible = expansionIndex.eligibleGists(for: move, excluding: [])
            if eligible.count > 0 {
                moveSupply.append((move, eligible.count))
            }
        }
        moveSupply.sort { $0.total > $1.total }

        lines.append("Gist supply per move type (total eligible, no exclusions):")
        for entry in moveSupply {
            lines.append("  \(entry.move.displayName): \(entry.total) gists")
        }

        // Show moves with ZERO supply
        let zeroSupply = allMoveTypes.filter { expansionIndex.eligibleGists(for: $0, excluding: []).isEmpty }
        if !zeroSupply.isEmpty {
            lines.append("")
            lines.append("⚠️ Moves with ZERO gists (can never be placed):")
            for move in zeroSupply {
                lines.append("  \(move.displayName)")
            }
        }
        lines.append("")

        // ─── Section 2: Pick dead ends to trace ───
        // Select 3 diverse dead ends: earliest position, median position, latest position

        let sorted = deadEnds.sorted { $0.positionIndex < $1.positionIndex }
        var traceCandidates: [(label: String, de: DeadEnd)] = []
        if let earliest = sorted.first {
            traceCandidates.append(("EARLIEST (position \(earliest.positionIndex))", earliest))
        }
        if sorted.count >= 3 {
            let median = sorted[sorted.count / 2]
            traceCandidates.append(("MEDIAN (position \(median.positionIndex))", median))
        }
        if let latest = sorted.last, sorted.count >= 2 {
            traceCandidates.append(("LATEST (position \(latest.positionIndex))", latest))
        }

        lines.append("── SECTION 2: Pipeline Traces (\(traceCandidates.count) dead ends) ──")
        lines.append("")

        for (traceIdx, trace) in traceCandidates.enumerated() {
            let de = trace.de
            let pathMoves = de.pathSoFar.compactMap { RhetoricalMoveType.parse($0) }

            lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            lines.append("TRACE \(traceIdx + 1): \(trace.label)")
            lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            lines.append("  Dead end position: \(de.positionIndex)")
            lines.append("  Path length: \(de.pathSoFar.count)")
            lines.append("  Dead end type: \(de.deadEndType.rawValue)")
            lines.append("  Stored lookupDepthUsed: \(de.lookupDepthUsed)")
            lines.append("  Stored lookupKey: \(de.lookupKey)")
            lines.append("  Stored candidatesFound: \(de.candidatesFound)")
            lines.append("  Stored rawCandidateMoveTypes: \(de.rawCandidateMoveTypes.map(\.displayName).joined(separator: ", "))")
            lines.append("")

            // Show the path with gist assignments
            lines.append("  Path (move → gist):")
            var replayUsedGists: Set<UUID> = []
            for (idx, move) in pathMoves.enumerated() {
                let gistId = idx < de.pathGistIds.count ? de.pathGistIds[idx] : nil
                let gistStr = gistId.map { String($0.uuidString.prefix(8)) } ?? "nil"
                if let gid = gistId { replayUsedGists.insert(gid) }
                lines.append("    [\(idx)] \(move.displayName) → gist \(gistStr)")
            }
            lines.append("  Used gists at dead end: \(replayUsedGists.count)/\(gists.count)")
            lines.append("")

            // ─── Re-run the EXACT pipeline at the dead end position ───
            lines.append("  ── Pipeline replay at position \(de.positionIndex) ──")
            lines.append("")

            // Step 1: What does the matrix return at each depth?
            let maxDepth = min(pathMoves.count, parameters.historyDepth)
            lines.append("  STEP 1: Matrix lookup (depth \(maxDepth) down to 1)")

            let recentCategories = pathMoves.suffix(parameters.maxConsecutiveSameCategory).map(\.category)

            for depth in stride(from: maxDepth, through: 1, by: -1) {
                let depthParams = ChainParameters(
                    transitionThreshold: parameters.transitionThreshold,
                    historyDepth: depth,
                    minObservationCount: parameters.minObservationCount,
                    useParentLevel: parameters.useParentLevel
                )
                let result = matrix.contextAwareNextMoves(
                    after: pathMoves.last!,
                    history: pathMoves,
                    parameters: depthParams,
                    topK: 25
                )

                if result.moves.isEmpty {
                    lines.append("    Depth \(depth): EMPTY (key: \(result.lookupKey))")
                    continue
                }

                lines.append("    Depth \(depth): \(result.moves.count) raw candidates (key: \(result.lookupKey))")

                // Step 2: Apply each filter to each candidate at this depth
                for candidate in result.moves {
                    var rejection: String? = nil

                    // Filter 1: Probability threshold
                    if candidate.probability < parameters.transitionThreshold {
                        rejection = "KILLED by threshold: \(String(format: "%.3f", candidate.probability)) < \(String(format: "%.3f", parameters.transitionThreshold))"
                    }

                    // Filter 2: Observation count
                    if rejection == nil && candidate.count < parameters.minObservationCount {
                        rejection = "KILLED by min observations: \(candidate.count) < \(parameters.minObservationCount)"
                    }

                    // Filter 3: Category consecutiveness
                    if rejection == nil {
                        if !parameters.allowConsecutiveSameCategory {
                            if let lastCat = recentCategories.last, lastCat == candidate.move.category {
                                rejection = "KILLED by consecutive category: \(candidate.move.category.rawValue) repeats"
                            }
                        } else if parameters.maxConsecutiveSameCategory > 0 {
                            let consecutiveCount = recentCategories.reversed()
                                .prefix(while: { $0 == candidate.move.category }).count
                            if consecutiveCount >= parameters.maxConsecutiveSameCategory {
                                rejection = "KILLED by max consecutive category: \(consecutiveCount) >= \(parameters.maxConsecutiveSameCategory)"
                            }
                        }
                    }

                    // Filter 4: Move-type frequency cap
                    if rejection == nil && parameters.maxMoveTypeShare < 1.0 && pathMoves.count >= 8 {
                        let moveCount = pathMoves.filter { $0 == candidate.move }.count
                        let currentShare = Double(moveCount) / Double(pathMoves.count)
                        if currentShare >= parameters.maxMoveTypeShare {
                            rejection = "KILLED by frequency cap: \(candidate.move.displayName) at \(Int(currentShare * 100))% >= \(Int(parameters.maxMoveTypeShare * 100))% max"
                        }
                    }

                    // Filter 5: Gist availability
                    if rejection == nil {
                        let totalForMove = expansionIndex.eligibleGists(for: candidate.move, excluding: []).count
                        let availableForMove = expansionIndex.eligibleGists(for: candidate.move, excluding: replayUsedGists).count

                        if availableForMove == 0 {
                            rejection = "KILLED by gist availability: 0 remaining (\(totalForMove) total, \(totalForMove) used)"
                        }
                    }

                    if let rejection = rejection {
                        lines.append("      \(candidate.move.displayName) p=\(String(format: "%.3f", candidate.probability)) obs=\(candidate.count) → \(rejection)")
                    } else {
                        let avail = expansionIndex.eligibleGists(for: candidate.move, excluding: replayUsedGists).count
                        let total = expansionIndex.eligibleGists(for: candidate.move, excluding: []).count
                        lines.append("      \(candidate.move.displayName) p=\(String(format: "%.3f", candidate.probability)) obs=\(candidate.count) → ✓ PASSES (\(avail)/\(total) gists available)")
                    }
                }

                // Check: did any survive at this depth?
                let survivorCount = result.moves.filter { candidate in
                    if candidate.probability < parameters.transitionThreshold { return false }
                    if candidate.count < parameters.minObservationCount { return false }
                    if !parameters.allowConsecutiveSameCategory {
                        if let lastCat = recentCategories.last, lastCat == candidate.move.category { return false }
                    } else if parameters.maxConsecutiveSameCategory > 0 {
                        let consecutiveCount = recentCategories.reversed()
                            .prefix(while: { $0 == candidate.move.category }).count
                        if consecutiveCount >= parameters.maxConsecutiveSameCategory { return false }
                    }
                    if parameters.maxMoveTypeShare < 1.0 && pathMoves.count >= 8 {
                        let moveCount = pathMoves.filter { $0 == candidate.move }.count
                        if Double(moveCount) / Double(pathMoves.count) >= parameters.maxMoveTypeShare { return false }
                    }
                    if !expansionIndex.hasEligibleGists(for: candidate.move, excluding: replayUsedGists) { return false }
                    return true
                }.count

                if survivorCount > 0 {
                    lines.append("    → \(survivorCount) survivors at depth \(depth) — chain builder would pick from these (but this is a dead end, so something is wrong)")
                    lines.append("    ⚠️ DISCREPANCY: Pipeline replay found survivors but stored dead end says 0 filtered")
                } else {
                    lines.append("    → 0 survivors at depth \(depth) — falling through to depth \(depth - 1)")
                }
                lines.append("")
            }

            // Step 3: Cross-check with getFilteredCandidates
            lines.append("  STEP 3: Cross-check via getFilteredCandidates()")
            let crossCheck = getFilteredCandidates(
                history: pathMoves,
                positionIndex: de.positionIndex,
                matrix: matrix,
                expansionIndex: expansionIndex,
                parameters: parameters,
                usedGistIds: replayUsedGists
            )
            lines.append("    Raw: \(crossCheck.raw.count), Filtered: \(crossCheck.filtered.count), Depth used: \(crossCheck.depthUsed)")
            if !crossCheck.filtered.isEmpty {
                lines.append("    ⚠️ CRITICAL: getFilteredCandidates FOUND survivors!")
                for c in crossCheck.filtered {
                    lines.append("      \(c.move.displayName) p=\(String(format: "%.3f", c.probability))")
                }
                lines.append("    This means the dead end should NOT exist — the chain builder had valid options.")
            }
            for alt in crossCheck.alternatives {
                lines.append("    Rejected: \(alt.moveType.displayName) — \(alt.rejectionReason)")
            }
            lines.append("")

            // Step 4: Gist exhaustion analysis at this position
            lines.append("  STEP 4: Gist exhaustion at position \(de.positionIndex)")
            let rawMoves = de.rawCandidateMoveTypes
            for move in rawMoves {
                let totalForMove = expansionIndex.eligibleGists(for: move, excluding: []).count
                let availableNow = expansionIndex.eligibleGists(for: move, excluding: replayUsedGists).count
                let usedForMove = totalForMove - availableNow
                lines.append("    \(move.displayName): \(availableNow) available / \(totalForMove) total (\(usedForMove) consumed by path)")
            }
            lines.append("")

            // Step 5: What killed this dead end — the verdict
            lines.append("  VERDICT:")
            let allKilledByGist = rawMoves.allSatisfy { !expansionIndex.hasEligibleGists(for: $0, excluding: replayUsedGists) }
            let allBelowThreshold = crossCheck.raw.allSatisfy { $0.probability < parameters.transitionThreshold }
            let allSparse = crossCheck.raw.allSatisfy { $0.count < parameters.minObservationCount }

            if crossCheck.raw.isEmpty {
                lines.append("    Matrix returned 0 candidates at all depths → no transitions exist from this history.")
            } else if allKilledByGist {
                lines.append("    All \(crossCheck.raw.count) candidates killed by gist exhaustion.")
                lines.append("    WHY: Every move the matrix says is valid has had all its gists consumed earlier in the path.")
            } else if allBelowThreshold {
                lines.append("    All \(crossCheck.raw.count) candidates killed by probability threshold.")
            } else if allSparse {
                lines.append("    All \(crossCheck.raw.count) candidates killed by min observation count.")
            } else {
                // Mixed reasons — break down
                var byGist = 0, byThreshold = 0, bySparse = 0, byCategory = 0
                for alt in crossCheck.alternatives {
                    if alt.rejectionReason.contains("gist") { byGist += 1 }
                    else if alt.rejectionReason.contains("threshold") || alt.rejectionReason.contains("Below") { byThreshold += 1 }
                    else if alt.rejectionReason.contains("Sparse") { bySparse += 1 }
                    else if alt.rejectionReason.contains("onsecutive") { byCategory += 1 }
                }
                lines.append("    Mixed kill: gist=\(byGist), threshold=\(byThreshold), sparse=\(bySparse), category=\(byCategory)")
            }
            lines.append("")
        }

        // ─── Section 3: Aggregate filter attribution ───

        lines.append("── SECTION 3: Aggregate Kill Attribution ──")
        lines.append("")
        lines.append("Re-running getFilteredCandidates for ALL \(deadEnds.count) dead ends...")
        lines.append("")

        var totalByGist = 0
        var totalByThreshold = 0
        var totalBySparse = 0
        var totalByCategory = 0
        var totalByFreqCap = 0
        var totalByBacktrack = 0
        var discrepancyCount = 0

        // Sample: check first 500 to keep report generation fast
        let sampleSize = min(deadEnds.count, 500)
        let sampleDeadEnds = Array(deadEnds.prefix(sampleSize))

        for de in sampleDeadEnds {
            let pathMoves = de.pathSoFar.compactMap { RhetoricalMoveType.parse($0) }
            var usedGists: Set<UUID> = []
            for (idx, _) in pathMoves.enumerated() {
                if idx < de.pathGistIds.count, let gid = de.pathGistIds[idx] {
                    usedGists.insert(gid)
                }
            }

            let lookup = getFilteredCandidates(
                history: pathMoves,
                positionIndex: de.positionIndex,
                matrix: matrix,
                expansionIndex: expansionIndex,
                parameters: parameters,
                usedGistIds: usedGists
            )

            if !lookup.filtered.isEmpty { discrepancyCount += 1 }

            for alt in lookup.alternatives {
                if alt.rejectionReason.contains("frequency cap") { totalByFreqCap += 1 }
                else if alt.rejectionReason.contains("gist") { totalByGist += 1 }
                else if alt.rejectionReason.contains("threshold") || alt.rejectionReason.contains("Below") { totalByThreshold += 1 }
                else if alt.rejectionReason.contains("Sparse") { totalBySparse += 1 }
                else if alt.rejectionReason.contains("onsecutive") { totalByCategory += 1 }
                else if alt.rejectionReason.contains("backtrack") || alt.rejectionReason.contains("Excluded") { totalByBacktrack += 1 }
            }
        }

        let totalKills = totalByGist + totalByThreshold + totalBySparse + totalByCategory + totalByFreqCap + totalByBacktrack
        lines.append("Sample: \(sampleSize)/\(deadEnds.count) dead ends")
        lines.append("Total candidate rejections: \(totalKills)")
        if totalKills > 0 {
            lines.append("  Gist exhaustion:  \(totalByGist) (\(String(format: "%.1f", Double(totalByGist) / Double(totalKills) * 100))%)")
            lines.append("  Below threshold:  \(totalByThreshold) (\(String(format: "%.1f", Double(totalByThreshold) / Double(totalKills) * 100))%)")
            lines.append("  Sparse data:      \(totalBySparse) (\(String(format: "%.1f", Double(totalBySparse) / Double(totalKills) * 100))%)")
            lines.append("  Category limit:   \(totalByCategory) (\(String(format: "%.1f", Double(totalByCategory) / Double(totalKills) * 100))%)")
            lines.append("  Frequency cap:    \(totalByFreqCap) (\(String(format: "%.1f", Double(totalByFreqCap) / Double(totalKills) * 100))%)")
            lines.append("  Backtrack excl:   \(totalByBacktrack) (\(String(format: "%.1f", Double(totalByBacktrack) / Double(totalKills) * 100))%)")
        }
        lines.append("")

        if discrepancyCount > 0 {
            lines.append("⚠️ CRITICAL: \(discrepancyCount)/\(sampleSize) dead ends have survivors when re-checked!")
            lines.append("   These dead ends should NOT be dead ends — the pipeline would have found valid moves.")
            lines.append("   This proves data corruption or a state mismatch during the tree walk.")
        } else {
            lines.append("✓ All \(sampleSize) dead ends confirmed: 0 survivors on replay. Pipeline is consistent.")
        }
        lines.append("")

        lines.append("═══════════════════════════════════════════════")
        lines.append("  END OF PIPELINE TRACE")
        lines.append("═══════════════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting

    private static func pct(_ value: Double) -> String { "\(Int(value * 100))%" }
    private static func fmt2(_ value: Double) -> String { String(format: "%.2f", value) }
}
