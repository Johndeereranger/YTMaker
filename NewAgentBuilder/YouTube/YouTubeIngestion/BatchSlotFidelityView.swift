//
//  BatchSlotFidelityView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/13/26.
//

import SwiftUI

// MARK: - Concurrency Actors

actor AsyncSemaphore {
    private let limit: Int
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
        self.count = limit
    }

    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        } else {
            count += 1
        }
    }
}

actor BatchResultCollector {
    struct SectionMeta {
        let videoId: String
        let videoTitle: String
        let sectionIndex: Int
        let originalSentences: [String]
        let cleanedSentences: [String]
        let moveType: String
        let category: String
        let preFilterResult: PreFilterResult?
    }

    struct DebugInfo {
        let systemPrompt: String
        let userPrompt: String
        let rawResponse: String
        let parseSucceeded: Bool
    }

    private var runsBySectionKey: [String: [Int: [SlotFidelitySentenceResult]]] = [:]
    private var processedRunsBySectionKey: [String: [Int: [SlotFidelitySentenceResult]]] = [:]
    private var sectionMeta: [String: SectionMeta] = [:]
    private var sectionDebug: [String: DebugInfo] = [:]

    private func key(videoId: String, sectionIndex: Int) -> String {
        "\(videoId)|\(sectionIndex)"
    }

    func add(
        videoId: String,
        videoTitle: String,
        sectionIndex: Int,
        runIndex: Int,
        rawResults: [SlotFidelitySentenceResult],
        processedResults: [SlotFidelitySentenceResult],
        originalSentences: [String],
        cleanedSentences: [String],
        moveType: String,
        category: String,
        preFilterResult: PreFilterResult? = nil,
        debugInfo: DebugInfo? = nil
    ) {
        let k = key(videoId: videoId, sectionIndex: sectionIndex)
        runsBySectionKey[k, default: [:]][runIndex] = rawResults
        processedRunsBySectionKey[k, default: [:]][runIndex] = processedResults
        if sectionMeta[k] == nil {
            sectionMeta[k] = SectionMeta(
                videoId: videoId,
                videoTitle: videoTitle,
                sectionIndex: sectionIndex,
                originalSentences: originalSentences,
                cleanedSentences: cleanedSentences,
                moveType: moveType,
                category: category,
                preFilterResult: preFilterResult
            )
        }
        if let debug = debugInfo, sectionDebug[k] == nil {
            sectionDebug[k] = debug
        }
    }

    struct CollectedSection {
        let videoId: String
        let videoTitle: String
        let sectionIndex: Int
        let runResults: [Int: [SlotFidelitySentenceResult]]
        let processedRunResults: [Int: [SlotFidelitySentenceResult]]
        let originalSentences: [String]
        let cleanedSentences: [String]
        let moveType: String
        let category: String
        let preFilterResult: PreFilterResult?
        let debugInfo: DebugInfo?
    }

    func allResults() -> [CollectedSection] {
        runsBySectionKey.compactMap { k, runs in
            guard let meta = sectionMeta[k] else { return nil }
            return CollectedSection(
                videoId: meta.videoId,
                videoTitle: meta.videoTitle,
                sectionIndex: meta.sectionIndex,
                runResults: runs,
                processedRunResults: processedRunsBySectionKey[k] ?? [:],
                originalSentences: meta.originalSentences,
                cleanedSentences: meta.cleanedSentences,
                moveType: meta.moveType,
                category: meta.category,
                preFilterResult: meta.preFilterResult,
                debugInfo: sectionDebug[k]
            )
        }
    }
}

// MARK: - Data Models

enum BatchVideoStatus: Equatable {
    case pending
    case running(completedSections: Int, totalSections: Int)
    case complete
    case failed(String)
}

struct BatchSectionResult: Identifiable {
    let id = UUID()
    let sectionIndex: Int
    let moveType: String
    let category: String
    let sentenceCount: Int
    let runs: [SlotFidelityRun]
    let comparisons: [SlotFidelitySentenceComparison]
    let signatureMatchRate: Double
    let phraseMatchRate: Double
    let functionMatchRate: Double
    let hintMismatchCount: Int
    // Debug: raw prompt/response from first run
    let debugSystemPrompt: String
    let debugUserPrompt: String
    let debugRawResponse: String
    let debugParseSucceeded: Bool
    // Post-processing pipeline results
    let preFilterResult: PreFilterResult?
    let postProcessedComparisons: [SlotFidelitySentenceComparison]
    let postProcessedSignatureMatchRate: Double
    let postProcessedPhraseMatchRate: Double
    let rawOtherRate: Double
    let postProcessedOtherRate: Double
}

struct BatchVideoResult: Identifiable {
    var id: String { videoId }
    let videoId: String
    let videoTitle: String
    var status: BatchVideoStatus
    var sectionResults: [BatchSectionResult]

    var avgSignatureMatchRate: Double {
        guard !sectionResults.isEmpty else { return 0 }
        return sectionResults.map(\.signatureMatchRate).reduce(0, +) / Double(sectionResults.count)
    }

    var avgPhraseMatchRate: Double {
        guard !sectionResults.isEmpty else { return 0 }
        return sectionResults.map(\.phraseMatchRate).reduce(0, +) / Double(sectionResults.count)
    }

    var avgFunctionMatchRate: Double {
        guard !sectionResults.isEmpty else { return 0 }
        return sectionResults.map(\.functionMatchRate).reduce(0, +) / Double(sectionResults.count)
    }
}

struct OtherFrequencyMetric {
    let rawTotalOtherPhrases: Int
    let rawTotalPhrases: Int
    let rawRate: Double
    let rawSamples: [(phraseText: String, sentenceText: String, videoTitle: String)]
    let processedTotalOtherPhrases: Int
    let processedTotalPhrases: Int
    let processedRate: Double
    let processedSamples: [(phraseText: String, sentenceText: String, videoTitle: String)]
    let deltaRate: Double          // rawRate - processedRate (positive = improvement)
    let phrasesEliminated: Int     // raw - processed other count
}

struct AggregatePreFilterMetric {
    let totalOriginalSentences: Int
    let totalFilteredSentences: Int
    let totalJunkRemoved: Int
    let totalFragmentsMerged: Int
    let totalReactionBeatsTagged: Int
    let totalVisualAnchorsTagged: Int
    let junkSamples: [(text: String, videoTitle: String)]
}

struct AggregateSignatureDeltaMetric {
    let rawAvgMatchRate: Double
    let processedAvgMatchRate: Double
    let deltaMatchRate: Double
    let sectionsImproved: Int
    let sectionsUnchanged: Int
    let sectionsWorsened: Int
    let totalSections: Int
}

struct SignatureLengthMetric {
    let avgLength: Double
    let histogram: [(slotCount: Int, frequency: Int)]
    let percentOverSix: Double
    let longSamples: [(sentenceText: String, signature: String, length: Int, videoTitle: String)]
}

struct HintMismatchMetric {
    let overallRate: Double
    let totalSentences: Int
    let mismatchSentences: Int
    let perHintType: [(hintType: String, count: Int, rate: Double)]
}

struct ConfusablePairMetric: Identifiable {
    let id = UUID()
    let roleA: String
    let roleB: String
    let frequency: Int
    let samples: [String]
}

// MARK: - View Model

@MainActor
class BatchSlotFidelityViewModel: ObservableObject {
    static var shared: BatchSlotFidelityViewModel?

    let channel: YouTubeChannel

    // Config
    @Published var runCount: Int = 5
    @Published var temperature: Double = 0.1
    @Published var maxVideos: Int = 10
    @Published var maxSections: Int = 2

    // Videos
    @Published var allEligibleVideos: [YouTubeVideo] = []
    @Published var videos: [YouTubeVideo] = []  // capped subset actually tested
    @Published var isLoadingVideos = true

    // Progress
    @Published var isRunning = false
    @Published var overallPhase = ""
    @Published var completedWorkItems = 0
    @Published var totalWorkItems = 0

    // Per-video results
    @Published var videoResults: [String: BatchVideoResult] = [:]

    // Aggregates
    @Published var otherFrequency: OtherFrequencyMetric?
    @Published var signatureLengthDist: SignatureLengthMetric?
    @Published var hintMismatchMetric: HintMismatchMetric?
    @Published var confusablePairs: [ConfusablePairMetric] = []
    @Published var preFilterMetric: AggregatePreFilterMetric?
    @Published var signatureDelta: AggregateSignatureDeltaMetric?

    @Published var savedPairsCount: Int?
    @Published var isSavingPairs = false

    @Published var errorMessage: String?

    init(channel: YouTubeChannel) {
        self.channel = channel
        BatchSlotFidelityViewModel.shared = self
    }

    // MARK: - Load Videos

    func loadVideos() async {
        isLoadingVideos = true
        let vm = CreatorDetailViewModel.shared
        await vm.setChannel(channel)
        allEligibleVideos = vm.videos
            .filter { $0.hasRhetoricalSequence && $0.hasTranscript && $0.durationMinutes >= 5.0 }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        applyCap()
        isLoadingVideos = false
    }

    func applyCap() {
        videos = Array(allEligibleVideos.prefix(maxVideos))
    }

    var estimatedCalls: Int {
        videos.reduce(0) { total, video in
            let sectionCount = min(video.rhetoricalSequence?.moves.count ?? 0, maxSections)
            return total + sectionCount * runCount
        }
    }

    // MARK: - Run Batch Test

