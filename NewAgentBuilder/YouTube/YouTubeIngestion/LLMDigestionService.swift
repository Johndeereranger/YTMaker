//
//  LLMDigestionService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/4/26.
//

import Foundation
import Combine
import FirebaseFirestore

/// Orchestrates the LLM-based digestion pipeline:
/// 1. Parse transcript → sentences
/// 2. LLM digression detection
/// 3. Legacy splitter on clean transcript → section boundaries
/// 4. Build chunks from boundaries → Rhetorical moves extraction
///
/// Skips per-sentence rhetorical tagging entirely.
@MainActor
class LLMDigestionService: ObservableObject {

    static let shared = LLMDigestionService()

    // MARK: - Published State

    @Published var isRunning = false
    @Published var progress = ""
    @Published var currentStep = ""
    @Published var completedVideos = 0
    @Published var totalVideos = 0
    @Published var perVideoProgress: [String: String] = [:]

    // Concurrency limits (tuned per step based on LLM calls per video)
    private let maxConcurrentDigression = 15    // 1 LLM call per video
    private let maxConcurrentBoundaries = 3     // ~65 LLM calls per video (splitter windows)
    private let maxConcurrentMoves = 5          // ~5-15 LLM calls per video (one per chunk)

    private init() {}

    // MARK: - Full Pipeline (Single Video)

