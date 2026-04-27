//
//  DigressionChunkComparisonViewModel.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/27/26.
//

import Foundation
import SwiftUI

// MARK: - Sort Order

enum ChunkComparisonSortOrder: String, CaseIterable {
    case digressionCount = "Digressions"
    case chunkDelta = "Chunk Delta"
    case title = "Title"
}

// MARK: - Video Summary (Sidebar)

struct VideoDigressionSummary: Identifiable, Hashable {
    let id: String  // videoId
    let videoId: String
    let videoTitle: String
    let digressionCount: Int
    let digressedSentenceCount: Int
    let totalSentences: Int
    let originalChunkCount: Int
    let cleanedChunkCount: Int

    var chunkDelta: Int { originalChunkCount - cleanedChunkCount }

    var digressionPercent: Double {
        guard totalSentences > 0 else { return 0 }
        return Double(digressedSentenceCount) / Double(totalSentences) * 100.0
    }
}

// MARK: - Digression Range Info

struct DigressionRangeInfo: Identifiable {
    let id = UUID()
    let startSentence: Int
    let endSentence: Int
    let type: DigressionType
    let confidence: Double

    var sentenceRange: ClosedRange<Int> { startSentence...endSentence }

    func contains(_ sentenceIndex: Int) -> Bool {
        sentenceRange.contains(sentenceIndex)
    }
}

// MARK: - Chunk Comparison Data (Detail)

struct ChunkComparisonData {
    let videoId: String
    let videoTitle: String
    let allSentences: [SentenceTelemetry]
    let originalChunks: [Chunk]
    let cleanedChunks: [Chunk]
    let digressionRanges: [DigressionRangeInfo]
    let excludedIndices: Set<Int>

    // Lookup: sentenceIndex -> original chunk index
    private let originalChunkMap: [Int: Int]
    // Lookup: sentenceIndex -> cleaned chunk index
    private let cleanedChunkMap: [Int: Int]
    // Lookup: sentenceIndex -> boundary trigger (original)
    private let originalTriggerMap: [Int: BoundaryTrigger]
    // Lookup: sentenceIndex -> boundary trigger (cleaned)
    private let cleanedTriggerMap: [Int: BoundaryTrigger]

    init(
        videoId: String,
        videoTitle: String,
        allSentences: [SentenceTelemetry],
        originalChunks: [Chunk],
        cleanedChunks: [Chunk],
        digressionRanges: [DigressionRangeInfo],
        excludedIndices: Set<Int>
    ) {
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.allSentences = allSentences
        self.originalChunks = originalChunks
        self.cleanedChunks = cleanedChunks
        self.digressionRanges = digressionRanges
        self.excludedIndices = excludedIndices

        // Build original chunk lookup
        var origMap: [Int: Int] = [:]
        var origTriggers: [Int: BoundaryTrigger] = [:]
        for chunk in originalChunks {
            if let trigger = chunk.profile.boundaryTrigger {
                origTriggers[chunk.startSentence] = trigger
            }
            for sentence in chunk.sentences {
                origMap[sentence.sentenceIndex] = chunk.chunkIndex
            }
        }
        self.originalChunkMap = origMap
        self.originalTriggerMap = origTriggers

        // Build cleaned chunk lookup
        var cleanMap: [Int: Int] = [:]
        var cleanTriggers: [Int: BoundaryTrigger] = [:]
        for chunk in cleanedChunks {
            if let trigger = chunk.profile.boundaryTrigger {
                cleanTriggers[chunk.startSentence] = trigger
            }
            for sentence in chunk.sentences {
                cleanMap[sentence.sentenceIndex] = chunk.chunkIndex
            }
        }
        self.cleanedChunkMap = cleanMap
        self.cleanedTriggerMap = cleanTriggers
    }

    func originalChunkIndex(for sentenceIndex: Int) -> Int? {
        originalChunkMap[sentenceIndex]
    }

    func cleanedChunkIndex(for sentenceIndex: Int) -> Int? {
        cleanedChunkMap[sentenceIndex]
    }

