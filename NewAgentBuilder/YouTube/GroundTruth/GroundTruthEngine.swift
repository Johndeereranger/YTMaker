//
//  GroundTruthEngine.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 2/27/26.
//

import Foundation

class GroundTruthEngine {

    static let shared = GroundTruthEngine()
    private init() {}

    private let desertThreshold = 10

    // MARK: - Full Analysis

    func runFullAnalysis(
        video: YouTubeVideo,
        sentences: [SentenceTelemetry],
        transcript: String,
        windowSize: Int = 5,
        stepSize: Int = 2,
        temperature: Double = 0.3,
        slidingWindowRunCount: Int = 1,
        skipSingleShot: Bool = true,
        onProgress: @escaping (String, Double) -> Void
    ) async -> GroundTruthResult {
        let startTime = Date()
        let sentenceTexts = sentences.map { $0.text }
        var singleShotResult: SingleShotResult?
        let runCount = max(1, slidingWindowRunCount)

        // Method 1: Deterministic (clean) — instant
        onProgress("Method 1: Deterministic (clean)", 0.05)
        let method1Start = Date()
        let method1Chunks = BoundaryDetectionService.shared.detectBoundaries(from: sentences)
        let method1Gaps = extractGapIndices(from: method1Chunks)
        let method1Details = extractDeterministicDetails(from: method1Chunks)
        let method1Duration = Date().timeIntervalSince(method1Start)
        let method1Result = MethodBoundarySet(
            method: .deterministicClean,
            boundaryGapIndices: method1Gaps,
            runDuration: method1Duration,
            debugSummary: "Deterministic rules on \(sentences.count) sentences → \(method1Gaps.count) boundaries",
            internalRunCount: nil,
            unanimousCount: nil,
            majorityCount: nil,
            pass1GapIndices: nil,
            perBoundaryDetails: method1Details
        )

        // Method 2: Deterministic (digression-excluded) — instant (rules only, no LLM)
        onProgress("Method 2: Deterministic (digression-excluded)", 0.10)
        let method2Start = Date()
        let digressionResult = await DigressionDetectionService.shared.detectDigressions(
            from: sentences,
            config: .default
        )
        let excludeSet = DigressionDetectionService.shared.buildExcludeSet(from: digressionResult.digressions)
        let method2Chunks = BoundaryDetectionService.shared.detectBoundaries(from: sentences, excludeIndices: excludeSet)
        let method2Gaps = extractGapIndices(from: method2Chunks)
        let method2Details = extractDeterministicDetails(from: method2Chunks)
        let method2Duration = Date().timeIntervalSince(method2Start)
        let method2Result = MethodBoundarySet(
            method: .deterministicDigression,
            boundaryGapIndices: method2Gaps,
            runDuration: method2Duration,
            debugSummary: "Deterministic rules with \(excludeSet.count) digression sentences excluded → \(method2Gaps.count) boundaries",
            internalRunCount: nil,
            unanimousCount: nil,
            majorityCount: nil,
            pass1GapIndices: nil,
            perBoundaryDetails: method2Details
        )

        // Sliding window LLM — run N times
        var allSlidingWindowRuns: [SectionSplitterRunResult] = []
        let progressPerRun = 0.65 / Double(runCount) // 0.10–0.75 divided among runs

        for runIndex in 0..<runCount {
            let runNum = runIndex + 1
            let runStart = 0.10 + Double(runIndex) * progressPerRun
            onProgress("Sliding window run \(runNum)/\(runCount)", runStart)

            if let runResult = await runSplitterSafe(transcript: transcript, windowSize: windowSize, stepSize: stepSize, temperature: temperature) {
                allSlidingWindowRuns.append(runResult)
            }
        }
        onProgress("Sliding window complete (\(allSlidingWindowRuns.count) runs)", 0.75)

        // Use run 1 for the 4-method consensus (W1 and W)
        let run1 = allSlidingWindowRuns.first
        let method3Result: MethodBoundarySet
        let method4Result: MethodBoundarySet

        if let run1 {
            let extracted = extractSlidingWindowDetails(from: run1)
            method3Result = MethodBoundarySet(
                method: .slidingWindowP1,
                boundaryGapIndices: extracted.pass1GapIndices,
                runDuration: extracted.duration,
                debugSummary: "Sliding Window Pass 1: \(extracted.pass1GapIndices.count) boundaries",
                internalRunCount: 1,
                unanimousCount: nil,
                majorityCount: extracted.pass1GapIndices.count,
                pass1GapIndices: nil,
                perBoundaryDetails: extracted.pass1Details
            )
            method4Result = MethodBoundarySet(
                method: .slidingWindowLLM,
                boundaryGapIndices: extracted.finalGapIndices,
                runDuration: extracted.duration,
                debugSummary: extracted.debug,
                internalRunCount: 2,
                unanimousCount: extracted.pass1GapIndices.count,
                majorityCount: extracted.finalGapIndices.count,
                pass1GapIndices: extracted.pass1GapIndices,
                perBoundaryDetails: extracted.mergedDetails
            )
        } else {
            // All runs failed
            method3Result = MethodBoundarySet(
                method: .slidingWindowP1, boundaryGapIndices: [], runDuration: 0,
                debugSummary: "Sliding Window FAILED", internalRunCount: nil,
                unanimousCount: nil, majorityCount: nil, pass1GapIndices: nil, perBoundaryDetails: nil
            )
            method4Result = MethodBoundarySet(
                method: .slidingWindowLLM, boundaryGapIndices: [], runDuration: 0,
                debugSummary: "Sliding Window FAILED", internalRunCount: nil,
                unanimousCount: nil, majorityCount: nil, pass1GapIndices: nil, perBoundaryDetails: nil
            )
        }

        var methodResults = [method1Result, method2Result, method3Result, method4Result]

        // Method 5: Single-shot LLM (optional)
        if !skipSingleShot {
            onProgress("Method 5: Single-shot LLM", 0.80)
            let method5 = await SingleShotBoundaryService.shared.detectBoundaries(sentences: sentenceTexts)
            singleShotResult = method5
            onProgress("Single-shot complete", 0.85)

            let method5Result = MethodBoundarySet(
                method: .singleShotLLM,
                boundaryGapIndices: method5.consensusBoundaries,
                runDuration: method5.runDuration,
                debugSummary: method5.debugOutput,
                internalRunCount: method5.perRunBoundaries.count,
                unanimousCount: method5.unanimousBoundaries.count,
                majorityCount: method5.consensusBoundaries.count,
                pass1GapIndices: nil,
                perBoundaryDetails: nil
            )
            methodResults.append(method5Result)
        }

        // Build consensus matrix (uses 4-method system from run 1)
        onProgress("Building consensus", 0.90)
        let gapVotes = buildConsensusMatrix(
            totalSentences: sentences.count,
            sentenceTexts: sentenceTexts,
            methodResults: methodResults
        )
        let deserts = detectDeserts(gapVotes: gapVotes)

        let totalDuration = Date().timeIntervalSince(startTime)
        onProgress("Complete (\(String(format: "%.1f", totalDuration))s)", 1.0)

        return GroundTruthResult(
            videoId: video.videoId,
            totalSentences: sentences.count,
            totalMethods: methodResults.count,
            methodResults: methodResults,
            gapVotes: gapVotes,
            deserts: deserts,
            pass1WindowResults: run1?.pass1Results,
            mergedWindowResults: run1?.mergedResults,
            slidingWindowRuns: allSlidingWindowRuns.isEmpty ? nil : allSlidingWindowRuns,
            createdAt: Date()
        )
    }