    /// Run the complete LLM pipeline for one video:
    /// parse → digression → strip → split → chunk → moves → save
    func processVideo(
        video: YouTubeVideo,
        channelId: String,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> RhetoricalSequence {
        guard let transcript = video.transcript, !transcript.isEmpty else {
            throw LLMPipelineError.noTranscript
        }

        // Step 1: Parse transcript into sentences
        onProgress?("Parsing sentences...")
        let sentences = SentenceParser.parse(transcript)
        guard !sentences.isEmpty else {
            throw LLMPipelineError.noSentences
        }
        print("[LLMPipeline] \(video.videoId): \(sentences.count) sentences parsed")

        // Step 2: Detect digressions — reuse existing if already saved
        let lightweightTelemetry = makeLightweightTelemetry(sentences: sentences)
        let digressions: [DigressionAnnotation]

        let existingResult = CreatorDetailViewModel.shared.batchDigressionService.videoResults.first(where: { $0.videoId == video.videoId })
        if let existing = existingResult, let run = existing.runs.first {
            digressions = run.digressions
            print("[LLMPipeline] \(video.videoId): Reusing \(digressions.count) existing digressions (skipping LLM)")
        } else {
            onProgress?("Detecting digressions (LLM)...")
            digressions = await DigressionLLMDetector.shared.detectDigressions(
                sentences: lightweightTelemetry,
                enabledTypes: Set(DigressionType.allCases),
                temperature: 0.3,
                onProgress: onProgress
            )
            print("[LLMPipeline] \(video.videoId): \(digressions.count) digressions found")

            // Save new digression results to Firebase
            try await saveDigressionResult(
                videoId: video.videoId,
                videoTitle: video.title,
                channelId: channelId,
                digressions: digressions,
                totalSentences: sentences.count
            )
        }

        // Step 3: Build exclude set and run legacy splitter (window 10, step 3)
        onProgress?("Running legacy splitter...")
        let excludeSet = DigressionDetectionService.shared.buildExcludeSet(from: digressions)
        let splitterResult = try await SectionSplitterService.shared.runSplitter(
            transcript: transcript,
            windowSize: 10,
            stepSize: 3,
            temperature: 0.3,
            promptVariant: .legacy,
            excludeIndices: excludeSet,
            onProgress: { completed, total, phase in
                onProgress?("Boundaries (\(phase): \(completed)/\(total))")
            }
        )
        print("[LLMPipeline] \(video.videoId): \(splitterResult.boundaries.count) boundaries found")

        // Step 4: Build chunks from boundaries
        let cleanTelemetry = lightweightTelemetry.filter { !excludeSet.contains($0.sentenceIndex) }
        let boundaryIndices = splitterResult.boundaries.map { $0.sentenceNumber }
        let chunks = buildChunksFromBoundaries(
            sentences: cleanTelemetry,
            boundaryNumbers: boundaryIndices
        )
        guard !chunks.isEmpty else {
            throw LLMPipelineError.noChunks
        }
        print("[LLMPipeline] \(video.videoId): \(chunks.count) chunks built")

        // Save boundary result to Firebase (fire-and-forget: don't kill pipeline on save failure)
        do {
            let chunkRecords = buildChunkRecords(from: chunks)
            let boundaryResult = LLMBoundaryVideoResult(
                channelId: channelId,
                videoId: video.videoId,
                videoTitle: video.title,
                boundaries: splitterResult.boundaries,
                chunks: chunkRecords,
                totalSentences: sentences.count,
                cleanSentenceCount: cleanTelemetry.count,
                excludedSentenceIndices: Array(excludeSet),
                splitterConfig: LLMSplitterConfig(
                    windowSize: 10, stepSize: 3, temperature: 0.3,
                    promptVariant: "legacy",
                    boundaryCount: splitterResult.boundaries.count
                )
            )
            try await CreatorDetailViewModel.shared.llmBoundaryService.saveResult(boundaryResult)
        } catch {
            print("[LLMPipeline] WARNING: Boundary save failed for \(video.videoId) — continuing to moves: \(error)")
        }

        // Step 5: Extract rhetorical moves
        onProgress?("Extracting rhetorical moves...")
        let sequence = try await RhetoricalMoveService.shared.extractRhetoricalSequence(
            videoId: video.videoId,
            chunks: chunks,
            temperature: 0.1
        )
        print("[LLMPipeline] \(video.videoId): \(sequence.moves.count) moves extracted")

        // Copy-construct moves with sentence ranges from chunks
        let enrichedSequence = enrichMovesWithSentenceRanges(sequence: sequence, chunks: chunks)

        // Save rhetorical sequence to Firebase
        onProgress?("Saving to Firebase...")
        try await YouTubeFirebaseService.shared.saveRhetoricalSequence(
            videoId: video.videoId,
            sequence: enrichedSequence
        )

        return enrichedSequence
    }

    // MARK: - Batch Pipeline

    /// Run the full LLM pipeline for a limited number of eligible videos
    func runFullPipeline(videos: [YouTubeVideo], limit: Int) async {
        let eligible = Array(videos.filter { $0.hasTranscript && $0.rhetoricalSequence == nil }.prefix(limit))
        guard !eligible.isEmpty else {
            progress = "No videos ready for LLM pipeline"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }
        await runFullPipeline(eligibleVideos: eligible)
    }

    /// Run the full LLM pipeline for all eligible videos
    func runFullPipeline(videos: [YouTubeVideo]) async {
        let eligible = videos.filter { $0.hasTranscript && $0.rhetoricalSequence == nil }
        guard !eligible.isEmpty else {
            progress = "No videos ready for LLM pipeline"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }
        await runFullPipeline(eligibleVideos: eligible)
    }

    /// Core full pipeline runner — takes pre-filtered eligible list
    private func runFullPipeline(eligibleVideos eligible: [YouTubeVideo]) async {
        guard let channelId = CreatorDetailViewModel.shared.currentChannel?.channelId, !channelId.isEmpty else {
            print("[LLMPipeline] ERROR: No channel selected — cannot save results")
            progress = "Error: No channel selected"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }

        // Sort smallest transcripts first for fastest feedback & fewer partial runs on exit
        let sorted = eligible.sorted { ($0.transcript?.count ?? Int.max) < ($1.transcript?.count ?? Int.max) }

        isRunning = true
        totalVideos = sorted.count
        completedVideos = 0
        progress = "Starting \(sorted.count) videos..."

        print("\n========================================")
        print("LLM DIGESTION PIPELINE - FULL RUN")
        print("========================================")
        // Full pipeline: use boundary concurrency (the bottleneck step)
        let concurrency = maxConcurrentBoundaries
        print("Videos: \(sorted.count), Max concurrent: \(concurrency)")

        let tracker = PipelineTracker()

        await withTaskGroup(of: Void.self) { group in
            var iterator = sorted.makeIterator()

            // Seed initial batch
            for _ in 0..<min(concurrency, eligible.count) {
                if let video = iterator.next() {
                    group.addTask { [weak self] in
                        await self?.runSingleVideoInPipeline(
                            video: video,
                            channelId: channelId,
                            tracker: tracker
                        )
                    }
                }
            }

            // As each completes, launch the next
            for await _ in group {
                let stats = await tracker.getStats()
                completedVideos = stats.completed
                progress = "[\(stats.completed + stats.failed)/\(totalVideos)] processing..."

                if let video = iterator.next() {
                    group.addTask { [weak self] in
                        await self?.runSingleVideoInPipeline(
                            video: video,
                            channelId: channelId,
                            tracker: tracker
                        )
                    }
                }
            }
        }

        let finalStats = await tracker.getStats()
        print("[LLMPipeline] Complete: \(finalStats.completed) success, \(finalStats.failed) failed")

        progress = "Done: \(finalStats.completed) success, \(finalStats.failed) failed"
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Reload everything (videos + all services) so UI reflects saved data
        await CreatorDetailViewModel.shared.loadVideos()

        isRunning = false
        progress = ""
        currentStep = ""
        perVideoProgress = [:]
    }

    /// Internal: run one video through the full pipeline, updating tracker
    private func runSingleVideoInPipeline(
        video: YouTubeVideo,
        channelId: String,
        tracker: PipelineTracker
    ) async {
        do {
            let sequence = try await processVideo(video: video, channelId: channelId) { stepProgress in
                Task { @MainActor in
                    self.perVideoProgress[video.videoId] = stepProgress
                }
            }
            await tracker.markCompleted(videoId: video.videoId, moveCount: sequence.moves.count)
            print("[LLMPipeline] Done: \(video.title)")
        } catch {
            await tracker.markFailed()
            print("[LLMPipeline] Failed: \(video.title) - \(error)")
        }
        Task { @MainActor in
            self.perVideoProgress.removeValue(forKey: video.videoId)
        }
    }

    // MARK: - Limited Run Helpers

    /// Run digression for a limited number of eligible videos
    func runDigressionOnly(videos: [YouTubeVideo], limit: Int) async {
        let existingIds = Set(CreatorDetailViewModel.shared.batchDigressionService.videoResults.map { $0.videoId })
        let eligible = Array(videos.filter { $0.hasTranscript && !existingIds.contains($0.videoId) }.prefix(limit))
        guard !eligible.isEmpty else {
            progress = "No videos ready for digressions"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }
        await runDigressionOnly(eligibleVideos: eligible)
    }

    /// Run boundaries for a limited number of eligible videos
    func runBoundariesOnly(videos: [YouTubeVideo], limit: Int) async {
        let digressionService = CreatorDetailViewModel.shared.batchDigressionService
        let boundaryService = CreatorDetailViewModel.shared.llmBoundaryService
        let existingDigressionIds = Set(digressionService.videoResults.map { $0.videoId })
        let existingBoundaryIds = Set(boundaryService.videoResults.map { $0.videoId })
        let eligible = Array(videos.filter {
            $0.hasTranscript &&
            existingDigressionIds.contains($0.videoId) &&
            !existingBoundaryIds.contains($0.videoId)
        }.prefix(limit))
        guard !eligible.isEmpty else {
            progress = "No videos ready for boundaries"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }
        await runBoundariesOnly(eligibleVideos: eligible)
    }

    /// Run moves for a limited number of eligible videos
    func runMovesOnly(videos: [YouTubeVideo], limit: Int) async {
        let boundaryService = CreatorDetailViewModel.shared.llmBoundaryService
        let eligible = Array(videos.filter {
            $0.rhetoricalSequence == nil &&
            boundaryService.hasBoundaries(forVideoId: $0.videoId)
        }.prefix(limit))
        guard !eligible.isEmpty else {
            progress = "No videos ready for moves"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }
        await runMovesOnly(eligibleVideos: eligible)
    }

    // MARK: - Digression Only (Parallel)

    /// Run digression detection for all eligible videos (15 concurrent), saving results to Firebase
    func runDigressionOnly(videos: [YouTubeVideo]) async {
        let existingIds = Set(CreatorDetailViewModel.shared.batchDigressionService.videoResults.map { $0.videoId })
        let eligible = videos.filter { $0.hasTranscript && !existingIds.contains($0.videoId) }
        guard !eligible.isEmpty else {
            progress = "All videos already have digressions"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }
        await runDigressionOnly(eligibleVideos: eligible)
    }

    /// Core digression runner — takes pre-filtered eligible list
    private func runDigressionOnly(eligibleVideos eligible: [YouTubeVideo]) async {
        guard let channelId = CreatorDetailViewModel.shared.currentChannel?.channelId, !channelId.isEmpty else {
            print("[LLMPipeline] ERROR: No channel selected — cannot save digression results")
            progress = "Error: No channel selected"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }

        // Sort smallest transcripts first
        let sorted = eligible.sorted { ($0.transcript?.count ?? Int.max) < ($1.transcript?.count ?? Int.max) }

        isRunning = true
        totalVideos = sorted.count
        completedVideos = 0
        currentStep = "Digression"
        progress = "Detecting digressions for \(sorted.count) videos..."

        print("\n========================================")
        print("LLM PIPELINE - DIGRESSION ONLY")
        print("========================================")
        print("Videos: \(sorted.count), Max concurrent: \(maxConcurrentDigression)")

        let tracker = PipelineTracker()

        await withTaskGroup(of: Void.self) { group in
            var iterator = sorted.makeIterator()

            // Seed initial batch
            for _ in 0..<min(maxConcurrentDigression, eligible.count) {
                if let video = iterator.next() {
                    group.addTask { [weak self] in
                        await self?.runSingleDigression(
                            video: video,
                            channelId: channelId,
                            tracker: tracker
                        )
                    }
                }
            }

            // As each completes, launch the next
            for await _ in group {
                let stats = await tracker.getStats()
                completedVideos = stats.completed
                progress = "[\(stats.completed + stats.failed)/\(totalVideos)] detecting digressions..."

                if let video = iterator.next() {
                    group.addTask { [weak self] in
                        await self?.runSingleDigression(
                            video: video,
                            channelId: channelId,
                            tracker: tracker
                        )
                    }
                }
            }
        }

        let finalStats = await tracker.getStats()
        print("[LLMPipeline] Digression complete: \(finalStats.completed) success, \(finalStats.failed) failed")

        // Reload digression results so UI reflects them
        if let channel = CreatorDetailViewModel.shared.currentChannel {
            await CreatorDetailViewModel.shared.batchDigressionService.loadResults(forChannelId: channel.channelId)
        }

        progress = "Done: \(finalStats.completed) success, \(finalStats.failed) failed"
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        isRunning = false
        progress = ""
        currentStep = ""
        perVideoProgress = [:]
    }

    /// Internal: run digression for one video and save to Firebase
    private func runSingleDigression(
        video: YouTubeVideo,
        channelId: String,
        tracker: PipelineTracker
    ) async {
        guard let transcript = video.transcript, !transcript.isEmpty else {
            await tracker.markFailed()
            return
        }

        Task { @MainActor in
            self.perVideoProgress[video.videoId] = "Detecting..."
        }

        let sentences = SentenceParser.parse(transcript)
        let telemetry = makeLightweightTelemetry(sentences: sentences)
        let digressions = await DigressionLLMDetector.shared.detectDigressions(
            sentences: telemetry,
            enabledTypes: Set(DigressionType.allCases),
            temperature: 0.3
        )

        // Save to Firebase
        do {
            try await saveDigressionResult(
                videoId: video.videoId,
                videoTitle: video.title,
                channelId: channelId,
                digressions: digressions,
                totalSentences: sentences.count
            )
            await tracker.markCompleted(videoId: video.videoId, moveCount: 0)
            print("[LLMPipeline] Digression saved: \(video.title) (\(digressions.count) found)")
        } catch {
            await tracker.markFailed()
            print("[LLMPipeline] Digression save failed: \(video.title) - \(error)")
        }

        Task { @MainActor in
            self.perVideoProgress.removeValue(forKey: video.videoId)
        }
    }

    // MARK: - Boundaries Only (Parallel)

    /// Run boundary detection for all eligible videos (3 concurrent — splitter uses ~65 LLM calls per video)
    func runBoundariesOnly(videos: [YouTubeVideo]) async {
        let digressionService = CreatorDetailViewModel.shared.batchDigressionService
        let boundaryService = CreatorDetailViewModel.shared.llmBoundaryService
        let existingDigressionIds = Set(digressionService.videoResults.map { $0.videoId })
        let existingBoundaryIds = Set(boundaryService.videoResults.map { $0.videoId })

        let eligible = videos.filter {
            $0.hasTranscript &&
            existingDigressionIds.contains($0.videoId) &&
            !existingBoundaryIds.contains($0.videoId)
        }
        guard !eligible.isEmpty else {
            progress = "No videos ready for boundaries"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }
        await runBoundariesOnly(eligibleVideos: eligible)
    }

    /// Core boundary runner — takes pre-filtered eligible list
    private func runBoundariesOnly(eligibleVideos eligible: [YouTubeVideo]) async {
        guard let channelId = CreatorDetailViewModel.shared.currentChannel?.channelId, !channelId.isEmpty else {
            print("[LLMPipeline] ERROR: No channel selected")
            progress = "Error: No channel selected"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }

        // Sort smallest transcripts first
        let sorted = eligible.sorted { ($0.transcript?.count ?? Int.max) < ($1.transcript?.count ?? Int.max) }

        isRunning = true
        totalVideos = sorted.count
        completedVideos = 0
        currentStep = "Boundaries"
        progress = "Splitting \(sorted.count) videos..."

        print("\n========================================")
        print("LLM PIPELINE - BOUNDARIES ONLY")
        print("========================================")
        print("Videos: \(sorted.count), Max concurrent: \(maxConcurrentBoundaries)")

        let tracker = PipelineTracker()

        await withTaskGroup(of: Void.self) { group in
            var iterator = sorted.makeIterator()

            for _ in 0..<min(maxConcurrentBoundaries, eligible.count) {
                if let video = iterator.next() {
                    group.addTask { [weak self] in
                        await self?.runSingleBoundary(
                            video: video,
                            channelId: channelId,
                            tracker: tracker
                        )
                    }
                }
            }

            for await _ in group {
                let stats = await tracker.getStats()
                completedVideos = stats.completed
                progress = "[\(stats.completed + stats.failed)/\(totalVideos)] splitting..."

                if let video = iterator.next() {
                    group.addTask { [weak self] in
                        await self?.runSingleBoundary(
                            video: video,
                            channelId: channelId,
                            tracker: tracker
                        )
                    }
                }
            }
        }

        let finalStats = await tracker.getStats()
        print("[LLMPipeline] Boundaries complete: \(finalStats.completed) success, \(finalStats.failed) failed")

        if let channel = CreatorDetailViewModel.shared.currentChannel {
            await CreatorDetailViewModel.shared.llmBoundaryService.loadResults(forChannelId: channel.channelId)
        }

        progress = "Done: \(finalStats.completed) success, \(finalStats.failed) failed"
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        isRunning = false
        progress = ""
        currentStep = ""
        perVideoProgress = [:]
    }

    /// Internal: run boundary detection for one video
    private func runSingleBoundary(
        video: YouTubeVideo,
        channelId: String,
        tracker: PipelineTracker
    ) async {
        guard let transcript = video.transcript, !transcript.isEmpty else {
            await tracker.markFailed()
            return
        }

        Task { @MainActor in
            self.perVideoProgress[video.videoId] = "Splitting..."
        }

        do {
            // Load existing digressions
            let digressionService = CreatorDetailViewModel.shared.batchDigressionService
            guard let digressionResult = digressionService.videoResults.first(where: { $0.videoId == video.videoId }),
                  let run = digressionResult.runs.first else {
                await tracker.markFailed()
                print("[LLMPipeline] No digression data for \(video.title)")
                return
            }

            let sentences = SentenceParser.parse(transcript)
            let excludeSet = DigressionDetectionService.shared.buildExcludeSet(from: run.digressions)

            // Run splitter
            let splitterResult = try await SectionSplitterService.shared.runSplitter(
                transcript: transcript,
                windowSize: 10,
                stepSize: 3,
                temperature: 0.3,
                promptVariant: .legacy,
                excludeIndices: excludeSet,
                onProgress: { completed, total, phase in
                    Task { @MainActor in
                        self.perVideoProgress[video.videoId] = "Splitting (\(phase): \(completed)/\(total))"
                    }
                }
            )

            // Build chunks and save
            let lightweightTelemetry = makeLightweightTelemetry(sentences: sentences)
            let cleanTelemetry = lightweightTelemetry.filter { !excludeSet.contains($0.sentenceIndex) }
            let boundaryIndices = splitterResult.boundaries.map { $0.sentenceNumber }
            let chunks = buildChunksFromBoundaries(sentences: cleanTelemetry, boundaryNumbers: boundaryIndices)
            let chunkRecords = buildChunkRecords(from: chunks)

            let boundaryResult = LLMBoundaryVideoResult(
                channelId: channelId,
                videoId: video.videoId,
                videoTitle: video.title,
                boundaries: splitterResult.boundaries,
                chunks: chunkRecords,
                totalSentences: sentences.count,
                cleanSentenceCount: cleanTelemetry.count,
                excludedSentenceIndices: Array(excludeSet),
                splitterConfig: LLMSplitterConfig(
                    windowSize: 10, stepSize: 3, temperature: 0.3,
                    promptVariant: "legacy",
                    boundaryCount: splitterResult.boundaries.count
                )
            )

            try await CreatorDetailViewModel.shared.llmBoundaryService.saveResult(boundaryResult)
            await tracker.markCompleted(videoId: video.videoId, moveCount: 0)
            print("[LLMPipeline] Boundary saved: \(video.title) (\(chunks.count) chunks)")

        } catch {
            await tracker.markFailed()
            print("[LLMPipeline] Boundary failed: \(video.title) - \(error)")
        }

        Task { @MainActor in
            self.perVideoProgress.removeValue(forKey: video.videoId)
        }
    }

    // MARK: - Moves Only (Parallel)

    /// Run rhetorical move extraction for all eligible videos (5 concurrent)
    func runMovesOnly(videos: [YouTubeVideo]) async {
        let boundaryService = CreatorDetailViewModel.shared.llmBoundaryService
        let eligible = videos.filter {
            $0.rhetoricalSequence == nil &&
            boundaryService.hasBoundaries(forVideoId: $0.videoId)
        }
        guard !eligible.isEmpty else {
            progress = "No videos ready for moves"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }
        await runMovesOnly(eligibleVideos: eligible)
    }

    /// Core moves runner — takes pre-filtered eligible list
    private func runMovesOnly(eligibleVideos eligible: [YouTubeVideo]) async {
        // Sort smallest transcripts first
        let sorted = eligible.sorted { ($0.transcript?.count ?? Int.max) < ($1.transcript?.count ?? Int.max) }

        isRunning = true
        totalVideos = sorted.count
        completedVideos = 0
        currentStep = "Moves"
        progress = "Extracting moves for \(sorted.count) videos..."

        print("\n========================================")
        print("LLM PIPELINE - MOVES ONLY")
        print("========================================")
        print("Videos: \(sorted.count), Max concurrent: \(maxConcurrentMoves)")

        let tracker = PipelineTracker()

        await withTaskGroup(of: Void.self) { group in
            var iterator = sorted.makeIterator()

            for _ in 0..<min(maxConcurrentMoves, eligible.count) {
                if let video = iterator.next() {
                    group.addTask { [weak self] in
                        await self?.runSingleMoveExtraction(video: video, tracker: tracker)
                    }
                }
            }

            for await _ in group {
                let stats = await tracker.getStats()
                completedVideos = stats.completed
                progress = "[\(stats.completed + stats.failed)/\(totalVideos)] extracting moves..."

                if let video = iterator.next() {
                    group.addTask { [weak self] in
                        await self?.runSingleMoveExtraction(video: video, tracker: tracker)
                    }
                }
            }
        }

        let finalStats = await tracker.getStats()
        print("[LLMPipeline] Moves complete: \(finalStats.completed) success, \(finalStats.failed) failed")

        progress = "Done: \(finalStats.completed) success, \(finalStats.failed) failed"
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        await CreatorDetailViewModel.shared.loadVideos()

        isRunning = false
        progress = ""
        currentStep = ""
        perVideoProgress = [:]
    }

    /// Internal: extract moves for one video using saved boundary data
    private func runSingleMoveExtraction(
        video: YouTubeVideo,
        tracker: PipelineTracker
    ) async {
        Task { @MainActor in
            self.perVideoProgress[video.videoId] = "Extracting..."
        }

        do {
            let boundaryService = CreatorDetailViewModel.shared.llmBoundaryService
            guard let boundaryResult = boundaryService.result(forVideoId: video.videoId) else {
                await tracker.markFailed()
                print("[LLMPipeline] No boundary data for \(video.title)")
                return
            }

            // Reconstruct chunks from saved boundary data
            let chunks = chunksFromBoundaryResult(boundaryResult)
            guard !chunks.isEmpty else {
                await tracker.markFailed()
                print("[LLMPipeline] No chunks from boundary data for \(video.title)")
                return
            }

            // Extract moves
            let sequence = try await RhetoricalMoveService.shared.extractRhetoricalSequence(
                videoId: video.videoId,
                chunks: chunks,
                temperature: 0.1
            )

            // Copy-construct moves with sentence ranges
            let enrichedSequence = enrichMovesWithSentenceRanges(sequence: sequence, chunks: chunks)

            // Save
            try await YouTubeFirebaseService.shared.saveRhetoricalSequence(
                videoId: video.videoId,
                sequence: enrichedSequence
            )

            await tracker.markCompleted(videoId: video.videoId, moveCount: enrichedSequence.moves.count)
            print("[LLMPipeline] Moves saved: \(video.title) (\(enrichedSequence.moves.count) moves)")

        } catch {
            await tracker.markFailed()
            print("[LLMPipeline] Moves failed: \(video.title) - \(error)")
        }

        Task { @MainActor in
            self.perVideoProgress.removeValue(forKey: video.videoId)
        }
    }

    // MARK: - Partial Boundary Rerun

    /// Detect boundary results where chunks don't cover all clean sentences
    static func findPartialBoundaryResults() -> [LLMBoundaryVideoResult] {
        CreatorDetailViewModel.shared.llmBoundaryService.videoResults.filter { result in
            let coveredSentences = result.chunks.reduce(0) { $0 + $1.sentenceCount }
            return coveredSentences < result.cleanSentenceCount
        }
    }

    // MARK: - Demote (Strip Pipeline Data, Keep Transcript)

    /// Demote a single video back to transcript-only by deleting stages 2-4 data.
    /// Returns a summary string of what was deleted.
    func demoteVideo(video: YouTubeVideo, channelId: String) async -> String {
        var deleted: [String] = []

        // Stage 2: Digression
        let digressionService = CreatorDetailViewModel.shared.batchDigressionService
        if digressionService.videoResults.contains(where: { $0.videoId == video.videoId }) {
            do {
                try await digressionService.deleteResult(forVideoId: video.videoId, channelId: channelId)
                deleted.append("digression")
            } catch {
                print("[Demote] Failed to delete digression for \(video.title): \(error)")
            }
        }

        // Stage 3: Boundaries
        let boundaryService = CreatorDetailViewModel.shared.llmBoundaryService
        if boundaryService.result(forVideoId: video.videoId) != nil {
            do {
                try await boundaryService.deleteResult(forVideoId: video.videoId, channelId: channelId)
                deleted.append("boundaries")
            } catch {
                print("[Demote] Failed to delete boundaries for \(video.title): \(error)")
            }
        }

        // Stage 4: Rhetorical Moves
        if video.rhetoricalSequence != nil {
            do {
                try await YouTubeFirebaseService.shared.clearRhetoricalSequence(forVideoId: video.videoId)
                deleted.append("moves")
            } catch {
                print("[Demote] Failed to clear rhetorical sequence for \(video.title): \(error)")
            }
        }

        let summary = deleted.isEmpty ? "nothing to demote" : "deleted: \(deleted.joined(separator: ", "))"
        print("[Demote] \(video.title) → \(summary)")
        return summary
    }

    /// Demote multiple videos by title, matching case-insensitively against the provided video list.
    func demoteVideos(titles: [String], videos: [YouTubeVideo], channelId: String) async {
        isRunning = true
        progress = "Matching titles..."

        // Match titles to video objects
        var matched: [YouTubeVideo] = []
        var unmatched: [String] = []

        // Normalize curly apostrophes to straight for matching
        func normalize(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: "\u{2019}", with: "'")  // '
                .replacingOccurrences(of: "\u{2018}", with: "'")  // '
        }

        for title in titles {
            let normalTitle = normalize(title)
            if let video = videos.first(where: { normalize($0.title) == normalTitle }) {
                matched.append(video)
            } else if let video = videos.first(where: { normalize($0.title).contains(normalTitle) || normalTitle.contains(normalize($0.title)) }) {
                matched.append(video)
                print("[Demote] Fuzzy match: '\(title)' → '\(video.title)'")
            } else {
                unmatched.append(title)
            }
        }

        if !unmatched.isEmpty {
            print("[Demote] WARNING: \(unmatched.count) unmatched titles:")
            for t in unmatched { print("  - \(t)") }
        }

        progress = "Demoting 0/\(matched.count)..."
        var demotedCount = 0

        for (i, video) in matched.enumerated() {
            progress = "Demoting \(i + 1)/\(matched.count): \(video.title)"
            let result = await demoteVideo(video: video, channelId: channelId)
            if result != "nothing to demote" {
                demotedCount += 1
            }
        }

        // Reload so UI reflects changes
        await CreatorDetailViewModel.shared.loadVideos()
        if let channel = CreatorDetailViewModel.shared.currentChannel {
            await CreatorDetailViewModel.shared.batchDigressionService.loadResults(forChannelId: channel.channelId)
            await CreatorDetailViewModel.shared.llmBoundaryService.loadResults(forChannelId: channel.channelId)
        }

        progress = "Demoted \(demotedCount)/\(matched.count) videos (\(unmatched.count) unmatched)"
        print("[Demote] DONE — demoted \(demotedCount), matched \(matched.count)/\(titles.count)")

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        progress = ""
        isRunning = false
    }