    func runBatchTest() async {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        videoResults = [:]
        otherFrequency = nil
        signatureLengthDist = nil
        hintMismatchMetric = nil
        confusablePairs = []
        overallPhase = "Preparing work items..."

        // 1. Build all work items
        struct WorkItem: Sendable {
            let videoId: String
            let videoTitle: String
            let sectionIndex: Int
            let sentences: [String]           // post-prefilter + stripped
            let originalSentences: [String]   // raw from parser
            let hints: [SentenceHints]
            let moveType: String
            let category: String
            let runIndex: Int
            let temperature: Double
        }

        var allWorkItems: [WorkItem] = []
        var videoSectionCounts: [String: Int] = [:]
        // Store pre-filter results per section key for the collector
        var preFilterResults: [String: PreFilterResult] = [:]

        for video in videos {
            guard let sequence = video.rhetoricalSequence,
                  let transcript = video.transcript else { continue }

            let allSentences = SentenceParser.parse(transcript)
            guard !allSentences.isEmpty else { continue }

            var sectionCount = 0

            for (sectionIdx, move) in sequence.moves.prefix(maxSections).enumerated() {
                let startIdx = move.startSentence ?? 0
                let endIdx = move.endSentence ?? min(startIdx + 20, allSentences.count - 1)
                guard startIdx < allSentences.count else { continue }

                let clampedEnd = min(endIdx, allSentences.count - 1)
                guard startIdx <= clampedEnd else { continue }
                let raw = Array(allSentences[startIdx...clampedEnd])
                guard !raw.isEmpty else { continue }

                // Strip parentheticals first
                let stripped = raw.map { DeterministicHints.stripParentheticals($0) }

                // Pre-filter: remove junk, merge fragments, tag interjections/deictic
                let preFilter = SlotPreFilter.filter(stripped)
                let sectionKey = "\(video.videoId)|\(sectionIdx)"
                preFilterResults[sectionKey] = preFilter

                let cleaned = preFilter.filteredSentences
                guard !cleaned.isEmpty else { continue }
                let hints = cleaned.map { DeterministicHints.compute(for: $0) }

                sectionCount += 1

                for runIdx in 0..<runCount {
                    allWorkItems.append(WorkItem(
                        videoId: video.videoId,
                        videoTitle: video.title,
                        sectionIndex: sectionIdx,
                        sentences: cleaned,
                        originalSentences: raw,
                        hints: hints,
                        moveType: move.moveType.rawValue,
                        category: move.moveType.category.rawValue,
                        runIndex: runIdx,
                        temperature: temperature
                    ))
                }
            }

            videoSectionCounts[video.videoId] = sectionCount
            videoResults[video.videoId] = BatchVideoResult(
                videoId: video.videoId,
                videoTitle: video.title,
                status: .pending,
                sectionResults: []
            )
        }

        totalWorkItems = allWorkItems.count
        completedWorkItems = 0

        guard totalWorkItems > 0 else {
            errorMessage = "No work items to process"
            isRunning = false
            return
        }

        // Mark all videos as running
        for (videoId, sectionCount) in videoSectionCounts {
            videoResults[videoId]?.status = .running(completedSections: 0, totalSections: sectionCount)
        }

        overallPhase = "Running \(totalWorkItems) LLM calls (15 concurrent)..."

        // 2. Execute with bounded parallelism
        let semaphore = AsyncSemaphore(limit: 15)
        let collector = BatchResultCollector()

        await withTaskGroup(of: Void.self) { group in
            for item in allWorkItems {
                group.addTask { [preFilterResults] in
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    do {
                        let debugResult = try await DonorLibraryA2Service.shared.callSlotAnnotationWithDebug(
                            sentences: item.sentences,
                            hints: item.hints,
                            moveType: item.moveType,
                            category: item.category,
                            temperature: item.temperature
                        )

                        // Raw sentence results (from LLM as-is)
                        let rawSentenceResults: [SlotFidelitySentenceResult] = debugResult.results.enumerated().map { idx, r in
                            SlotFidelitySentenceResult(
                                sentenceIndex: idx,
                                rawText: idx < item.sentences.count ? item.sentences[idx] : "",
                                phrases: r.phrases,
                                slotSequence: r.slotSequence,
                                slotSignature: r.slotSequence.joined(separator: "|"),
                                sentenceFunction: r.sentenceFunction,
                                hints: r.deterministicHints,
                                hintMismatches: r.hintMismatches
                            )
                        }

                        // Post-process: merge "other" phrases into adjacent
                        let postProcessed = SlotPostProcessor.process(debugResult.results)
                        let processedSentenceResults: [SlotFidelitySentenceResult] = postProcessed.enumerated().map { idx, pp in
                            let rawResult = idx < debugResult.results.count ? debugResult.results[idx] : nil
                            return SlotFidelitySentenceResult(
                                sentenceIndex: idx,
                                rawText: idx < item.sentences.count ? item.sentences[idx] : "",
                                phrases: pp.processedPhrases,
                                slotSequence: pp.processedPhrases.map(\.role),
                                slotSignature: pp.processedSignature,
                                sentenceFunction: rawResult?.sentenceFunction ?? "other",
                                hints: rawResult?.deterministicHints ?? [],
                                hintMismatches: rawResult?.hintMismatches ?? []
                            )
                        }

                        let debug: BatchResultCollector.DebugInfo? = item.runIndex == 0
                            ? BatchResultCollector.DebugInfo(
                                systemPrompt: debugResult.systemPrompt,
                                userPrompt: debugResult.userPrompt,
                                rawResponse: debugResult.rawResponse,
                                parseSucceeded: debugResult.parseSucceeded
                            )
                            : nil

                        let sectionKey = "\(item.videoId)|\(item.sectionIndex)"
                        let preFilter = item.runIndex == 0 ? preFilterResults[sectionKey] : nil

                        await collector.add(
                            videoId: item.videoId,
                            videoTitle: item.videoTitle,
                            sectionIndex: item.sectionIndex,
                            runIndex: item.runIndex,
                            rawResults: rawSentenceResults,
                            processedResults: processedSentenceResults,
                            originalSentences: item.originalSentences,
                            cleanedSentences: item.sentences,
                            moveType: item.moveType,
                            category: item.category,
                            preFilterResult: preFilter,
                            debugInfo: debug
                        )
                    } catch {
                        // Failures are silently counted — we still continue
                    }

                    await MainActor.run {
                        self.completedWorkItems += 1
                        self.overallPhase = "\(self.completedWorkItems)/\(self.totalWorkItems) calls complete"
                    }
                }
            }
        }

        // 3. Assemble results
        overallPhase = "Assembling results..."
        let collected = await collector.allResults()
        assembleResults(from: collected, videoSectionCounts: videoSectionCounts)

        // 4. Compute aggregates
        overallPhase = "Computing aggregates..."
        computeAggregates()

        isRunning = false
        overallPhase = "Complete"
    }

    // MARK: - Assemble Results

    private func assembleResults(
        from collected: [BatchResultCollector.CollectedSection],
        videoSectionCounts: [String: Int]
    ) {
        // Group by videoId
        var byVideo: [String: [BatchResultCollector.CollectedSection]] = [:]
        for section in collected {
            byVideo[section.videoId, default: []].append(section)
        }

        for (videoId, sections) in byVideo {
            var sectionResults: [BatchSectionResult] = []

            for section in sections.sorted(by: { $0.sectionIndex < $1.sectionIndex }) {
                let sortedRunIndices = section.runResults.keys.sorted()

                // Raw runs
                let runs: [SlotFidelityRun] = sortedRunIndices.map { runIdx in
                    SlotFidelityRun(
                        runNumber: runIdx + 1,
                        temperature: temperature,
                        results: section.runResults[runIdx] ?? []
                    )
                }

                // Processed runs
                let processedRuns: [SlotFidelityRun] = sortedRunIndices.map { runIdx in
                    SlotFidelityRun(
                        runNumber: runIdx + 1,
                        temperature: temperature,
                        results: section.processedRunResults[runIdx] ?? []
                    )
                }

                guard !runs.isEmpty else { continue }

                // Raw comparisons
                let comparisons = buildComparisons(
                    runs: runs,
                    originalSentences: section.cleanedSentences,
                    cleanedSentences: section.cleanedSentences
                )

                let sigRate = comparisons.isEmpty ? 0 :
                    Double(comparisons.filter { $0.runsAgreedOnSignature }.count) / Double(comparisons.count)
                let phraseRate: Double = {
                    let allAlignments = comparisons.flatMap(\.phraseAlignment)
                    guard !allAlignments.isEmpty else { return 0 }
                    return Double(allAlignments.filter(\.isUnanimous).count) / Double(allAlignments.count)
                }()
                let funcRate = comparisons.isEmpty ? 0 :
                    Double(comparisons.filter { $0.runsAgreedOnFunction }.count) / Double(comparisons.count)
                let hintCount = comparisons.filter { !$0.hintMismatchesAcrossRuns.isEmpty }.count

                // Post-processed comparisons
                let ppComparisons = buildComparisons(
                    runs: processedRuns,
                    originalSentences: section.cleanedSentences,
                    cleanedSentences: section.cleanedSentences
                )

                let ppSigRate = ppComparisons.isEmpty ? 0 :
                    Double(ppComparisons.filter { $0.runsAgreedOnSignature }.count) / Double(ppComparisons.count)
                let ppPhraseRate: Double = {
                    let allAlignments = ppComparisons.flatMap(\.phraseAlignment)
                    guard !allAlignments.isEmpty else { return 0 }
                    return Double(allAlignments.filter(\.isUnanimous).count) / Double(allAlignments.count)
                }()

                // Compute "other" rates for raw vs processed
                let rawOther = computeOtherRateForComparisons(comparisons)
                let ppOther = computeOtherRateForComparisons(ppComparisons)

                sectionResults.append(BatchSectionResult(
                    sectionIndex: section.sectionIndex,
                    moveType: section.moveType,
                    category: section.category,
                    sentenceCount: section.cleanedSentences.count,
                    runs: runs,
                    comparisons: comparisons,
                    signatureMatchRate: sigRate,
                    phraseMatchRate: phraseRate,
                    functionMatchRate: funcRate,
                    hintMismatchCount: hintCount,
                    debugSystemPrompt: section.debugInfo?.systemPrompt ?? "",
                    debugUserPrompt: section.debugInfo?.userPrompt ?? "",
                    debugRawResponse: section.debugInfo?.rawResponse ?? "",
                    debugParseSucceeded: section.debugInfo?.parseSucceeded ?? true,
                    preFilterResult: section.preFilterResult,
                    postProcessedComparisons: ppComparisons,
                    postProcessedSignatureMatchRate: ppSigRate,
                    postProcessedPhraseMatchRate: ppPhraseRate,
                    rawOtherRate: rawOther,
                    postProcessedOtherRate: ppOther
                ))
            }

            let videoTitle = sections.first?.videoTitle ?? videoId
            videoResults[videoId] = BatchVideoResult(
                videoId: videoId,
                videoTitle: videoTitle,
                status: sectionResults.isEmpty ? .failed("No sections completed") : .complete,
                sectionResults: sectionResults.sorted { $0.sectionIndex < $1.sectionIndex }
            )
        }

        // Mark videos with no collected results as failed
        for (videoId, result) in videoResults {
            if case .running = result.status {
                videoResults[videoId]?.status = .failed("No results returned")
            }
        }
    }

