//
//  SpineAlignmentService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/2/26.
//

import Foundation

@MainActor
class SpineAlignmentService: ObservableObject {
    static let shared = SpineAlignmentService()

    private let firebase = SpineAlignmentFirebaseService.shared
    private let spineFirebase = NarrativeSpineFirebaseService.shared

    @Published var isRunning = false
    @Published var progress = ""
    @Published var completedVideos = 0
    @Published var totalVideos = 0
    @Published var perVideoProgress: [String: String] = [:]

    private init() {}

    // MARK: - Parallel-Safe Alignment (no MainActor involvement)

    nonisolated static func alignParallel(
        for video: YouTubeVideo,
        spine: NarrativeSpine,
        runNumber: Int = 1,
        temperature: Double
    ) async throws -> SpineRhetoricalAlignment {
        guard let rhetoricalSequence = video.rhetoricalSequence else {
            throw SpineAlignmentError.missingRhetoricalSequence
        }

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let (systemPrompt, userPrompt) = SpineAlignmentPromptEngine.generatePrompt(
            video: video,
            spine: spine,
            rhetoricalSequence: rhetoricalSequence
        )

        let response = await adapter.generate_response(
            prompt: userPrompt,
            promptBackgroundInfo: systemPrompt,
            params: [
                "temperature": temperature,
                "max_tokens": 16000
            ]
        )

        guard !response.isEmpty, !response.hasPrefix("Error:") else {
            throw SpineAlignmentError.apiError(response.isEmpty ? "Empty response from LLM" : response)
        }

        return try SpineAlignmentPromptEngine.parseResponse(response, video: video, spine: spine, runNumber: runNumber)
    }

    // MARK: - Batch Alignment (3 runs per video, parallel with concurrency limit of 5)