    /// Delete partial boundary results from Firebase and re-run boundaries for those videos
    func rerunPartialBoundaries(videos: [YouTubeVideo]) async {
        let partials = Self.findPartialBoundaryResults()
        guard !partials.isEmpty else {
            progress = "No partial boundary runs found"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }

        guard let channelId = CreatorDetailViewModel.shared.currentChannel?.channelId, !channelId.isEmpty else {
            progress = "Error: No channel selected"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }

        // Nuke partial results from Firebase
        let boundaryService = CreatorDetailViewModel.shared.llmBoundaryService
        for partial in partials {
            do {
                try await boundaryService.deleteResult(forVideoId: partial.videoId, channelId: channelId)
                print("[LLMPipeline] Deleted partial boundary: \(partial.videoTitle)")
            } catch {
                print("[LLMPipeline] Failed to delete partial boundary for \(partial.videoTitle): \(error)")
            }
        }

        // Re-run boundaries for the now-eligible videos
        let partialIds = Set(partials.map { $0.videoId })
        let eligible = videos.filter { partialIds.contains($0.videoId) && $0.hasTranscript }
        guard !eligible.isEmpty else {
            progress = "Partial results deleted but videos not found"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progress = ""
            return
        }

        await runBoundariesOnly(eligibleVideos: eligible)
    }