    // MARK: - Comparison Builder (same logic as SlotFidelityViewModel)

    private func buildComparisons(
        runs: [SlotFidelityRun],
        originalSentences: [String],
        cleanedSentences: [String]
    ) -> [SlotFidelitySentenceComparison] {
        guard !runs.isEmpty, !cleanedSentences.isEmpty else { return [] }
        let sentenceCount = cleanedSentences.count

        return (0..<sentenceCount).map { idx in
            let runsForSentence = runs.compactMap { run -> SlotFidelitySentenceResult? in
                idx < run.results.count ? run.results[idx] : nil
            }

            let signatures = runsForSentence.map { $0.slotSignature }
            let functions = runsForSentence.map { $0.sentenceFunction }

            let dominantSig = mostCommon(signatures) ?? ""
            let sigMatch = signatures.isEmpty ? 0 : Double(signatures.filter { $0 == dominantSig }.count) / Double(signatures.count)
            let allSigsMatch = Set(signatures).count <= 1

            let dominantFunc = mostCommon(functions) ?? ""
            let funcMatch = Set(functions).count <= 1

            let phraseAlignment = buildPhraseAlignment(from: runsForSentence)
            let allMismatches = Array(Set(runsForSentence.flatMap { $0.hintMismatches }))

            return SlotFidelitySentenceComparison(
                sentenceIndex: idx,
                rawText: idx < originalSentences.count ? originalSentences[idx] : cleanedSentences[idx],
                runsAgreedOnSignature: allSigsMatch,
                signatureConsistency: sigMatch,
                dominantSignature: dominantSig,
                runsAgreedOnFunction: funcMatch,
                dominantFunction: dominantFunc,
                phraseAlignment: phraseAlignment,
                hintMismatchesAcrossRuns: allMismatches,
                perRunSignatures: signatures,
                perRunFunctions: functions
            )
        }
    }

    private func buildPhraseAlignment(from results: [SlotFidelitySentenceResult]) -> [PhraseAlignment] {
        guard !results.isEmpty else { return [] }
        let reference = results[0].phrases
        var alignments: [PhraseAlignment] = []

        for (phraseIdx, refPhrase) in reference.enumerated() {
            var rolesPerRun: [Int: String] = [1: refPhrase.role]

            for runIdx in 1..<results.count {
                let otherPhrases = results[runIdx].phrases
                if phraseIdx < otherPhrases.count {
                    rolesPerRun[runIdx + 1] = otherPhrases[phraseIdx].role
                } else {
                    let match = otherPhrases.first { $0.text.lowercased() == refPhrase.text.lowercased() }
                    rolesPerRun[runIdx + 1] = match?.role ?? "missing"
                }
            }

            let roles = Array(rolesPerRun.values)
            let dominant = mostCommon(roles) ?? refPhrase.role
            let unanimous = Set(roles.filter { $0 != "missing" }).count <= 1

            alignments.append(PhraseAlignment(
                phraseText: refPhrase.text,
                rolesPerRun: rolesPerRun,
                isUnanimous: unanimous,
                dominantRole: dominant
            ))
        }

        return alignments
    }