    func runBatchAlignment(videos: [YouTubeVideo], limit: Int? = nil) async {
        let runsPerVideo = 3

        // 1. Filter eligible: has BOTH spine + rhetorical sequence, not yet fully aligned (< 3 runs)
        let eligible = videos.filter { video in
            video.hasNarrativeSpine &&
            video.hasRhetoricalSequence &&
            (video.spineAlignmentStatus?.completedRunCount ?? 0) < runsPerVideo
        }

        // 2. Apply limit
        let toProcess = limit.map { Array(eligible.prefix($0)) } ?? eligible
        guard !toProcess.isEmpty else {
            progress = "No eligible videos"
            return
        }

        // 3. Set running state
        isRunning = true
        completedVideos = 0
        totalVideos = toProcess.count
        progress = "Processing 0/\(totalVideos) videos (3 runs each)"
        perVideoProgress = [:]

        // 4. Load spines for the batch
        let channelId = toProcess.first?.channelId ?? ""
        var spineMap: [String: NarrativeSpine] = [:]
        do {
            let allSpines = try await spineFirebase.loadSpines(channelId: channelId)
            for spine in allSpines {
                spineMap[spine.videoId] = spine
            }
        } catch {
            print("⚠️ Could not load spines: \(error.localizedDescription)")
        }

        // 5. Process with concurrency limit of 5 videos at a time.
        //    Each video does 3 sequential LLM calls internally.
        let maxConcurrency = 15
        var videoQueue = toProcess[...]

        // Result type: video + array of 3 alignments (or error)
        typealias VideoResult = (YouTubeVideo, Result<[SpineRhetoricalAlignment], Error>)

        for video in videoQueue.prefix(maxConcurrency) {
            let startRun = (video.spineAlignmentStatus?.completedRunCount ?? 0) + 1
            perVideoProgress[video.videoId] = "Run \(startRun)/\(runsPerVideo)..."
        }

        await withTaskGroup(of: VideoResult.self) { group in
            var inFlight = 0

            // Per-video task: run 3 alignments sequentially, return all 3
            func addVideoTask(_ video: YouTubeVideo, spine: NarrativeSpine?) {
                group.addTask {
                    guard let spine = spine else {
                        return (video, .failure(SpineAlignmentError.missingSpine))
                    }
                    let startRun = (video.spineAlignmentStatus?.completedRunCount ?? 0) + 1
                    var runs: [SpineRhetoricalAlignment] = []

                    for runNum in startRun...runsPerVideo {
                        do {
                            let alignment = try await Self.alignParallel(
                                for: video,
                                spine: spine,
                                runNumber: runNum,
                                temperature: 0.5
                            )
                            runs.append(alignment)
                        } catch {
                            // If any run fails, return what we have + the error
                            if runs.isEmpty {
                                return (video, .failure(error))
                            }
                            break
                        }
                    }
                    return (video, .success(runs))
                }
            }

            // Seed initial tasks
            while !videoQueue.isEmpty && inFlight < maxConcurrency {
                let video = videoQueue.removeFirst()
                addVideoTask(video, spine: spineMap[video.videoId])
                inFlight += 1
            }

            // As tasks complete, save results and launch new ones
            for await (video, result) in group {
                inFlight -= 1

                switch result {
                case .success(let runs):
                    // Save each run to Firebase
                    for alignment in runs {
                        do {
                            try await firebase.saveAlignment(alignment)
                            try await firebase.markRunComplete(
                                videoId: video.videoId,
                                runNumber: alignment.runNumber,
                                beatCount: alignment.beatCount,
                                orphanBeatCount: alignment.orphanBeats.count,
                                unmappedMoveCount: alignment.unmappedMoves.count
                            )
                        } catch {
                            print("❌ Firebase save failed for \(video.title) run \(alignment.runNumber): \(error)")
                        }
                    }

                    // Extract and save confusable pairs if we have 3 runs
                    if runs.count >= 2 {
                        let pairs = Self.extractConfusablePairsFromRuns(
                            runs: runs,
                            videoId: video.videoId,
                            channelId: video.channelId ?? channelId
                        )
                        if !pairs.isEmpty {
                            do {
                                try await firebase.saveConfusablePairs(pairs)
                            } catch {
                                print("❌ Confusable pair save failed for \(video.title): \(error)")
                            }
                        }
                    }

                    completedVideos += 1
                    let pairCount = runs.count >= 2 ? Self.extractConfusablePairsFromRuns(runs: runs, videoId: video.videoId, channelId: channelId).count : 0
                    perVideoProgress[video.videoId] = "✓ \(runs.count) runs, \(pairCount) pairs"

                case .failure(let error):
                    perVideoProgress[video.videoId] = "✗ \(error.localizedDescription)"
                    print("❌ Alignment failed for \(video.title): \(error)")
                }

                progress = "Processing \(completedVideos)/\(totalVideos) videos"

                // Launch next video if available
                if !videoQueue.isEmpty {
                    let nextVideo = videoQueue.removeFirst()
                    let startRun = (nextVideo.spineAlignmentStatus?.completedRunCount ?? 0) + 1
                    perVideoProgress[nextVideo.videoId] = "Run \(startRun)/\(runsPerVideo)..."
                    addVideoTask(nextVideo, spine: spineMap[nextVideo.videoId])
                    inFlight += 1
                }
            }
        }

        // 6. Done
        isRunning = false
        progress = "Done: \(completedVideos)/\(totalVideos) videos"
    }

    // MARK: - Extract Confusable Pairs from In-Memory Runs (no Firebase reads)