    // MARK: - Helpers

    /// Build lightweight LLMChunkRecord array from Chunk objects
    private func buildChunkRecords(from chunks: [Chunk]) -> [LLMChunkRecord] {
        chunks.map { chunk in
            LLMChunkRecord(
                chunkIndex: chunk.chunkIndex,
                startSentence: chunk.startSentence,
                endSentence: chunk.endSentence,
                sentenceCount: chunk.sentenceCount,
                positionInVideo: chunk.positionInVideo,
                text: chunk.fullText
            )
        }
    }

    /// Reconstruct Chunk objects from a saved LLMBoundaryVideoResult
    private func chunksFromBoundaryResult(_ result: LLMBoundaryVideoResult) -> [Chunk] {
        result.chunks.map { record in
            // Build lightweight telemetry from stored text
            let sentenceTexts = record.text.components(separatedBy: ". ")
                .flatMap { $0.components(separatedBy: "? ") }
                .flatMap { $0.components(separatedBy: "! ") }
            let telemetry = makeLightweightTelemetry(sentences: sentenceTexts.isEmpty ? [record.text] : sentenceTexts)

            let emptyProfile = ChunkProfile(
                dominantPerspective: .mixed,
                dominantStance: .mixed,
                tagDensity: TagDensity(
                    hasNumber: 0, hasStatistic: 0, hasNamedEntity: 0, hasQuote: 0,
                    hasContrastMarker: 0, hasRevealLanguage: 0, hasChallengeLanguage: 0,
                    hasFirstPerson: 0, hasSecondPerson: 0, isTransition: 0,
                    isSponsorContent: 0, isCallToAction: 0
                ),
                boundaryTrigger: nil
            )

            return Chunk(
                chunkIndex: record.chunkIndex,
                startSentence: record.startSentence,
                endSentence: record.endSentence,
                sentences: telemetry,
                profile: emptyProfile,
                positionInVideo: record.positionInVideo,
                sentenceCount: record.sentenceCount
            )
        }
    }