    private func mostCommon(_ items: [String]) -> String? {
        guard !items.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    /// Compute "other" rate from a set of comparisons (fraction of dominant phrase roles that are "other")
    private func computeOtherRateForComparisons(_ comparisons: [SlotFidelitySentenceComparison]) -> Double {
        let allAlignments = comparisons.flatMap(\.phraseAlignment)
        guard !allAlignments.isEmpty else { return 0 }
        let otherCount = allAlignments.filter { $0.dominantRole == "other" }.count
        return Double(otherCount) / Double(allAlignments.count)
    }

    // MARK: - Compute Aggregates

    private func computeAggregates() {
        let allSectionResults = videoResults.values.flatMap(\.sectionResults)
        let allRawComparisons = allSectionResults.flatMap(\.comparisons)
        let allProcessedComparisons = allSectionResults.flatMap(\.postProcessedComparisons)

        computeOtherFrequency(rawComparisons: allRawComparisons, processedComparisons: allProcessedComparisons)
        computeSignatureLengthDistribution(from: allRawComparisons)
        computeHintMismatchRate(from: allRawComparisons)
        computeConfusablePairs(from: allRawComparisons)
        computePreFilterAggregate(from: allSectionResults)
        computeSignatureDeltaAggregate(from: allSectionResults)
    }

    private func computeOtherFrequency(
        rawComparisons: [SlotFidelitySentenceComparison],
        processedComparisons: [SlotFidelitySentenceComparison]
    ) {
        func computeStats(from comparisons: [SlotFidelitySentenceComparison])
            -> (otherCount: Int, totalCount: Int, rate: Double, samples: [(phraseText: String, sentenceText: String, videoTitle: String)]) {
            var totalPhrases = 0
            var otherPhrases = 0
            var samples: [(phraseText: String, sentenceText: String, videoTitle: String)] = []

            for comp in comparisons {
                for align in comp.phraseAlignment {
                    totalPhrases += 1
                    if align.dominantRole == "other" {
                        otherPhrases += 1
                        let videoTitle = videoResults.values.first { result in
                            result.sectionResults.contains { section in
                                section.comparisons.contains { $0.sentenceIndex == comp.sentenceIndex && $0.rawText == comp.rawText }
                            }
                        }?.videoTitle ?? ""
                        samples.append((align.phraseText, comp.rawText, videoTitle))
                    }
                }
            }
            let rate = totalPhrases > 0 ? Double(otherPhrases) / Double(totalPhrases) : 0
            return (otherPhrases, totalPhrases, rate, samples)
        }

        let raw = computeStats(from: rawComparisons)
        let processed = computeStats(from: processedComparisons)

        otherFrequency = OtherFrequencyMetric(
            rawTotalOtherPhrases: raw.otherCount,
            rawTotalPhrases: raw.totalCount,
            rawRate: raw.rate,
            rawSamples: raw.samples,
            processedTotalOtherPhrases: processed.otherCount,
            processedTotalPhrases: processed.totalCount,
            processedRate: processed.rate,
            processedSamples: processed.samples,
            deltaRate: raw.rate - processed.rate,
            phrasesEliminated: raw.otherCount - processed.otherCount
        )
    }

    private func computePreFilterAggregate(from sectionResults: [BatchSectionResult]) {
        var totalOriginal = 0
        var totalFiltered = 0
        var totalJunk = 0
        var totalMerged = 0
        var totalReaction = 0
        var totalVisual = 0
        var junkSamples: [(text: String, videoTitle: String)] = []

        for section in sectionResults {
            guard let pf = section.preFilterResult else { continue }
            totalOriginal += pf.originalSentences.count
            totalFiltered += pf.filteredSentences.count

            for action in pf.actions {
                switch action {
                case .removedJunk(_, let text):
                    totalJunk += 1
                    if junkSamples.count < 20 {
                        let title = videoResults.values.first { $0.sectionResults.contains { $0.id == section.id } }?.videoTitle ?? ""
                        junkSamples.append((text, title))
                    }
                case .mergedFragment:
                    totalMerged += 1
                case .taggedReactionBeat:
                    totalReaction += 1
                case .taggedVisualAnchor:
                    totalVisual += 1
                }
            }
        }

        preFilterMetric = AggregatePreFilterMetric(
            totalOriginalSentences: totalOriginal,
            totalFilteredSentences: totalFiltered,
            totalJunkRemoved: totalJunk,
            totalFragmentsMerged: totalMerged,
            totalReactionBeatsTagged: totalReaction,
            totalVisualAnchorsTagged: totalVisual,
            junkSamples: junkSamples
        )
    }

    private func computeSignatureDeltaAggregate(from sectionResults: [BatchSectionResult]) {
        guard !sectionResults.isEmpty else {
            signatureDelta = nil
            return
        }

        let rawAvg = sectionResults.map(\.signatureMatchRate).reduce(0, +) / Double(sectionResults.count)
        let ppAvg = sectionResults.map(\.postProcessedSignatureMatchRate).reduce(0, +) / Double(sectionResults.count)

        var improved = 0, unchanged = 0, worsened = 0
        for section in sectionResults {
            let diff = section.postProcessedSignatureMatchRate - section.signatureMatchRate
            if diff > 0.001 { improved += 1 }
            else if diff < -0.001 { worsened += 1 }
            else { unchanged += 1 }
        }

        signatureDelta = AggregateSignatureDeltaMetric(
            rawAvgMatchRate: rawAvg,
            processedAvgMatchRate: ppAvg,
            deltaMatchRate: ppAvg - rawAvg,
            sectionsImproved: improved,
            sectionsUnchanged: unchanged,
            sectionsWorsened: worsened,
            totalSections: sectionResults.count
        )
    }

    private func computeSignatureLengthDistribution(from comparisons: [SlotFidelitySentenceComparison]) {
        var lengths: [Int] = []
        var longSamples: [(sentenceText: String, signature: String, length: Int, videoTitle: String)] = []

        for comp in comparisons {
            let sig = comp.dominantSignature
            guard !sig.isEmpty else { continue }
            let slotCount = sig.split(separator: "|").count
            lengths.append(slotCount)

            if slotCount > 6 {
                let videoTitle = videoResults.values.first { result in
                    result.sectionResults.contains { section in
                        section.comparisons.contains { $0.sentenceIndex == comp.sentenceIndex && $0.rawText == comp.rawText }
                    }
                }?.videoTitle ?? ""
                longSamples.append((comp.rawText, sig, slotCount, videoTitle))
            }
        }

        guard !lengths.isEmpty else {
            signatureLengthDist = nil
            return
        }

        let avg = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let overSix = Double(lengths.filter { $0 > 6 }.count) / Double(lengths.count)

        var hist: [Int: Int] = [:]
        for l in lengths { hist[l, default: 0] += 1 }
        let histogram = hist.sorted { $0.key < $1.key }.map { (slotCount: $0.key, frequency: $0.value) }

        signatureLengthDist = SignatureLengthMetric(
            avgLength: avg,
            histogram: histogram,
            percentOverSix: overSix,
            longSamples: longSamples.sorted { $0.length > $1.length }
        )
    }

    private func computeHintMismatchRate(from comparisons: [SlotFidelitySentenceComparison]) {
        let total = comparisons.count
        let mismatched = comparisons.filter { !$0.hintMismatchesAcrossRuns.isEmpty }
        let mismatchCount = mismatched.count

        // Group by hint type
        var typeCounts: [String: Int] = [:]
        for comp in mismatched {
            for mismatch in comp.hintMismatchesAcrossRuns {
                // Extract the hint name prefix (e.g., "hasTemporalMarker" from "hasTemporalMarker but no temporal_marker phrase")
                let hintType = String(mismatch.prefix(while: { $0 != " " }))
                typeCounts[hintType, default: 0] += 1
            }
        }

        let perType = typeCounts.map { type, count in
            (hintType: type, count: count, rate: total > 0 ? Double(count) / Double(total) : 0)
        }.sorted { $0.rate > $1.rate }

        hintMismatchMetric = HintMismatchMetric(
            overallRate: total > 0 ? Double(mismatchCount) / Double(total) : 0,
            totalSentences: total,
            mismatchSentences: mismatchCount,
            perHintType: perType
        )
    }

    private func computeConfusablePairs(from comparisons: [SlotFidelitySentenceComparison]) {
        var pairCounts: [String: Int] = [:]
        var pairSamples: [String: [String]] = [:]

        for comp in comparisons {
            for align in comp.phraseAlignment where !align.isUnanimous {
                let roles = Set(align.rolesPerRun.values.filter { $0 != "missing" })
                let sortedRoles = Array(roles).sorted()

                // Generate all pairs
                for i in 0..<sortedRoles.count {
                    for j in (i + 1)..<sortedRoles.count {
                        let pairKey = "\(sortedRoles[i])|\(sortedRoles[j])"
                        pairCounts[pairKey, default: 0] += 1
                        if (pairSamples[pairKey]?.count ?? 0) < 5 {
                            pairSamples[pairKey, default: []].append(align.phraseText)
                        }
                    }
                }
            }
        }

        confusablePairs = pairCounts.map { key, count in
            let parts = key.split(separator: "|")
            return ConfusablePairMetric(
                roleA: String(parts[0]),
                roleB: String(parts.count > 1 ? parts[1] : ""),
                frequency: count,
                samples: pairSamples[key] ?? []
            )
        }.sorted { $0.frequency > $1.frequency }
    }

    // MARK: - Save Confusable Pairs to Firebase

    func extractAndSaveConfusablePairs() async {
        isSavingPairs = true
        var allPairs: [ConfusablePair] = []

        for videoResult in videoResults.values {
            for section in videoResult.sectionResults {
                let pairs = ConfusablePairService.shared.extractPairs(
                    from: section.comparisons,
                    moveType: section.moveType,
                    creatorId: channel.channelId,
                    videoId: videoResult.videoId
                )
                allPairs.append(contentsOf: pairs)
            }
        }

        guard !allPairs.isEmpty else {
            savedPairsCount = 0
            isSavingPairs = false
            return
        }

        do {
            try await ConfusablePairService.shared.savePairs(allPairs)
            savedPairsCount = allPairs.count
        } catch {
            errorMessage = "Confusable save failed: \(error.localizedDescription)"
        }
        isSavingPairs = false
    }

    // MARK: - Per-Card Copy Text

    var otherFrequencyCopyText: String {
        guard let other = otherFrequency else { return "" }
        var lines: [String] = []
        lines.append("\"OTHER\" FREQUENCY — \(channel.name)")
        lines.append("Raw: \(String(format: "%.1f%%", other.rawRate * 100)) (\(other.rawTotalOtherPhrases)/\(other.rawTotalPhrases) phrases)")
        lines.append("Processed: \(String(format: "%.1f%%", other.processedRate * 100)) (\(other.processedTotalOtherPhrases)/\(other.processedTotalPhrases) phrases)")
        lines.append("Delta: -\(String(format: "%.1f%%", other.deltaRate * 100)) (\(other.phrasesEliminated) phrases eliminated)")
        lines.append("")
        lines.append("REMAINING 'OTHER' PHRASES (post-pipeline):")
        for (i, s) in other.processedSamples.enumerated() {
            lines.append("  \(i + 1). \"\(s.phraseText)\"")
            lines.append("     sentence: \"\(s.sentenceText)\"")
            lines.append("     video: \(s.videoTitle)")
        }
        return lines.joined(separator: "\n")
    }

    var pipelineImprovementCopyText: String {
        var lines: [String] = []
        lines.append("PIPELINE IMPROVEMENT — \(channel.name)")
        if let pf = preFilterMetric {
            lines.append("Pre-filter: \(pf.totalOriginalSentences) -> \(pf.totalFilteredSentences) sentences (-\(pf.totalOriginalSentences - pf.totalFilteredSentences))")
        }
        if let other = otherFrequency {
            lines.append("Other rate: \(String(format: "%.1f%%", other.rawRate * 100)) -> \(String(format: "%.1f%%", other.processedRate * 100)) (-\(other.phrasesEliminated) phrases)")
        }
        if let sig = signatureDelta {
            lines.append("Sig match: \(String(format: "%.0f%%", sig.rawAvgMatchRate * 100)) -> \(String(format: "%.0f%%", sig.processedAvgMatchRate * 100))")
            lines.append("  Sections: +\(sig.sectionsImproved) improved, \(sig.sectionsUnchanged) unchanged, -\(sig.sectionsWorsened) worsened")
        }
        return lines.joined(separator: "\n")
    }

    var preFilterSummaryCopyText: String {
        guard let pf = preFilterMetric else { return "" }
        var lines: [String] = []
        lines.append("PRE-FILTER SUMMARY — \(channel.name)")
        lines.append("Sentences: \(pf.totalOriginalSentences) -> \(pf.totalFilteredSentences)")
        lines.append("Junk removed: \(pf.totalJunkRemoved)")
        lines.append("Fragments merged: \(pf.totalFragmentsMerged)")
        lines.append("Reaction beats tagged: \(pf.totalReactionBeatsTagged)")
        lines.append("Visual anchors tagged: \(pf.totalVisualAnchorsTagged)")
        if !pf.junkSamples.isEmpty {
            lines.append("")
            lines.append("JUNK SAMPLES:")
            for (i, s) in pf.junkSamples.enumerated() {
                lines.append("  \(i + 1). \"\(s.text)\" — \(s.videoTitle)")
            }
        }
        return lines.joined(separator: "\n")
    }

    var signatureLengthCopyText: String {
        guard let sig = signatureLengthDist else { return "" }
        var lines: [String] = []
        lines.append("SIGNATURE LENGTH DISTRIBUTION — \(channel.name)")
        lines.append("Average: \(String(format: "%.1f", sig.avgLength)) slots | >6 slots: \(String(format: "%.1f%%", sig.percentOverSix * 100))")
        lines.append("")
        lines.append("HISTOGRAM:")
        for h in sig.histogram {
            let bar = String(repeating: "#", count: min(h.frequency, 40))
            lines.append("  \(h.slotCount) slots: \(bar) (\(h.frequency))")
        }
        if !sig.longSamples.isEmpty {
            lines.append("")
            lines.append("ALL SIGNATURES > 6 SLOTS:")
            for (i, s) in sig.longSamples.enumerated() {
                lines.append("  \(i + 1). [\(s.length) slots] \"\(s.sentenceText)\"")
                lines.append("     \(s.signature)")
                lines.append("     video: \(s.videoTitle)")
            }
        }
        return lines.joined(separator: "\n")
    }

    var hintMismatchCopyText: String {
        guard let hint = hintMismatchMetric else { return "" }
        var lines: [String] = []
        lines.append("HINT MISMATCH RATE — \(channel.name)")
        lines.append("\(String(format: "%.1f%%", hint.overallRate * 100)) — \(hint.mismatchSentences) / \(hint.totalSentences) sentences with mismatches")
        lines.append("")
        lines.append("PER-HINT-TYPE BREAKDOWN:")
        for h in hint.perHintType {
            lines.append("  \(h.hintType): \(h.count) (\(String(format: "%.1f%%", h.rate * 100)))")
        }
        return lines.joined(separator: "\n")
    }

    var confusablePairsCopyText: String {
        guard !confusablePairs.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("CONFUSABLE PAIRS — \(channel.name)")
        lines.append("\(confusablePairs.count) distinct pairs found")
        lines.append("")
        for (i, pair) in confusablePairs.enumerated() {
            lines.append("\(i + 1). \(pair.roleA) <-> \(pair.roleB): \(pair.frequency)x")
            for sample in pair.samples {
                lines.append("     \"\(sample)\"")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Full Copy Text

    var aggregateCopyText: String {
        var lines: [String] = []
        lines.append("BATCH SLOT FIDELITY — \(channel.name)")
        lines.append("Videos: \(videoResults.values.filter { $0.status == .complete }.count) / \(videos.count)")
        lines.append("Runs per section: \(runCount) | Temperature: \(String(format: "%.2f", temperature))")
        lines.append("")

        // Pipeline improvement summary
        if let pf = preFilterMetric {
            lines.append("PRE-FILTER: \(pf.totalOriginalSentences) -> \(pf.totalFilteredSentences) sentences | \(pf.totalJunkRemoved) junk, \(pf.totalFragmentsMerged) merged, \(pf.totalReactionBeatsTagged) RXN, \(pf.totalVisualAnchorsTagged) VAN")
        }
        if let other = otherFrequency {
            lines.append("OTHER RATE: \(String(format: "%.1f%%", other.rawRate * 100)) -> \(String(format: "%.1f%%", other.processedRate * 100)) (-\(other.phrasesEliminated) phrases)")
        }
        if let sig = signatureDelta {
            lines.append("SIG MATCH: \(String(format: "%.0f%%", sig.rawAvgMatchRate * 100)) -> \(String(format: "%.0f%%", sig.processedAvgMatchRate * 100)) (+\(sig.sectionsImproved)/-\(sig.sectionsWorsened) sections)")
        }
        lines.append("")

        if let other = otherFrequency {
            lines.append("WHAT: \"Other\" Frequency (post-pipeline): \(String(format: "%.1f%%", other.processedRate * 100))")
            lines.append("  \(other.processedTotalOtherPhrases) / \(other.processedTotalPhrases) phrases still labeled 'other'")
            if !other.processedSamples.isEmpty {
                lines.append("  WHY: Remaining 'other' phrases:")
                for s in other.processedSamples.prefix(10) {
                    lines.append("    \"\(s.phraseText)\" ← \"\(String(s.sentenceText.prefix(50)))...\"")
                }
            }
            lines.append("")
        }

        if let sig = signatureLengthDist {
            lines.append("WHAT: Signature Length: avg \(String(format: "%.1f", sig.avgLength)) slots")
            lines.append("  \(String(format: "%.1f%%", sig.percentOverSix * 100)) of signatures have >6 slots")
            lines.append("  WHY: Distribution:")
            for h in sig.histogram {
                let bar = String(repeating: "#", count: min(h.frequency, 40))
                lines.append("    \(h.slotCount) slots: \(bar) (\(h.frequency))")
            }
            if !sig.longSamples.isEmpty {
                lines.append("  Long signature samples:")
                for s in sig.longSamples.prefix(5) {
                    lines.append("    [\(s.length)] \"\(String(s.sentenceText.prefix(50)))...\"")
                    lines.append("         \(s.signature)")
                }
            }
            lines.append("")
        }

        if let hint = hintMismatchMetric {
            lines.append("WHAT: Hint Mismatch Rate: \(String(format: "%.1f%%", hint.overallRate * 100))")
            lines.append("  \(hint.mismatchSentences) / \(hint.totalSentences) sentences with mismatches")
            lines.append("  WHY: Per-hint-type breakdown:")
            for h in hint.perHintType {
                lines.append("    \(h.hintType): \(h.count) (\(String(format: "%.1f%%", h.rate * 100)))")
            }
            lines.append("")
        }

        if !confusablePairs.isEmpty {
            lines.append("WHAT: Confusable Pairs (top 15):")
            for pair in confusablePairs.prefix(15) {
                let samples = pair.samples.prefix(2).map { "\"\(String($0.prefix(30)))\"" }.joined(separator: ", ")
                lines.append("  \(pair.roleA) <-> \(pair.roleB): \(pair.frequency)x   e.g. \(samples)")
            }
        }

        return lines.joined(separator: "\n")
    }

    func videoCopyText(for videoId: String) -> String {
        guard let result = videoResults[videoId] else { return "" }
        var lines: [String] = []
        lines.append("VIDEO DETAIL — \(result.videoTitle)")
        lines.append("Sig: \(String(format: "%.0f%%", result.avgSignatureMatchRate * 100)) | Phr: \(String(format: "%.0f%%", result.avgPhraseMatchRate * 100)) | Func: \(String(format: "%.0f%%", result.avgFunctionMatchRate * 100))")
        lines.append("")

        for section in result.sectionResults {
            lines.append("Section \(section.sectionIndex + 1) — \(section.moveType) (\(section.category))")
            lines.append("  \(section.sentenceCount) sentences | Sig: \(String(format: "%.0f%%", section.signatureMatchRate * 100)) | Phr: \(String(format: "%.0f%%", section.phraseMatchRate * 100))")
            for comp in section.comparisons {
                let icon = comp.runsAgreedOnSignature ? "OK" : "DIVERGENT"
                lines.append("  [\(comp.sentenceIndex + 1)] [\(icon)] \"\(String(comp.rawText.prefix(60)))...\"")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    var fullBatchCopyText: String {
        let divider = String(repeating: "=", count: 60)
        var parts = [aggregateCopyText]
        for result in videoResults.values.sorted(by: { $0.videoTitle < $1.videoTitle }) {
            parts.append(divider)
            parts.append(videoCopyText(for: result.videoId))
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Main View

struct BatchSlotFidelityView: View {
    @StateObject private var vm: BatchSlotFidelityViewModel
    @EnvironmentObject var nav: NavigationViewModel
    @State private var selectedTab = 0
    @State private var confusableSaveConfirmed = false

    init(channel: YouTubeChannel) {
        _vm = StateObject(wrappedValue: BatchSlotFidelityViewModel(channel: channel))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if vm.isLoadingVideos {
                    HStack {
                        ProgressView()
                        Text("Loading videos...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    controlsSection
                    progressSection
                    if !vm.videoResults.isEmpty {
                        tabPickerSection
                        switch selectedTab {
                        case 0: aggregateTab
                        case 1: videosTab
                        default: EmptyView()
                        }
                    }
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding()
        }
        .navigationTitle("Batch Slot Fidelity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadVideos() }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.channel.name)
                        .font(.subheadline.bold())
                    Text("\(vm.allEligibleVideos.count) eligible videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("Videos:")
                        .font(.caption)
                    Text("\(vm.maxVideos)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 24)
                    Stepper("", value: $vm.maxVideos, in: 1...min(vm.allEligibleVideos.count, 50))
                        .labelsHidden()
                        .onChange(of: vm.maxVideos) { _, _ in vm.applyCap() }
                }

                HStack(spacing: 4) {
                    Text("Sect:")
                        .font(.caption)
                    Text("\(vm.maxSections)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 20)
                    Stepper("", value: $vm.maxSections, in: 1...25)
                        .labelsHidden()
                }

                HStack(spacing: 4) {
                    Text("Runs:")
                        .font(.caption)
                    Text("\(vm.runCount)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 20)
                    Stepper("", value: $vm.runCount, in: 2...10)
                        .labelsHidden()
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("Temp:")
                        .font(.caption)
                    Text(String(format: "%.2f", vm.temperature))
                        .font(.caption.monospacedDigit())
                        .frame(width: 36)
                    Slider(value: $vm.temperature, in: 0.0...1.0, step: 0.05)
                        .frame(maxWidth: 120)
                }

                Spacer()

                Text("~\(vm.estimatedCalls) LLM calls")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundColor(vm.estimatedCalls > 500 ? .red : (vm.estimatedCalls > 200 ? .orange : .green))
            }

            Button {
                Task { await vm.runBatchTest() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Run Batch (\(vm.videos.count) videos)")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.purple.opacity(0.15))
                .foregroundColor(.purple)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(vm.isRunning || vm.videos.isEmpty)
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        if vm.isRunning {
            VStack(spacing: 6) {
                ProgressView(value: Double(vm.completedWorkItems), total: max(Double(vm.totalWorkItems), 1))
                    .tint(.purple)
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(vm.overallPhase)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    // MARK: - Tab Picker

    private var tabPickerSection: some View {
        HStack(spacing: 8) {
            Picker("Tab", selection: $selectedTab) {
                Text("Aggregate").tag(0)
                Text("Videos").tag(1)
            }
            .pickerStyle(.segmented)

            CompactCopyButton(text: vm.fullBatchCopyText)
        }
    }

    // MARK: - Aggregate Tab

    private var aggregateTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            pipelineImprovementCard
            preFilterSummaryCard
            otherFrequencyCard
            signatureLengthCard
            hintMismatchCard
            confusablePairsCard
        }
    }

    // MARK: - Pipeline Improvement Card (Hero)

    @ViewBuilder
    private var pipelineImprovementCard: some View {
        if let other = vm.otherFrequency, let sigDelta = vm.signatureDelta, let pf = vm.preFilterMetric {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Pipeline Improvement")
                        .font(.subheadline.bold())
                    Spacer()
                    CompactCopyButton(text: vm.pipelineImprovementCopyText)
                }

                HStack(spacing: 16) {
                    // Pre-filter: sentence count reduction
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text("\(pf.totalOriginalSentences)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Text("\(pf.totalFilteredSentences)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(.blue)
                        }
                        Text("sentences")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        let removed = pf.totalOriginalSentences - pf.totalFilteredSentences
                        if removed > 0 {
                            Text("-\(removed) cleaned")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.blue)
                        }
                    }

                    // Other rate delta
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(String(format: "%.1f%%", other.rawRate * 100))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(.red)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", other.processedRate * 100))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(.green)
                        }
                        Text("\"other\" rate")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        if other.phrasesEliminated > 0 {
                            Text("-\(other.phrasesEliminated) phrases")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }

                    // Signature match delta
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(String(format: "%.0f%%", sigDelta.rawAvgMatchRate * 100))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(sigDelta.rawAvgMatchRate >= 0.9 ? .green : .orange)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f%%", sigDelta.processedAvgMatchRate * 100))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(sigDelta.processedAvgMatchRate >= 0.9 ? .green : .orange)
                        }
                        Text("sig match")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            if sigDelta.sectionsImproved > 0 {
                                Text("+\(sigDelta.sectionsImproved)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            if sigDelta.sectionsWorsened > 0 {
                                Text("-\(sigDelta.sectionsWorsened)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    // MARK: - Pre-Filter Summary Card

    @ViewBuilder
    private var preFilterSummaryCard: some View {
        if let pf = vm.preFilterMetric {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pre-Filter Summary")
                        .font(.subheadline.bold())
                    Spacer()
                    CompactCopyButton(text: vm.preFilterSummaryCopyText)
                }

                HStack(spacing: 12) {
                    if pf.totalJunkRemoved > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 9))
                            Text("\(pf.totalJunkRemoved) junk")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.red)
                    }
                    if pf.totalFragmentsMerged > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.system(size: 9))
                            Text("\(pf.totalFragmentsMerged) merged")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.orange)
                    }
                    if pf.totalReactionBeatsTagged > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 9))
                            Text("\(pf.totalReactionBeatsTagged) RXN")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.pink)
                    }
                    if pf.totalVisualAnchorsTagged > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 9))
                            Text("\(pf.totalVisualAnchorsTagged) VAN")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.mint)
                    }
                }

                if !pf.junkSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sample junk removed:")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        ForEach(Array(pf.junkSamples.prefix(5).enumerated()), id: \.offset) { _, sample in
                            HStack(spacing: 4) {
                                Text("\"\(sample.text)\"")
                                    .font(.system(size: 9))
                                    .foregroundColor(.red.opacity(0.7))
                                    .strikethrough()
                                Text("- \(sample.videoTitle)")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    // MARK: - Other Frequency Card (Raw -> Processed Delta)

    @ViewBuilder
    private var otherFrequencyCard: some View {
        if let other = vm.otherFrequency {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\"Other\" Frequency")
                        .font(.subheadline.bold())
                    Spacer()
                    CompactCopyButton(text: vm.otherFrequencyCopyText)
                }

                // Before/after delta row
                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f%%", other.rawRate * 100))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundColor(.red.opacity(0.8))
                        Text("raw")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text("\(other.rawTotalOtherPhrases)/\(other.rawTotalPhrases)")
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    VStack(spacing: 2) {
                        Text(String(format: "%.1f%%", other.processedRate * 100))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundColor(other.processedRate < 0.1 ? .green : (other.processedRate < 0.3 ? .orange : .red))
                        Text("processed")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text("\(other.processedTotalOtherPhrases)/\(other.processedTotalPhrases)")
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if other.deltaRate > 0 {
                        VStack(spacing: 2) {
                            Text(String(format: "-%.1f%%", other.deltaRate * 100))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundColor(.green)
                            Text("\(other.phrasesEliminated) eliminated")
                                .font(.system(size: 8))
                                .foregroundColor(.green)
                        }
                    }
                }

                // Remaining "other" samples (post-pipeline — the ones to investigate)
                if !other.processedSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remaining 'other' phrases (post-pipeline):")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        ForEach(Array(other.processedSamples.prefix(10).enumerated()), id: \.offset) { _, sample in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\"\(sample.phraseText)\"")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.orange)
                                Text("from: \"\(String(sample.sentenceText.prefix(60)))...\"")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(4)
                            .background(Color.orange.opacity(0.05))
                            .cornerRadius(3)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    // Signature Length Card
    @ViewBuilder
    private var signatureLengthCard: some View {
        if let sig = vm.signatureLengthDist {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Signature Length Distribution")
                        .font(.subheadline.bold())
                    Spacer()
                    CompactCopyButton(text: vm.signatureLengthCopyText)
                }

                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", sig.avgLength))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundColor(.blue)
                        Text("avg slots")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 2) {
                        Text(String(format: "%.0f%%", sig.percentOverSix * 100))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundColor(sig.percentOverSix < 0.1 ? .green : (sig.percentOverSix < 0.25 ? .orange : .red))
                        Text("> 6 slots")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }

                // Histogram
                let maxFreq = sig.histogram.map(\.frequency).max() ?? 1
                ForEach(sig.histogram, id: \.slotCount) { entry in
                    HStack(spacing: 6) {
                        Text("\(entry.slotCount)")
                            .font(.caption.monospacedDigit())
                            .frame(width: 20, alignment: .trailing)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(entry.slotCount > 6 ? Color.red.opacity(0.6) : Color.blue.opacity(0.4))
                                .frame(width: geo.size.width * CGFloat(entry.frequency) / CGFloat(maxFreq), height: 8)
                        }
                        .frame(height: 8)
                        Text("\(entry.frequency)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }

                if !sig.longSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Longest signatures:")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        ForEach(Array(sig.longSamples.prefix(5).enumerated()), id: \.offset) { _, sample in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("[\(sample.length) slots] \"\(String(sample.sentenceText.prefix(50)))...\"")
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                Text(sample.signature)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(4)
                            .background(Color.red.opacity(0.05))
                            .cornerRadius(3)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    // Hint Mismatch Card
    @ViewBuilder
    private var hintMismatchCard: some View {
        if let hint = vm.hintMismatchMetric {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Hint Mismatch Rate")
                        .font(.subheadline.bold())
                    Spacer()
                    CompactCopyButton(text: vm.hintMismatchCopyText)
                }

                HStack(spacing: 12) {
                    Text(String(format: "%.1f%%", hint.overallRate * 100))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundColor(hint.overallRate < 0.05 ? .green : (hint.overallRate < 0.15 ? .orange : .red))
                    Text("\(hint.mismatchSentences) / \(hint.totalSentences) sentences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !hint.perHintType.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Per-hint-type breakdown:")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                        let maxRate = hint.perHintType.map(\.rate).max() ?? 1
                        ForEach(hint.perHintType, id: \.hintType) { entry in
                            HStack(spacing: 6) {
                                Text(entry.hintType)
                                    .font(.system(size: 9, weight: .medium))
                                    .frame(width: 130, alignment: .leading)
                                    .lineLimit(1)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(.systemGray4))
                                            .frame(height: 8)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(entry.rate < 0.05 ? Color.green : (entry.rate < 0.15 ? Color.orange : Color.red))
                                            .frame(width: maxRate > 0 ? geo.size.width * entry.rate / maxRate : 0, height: 8)
                                    }
                                }
                                .frame(height: 8)

                                Text("\(entry.count)")
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 25, alignment: .trailing)
                                Text("(\(String(format: "%.1f%%", entry.rate * 100)))")
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundColor(entry.rate < 0.05 ? .green : (entry.rate < 0.15 ? .orange : .red))
                                    .frame(width: 45, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    // Confusable Pairs Card
    @ViewBuilder
    private var confusablePairsCard: some View {
        if !vm.confusablePairs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Confusable Pairs")
                        .font(.subheadline.bold())
                    Spacer()

                    Button {
                        Task {
                            await vm.extractAndSaveConfusablePairs()
                            confusableSaveConfirmed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                confusableSaveConfirmed = false
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if vm.isSavingPairs {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else {
                                Image(systemName: confusableSaveConfirmed ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    .font(.system(size: 10))
                            }
                            Text(confusableSaveConfirmed ? "Saved \(vm.savedPairsCount ?? 0)" : "Save to Index")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(confusableSaveConfirmed ? Color.green.opacity(0.15) : Color.purple.opacity(0.12))
                        .foregroundColor(confusableSaveConfirmed ? .green : .purple)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isSavingPairs)

                    CompactCopyButton(text: vm.confusablePairsCopyText)
                }

                ForEach(Array(vm.confusablePairs.prefix(15))) { pair in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            slotBadge(pair.roleA)
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                            slotBadge(pair.roleB)
                            Spacer()
                            Text("\(pair.frequency)x")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(.orange)
                        }

                        if !pair.samples.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(pair.samples.prefix(3), id: \.self) { sample in
                                    Text("\"\(String(sample.prefix(20)))\"")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(6)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    // MARK: - Videos Tab

    private var videosTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Per-Video Results")
                    .font(.subheadline.bold())
                Spacer()
                let completeCount = vm.videoResults.values.filter {
                    if case .complete = $0.status { return true }; return false
                }.count
                Text("\(completeCount)/\(vm.videos.count) complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(vm.videoResults.values.sorted(by: { $0.videoTitle < $1.videoTitle })) { result in
                videoCard(result)
            }
        }
    }

    private func videoCard(_ result: BatchVideoResult) -> some View {
        Button {
            nav.push(.batchSlotVideoDetail(result.videoId))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(result.videoTitle)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    Spacer()
                    statusBadge(result.status)
                }

                if case .complete = result.status {
                    HStack(spacing: 12) {
                        Text("\(result.sectionResults.count) sections")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        // Parse failure warning
                        if result.sectionResults.contains(where: { !$0.debugParseSucceeded }) {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.red)
                                Text("parse fail")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        }

                        HStack(spacing: 4) {
                            Text("Sig:")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f%%", result.avgSignatureMatchRate * 100))
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundColor(result.avgSignatureMatchRate >= 0.9 ? .green : (result.avgSignatureMatchRate >= 0.7 ? .orange : .red))
                        }

                        HStack(spacing: 4) {
                            Text("Phr:")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f%%", result.avgPhraseMatchRate * 100))
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundColor(result.avgPhraseMatchRate >= 0.9 ? .green : (result.avgPhraseMatchRate >= 0.7 ? .orange : .red))
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(_ status: BatchVideoStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Text("Pending")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray4))
                    .foregroundColor(.secondary)
                    .cornerRadius(4)

            case .running(let done, let total):
                HStack(spacing: 3) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("\(done)/\(total)")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .cornerRadius(4)

            case .complete:
                Text("Complete")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(4)

            case .failed(let msg):
                Text("Failed")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(4)
                    .help(msg)
            }
        }
    }

    // MARK: - Helpers

    private func slotBadge(_ type: String) -> some View {
        Text(shortSlotName(type))
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(slotColor(type).opacity(0.15))
            .foregroundColor(slotColor(type))
            .cornerRadius(3)
    }

    private func slotColor(_ type: String) -> Color {
        switch type {
        case "geographic_location": return .blue
        case "visual_detail": return .cyan
        case "quantitative_claim": return .purple
        case "temporal_marker": return .orange
        case "actor_reference": return .green
        case "contradiction": return .red
        case "sensory_detail": return .mint
        case "rhetorical_question": return .pink
        case "evaluative_claim": return .yellow
        case "pivot_phrase": return .indigo
        case "direct_address": return .teal
        case "narrative_action": return .brown
        case "abstract_framing": return .gray
        case "comparison": return .purple
        case "empty_connector": return .gray
        case "factual_relay": return .cyan
        case "reaction_beat": return .pink
        case "visual_anchor": return .mint
        default: return .secondary
        }
    }

    private func shortSlotName(_ type: String) -> String {
        switch type {
        case "geographic_location": return "GEO"
        case "visual_detail": return "VIS"
        case "quantitative_claim": return "QNT"
        case "temporal_marker": return "TMP"
        case "actor_reference": return "ACT"
        case "contradiction": return "CTR"
        case "sensory_detail": return "SNS"
        case "rhetorical_question": return "RHQ"
        case "evaluative_claim": return "EVL"
        case "pivot_phrase": return "PVT"
        case "direct_address": return "DIR"
        case "narrative_action": return "NAR"
        case "abstract_framing": return "ABS"
        case "comparison": return "CMP"
        case "empty_connector": return "EMT"
        case "factual_relay": return "FCT"
        case "reaction_beat": return "RXN"
        case "visual_anchor": return "VAN"
        case "other": return "OTH"
        case "missing": return "---"
        default: return String(type.prefix(3)).uppercased()
        }
    }
}

// MARK: - Video Detail View

struct BatchVideoDetailView: View {
    let videoId: String
    @State private var expandedSections: Set<Int> = []
    @State private var expandedSentences: Set<String> = []
    @State private var expandedDebug: Set<Int> = []
    @State private var selectedDetailTab = 1  // default to Raw LLM

    private var result: BatchVideoResult? {
        BatchSlotFidelityViewModel.shared?.videoResults[videoId]
    }

    var body: some View {
        ScrollView {
            if let result = result {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(result.videoTitle)
                                .font(.subheadline.bold())
                                .lineLimit(2)
                            Spacer()
                            if let vm = BatchSlotFidelityViewModel.shared {
                                CompactCopyButton(text: vm.videoCopyText(for: videoId))
                            }
                        }

                        HStack(spacing: 12) {
                            rateLabel("Sig", result.avgSignatureMatchRate)
                            rateLabel("Phr", result.avgPhraseMatchRate)
                            rateLabel("Func", result.avgFunctionMatchRate)
                            Text("\(result.sectionResults.count) sections")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                    // 4-tab picker
                    Picker("View", selection: $selectedDetailTab) {
                        Text("Pre-Filter").tag(0)
                        Text("Raw LLM").tag(1)
                        Text("Processed").tag(2)
                        Text("Compare").tag(3)
                    }
                    .pickerStyle(.segmented)

                    // Tab content
                    switch selectedDetailTab {
                    case 0: preFilterTab(result)
                    case 1: rawLLMTab(result)
                    case 2: processedTab(result)
                    case 3: comparisonTab(result)
                    default: EmptyView()
                    }
                }
                .padding()
            } else {
                Text("No results found")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .navigationTitle("Video Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tab 0: Pre-Filter

    private func preFilterTab(_ result: BatchVideoResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(result.sectionResults) { section in
                if let pf = section.preFilterResult {
                    VStack(alignment: .leading, spacing: 8) {
                        // Section header
                        HStack {
                            Text("Section \(section.sectionIndex + 1) — \(section.moveType)")
                                .font(.caption.bold())
                            Spacer()
                            Text("\(pf.originalSentences.count) → \(pf.filteredSentences.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.blue)
                        }

                        // Summary counts
                        let removed = pf.actions.filter { if case .removedJunk = $0 { return true }; return false }.count
                        let merged = pf.actions.filter { if case .mergedFragment = $0 { return true }; return false }.count
                        let tagged = pf.actions.filter {
                            if case .taggedReactionBeat = $0 { return true }
                            if case .taggedVisualAnchor = $0 { return true }
                            return false
                        }.count

                        if removed > 0 || merged > 0 || tagged > 0 {
                            HStack(spacing: 8) {
                                if removed > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 8))
                                        Text("\(removed) junk")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundColor(.red)
                                }
                                if merged > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.triangle.merge")
                                            .font(.system(size: 8))
                                        Text("\(merged) merged")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundColor(.orange)
                                }
                                if tagged > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 8))
                                        Text("\(tagged) tagged")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                        }

                        // Action list
                        ForEach(Array(pf.actions.enumerated()), id: \.offset) { _, action in
                            preFilterActionRow(action)
                        }

                        if pf.actions.isEmpty {
                            Text("No pre-filter actions needed")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            }
        }
    }

    private func preFilterActionRow(_ action: PreFilterAction) -> some View {
        HStack(spacing: 6) {
            switch action {
            case .removedJunk(let idx, let text):
                Text("[REMOVED]")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.red)
                Text("[\(idx + 1)]")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("\"\(text)\"")
                    .font(.system(size: 9))
                    .foregroundColor(.red.opacity(0.7))
                    .strikethrough()
                    .lineLimit(1)

            case .mergedFragment(let idx, let text, let target):
                Text("[MERGED → \(target + 1)]")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.orange)
                Text("[\(idx + 1)]")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("\"\(text)\"")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .lineLimit(1)

            case .taggedReactionBeat(let idx, let text):
                Text("[TAGGED: RXN]")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.pink)
                Text("[\(idx + 1)]")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("\"\(text)\"")
                    .font(.system(size: 9))
                    .foregroundColor(.pink)
                    .lineLimit(1)

            case .taggedVisualAnchor(let idx, let text):
                Text("[TAGGED: VAN]")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.mint)
                Text("[\(idx + 1)]")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("\"\(text)\"")
                    .font(.system(size: 9))
                    .foregroundColor(.mint)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(4)
        .background(Color(.systemGray5))
        .cornerRadius(3)
    }

    // MARK: - Tab 1: Raw LLM (existing section cards)

    private func rawLLMTab(_ result: BatchVideoResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(result.sectionResults) { section in
                sectionCard(section)
            }
        }
    }

    // MARK: - Tab 2: Post-Processed

    private func processedTab(_ result: BatchVideoResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(result.sectionResults) { section in
                processedSectionCard(section)
            }
        }
    }

    private func processedSectionCard(_ section: BatchSectionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section header
            HStack(spacing: 6) {
                Text("Section \(section.sectionIndex + 1)")
                    .font(.caption.bold())
                Text(section.moveType)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.teal.opacity(0.15))
                    .foregroundColor(.teal)
                    .cornerRadius(3)
                Spacer()
                // Show processed metrics
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Text("Sig:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", section.postProcessedSignatureMatchRate * 100))
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundColor(section.postProcessedSignatureMatchRate >= 0.9 ? .green : .orange)
                    }
                    HStack(spacing: 2) {
                        Text("Oth:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", section.postProcessedOtherRate * 100))
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundColor(section.postProcessedOtherRate < 0.1 ? .green : .orange)
                    }
                }
            }