    // MARK: - Additional Run

    func runAdditionalSlidingWindow(
        existingResult: GroundTruthResult,
        transcript: String,
        windowSize: Int = 5,
        stepSize: Int = 2,
        temperature: Double = 0.3,
        onProgress: @escaping (String, Double) -> Void
    ) async -> GroundTruthResult {
        let existingRuns = existingResult.slidingWindowRuns ?? []
        let runNum = existingRuns.count + 1
        onProgress("Running additional pass \(runNum)", 0.1)

        guard let newRun = await runSplitterSafe(transcript: transcript, windowSize: windowSize, stepSize: stepSize, temperature: temperature) else {
            onProgress("Additional pass failed", 1.0)
            return existingResult
        }

        onProgress("Pass \(runNum) complete", 0.9)

        var updatedRuns = existingRuns
        updatedRuns.append(newRun)

        onProgress("Complete", 1.0)

        return GroundTruthResult(
            videoId: existingResult.videoId,
            totalSentences: existingResult.totalSentences,
            totalMethods: existingResult.totalMethods,
            methodResults: existingResult.methodResults,
            gapVotes: existingResult.gapVotes,
            deserts: existingResult.deserts,
            pass1WindowResults: existingResult.pass1WindowResults,
            mergedWindowResults: existingResult.mergedWindowResults,
            slidingWindowRuns: updatedRuns,
            createdAt: existingResult.createdAt
        )
    }

    // MARK: - Method Helpers

    /// Extract 0-indexed gap indices from Chunk array.
    /// Boundary is at chunk.startSentence - 1 for every chunk after the first
    /// (gap after the last sentence of the previous chunk).
    private func extractGapIndices(from chunks: [Chunk]) -> Set<Int> {
        var gaps = Set<Int>()
        for chunk in chunks where chunk.chunkIndex > 0 {
            let gapIndex = chunk.startSentence - 1
            if gapIndex >= 0 {
                gaps.insert(gapIndex)
            }
        }
        return gaps
    }