    /// Copy-construct RhetoricalMove instances with sentence ranges from chunks
    private func enrichMovesWithSentenceRanges(
        sequence: RhetoricalSequence,
        chunks: [Chunk]
    ) -> RhetoricalSequence {
        let enrichedMoves = sequence.moves.map { move -> RhetoricalMove in
            let chunk = chunks.first(where: { $0.chunkIndex == move.chunkIndex })
            return RhetoricalMove(
                id: move.id,
                chunkIndex: move.chunkIndex,
                moveType: move.moveType,
                confidence: move.confidence,
                alternateType: move.alternateType,
                alternateConfidence: move.alternateConfidence,
                briefDescription: move.briefDescription,
                gistA: move.gistA,
                gistB: move.gistB,
                expandedDescription: move.expandedDescription,
                telemetry: move.telemetry,
                startSentence: chunk?.startSentence,
                endSentence: chunk?.endSentence
            )
        }
        return RhetoricalSequence(
            id: sequence.id,
            videoId: sequence.videoId,
            moves: enrichedMoves,
            extractedAt: sequence.extractedAt
        )
    }

    // MARK: - Firebase Save

    /// Save digression results as a BatchDigressionVideoResult so it shows up in the existing UI
    private func saveDigressionResult(
        videoId: String,
        videoTitle: String,
        channelId: String,
        digressions: [DigressionAnnotation],
        totalSentences: Int
    ) async throws {
        let config = DigressionDetectionConfig(
            enableLLMEscalation: false,
            temperature: 0.3,
            maxConcurrentLLMCalls: 1,
            enabledTypes: Set(DigressionType.allCases),
            minConfidenceThreshold: 0.0,
            boundaryBoostEnabled: false,
            boundaryBoostAmount: 0.0,
            detectionMode: .llmFirst
        )

        let digressionIndices = Set(digressions.flatMap { Array($0.sentenceRange) })
        let cleanIndices = (0..<totalSentences).filter { !digressionIndices.contains($0) }

        let run = DigressionFidelityRunResult(
            runNumber: 1,
            temperature: 0.3,
            enabledLLMEscalation: false,
            digressions: digressions,
            cleanSentenceIndices: cleanIndices,
            totalSentences: totalSentences,
            detectionMode: .llmFirst
        )

        var result = BatchDigressionVideoResult(
            channelId: channelId,
            videoId: videoId,
            videoTitle: videoTitle,
            runs: [run],
            totalSentences: totalSentences,
            config: config
        )
        result.completedAt = Date()

        let db = Firestore.firestore()
        let docId = BatchDigressionVideoResult.docId(channelId: channelId, videoId: videoId)
        let data = try Firestore.Encoder().encode(result)
        try await db.collection("batchDigressionResults").document(docId).setData(data)
    }