            // Post-processed sentence rows
            ForEach(section.postProcessedComparisons) { comp in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("[\(comp.sentenceIndex + 1)]")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(comp.rawText)
                            .font(.system(size: 10))
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f%%", comp.signatureConsistency * 100))
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundColor(comp.runsAgreedOnSignature ? .green : .orange)
                    }

                    // Show processed signature
                    Text(comp.dominantSignature)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 28)
                }
                .padding(4)
                .background(comp.runsAgreedOnSignature ? Color.clear : Color.orange.opacity(0.03))
                .cornerRadius(3)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Tab 3: Before/After Comparison

    private func comparisonTab(_ result: BatchVideoResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Global delta summary
            let rawSigAvg = result.avgSignatureMatchRate
            let ppSigAvg = result.sectionResults.isEmpty ? 0 :
                result.sectionResults.map(\.postProcessedSignatureMatchRate).reduce(0, +) / Double(result.sectionResults.count)
            let rawOtherAvg = result.sectionResults.isEmpty ? 0 :
                result.sectionResults.map(\.rawOtherRate).reduce(0, +) / Double(result.sectionResults.count)
            let ppOtherAvg = result.sectionResults.isEmpty ? 0 :
                result.sectionResults.map(\.postProcessedOtherRate).reduce(0, +) / Double(result.sectionResults.count)

            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("Other Rate")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f%%", rawOtherAvg * 100))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(.red)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", ppOtherAvg * 100))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(.green)
                    }
                }
                VStack(spacing: 2) {
                    Text("Sig Match")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f%%", rawSigAvg * 100))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(rawSigAvg >= 0.9 ? .green : .orange)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", ppSigAvg * 100))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(ppSigAvg >= 0.9 ? .green : .orange)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            // Per-section comparison
            ForEach(result.sectionResults) { section in
                comparisonSectionCard(section)
            }
        }
    }

    private func comparisonSectionCard(_ section: BatchSectionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Section \(section.sectionIndex + 1) — \(section.moveType)")
                    .font(.caption.bold())
                Spacer()
                // Delta badges
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Text("Oth:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%→%.0f%%", section.rawOtherRate * 100, section.postProcessedOtherRate * 100))
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundColor(section.postProcessedOtherRate < section.rawOtherRate ? .green : .secondary)
                    }
                    HStack(spacing: 2) {
                        Text("Sig:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%→%.0f%%", section.signatureMatchRate * 100, section.postProcessedSignatureMatchRate * 100))
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundColor(section.postProcessedSignatureMatchRate > section.signatureMatchRate ? .green : .secondary)
                    }
                }
            }

            // Side-by-side per sentence
            let rawComps = section.comparisons
            let ppComps = section.postProcessedComparisons

            ForEach(0..<min(rawComps.count, ppComps.count), id: \.self) { idx in
                let raw = rawComps[idx]
                let pp = ppComps[idx]
                let changed = raw.dominantSignature != pp.dominantSignature

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("[\(idx + 1)]")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(raw.rawText)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundColor(changed ? .primary : .secondary)
                        Spacer()
                        if changed {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 8))
                                .foregroundColor(.green)
                        }
                    }

                    if changed {
                        // Raw signature
                        HStack(spacing: 4) {
                            Text("RAW:")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.red.opacity(0.7))
                                .frame(width: 30, alignment: .leading)
                            Text(raw.dominantSignature)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.red.opacity(0.6))
                                .lineLimit(1)
                        }
                        .padding(.leading, 28)

                        // Processed signature
                        HStack(spacing: 4) {
                            Text("POST:")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.green.opacity(0.8))
                                .frame(width: 30, alignment: .leading)
                            Text(pp.dominantSignature)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.green.opacity(0.7))
                                .lineLimit(1)
                        }
                        .padding(.leading, 28)
                    }
                }
                .padding(4)
                .background(changed ? Color.green.opacity(0.03) : Color.clear)
                .cornerRadius(3)
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func rateLabel(_ label: String, _ rate: Double) -> some View {
        HStack(spacing: 3) {
            Text("\(label):")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.0f%%", rate * 100))
                .font(.caption.bold().monospacedDigit())
                .foregroundColor(rate >= 0.9 ? .green : (rate >= 0.7 ? .orange : .red))
        }
    }

    private func sectionCard(_ section: BatchSectionResult) -> some View {
        let isExpanded = expandedSections.contains(section.sectionIndex)

        return VStack(alignment: .leading, spacing: 6) {
            // Section header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedSections.remove(section.sectionIndex)
                    } else {
                        expandedSections.insert(section.sectionIndex)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Text("Section \(section.sectionIndex + 1)")
                        .font(.caption.bold())
                        .foregroundColor(.primary)

                    Text(section.moveType)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.teal.opacity(0.15))
                        .foregroundColor(.teal)
                        .cornerRadius(3)

                    Text(section.category)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(section.sentenceCount) sent")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Text(String(format: "%.0f%%", section.signatureMatchRate * 100))
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundColor(section.signatureMatchRate >= 0.9 ? .green : (section.signatureMatchRate >= 0.7 ? .orange : .red))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    // Metrics row
                    HStack(spacing: 12) {
                        rateLabel("Sig", section.signatureMatchRate)
                        rateLabel("Phr", section.phraseMatchRate)
                        rateLabel("Func", section.functionMatchRate)
                        if section.hintMismatchCount > 0 {
                            Text("\(section.hintMismatchCount) hint mismatches")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.leading, 18)

                    // Parse status warning for failed parses
                    if !section.debugParseSucceeded {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                            Text("LLM response failed to parse — results are fallback defaults")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                        .padding(.leading, 18)
                    }

                    // Sentence rows
                    ForEach(section.comparisons) { comp in
                        sentenceRow(comp, section: section)
                    }

                    // Debug: raw prompt/response
                    debugSection(section)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func sentenceRow(_ comp: SlotFidelitySentenceComparison, section: BatchSectionResult) -> some View {
        let sentenceKey = "\(section.sectionIndex)_\(comp.sentenceIndex)"
        let isSentenceExpanded = expandedSentences.contains(sentenceKey)

        return VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isSentenceExpanded {
                        expandedSentences.remove(sentenceKey)
                    } else {
                        expandedSentences.insert(sentenceKey)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("[\(comp.sentenceIndex + 1)]")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 24, alignment: .leading)

                    Text(comp.rawText)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    Spacer()

                    HStack(spacing: 2) {
                        ForEach(0..<comp.perRunSignatures.count, id: \.self) { runIdx in
                            Circle()
                                .fill(comp.perRunSignatures[runIdx] == comp.dominantSignature ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }

                    Text(String(format: "%.0f%%", comp.signatureConsistency * 100))
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundColor(comp.runsAgreedOnSignature ? .green : .orange)
                        .frame(width: 30, alignment: .trailing)

                    Image(systemName: isSentenceExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isSentenceExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // Per-run phrase badges
                    ForEach(0..<section.runs.count, id: \.self) { runIdx in
                        HStack(alignment: .top, spacing: 4) {
                            Text("R\(runIdx + 1):")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 28, alignment: .leading)

                            if comp.sentenceIndex < section.runs[runIdx].results.count {
                                let result = section.runs[runIdx].results[comp.sentenceIndex]
                                FlowLayout(spacing: 2) {
                                    ForEach(result.phrases.indices, id: \.self) { pIdx in
                                        let phrase = result.phrases[pIdx]
                                        Text(phrase.role)
                                            .font(.system(size: 8, weight: .medium))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(slotColor(phrase.role).opacity(0.15))
                                            .foregroundColor(slotColor(phrase.role))
                                            .cornerRadius(2)
                                    }
                                }
                            }
                        }
                    }

                    // Function comparison
                    HStack(spacing: 4) {
                        Text("Func:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                        ForEach(0..<comp.perRunFunctions.count, id: \.self) { idx in
                            Text(comp.perRunFunctions[idx])
                                .font(.system(size: 8))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(comp.runsAgreedOnFunction ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                                .cornerRadius(2)
                        }
                    }

                    // Hint mismatches
                    if !comp.hintMismatchesAcrossRuns.isEmpty {
                        ForEach(comp.hintMismatchesAcrossRuns, id: \.self) { mismatch in
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                                Text(mismatch)
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding(.leading, 30)
                .padding(.vertical, 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(4)
        .background(comp.runsAgreedOnSignature ? Color.clear : Color.orange.opacity(0.03))
        .cornerRadius(4)
    }

    // MARK: - Debug Section (Raw Prompt / Response)

    @ViewBuilder
    private func debugSection(_ section: BatchSectionResult) -> some View {
        let isDebugExpanded = expandedDebug.contains(section.sectionIndex)

        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isDebugExpanded {
                        expandedDebug.remove(section.sectionIndex)
                    } else {
                        expandedDebug.insert(section.sectionIndex)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isDebugExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Image(systemName: "ant.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.purple)
                    Text("Debug: Raw Prompt & Response")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.purple)
                    if !section.debugParseSucceeded {
                        Text("PARSE FAILED")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(3)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isDebugExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Response stats
                    HStack(spacing: 12) {
                        HStack(spacing: 3) {
                            Text("Response length:")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("\(section.debugRawResponse.count) chars")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundColor(section.debugRawResponse.count < 50 ? .red : .green)
                        }
                        HStack(spacing: 3) {
                            Text("Parse:")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(section.debugParseSucceeded ? "OK" : "FAILED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(section.debugParseSucceeded ? .green : .red)
                        }
                    }

                    // User Prompt (shorter, more relevant for debugging)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("User Prompt")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                            Spacer()
                            CompactCopyButton(text: section.debugUserPrompt)
                        }
                        ScrollView {
                            Text(section.debugUserPrompt)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        .padding(6)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    }

                    // Raw Response
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Raw LLM Response")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(section.debugParseSucceeded ? .green : .red)
                            Spacer()
                            CompactCopyButton(text: section.debugRawResponse)
                        }
                        ScrollView {
                            Text(section.debugRawResponse.isEmpty ? "(empty response)" : section.debugRawResponse)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(section.debugRawResponse.isEmpty ? .red : .primary.opacity(0.8))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                        .padding(6)
                        .background(section.debugParseSucceeded ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke((section.debugParseSucceeded ? Color.green : Color.red).opacity(0.2), lineWidth: 1)
                        )
                    }

                    // System Prompt (collapsed by default since it's the same for all)
                    DisclosureGroup {
                        ScrollView {
                            Text(section.debugSystemPrompt)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                        .padding(6)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                    } label: {
                        HStack {
                            Text("System Prompt (same for all sections)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            CompactCopyButton(text: section.debugSystemPrompt)
                        }
                    }
                }
                .padding(.leading, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, 18)
        .padding(.top, 4)
    }

    // Slot helpers (same as main view)
    private func slotColor(_ type: String) -> Color {
        switch type {
        case "geographic_location": return .blue
        case "visual_detail": return .cyan
        case "quantitative_claim": return .purple
        case "temporal_marker": return .orange
        case "actor_reference": return .green
        case "contradiction": return .red
        case "sensory_detail": return .mint
        case "rhetorical_question": return .pink
        case "evaluative_claim": return .yellow
        case "pivot_phrase": return .indigo
        case "direct_address": return .teal
        case "narrative_action": return .brown
        case "abstract_framing": return .gray
        case "comparison": return .purple
        case "empty_connector": return .gray
        case "factual_relay": return .cyan
        case "reaction_beat": return .pink
        case "visual_anchor": return .mint
        default: return .secondary
        }
    }
}