    nonisolated static func extractConfusablePairsFromRuns(
        runs: [SpineRhetoricalAlignment],
        videoId: String,
        channelId: String
    ) -> [SpineAlignmentConfusablePair] {
        guard runs.count >= 2 else { return [] }

        var pairs: [String: SpineAlignmentConfusablePair] = [:]
        let minBeats = runs.map { $0.beatAlignments.count }.min() ?? 0

        for pos in 0..<minBeats {
            let function = runs[0].beatAlignments[pos].function
            let moveSets = runs.map { Set($0.beatAlignments[pos].mappedMoves.map { $0.moveType }) }

            let union = moveSets.reduce(Set<String>()) { $0.union($1) }
            let intersection = moveSets.reduce(moveSets[0]) { $0.intersection($1) }
            let unstable = union.subtracting(intersection)

            guard !unstable.isEmpty else { continue }

            // Each unstable move paired against each stable move
            for unstableMove in unstable {
                for stableMove in intersection {
                    let pair = SpineAlignmentConfusablePair.create(
                        function: function, move1: stableMove, move2: unstableMove,
                        creatorId: channelId, videoId: videoId, sampleSize: runs.count
                    )
                    if let existing = pairs[pair.id] {
                        pairs[pair.id] = existing.merging(additionalSwaps: 1, additionalSamples: runs.count, videoId: videoId)
                    } else {
                        pairs[pair.id] = pair
                    }
                }
            }

            // If ALL moves are unstable, pair them against each other
            if intersection.isEmpty {
                let unstableSorted = unstable.sorted()
                for i in 0..<unstableSorted.count {
                    for j in (i+1)..<unstableSorted.count {
                        let pair = SpineAlignmentConfusablePair.create(
                            function: function, move1: unstableSorted[i], move2: unstableSorted[j],
                            creatorId: channelId, videoId: videoId, sampleSize: runs.count
                        )
                        if let existing = pairs[pair.id] {
                            pairs[pair.id] = existing.merging(additionalSwaps: 1, additionalSamples: runs.count, videoId: videoId)
                        } else {
                            pairs[pair.id] = pair
                        }
                    }
                }
            }
        }

        return Array(pairs.values).sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Compute Mapping Table (aggregate all alignments for channel)

    func computeMappingTable(channelId: String) async throws -> SpineRhetoricalMappingTable {
        let alignments = try await firebase.loadAlignments(channelId: channelId)
        let uniqueVideoCount = Set(alignments.map { $0.videoId }).count

        // Build frequency tables with dual counting
        // function → moveType → (rawCount, weightedScore, fullCount, partialCount, tangentialCount)
        struct MoveTally {
            var rawCount = 0
            var weightedScore = 0.0
            var fullCount = 0
            var partialCount = 0
            var tangentialCount = 0
        }

        var functionData: [String: [String: MoveTally]] = [:]
        var functionBeatCounts: [String: Int] = [:]          // how many beats per function
        var functionTotalMoves: [String: Int] = [:]          // total mapped moves per function

        // Track all move appearances (mapped + unmapped) for orphan stats
        var moveAppearances: [String: Int] = [:]             // moveType → total appearances
        var moveUnmappedCounts: [String: Int] = [:]          // moveType → times unmapped

        for alignment in alignments {
            for ba in alignment.beatAlignments {
                functionBeatCounts[ba.function, default: 0] += 1
                functionTotalMoves[ba.function, default: 0] += ba.mappedMoves.count

                for mm in ba.mappedMoves {
                    moveAppearances[mm.moveType, default: 0] += 1

                    var tally = functionData[ba.function, default: [:]][mm.moveType, default: MoveTally()]
                    tally.rawCount += 1
                    tally.weightedScore += mm.weight
                    switch mm.overlapStrength {
                    case "full": tally.fullCount += 1
                    case "partial": tally.partialCount += 1
                    case "tangential": tally.tangentialCount += 1
                    default: tally.partialCount += 1
                    }
                    functionData[ba.function, default: [:]][mm.moveType] = tally
                }
            }

            for um in alignment.unmappedMoves {
                moveAppearances[um.moveType, default: 0] += 1
                moveUnmappedCounts[um.moveType, default: 0] += 1
            }
        }

        // Build FunctionMoveMapping array sorted by spine function label order
        let mappings: [FunctionMoveMapping] = NarrativeSpineBeat.functionLabels.compactMap { fn in
            guard let moveTallies = functionData[fn] else { return nil }
            let totalBeats = functionBeatCounts[fn] ?? 0
            let totalMappedMoves = functionTotalMoves[fn] ?? 0
            let avgMoves = totalBeats > 0 ? Double(totalMappedMoves) / Double(totalBeats) : 0

            // Compute totals for percentage calculation
            let totalRawCount = moveTallies.values.reduce(0) { $0 + $1.rawCount }
            let totalWeightedScore = moveTallies.values.reduce(0.0) { $0 + $1.weightedScore }

            let distribution = moveTallies.map { (moveType, tally) in
                MoveFrequency(
                    moveType: moveType,
                    rawCount: tally.rawCount,
                    rawPercentage: totalRawCount > 0 ? (Double(tally.rawCount) / Double(totalRawCount)) * 100 : 0,
                    weightedScore: tally.weightedScore,
                    weightedPercentage: totalWeightedScore > 0 ? (tally.weightedScore / totalWeightedScore) * 100 : 0,
                    fullCount: tally.fullCount,
                    partialCount: tally.partialCount,
                    tangentialCount: tally.tangentialCount
                )
            }.sorted { $0.weightedScore > $1.weightedScore }  // Sort by weighted (the stronger signal)

            return FunctionMoveMapping(
                function: fn,
                totalOccurrences: totalBeats,
                avgMovesPerBeat: avgMoves,
                moveDistribution: distribution
            )
        }

        // Build unmapped move stats
        let unmappedStats: [UnmappedMoveStat] = moveUnmappedCounts.map { (moveType, unmappedCount) in
            let total = moveAppearances[moveType] ?? unmappedCount
            return UnmappedMoveStat(
                moveType: moveType,
                unmappedCount: unmappedCount,
                totalCount: total,
                unmappedPercentage: total > 0 ? (Double(unmappedCount) / Double(total)) * 100 : 0
            )
        }.sorted { $0.unmappedPercentage > $1.unmappedPercentage }

        // Render text
        let renderedText = renderMappingTableText(mappings: mappings, unmappedStats: unmappedStats, videoCount: uniqueVideoCount)

        let table = SpineRhetoricalMappingTable(
            channelId: channelId,
            computedAt: Date(),
            videoCount: uniqueVideoCount,
            functionMappings: mappings,
            unmappedMoveStats: unmappedStats,
            renderedText: renderedText
        )

        try await firebase.saveMappingTable(table)
        return table
    }

    // MARK: - Render Mapping Table Text

    private func renderMappingTableText(
        mappings: [FunctionMoveMapping],
        unmappedStats: [UnmappedMoveStat],
        videoCount: Int
    ) -> String {
        var lines: [String] = []

        lines.append("SPINE-RHETORICAL MAPPING TABLE")
        lines.append("Videos: \(videoCount)")
        lines.append("")
        lines.append("=== WEIGHTED VIEW (full=1.0, partial=0.5, tangential=0.25) ===")
        lines.append("")

        for mapping in mappings {
            lines.append("\(mapping.function) (\(mapping.totalOccurrences) beats, avg \(String(format: "%.1f", mapping.avgMovesPerBeat)) moves/beat)")
            for mf in mapping.moveDistribution.prefix(6) {
                let breakdown = "F:\(mf.fullCount) P:\(mf.partialCount) T:\(mf.tangentialCount)"
                lines.append("  \(mf.moveType): W=\(String(format: "%.1f%%", mf.weightedPercentage)) R=\(String(format: "%.1f%%", mf.rawPercentage)) [\(breakdown)]")
            }
            lines.append("")
        }

        if !unmappedStats.isEmpty {
            lines.append("=== UNMAPPED MOVES ===")
            for stat in unmappedStats {
                lines.append("  \(stat.moveType): \(String(format: "%.0f%%", stat.unmappedPercentage)) unmapped (\(stat.unmappedCount)/\(stat.totalCount))")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - DonorServiceProgress Conformance

extension SpineAlignmentService: DonorServiceProgress {}