    // MARK: - Lightweight Telemetry

    /// Create minimal SentenceTelemetry stubs from plain text.
    /// Populates only index, text, wordCount, and defaults for everything else.
    /// This allows reusing DigressionLLMDetector and Chunk without modifying their interfaces.
    func makeLightweightTelemetry(sentences: [String]) -> [SentenceTelemetry] {
        let total = sentences.count
        return sentences.enumerated().map { index, text in
            let words = text.split(separator: " ")
            return SentenceTelemetry(
                sentenceIndex: index,
                text: text,
                positionPercentile: total > 1 ? Double(index) / Double(total - 1) : 0.0,
                wordCount: words.count,
                hasNumber: words.contains { $0.rangeOfCharacter(from: .decimalDigits) != nil },
                endsWithQuestion: text.hasSuffix("?"),
                endsWithExclamation: text.hasSuffix("!"),
                hasContrastMarker: false,
                hasTemporalMarker: false,
                hasFirstPerson: false,
                hasSecondPerson: false,
                hasStatistic: false,
                hasQuote: false,
                hasNamedEntity: false,
                hasRevealLanguage: false,
                hasPromiseLanguage: false,
                hasChallengeLanguage: false,
                stance: "neutral",
                perspective: "third",
                isTransition: false,
                isSponsorContent: false,
                isCallToAction: false
            )
        }
    }