    func isDigression(_ sentenceIndex: Int) -> Bool {
        excludedIndices.contains(sentenceIndex)
    }

    func digressionType(for sentenceIndex: Int) -> DigressionType? {
        digressionRanges.first { $0.contains(sentenceIndex) }?.type
    }

    /// Returns the boundary trigger if this sentence is the START of a chunk (original side)
    func originalBoundaryTrigger(at sentenceIndex: Int) -> BoundaryTrigger? {
        originalTriggerMap[sentenceIndex]
    }

    /// Returns the boundary trigger if this sentence is the START of a chunk (cleaned side)
    func cleanedBoundaryTrigger(at sentenceIndex: Int) -> BoundaryTrigger? {
        cleanedTriggerMap[sentenceIndex]
    }

    /// Whether this sentence is the first sentence of a chunk (original)
    func isOriginalChunkStart(_ sentenceIndex: Int) -> Bool {
        originalChunks.contains { $0.startSentence == sentenceIndex }
    }

    /// Whether this sentence is the first sentence of a chunk (cleaned)
    func isCleanedChunkStart(_ sentenceIndex: Int) -> Bool {
        cleanedChunks.contains { $0.startSentence == sentenceIndex }
    }
}

// MARK: - ViewModel

@MainActor
class DigressionChunkComparisonViewModel: ObservableObject {

    // MARK: - Published State

    @Published var videoSummaries: [VideoDigressionSummary] = []
    @Published var selectedVideoId: String?
    @Published var comparisonData: ChunkComparisonData?
    @Published var isLoadingList = false
    @Published var isLoadingComparison = false
    @Published var sortOrder: ChunkComparisonSortOrder = .digressionCount
    @Published var errorMessage: String?

    // MARK: - Dependencies

    let channel: YouTubeChannel
    private var batchResults: [BatchDigressionVideoResult] = []
    private var sentenceCache: [String: [SentenceTelemetry]] = [:]

    init(channel: YouTubeChannel) {
        self.channel = channel
    }

    // MARK: - Sorted/Filtered List

    var sortedSummaries: [VideoDigressionSummary] {
        switch sortOrder {
        case .digressionCount:
            return videoSummaries.sorted { $0.digressionCount > $1.digressionCount }
        case .chunkDelta:
            return videoSummaries.sorted { $0.chunkDelta > $1.chunkDelta }
        case .title:
            return videoSummaries.sorted {
                $0.videoTitle.localizedCaseInsensitiveCompare($1.videoTitle) == .orderedAscending
            }
        }
    }

    // MARK: - Load Video List

    func loadVideoList() async {
        guard videoSummaries.isEmpty else { return }
        isLoadingList = true
        errorMessage = nil

        do {
            // Load batch digression results for this channel
            let service = BatchDigressionAnalysisService()
            await service.loadResults(forChannelId: channel.channelId)
            batchResults = service.videoResults

            // Filter to only videos with at least 1 digression across runs
            let videosWithDigressions = batchResults.filter { result in
                !result.runs.isEmpty && result.runs.contains { !$0.digressions.isEmpty }
            }

            guard !videosWithDigressions.isEmpty else {
                isLoadingList = false
                return
            }

            // Batch-load sentence data for all videos
            let videoIds = videosWithDigressions.map(\.videoId)
            let sentenceData = try await SentenceFidelityFirebaseService.shared
                .getTestRunsForVideos(videoIds)

            // Build summaries — compute original + cleaned chunks for each
            var summaries: [VideoDigressionSummary] = []

            for result in videosWithDigressions {
                guard let tests = sentenceData[result.videoId],
                      let latestTest = tests.first else { continue }

                let sentences = latestTest.sentences

                // Get digressions from cross-run regions (most stable)
                let regions = CrossRunDigressionRegion.buildRegions(from: result.runs)
                guard !regions.isEmpty else { continue }

                // Build exclude set from regions
                let excludeSet = buildExcludeSetFromRegions(regions)
                let digressedCount = excludeSet.count

                // Compute original chunks
                let originalChunks = BoundaryDetectionService.shared
                    .detectBoundaries(from: sentences)

                // Compute cleaned chunks
                let cleanedChunks = BoundaryDetectionService.shared
                    .detectBoundaries(from: sentences, excludeIndices: excludeSet)

                // Cache sentences for later detail loading
                sentenceCache[result.videoId] = sentences

                summaries.append(VideoDigressionSummary(
                    id: result.videoId,
                    videoId: result.videoId,
                    videoTitle: result.videoTitle,
                    digressionCount: regions.count,
                    digressedSentenceCount: digressedCount,
                    totalSentences: sentences.count,
                    originalChunkCount: originalChunks.count,
                    cleanedChunkCount: cleanedChunks.count
                ))
            }

            videoSummaries = summaries
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
            print("DigressionChunkComparison load error: \(error)")
        }

        isLoadingList = false
    }