    /// Run splitter once, returning nil on failure
    private func runSplitterSafe(transcript: String, windowSize: Int, stepSize: Int, temperature: Double) async -> SectionSplitterRunResult? {
        do {
            return try await SectionSplitterService.shared.runSplitter(transcript: transcript, windowSize: windowSize, stepSize: stepSize, temperature: temperature)
        } catch {
            return nil
        }
    }

    /// Extract gap indices and per-boundary details from a SectionSplitterRunResult for the 4-method consensus
    private func extractSlidingWindowDetails(from result: SectionSplitterRunResult) -> (pass1GapIndices: Set<Int>, finalGapIndices: Set<Int>, duration: TimeInterval, debug: String, pass1Details: [MethodBoundaryDetail], mergedDetails: [MethodBoundaryDetail]) {

        let finalGapIndices = Set(result.boundaries.compactMap { b -> Int? in
            let g = b.sentenceNumber - 1; return g >= 0 ? g : nil
        })
        let pass1GapIndices = Set(result.pass1Boundaries.compactMap { b -> Int? in
            let g = b.sentenceNumber - 1; return g >= 0 ? g : nil
        })

        // Pass 1 details
        var pass1Details: [MethodBoundaryDetail] = []
        for boundary in result.pass1Boundaries {
            let gapIndex = boundary.sentenceNumber - 1
            guard gapIndex >= 0 else { continue }
            pass1Details.append(MethodBoundaryDetail(
                gapIndex: gapIndex, triggerType: nil, triggerConfidence: nil,
                windowVotes: boundary.windowVotes, windowsOverlapping: boundary.windowsOverlapping,
                windowReasons: boundary.reasons, inPass1: true,
                inFinal: finalGapIndices.contains(gapIndex), passChange: nil
            ))
        }

        // Merged details
        let allGapIndices = finalGapIndices.union(pass1GapIndices)
        var mergedDetails: [MethodBoundaryDetail] = []
        for gapIndex in allGapIndices.sorted() {
            let sentenceNum = gapIndex + 1
            let finalBoundary = result.boundaries.first { $0.sentenceNumber == sentenceNum }
            let pass1Boundary = result.pass1Boundaries.first { $0.sentenceNumber == sentenceNum }
            let isInPass1 = pass1Boundary != nil
            let isInFinal = finalBoundary != nil
            let passChange: String
            if isInPass1 && isInFinal { passChange = "confirmed" }
            else if isInPass1 && !isInFinal { passChange = "REVOKED by pass 2" }
            else if !isInPass1 && isInFinal { passChange = "ADDED by pass 2" }
            else { passChange = "unknown" }
            let boundary = finalBoundary ?? pass1Boundary
            mergedDetails.append(MethodBoundaryDetail(
                gapIndex: gapIndex, triggerType: nil, triggerConfidence: nil,
                windowVotes: boundary?.windowVotes, windowsOverlapping: boundary?.windowsOverlapping,
                windowReasons: boundary?.reasons, inPass1: isInPass1, inFinal: isInFinal,
                passChange: passChange
            ))
        }

        var debug = "Sliding Window: \(result.totalWindows) windows, "
        debug += "pass1: \(result.pass1SplitCount) splits → \(result.pass1Boundaries.count) boundaries, "
        debug += "pass2: \(result.pass2RevokedCount) revoked, \(result.pass2MovedCount) moved → \(result.boundaries.count) final"

        return (pass1GapIndices, finalGapIndices, 0, debug, pass1Details, mergedDetails)
    }

    /// Extract per-boundary trigger details from deterministic chunks
    private func extractDeterministicDetails(from chunks: [Chunk]) -> [MethodBoundaryDetail] {
        var details: [MethodBoundaryDetail] = []
        for chunk in chunks where chunk.chunkIndex > 0 {
            let gapIndex = chunk.startSentence - 1
            guard gapIndex >= 0 else { continue }

            let trigger = chunk.profile.boundaryTrigger
            details.append(MethodBoundaryDetail(
                gapIndex: gapIndex,
                triggerType: trigger?.type.rawValue,
                triggerConfidence: trigger?.confidence.rawValue,
                windowVotes: nil,
                windowsOverlapping: nil,
                windowReasons: nil,
                inPass1: nil,
                inFinal: nil,
                passChange: nil
            ))
        }
        return details
    }

    // MARK: - Consensus Building