    // MARK: - Chunk Building

    /// Convert section splitter boundaries into Chunk objects for RhetoricalMoveService.
    ///
    /// - Parameters:
    ///   - sentences: Clean (post-digression-exclusion) SentenceTelemetry array
    ///   - boundaryNumbers: 1-indexed sentence numbers where splits occur (from SectionBoundary.sentenceNumber).
    ///                      Split is AFTER the given sentence, so chunk N ends at boundary[N], chunk N+1 starts at boundary[N]+1.
    /// - Returns: Array of Chunk objects ready for rhetorical move extraction
    func buildChunksFromBoundaries(
        sentences: [SentenceTelemetry],
        boundaryNumbers: [Int]
    ) -> [Chunk] {
        guard !sentences.isEmpty else { return [] }

        var splitPositions: [Int] = []
        for boundary in boundaryNumbers.sorted() {
            if let pos = sentences.firstIndex(where: { $0.sentenceIndex >= boundary }) {
                if pos > 0 && !splitPositions.contains(pos) {
                    splitPositions.append(pos)
                }
            }
        }

        var chunkStarts = [0] + splitPositions
        chunkStarts = Array(Set(chunkStarts)).sorted()

        var chunks: [Chunk] = []
        let totalSentences = sentences.count

        for (chunkIdx, start) in chunkStarts.enumerated() {
            let end = chunkIdx + 1 < chunkStarts.count
                ? chunkStarts[chunkIdx + 1] - 1
                : totalSentences - 1

            guard start <= end else { continue }

            let chunkSentences = Array(sentences[start...end])

            let emptyProfile = ChunkProfile(
                dominantPerspective: .mixed,
                dominantStance: .mixed,
                tagDensity: TagDensity(
                    hasNumber: 0, hasStatistic: 0, hasNamedEntity: 0, hasQuote: 0,
                    hasContrastMarker: 0, hasRevealLanguage: 0, hasChallengeLanguage: 0,
                    hasFirstPerson: 0, hasSecondPerson: 0, isTransition: 0,
                    isSponsorContent: 0, isCallToAction: 0
                ),
                boundaryTrigger: nil
            )

            let chunk = Chunk(
                chunkIndex: chunkIdx,
                startSentence: chunkSentences.first!.sentenceIndex,
                endSentence: chunkSentences.last!.sentenceIndex,
                sentences: chunkSentences,
                profile: emptyProfile,
                positionInVideo: Double(start) / Double(totalSentences),
                sentenceCount: chunkSentences.count
            )

            chunks.append(chunk)
        }

        return chunks
    }
}

// MARK: - Error Types

enum LLMPipelineError: LocalizedError {
    case noTranscript
    case noSentences
    case noChunks

    var errorDescription: String? {
        switch self {
        case .noTranscript: return "Video has no transcript"
        case .noSentences: return "Could not parse any sentences from transcript"
        case .noChunks: return "No chunks produced from boundaries"
        }
    }
}

// MARK: - Thread-Safe Tracker

private actor PipelineTracker {
    var completed = 0
    var failed = 0

    func markCompleted(videoId: String, moveCount: Int) {
        completed += 1
    }

    func markFailed() {
        failed += 1
    }

    func getStats() -> (completed: Int, failed: Int) {
        (completed, failed)
    }
}
