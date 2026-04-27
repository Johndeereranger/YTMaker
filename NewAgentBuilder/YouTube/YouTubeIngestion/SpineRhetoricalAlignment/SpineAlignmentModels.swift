//
//  SpineAlignmentModels.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/2/26.
//

import Foundation

// MARK: - Per-Video Alignment Result (Firebase Document)

struct SpineRhetoricalAlignment: Codable, Identifiable, Hashable {
    var id: String { "\(videoId)_run\(runNumber)" }

    let videoId: String
    let channelId: String
    let runNumber: Int                       // 1, 2, or 3 (for multi-run fidelity)
    let extractedAt: Date
    let beatCount: Int                       // total spine beats in this video
    let moveCount: Int                       // total rhetorical moves in this video
    let beatAlignments: [BeatMoveAlignment]
    let unmappedMoves: [UnmappedMove]        // orphan rhetorical moves (expected — pacing, viewer-address, etc.)
    let orphanBeats: [Int]                   // beat numbers with zero moves (diagnostic flag)
    var renderedText: String                 // deterministic text reconstruction

    func hash(into hasher: inout Hasher) {
        hasher.combine(videoId)
        hasher.combine(runNumber)
    }
    static func == (lhs: SpineRhetoricalAlignment, rhs: SpineRhetoricalAlignment) -> Bool {
        lhs.videoId == rhs.videoId && lhs.runNumber == rhs.runNumber && lhs.extractedAt == rhs.extractedAt
    }

    // MARK: - Render Text