    // MARK: - Select Video (Load Comparison)

    func selectVideo(_ videoId: String) async {
        print("🔍 [ChunkComparison] selectVideo called with: \(videoId)")
        // Don't re-load if we already have comparison data for this video
        if videoId == comparisonData?.videoId {
            print("🔍 [ChunkComparison] Already loaded, skipping")
            return
        }
        isLoadingComparison = true
        comparisonData = nil

        print("🔍 [ChunkComparison] batchResults count: \(batchResults.count)")
        guard let result = batchResults.first(where: { $0.videoId == videoId }) else {
            print("❌ [ChunkComparison] No batch result found for videoId: \(videoId)")
            isLoadingComparison = false
            return
        }
        print("✅ [ChunkComparison] Found batch result: \(result.videoTitle), runs: \(result.runs.count)")

        // Get sentences (from cache or Firebase)
        let sentences: [SentenceTelemetry]
        if let cached = sentenceCache[videoId] {
            sentences = cached
        } else {
            do {
                let tests = try await SentenceFidelityFirebaseService.shared
                    .getTestRuns(forVideoId: videoId)
                guard let latest = tests.first else {
                    isLoadingComparison = false
                    return
                }
                sentences = latest.sentences
                sentenceCache[videoId] = sentences
            } catch {
                errorMessage = "Failed to load sentences: \(error.localizedDescription)"
                isLoadingComparison = false
                return
            }
        }

        print("✅ [ChunkComparison] Got \(sentences.count) sentences")

        // Build digression regions + exclude set
        let regions = CrossRunDigressionRegion.buildRegions(from: result.runs)
        let excludeSet = buildExcludeSetFromRegions(regions)
        print("✅ [ChunkComparison] \(regions.count) regions, \(excludeSet.count) excluded sentences")

        // Convert regions to DigressionRangeInfo
        let digressionRanges = regions.map { region in
            DigressionRangeInfo(
                startSentence: region.mergedStart,
                endSentence: region.mergedEnd,
                type: region.primaryType,
                confidence: region.consistency
            )
        }

        // Compute chunks
        let originalChunks = BoundaryDetectionService.shared
            .detectBoundaries(from: sentences)
        let cleanedChunks = BoundaryDetectionService.shared
            .detectBoundaries(from: sentences, excludeIndices: excludeSet)

        print("✅ [ChunkComparison] Original: \(originalChunks.count) chunks, Cleaned: \(cleanedChunks.count) chunks")

        comparisonData = ChunkComparisonData(
            videoId: videoId,
            videoTitle: result.videoTitle,
            allSentences: sentences,
            originalChunks: originalChunks,
            cleanedChunks: cleanedChunks,
            digressionRanges: digressionRanges,
            excludedIndices: excludeSet
        )

        print("✅ [ChunkComparison] comparisonData set, isLoadingComparison -> false")
        isLoadingComparison = false
    }

    // MARK: - Helpers

    /// Build exclude set from cross-run regions (uses merged boundaries)
    private func buildExcludeSetFromRegions(_ regions: [CrossRunDigressionRegion]) -> Set<Int> {
        var indices = Set<Int>()
        for region in regions {
            for i in region.mergedStart...region.mergedEnd {
                indices.insert(i)
            }
        }
        return indices
    }
}