    private func buildConsensusMatrix(
        totalSentences: Int,
        sentenceTexts: [String],
        methodResults: [MethodBoundarySet]
    ) -> [SentenceGapVote] {
        guard totalSentences > 1 else { return [] }

        var votes: [SentenceGapVote] = []

        for gapIndex in 0..<(totalSentences - 1) {
            var methods = Set<BoundaryMethod>()
            for result in methodResults {
                if result.boundaryGapIndices.contains(gapIndex) {
                    methods.insert(result.method)
                }
            }

            // Only include gaps that have at least 1 vote
            guard !methods.isEmpty else { continue }

            let sentenceText = gapIndex < sentenceTexts.count ? sentenceTexts[gapIndex] : ""
            let nextText = (gapIndex + 1) < sentenceTexts.count ? sentenceTexts[gapIndex + 1] : ""

            votes.append(SentenceGapVote(
                gapAfterSentenceIndex: gapIndex,
                sentenceText: sentenceText,
                nextSentenceText: nextText,
                votes: methods,
                manualOverride: nil
            ))
        }

        return votes
    }

    // MARK: - Desert Detection

    private func detectDeserts(gapVotes: [SentenceGapVote]) -> [DesertRegion] {
        guard let maxGap = gapVotes.map({ $0.gapAfterSentenceIndex }).max() else { return [] }

        let votedGaps = Set(gapVotes.map { $0.gapAfterSentenceIndex })
        var deserts: [DesertRegion] = []
        var currentDesertStart: Int?
        var consecutiveZero = 0

        for gapIndex in 0...maxGap {
            if !votedGaps.contains(gapIndex) {
                if currentDesertStart == nil {
                    currentDesertStart = gapIndex
                }
                consecutiveZero += 1
            } else {
                if consecutiveZero >= desertThreshold, let start = currentDesertStart {
                    deserts.append(DesertRegion(
                        startSentenceIndex: start,
                        endSentenceIndex: gapIndex - 1
                    ))
                }
                currentDesertStart = nil
                consecutiveZero = 0
            }
        }

        // Check trailing desert
        if consecutiveZero >= desertThreshold, let start = currentDesertStart {
            deserts.append(DesertRegion(
                startSentenceIndex: start,
                endSentenceIndex: maxGap
            ))
        }

        return deserts
    }

    // MARK: - Codex Consensus (legacy, not currently called)

    private func buildCodexConsensusMatrix(
        totalSentences: Int,
        sentenceTexts: [String],
        runs: [CodexComparableRun]
    ) -> [CodexGapVote] {
        guard totalSentences > 1, !runs.isEmpty else { return [] }

        let totalRuns = runs.count
        let threshold = Int(ceil(Double(totalRuns) / 2.0))
        var votes: [CodexGapVote] = []

        for gapIndex in 0..<(totalSentences - 1) {
            let voters = runs.filter { $0.boundaryGapIndices.contains(gapIndex) }
            guard !voters.isEmpty else { continue }

            let runIds = voters.map(\.id)
            let voteCount = runIds.count
            let sentenceText = gapIndex < sentenceTexts.count ? sentenceTexts[gapIndex] : ""
            let nextText = (gapIndex + 1) < sentenceTexts.count ? sentenceTexts[gapIndex + 1] : ""

            votes.append(
                CodexGapVote(
                    gapAfterSentenceIndex: gapIndex,
                    sentenceText: sentenceText,
                    nextSentenceText: nextText,
                    runIds: runIds,
                    runCount: voteCount,
                    totalRuns: totalRuns,
                    consensusTier: CodexConsensusTier.from(voteCount: voteCount, totalRuns: totalRuns) ?? .weak,
                    isBoundary: voteCount >= threshold
                )
            )
        }

        return votes
    }

    private func buildPairwiseComparisons(runs: [CodexComparableRun]) -> [PairwiseRunComparison] {
        guard runs.count >= 2 else { return [] }

        var comparisons: [PairwiseRunComparison] = []
        for leftIndex in runs.indices {
            for rightIndex in (leftIndex + 1)..<runs.count {
                let left = runs[leftIndex]
                let right = runs[rightIndex]
                let shared = left.boundaryGapIndices.intersection(right.boundaryGapIndices)
                let union = left.boundaryGapIndices.union(right.boundaryGapIndices)
                let leftOnly = left.boundaryGapIndices.subtracting(right.boundaryGapIndices)
                let rightOnly = right.boundaryGapIndices.subtracting(left.boundaryGapIndices)
                let similarity = union.isEmpty ? 1.0 : Double(shared.count) / Double(union.count)
                let disagreements = Array(leftOnly.union(rightOnly)).sorted()

                comparisons.append(
                    PairwiseRunComparison(
                        leftRunId: left.id,
                        rightRunId: right.id,
                        sharedBoundaryCount: shared.count,
                        leftOnlyCount: leftOnly.count,
                        rightOnlyCount: rightOnly.count,
                        unionCount: union.count,
                        jaccardSimilarity: similarity,
                        disagreementGapIndices: disagreements
                    )
                )
            }
        }
        return comparisons
    }
}