    static func renderText(
        beatAlignments: [BeatMoveAlignment],
        unmappedMoves: [UnmappedMove],
        orphanBeats: [Int]
    ) -> String {
        var lines: [String] = []

        lines.append("SPINE-RHETORICAL ALIGNMENT")
        lines.append("")

        for ba in beatAlignments {
            lines.append("Beat \(ba.beatNumber) [\(ba.function)] — \(ba.contentTag)")
            if ba.mappedMoves.isEmpty {
                lines.append("  (no rhetorical moves mapped — ORPHAN)")
            } else {
                for mm in ba.mappedMoves {
                    lines.append("  → \(mm.moveType) (chunk \(mm.chunkIndex), \(mm.overlapStrength))")
                }
            }
            lines.append("  Rationale: \(ba.rationale)")
            lines.append("")
        }

        if !unmappedMoves.isEmpty {
            lines.append("---")
            lines.append("UNMAPPED RHETORICAL MOVES (\(unmappedMoves.count))")
            for um in unmappedMoves {
                lines.append("  chunk \(um.chunkIndex): \(um.moveType) — \(um.reason)")
            }
            lines.append("")
        }

        if !orphanBeats.isEmpty {
            lines.append("---")
            lines.append("ORPHAN SPINE BEATS: \(orphanBeats.map(String.init).joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Beat-to-Move Alignment

struct BeatMoveAlignment: Codable, Hashable {
    let beatNumber: Int
    let function: String                     // spine function label
    let contentTag: String                   // from spine beat, for reference
    let mappedMoves: [MappedMove]            // 1-5 rhetorical moves that overlap
    let rationale: String                    // LLM's reasoning for this alignment
}

// MARK: - Mapped Move

struct MappedMove: Codable, Hashable {
    let moveType: String                     // RhetoricalMoveType rawValue
    let chunkIndex: Int                      // position in rhetorical sequence
    let overlapStrength: String              // "full" | "partial" | "tangential"
    // full = move falls entirely within this beat's scope
    // partial = move straddles this beat and an adjacent beat
    // tangential = move touches same content from different angle

    /// Weight for aggregation: full=1.0, partial=0.5, tangential=0.25
    var weight: Double {
        switch overlapStrength {
        case "full": return 1.0
        case "partial": return 0.5
        case "tangential": return 0.25
        default: return 0.5
        }
    }
}

// MARK: - Unmapped Move (orphan rhetorical moves — expected)

struct UnmappedMove: Codable, Hashable {
    let chunkIndex: Int
    let moveType: String
    let reason: String                       // why it doesn't map (e.g., "viewer-address, pacing-only")
}

// MARK: - Aggregated Mapping Table (Firebase Document per Channel)

struct SpineRhetoricalMappingTable: Codable, Identifiable {
    var id: String { channelId }

    let channelId: String
    let computedAt: Date
    let videoCount: Int                      // how many videos contributed
    let functionMappings: [FunctionMoveMapping]    // one per function label that appeared
    let unmappedMoveStats: [UnmappedMoveStat]      // how often each move type goes unmapped
    var renderedText: String
}

// MARK: - Function → Move Distribution

struct FunctionMoveMapping: Codable, Hashable {
    let function: String                     // spine function label
    let totalOccurrences: Int                // how many beats had this function across all videos
    let avgMovesPerBeat: Double              // average rhetorical moves per beat with this function
    let moveDistribution: [MoveFrequency]    // sorted descending by weighted score
}

// MARK: - Move Frequency (dual raw + weighted)

struct MoveFrequency: Codable, Hashable {
    let moveType: String
    // Raw counts (unweighted — every mapping counts as 1 regardless of overlap)
    let rawCount: Int
    let rawPercentage: Double                // 0-100, based on rawCount
    // Weighted counts (full=1.0, partial=0.5, tangential=0.25)
    let weightedScore: Double
    let weightedPercentage: Double           // 0-100, based on weightedScore
    // Overlap breakdown
    let fullCount: Int
    let partialCount: Int
    let tangentialCount: Int
}

// MARK: - Unmapped Move Stats (for the mapping table)

struct UnmappedMoveStat: Codable, Hashable {
    let moveType: String
    let unmappedCount: Int
    let totalCount: Int                      // total times this move appeared across all videos
    let unmappedPercentage: Double           // how often this move goes orphaned
}

// MARK: - Status Flag (on video doc, same pattern as NarrativeSpineStatus)

struct SpineAlignmentStatus: Codable, Hashable {
    var complete: Bool = false                // legacy — use completedRunCount instead
    var completedRunCount: Int = 0           // 0, 1, 2, or 3
    var beatCount: Int = 0
    var orphanBeatCount: Int = 0             // diagnostic: how many beats had no moves
    var unmappedMoveCount: Int = 0           // how many moves had no beats
    var lastUpdated: Date?
}

// MARK: - Fidelity Support Types

struct SpineAlignmentFidelityRun: Identifiable {
    let id = UUID()
    let runNumber: Int
    let alignment: SpineRhetoricalAlignment
}

struct SpineAlignmentFidelityMetrics {
    let mappingConsistencyRate: Double        // across runs, how often same beat maps to same moves
    let avgMovesPerBeat: (min: Double, max: Double, mean: Double)
    let orphanBeatAgreement: Double          // do all runs agree on which beats are orphaned?
    let unmappedMoveAgreement: Double        // do all runs agree on which moves are unmapped?
    let perFunctionAgreement: [FunctionAgreementDetail]
    let confusableMappings: [(function: String, moveA: String, moveB: String, includedRuns: Int)]

    // MARK: - Compute Metrics

    static func compute(from runs: [SpineAlignmentFidelityRun]) -> SpineAlignmentFidelityMetrics {
        guard runs.count >= 2 else {
            return SpineAlignmentFidelityMetrics(
                mappingConsistencyRate: runs.isEmpty ? 0 : 1,
                avgMovesPerBeat: (0, 0, 0),
                orphanBeatAgreement: 1,
                unmappedMoveAgreement: 1,
                perFunctionAgreement: [],
                confusableMappings: []
            )
        }

        let minBeats = runs.map { $0.alignment.beatAlignments.count }.min() ?? 0

        // Avg moves per beat across runs
        let avgCounts = runs.map { run -> Double in
            let total = run.alignment.beatAlignments.reduce(0) { $0 + $1.mappedMoves.count }
            return run.alignment.beatAlignments.isEmpty ? 0 : Double(total) / Double(run.alignment.beatAlignments.count)
        }
        let avgMin = avgCounts.min() ?? 0
        let avgMax = avgCounts.max() ?? 0
        let avgMean = avgCounts.reduce(0, +) / Double(avgCounts.count)

        // Mapping consistency: for each beat position, do all runs agree on the set of mapped move types?
        var consistentCount = 0
        var totalPositions = 0

        // Per-function tracking
        var functionMovesets: [String: [[String]]] = [:]  // function → [run's moveTypes for that function]

        for pos in 0..<minBeats {
            totalPositions += 1
            let moveSets = runs.map { run -> Set<String> in
                guard pos < run.alignment.beatAlignments.count else { return [] }
                return Set(run.alignment.beatAlignments[pos].mappedMoves.map { $0.moveType })
            }

            let reference = moveSets[0]
            let allAgree = moveSets.allSatisfy { $0 == reference }
            if allAgree { consistentCount += 1 }

            // Track per-function
            if let function = runs.first.map({ $0.alignment.beatAlignments[pos].function }) {
                for run in runs {
                    guard pos < run.alignment.beatAlignments.count else { continue }
                    let ba = run.alignment.beatAlignments[pos]
                    functionMovesets[ba.function, default: []].append(ba.mappedMoves.map { $0.moveType })
                }
            }

            // (confusable pairs derived from perFunctionAgreement below)
        }

        let consistencyRate = totalPositions > 0 ? Double(consistentCount) / Double(totalPositions) : 1

        // Orphan beat agreement
        let orphanSets = runs.map { Set($0.alignment.orphanBeats) }
        let orphanReference = orphanSets[0]
        let orphanAgree = orphanSets.allSatisfy { $0 == orphanReference }
        let orphanAgreement: Double = orphanAgree ? 1 : 0

        // Unmapped move agreement
        let unmappedSets = runs.map { Set($0.alignment.unmappedMoves.map { $0.chunkIndex }) }
        let unmappedReference = unmappedSets[0]
        let unmappedAgree = unmappedSets.allSatisfy { $0 == unmappedReference }
        let unmappedAgreement: Double = unmappedAgree ? 1 : 0

        // Per-function agreement details
        var functionDetails: [FunctionAgreementDetail] = []
        for (function, runMoveSets) in functionMovesets {
            guard runMoveSets.count >= 2 else { continue }
            let sets = runMoveSets.map { Set($0) }
            let intersection = sets.reduce(sets[0]) { $0.intersection($1) }
            let union = sets.reduce(Set<String>()) { $0.union($1) }
            let agreementRate = union.isEmpty ? 1 : Double(intersection.count) / Double(union.count)

            functionDetails.append(FunctionAgreementDetail(
                function: function,
                agreementRate: agreementRate,
                stableMoves: intersection.sorted(),
                unstableMoves: union.subtracting(intersection).sorted()
            ))
        }
        functionDetails.sort { $0.function < $1.function }

        // Build confusable mappings — any function with < 100% agreement has confusable entries.
        // Each unstable move (present in some runs, absent in others) is a confusable entry.
        var confusable: [(function: String, moveA: String, moveB: String, includedRuns: Int)] = []
        for detail in functionDetails where detail.agreementRate < 1.0 {
            let runMoveSets = functionMovesets[detail.function] ?? []
            let totalRuns = runMoveSets.count

            for unstableMove in detail.unstableMoves {
                let includedCount = runMoveSets.filter { $0.contains(unstableMove) }.count

                if let primaryStable = detail.stableMoves.first {
                    // Pair unstable move against top stable move for context
                    confusable.append((detail.function, primaryStable, unstableMove, includedCount))
                }
            }

            // If ALL moves are unstable (no stable baseline), pair them against each other
            if detail.stableMoves.isEmpty && detail.unstableMoves.count >= 2 {
                for i in 0..<detail.unstableMoves.count {
                    for j in (i+1)..<detail.unstableMoves.count {
                        confusable.append((detail.function, detail.unstableMoves[i], detail.unstableMoves[j], 1))
                    }
                }
            }
        }
        confusable.sort { $0.includedRuns > $1.includedRuns }

        return SpineAlignmentFidelityMetrics(
            mappingConsistencyRate: consistencyRate,
            avgMovesPerBeat: (avgMin, avgMax, avgMean),
            orphanBeatAgreement: orphanAgreement,
            unmappedMoveAgreement: unmappedAgreement,
            perFunctionAgreement: functionDetails,
            confusableMappings: confusable
        )
    }
}

struct FunctionAgreementDetail: Identifiable {
    var id: String { function }
    let function: String
    let agreementRate: Double                // across runs, do the mapped moves agree?
    let stableMoves: [String]                // moves that appeared in ALL runs for this function
    let unstableMoves: [String]              // moves that appeared in SOME runs
}

// MARK: - Stored Fidelity Test (UserDefaults)

struct StoredAlignmentFidelityTest: Codable {
    let date: Date
    let runCount: Int
    let temperature: Double
    let mappingConsistencyRate: Double
    let avgMoveCountMean: Double
    let orphanBeatCount: Int
}

// MARK: - Confusable Pair (accumulated across videos, following ConfusablePairService pattern)

struct SpineAlignmentConfusablePair: Codable, Identifiable, Hashable {
    let id: String              // deterministic: "{function}_{moveA}_{moveB}" (alphabetically sorted)
    let function: String        // spine function label (e.g., "escalation")
    let moveA: String           // alphabetically first move type
    let moveB: String           // alphabetically second move type
    let creatorId: String       // channelId
    var swapCount: Int          // times this swap was observed across all videos
    var sampleSize: Int         // total observations of this function across all videos
    var confidence: Double      // swapCount / sampleSize
    var sourceVideoIds: [String]
    let createdAt: Date
    var updatedAt: Date

    static func create(
        function: String, move1: String, move2: String,
        creatorId: String, videoId: String, sampleSize: Int
    ) -> SpineAlignmentConfusablePair {
        let sorted = [move1, move2].sorted()
        let id = "\(function)_\(sorted[0])_\(sorted[1])"
        return SpineAlignmentConfusablePair(
            id: id, function: function,
            moveA: sorted[0], moveB: sorted[1],
            creatorId: creatorId,
            swapCount: 1, sampleSize: sampleSize,
            confidence: 1.0 / Double(sampleSize),
            sourceVideoIds: [videoId],
            createdAt: Date(), updatedAt: Date()
        )
    }

    /// Merge additional evidence into this pair (local, before Firebase upsert)
    func merging(additionalSwaps: Int, additionalSamples: Int, videoId: String) -> SpineAlignmentConfusablePair {
        var updated = self
        updated.swapCount += additionalSwaps
        updated.sampleSize += additionalSamples
        updated.confidence = updated.sampleSize > 0 ? Double(updated.swapCount) / Double(updated.sampleSize) : 0
        if !updated.sourceVideoIds.contains(videoId) {
            updated.sourceVideoIds.append(videoId)
        }
        updated.updatedAt = Date()
        return updated
    }
}

// MARK: - Error Types

enum SpineAlignmentError: LocalizedError {
    case missingSpine
    case missingRhetoricalSequence
    case parseFailed(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingSpine: return "Video has no narrative spine"
        case .missingRhetoricalSequence: return "Video has no rhetorical sequence"
        case .parseFailed(let detail): return "Parse failed: \(detail)"
        case .apiError(let detail): return "API error: \(detail)"
        }
    }
}
