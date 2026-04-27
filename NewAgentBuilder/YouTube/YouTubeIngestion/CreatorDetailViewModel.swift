//
//  CreatorDetailViewModel.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
class CreatorDetailViewModel: ObservableObject {
    static let shared = CreatorDetailViewModel()

    // MARK: - Published State

    @Published var currentChannel: YouTubeChannel?
    @Published var videos: [YouTubeVideo] = []
    @Published var isLoadingVideos = false

    // Search
    @Published var videoSearchText = ""
    @Published var searchTranscripts = false

    // Sentence analysis data
    @Published var videoSentenceData: [String: [SentenceFidelityTest]] = [:]
    @Published var isLoadingSentenceData = false
    

    // Transcript fetching
    @Published var isFetchingTranscripts = false
    @Published var transcriptFetchProgress = ""
    @Published var videoIdsBeingFetched: Set<String> = []

    // A3 state
    @Published var showA3Progress = false
    @Published var a3Progress = ""
    @Published var a3Error: String?

    // Efficient test state
    @Published var isRunningEfficientTest = false
    @Published var efficientTestProgress = ""

    // Rhetorical analysis state
    @Published var isRunningRhetoricalAnalysis = false
    @Published var rhetoricalAnalysisProgress = ""

    // Rhetorical queue system (for individual video selection)
    @Published var videosQueuedForRhetorical: Set<String> = []
    @Published var videosBeingProcessed: Set<String> = []
    @Published var rhetoricalQueueProgress: [String: String] = [:]  // videoId -> "Chunk 3/15"
    private let rhetoricalQueueConcurrency = 5  // Process up to 5 videos at once

    // Batch services
    let batchService = BatchAnalysisService()
    let sentenceBatchService = BatchVideoAnalysisService()
    let batchDigressionService = BatchDigressionAnalysisService()
    let llmBoundaryService = LLMBoundaryService()
    let narrativeSpineService = NarrativeSpineService.shared

    // Cancellables for observing nested objects
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Forward changes from nested observable objects to trigger view updates
        batchService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        sentenceBatchService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        batchDigressionService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        llmBoundaryService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        narrativeSpineService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Channel Management

    /// Set the current channel. Only reloads if it's a different channel.
    func setChannel(_ channel: YouTubeChannel) async {
        // If same channel, don't reload
        if currentChannel?.channelId == channel.channelId {
            return
        }

        // New channel - clear ALL old data first
        clearAllState()

        // Set new channel and load
        currentChannel = channel
        await loadVideos()
    }

    /// Clear all state when switching channels
    private func clearAllState() {
        currentChannel = nil
        videos = []
        videoSentenceData = [:]
        videoSearchText = ""
        searchTranscripts = false
        isSearchActive = false
        filteredVideoStatuses = []
        isLoadingVideos = false
        isLoadingSentenceData = false
        isFetchingTranscripts = false
        transcriptFetchProgress = ""
        videoIdsBeingFetched = []
        showA3Progress = false
        a3Progress = ""
        a3Error = nil
        isRunningEfficientTest = false
        efficientTestProgress = ""

        // Clear batch services
        batchService.videoStatuses = []
        batchDigressionService.videoResults = []
        batchDigressionService.aggregate = nil
        llmBoundaryService.videoResults = []

        // Reset template extraction service
        TemplateExtractionService.shared.forceReset()
    }

    /// Force reload everything for the current channel
    func refresh() async {
        guard currentChannel != nil else { return }

        videos = []
        videoSentenceData = [:]
        batchService.videoStatuses = []

        await loadVideos()
    }

    // MARK: - Load Videos

    func loadVideos() async {
        guard let channel = currentChannel else { return }

        isLoadingVideos = true

        do {
            let firebase = YouTubeFirebaseService.shared
            print("Loading videos for channel: \(channel.channelId)")
            videos = try await firebase.getVideos(forChannel: channel.channelId)
            print("Loaded \(videos.count) videos")

            // Load batch service statuses
            await batchService.loadStatuses(for: videos)

            // Load sentence analysis data
            await loadSentenceData()

            // Load batch digression results
            await batchDigressionService.loadResults(forChannelId: channel.channelId)

            // Load LLM boundary results
            await llmBoundaryService.loadResults(forChannelId: channel.channelId)

        } catch {
            print("Failed to load videos: \(error)")
        }

        isLoadingVideos = false
    }

    // MARK: - Sentence Data

    func loadSentenceData() async {
        guard let channel = currentChannel else { return }

        isLoadingSentenceData = true

        do {
            let videoIds = videos.map { $0.videoId }
            let firebaseService = SentenceFidelityFirebaseService.shared
            videoSentenceData = try await firebaseService.getTestRunsForVideos(videoIds)
            print("Loaded sentence data for \(videoSentenceData.count) videos")

            // Update channel's hasSentenceAnalysis flag based on whether any videos have analysis
            let hasSentenceAnalysis = !videoSentenceData.isEmpty
            if channel.hasSentenceAnalysis != hasSentenceAnalysis {
                try await YouTubeFirebaseService.shared.updateChannelSentenceAnalysisStatus(
                    channelId: channel.channelId,
                    hasSentenceAnalysis: hasSentenceAnalysis
                )
                // Update local channel state
                currentChannel?.hasSentenceAnalysis = hasSentenceAnalysis
                print("Updated channel hasSentenceAnalysis = \(hasSentenceAnalysis)")
            }
        } catch {
            print("Failed to load sentence data: \(error)")
        }

        isLoadingSentenceData = false
    }

    // MARK: - Granular Delete Operations

    /// Tracks which delete operation is currently running (nil = none)
    @Published var activeDeleteOp: String?
    /// Result text for each completed delete, keyed by operation name
    @Published var deleteResults: [String: String] = [:]

    func deleteSentenceFidelity() async {
        let op = "sentenceFidelity"
        activeDeleteOp = op
        deleteResults[op] = ""
        print("🗑️ DELETE START: Sentence Fidelity Tests — querying sentenceFidelityTests collection...")

        do {
            let count = try await SentenceFidelityFirebaseService.shared.deleteAllTestRuns()
            videoSentenceData = [:]
            deleteResults[op] = "Deleted \(count)"
            print("🗑️ DELETE DONE: Sentence Fidelity — \(count) documents deleted from sentenceFidelityTests")
        } catch {
            deleteResults[op] = "Error"
            print("🗑️ DELETE FAILED: Sentence Fidelity — \(error.localizedDescription)")
        }
        activeDeleteOp = nil
    }

    func deleteDigressionResults() async {
        let op = "digressions"
        activeDeleteOp = op
        deleteResults[op] = ""
        print("🗑️ DELETE START: Digression Results — querying digressionDetectionResults collection...")

        do {
            let count = try await DigressionFirebaseService.shared.deleteAllResults()
            deleteResults[op] = "Deleted \(count)"
            print("🗑️ DELETE DONE: Digressions — \(count) documents deleted from digressionDetectionResults")
        } catch {
            deleteResults[op] = "Error"
            print("🗑️ DELETE FAILED: Digressions — \(error.localizedDescription)")
        }
        activeDeleteOp = nil
    }

    func deleteBatchDigressions(channelId: String) async {
        let op = "batchDigressions"
        activeDeleteOp = op
        deleteResults[op] = ""
        print("🗑️ DELETE START: Batch Digression Results — targeting batchDigressionResults for channel '\(channelId)'...")

        do {
            let batchService = BatchDigressionAnalysisService()
            try await batchService.deleteResults(forChannelId: channelId)
            deleteResults[op] = "Deleted (channel)"
            print("🗑️ DELETE DONE: Batch Digressions — channel \(channelId) cleared")
        } catch {
            deleteResults[op] = "Error"
            print("🗑️ DELETE FAILED: Batch Digressions — \(error.localizedDescription)")
        }
        activeDeleteOp = nil
    }

    func deleteAllBatchDigressions() async {
        let op = "batchDigressions"
        activeDeleteOp = op
        deleteResults[op] = ""
        print("🗑️ DELETE START: ALL Batch Digression Results — targeting entire batchDigressionResults collection...")

        do {
            let batchService = BatchDigressionAnalysisService()
            let count = try await batchService.deleteAllResults()
            deleteResults[op] = "Deleted \(count)"
            print("🗑️ DELETE DONE: ALL Batch Digressions — \(count) documents deleted")
        } catch {
            deleteResults[op] = "Error"
            print("🗑️ DELETE FAILED: ALL Batch Digressions — \(error.localizedDescription)")
        }
        activeDeleteOp = nil
    }

    func deleteRhetoricalSequences() async {
        let op = "rhetorical"
        activeDeleteOp = op
        deleteResults[op] = ""
        print("🗑️ DELETE START: Rhetorical Sequences — clearing rhetoricalSequence field from youtube_videos...")

        do {
            let count = try await YouTubeFirebaseService.shared.clearAllRhetoricalSequences()
            deleteResults[op] = "Cleared \(count)"
            print("🗑️ DELETE DONE: Rhetorical Sequences — \(count) video documents cleared")
        } catch {
            deleteResults[op] = "Error"
            print("🗑️ DELETE FAILED: Rhetorical Sequences — \(error.localizedDescription)")
        }
        activeDeleteOp = nil
    }

    // Legacy wipe-all kept for compatibility but now calls granular methods
    @Published var isWipingData = false
    @Published var wipeProgress = ""
    @Published var lastWipeResult = ""

    func wipeAllSentenceData() async {
        isWipingData = true
        wipeProgress = "Deleting all..."
        print("🗑️ WIPE ALL START — running all 4 granular deletes...")

        await deleteSentenceFidelity()
        await deleteDigressionResults()
        // Note: batchDigressions requires channelId, skipped from wipe-all
        await deleteRhetoricalSequences()

        let results = deleteResults.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        lastWipeResult = results
        wipeProgress = "Done"
        print("🗑️ WIPE ALL DONE: \(results)")
        isWipingData = false
    }

    // MARK: - Search / Filtering

    @Published var isSearchActive = false
    @Published var filteredVideoStatuses: [VideoAnalysisStatus] = []

    func executeSearch() {
        let query = videoSearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            clearSearch()
            return
        }

        let lowerQuery = query.lowercased()
        filteredVideoStatuses = batchService.videoStatuses.filter { status in
            if status.video.title.lowercased().contains(lowerQuery) {
                return true
            }
            if searchTranscripts,
               let transcript = status.video.transcript,
               transcript.lowercased().contains(lowerQuery) {
                return true
            }
            return false
        }
        isSearchActive = true
    }

    func clearSearch() {
        videoSearchText = ""
        filteredVideoStatuses = []
        isSearchActive = false
    }

    /// The list to display — filtered results when searching, all videos otherwise
    var displayedVideoStatuses: [VideoAnalysisStatus] {
        isSearchActive ? filteredVideoStatuses : batchService.videoStatuses
    }

    // MARK: - Computed Properties

    var videosWithTranscripts: Int {
        videos.filter { $0.hasTranscript }.count
    }

    var videosWithSentenceAnalysis: Int {
        videoSentenceData.count
    }

    var missingTranscriptCount: Int {
        videos.filter { $0.transcript == nil || $0.transcript?.isEmpty == true }.count
    }

    var videosWithRhetoricalSequence: Int {
        videos.filter { $0.rhetoricalSequence != nil }.count
    }

    var videosWithNarrativeSpine: Int {
        videos.filter { $0.hasNarrativeSpine }.count
    }

    /// Videos that have sentence analysis but no rhetorical sequence yet
    var videosReadyForRhetoricalAnalysis: Int {
        videos.filter { video in
            video.rhetoricalSequence == nil && videoSentenceData[video.videoId] != nil
        }.count
    }

    /// Videos that need enhanced rhetorical analysis (no sequence OR outdated sequence)
    var videosNeedingEnhancedRhetorical: Int {
        videos.filter { videoNeedsRhetoricalAnalysis($0) }.count
    }

    /// Get the list of videos needing enhanced analysis
    var videosNeedingEnhancedRhetoricalList: [YouTubeVideo] {
        videos.filter { videoNeedsRhetoricalAnalysis($0) }
    }

    /// Queue all videos that need enhanced rhetorical analysis
    func queueAllVideosNeedingEnhancedRhetorical() {
        let videosToQueue = videosNeedingEnhancedRhetoricalList
        guard !videosToQueue.isEmpty else {
            print("⚠️ No videos need enhanced rhetorical analysis")
            return
        }

        print("📋 Queueing \(videosToQueue.count) videos for enhanced rhetorical analysis")
        for video in videosToQueue {
            if !isVideoInRhetoricalQueue(video.videoId) {
                queueVideoForRhetorical(video)
            }
        }
    }

    // MARK: - Transcript Fetching

    func fetchAllMissingTranscripts() async {
        guard !isFetchingTranscripts else { return }

        isFetchingTranscripts = true

        let videosNeedingTranscript = videos.filter {
            ($0.transcript == nil || $0.transcript?.isEmpty == true) &&
            !videoIdsBeingFetched.contains($0.videoId)
        }

        let totalCount = videosNeedingTranscript.count
        var completedCount = 0
        var failedCount = 0

        transcriptFetchProgress = "0/\(totalCount)"

        for video in videosNeedingTranscript {
            videoIdsBeingFetched.insert(video.videoId)

            do {
                let service = YouTubeTranscriptService()
                let transcript = try await service.fetchTranscript(videoId: video.videoId)

                try await YouTubeFirebaseService.shared.updateVideoTranscript(
                    videoId: video.videoId,
                    transcript: transcript
                )

                // Update local videos array
                if let index = videos.firstIndex(where: { $0.videoId == video.videoId }) {
                    videos[index].transcript = transcript
                }

                completedCount += 1
                print("Fetched transcript for \(video.videoId)")

            } catch {
                failedCount += 1
                print("Transcript error for \(video.videoId): \(error)")
            }

            transcriptFetchProgress = "\(completedCount + failedCount)/\(totalCount)"
            videoIdsBeingFetched.remove(video.videoId)

            // Rate limiting
            if completedCount + failedCount < totalCount {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        // Refresh batch service statuses
        await batchService.loadStatuses(for: videos)

        isFetchingTranscripts = false
        transcriptFetchProgress = ""

        print("Transcript fetch complete: \(completedCount) success, \(failedCount) failed")
    }

    func fetchTranscript(for video: YouTubeVideo) async {
        guard !videoIdsBeingFetched.contains(video.videoId) else { return }

        videoIdsBeingFetched.insert(video.videoId)

        do {
            let service = YouTubeTranscriptService()
            let transcript = try await service.fetchTranscript(videoId: video.videoId)

            try await YouTubeFirebaseService.shared.updateVideoTranscript(
                videoId: video.videoId,
                transcript: transcript
            )

            // Update local videos array
            if let index = videos.firstIndex(where: { $0.videoId == video.videoId }) {
                videos[index].transcript = transcript

                // Update batch service status too
                let updatedVideo = videos[index]
                if let statusIndex = batchService.videoStatuses.firstIndex(where: { $0.video.videoId == video.videoId }) {
                    let oldStatus = batchService.videoStatuses[statusIndex]
                    batchService.videoStatuses[statusIndex] = VideoAnalysisStatus(
                        id: oldStatus.id,
                        video: updatedVideo,
                        state: oldStatus.state,
                        sectionCount: oldStatus.sectionCount,
                        beatCount: oldStatus.beatCount,
                        hasScriptSummary: oldStatus.hasScriptSummary
                    )
                }
            }

            print("Fetched transcript for \(video.videoId)")

        } catch {
            print("Transcript error: \(error)")
        }

        videoIdsBeingFetched.remove(video.videoId)
    }

    // MARK: - A3 Analysis

    func runA3Analysis() async {
        guard let channel = currentChannel else { return }

        showA3Progress = true
        a3Progress = "Starting A3 clustering analysis..."

        do {
            let readyVideos = batchService.videoStatuses
                .filter { $0.state.isReadyForA3 }
                .map { $0.video }

            a3Progress = "Loading scriptSummaries for \(readyVideos.count) videos..."

            let service = A3ClusteringService()
            try await service.runClustering(
                channelId: channel.channelId,
                videos: readyVideos,
                onProgress: { progress in
                    Task { @MainActor in
                        self.a3Progress = progress
                    }
                }
            )

            a3Progress = "A3 analysis complete!"
            try? await Task.sleep(nanoseconds: 2_000_000_000)

        } catch {
            a3Error = error.localizedDescription
        }

        showA3Progress = false
    }

    // MARK: - Batch Sentence Analysis

    func runBatchSentenceAnalysis() async {
        let videosToAnalyze = videos.filter {
            $0.hasTranscript && videoSentenceData[$0.videoId] == nil
        }

        guard !videosToAnalyze.isEmpty else { return }

        await sentenceBatchService.analyzeVideos(videosToAnalyze, temperature: 0.3) { completed, total, title in
            print("Sentence analysis progress: \(completed)/\(total) - \(title)")
        }

        // Reload sentence data after batch completes
        await loadSentenceData()
    }

    // MARK: - Efficient Sentence Test

    func runEfficientSentenceTest() async {
        guard let channel = currentChannel else { return }

        isRunningEfficientTest = true
        efficientTestProgress = "Starting efficient analysis..."

        let videosToAnalyze = videos
            .filter { $0.hasTranscript && videoSentenceData[$0.videoId] == nil }
            .prefix(10)

        let taggingService = SentenceTaggingService()

        for (index, video) in videosToAnalyze.enumerated() {
            guard let transcript = video.transcript, !transcript.isEmpty else { continue }

            efficientTestProgress = "Video \(index + 1)/\(videosToAnalyze.count): \(video.title)"

            do {
                let existingRuns = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
                let nextRunNumber = (existingRuns.map { $0.runNumber }.max() ?? 0) + 1

                let startTime = Date()
                let sentences = try await taggingService.tagTranscript(
                    transcript: transcript,
                    temperature: 0.3,
                    mode: .efficient,
                    onProgress: nil
                )
                let duration = Date().timeIntervalSince(startTime)

                let test = SentenceFidelityTest(
                    id: UUID().uuidString,
                    videoId: video.videoId,
                    channelId: channel.channelId,
                    videoTitle: video.title,
                    createdAt: Date(),
                    runNumber: nextRunNumber,
                    promptVersion: "v2-efficient-cached",
                    modelUsed: "claude-sonnet-4-20250514",
                    temperature: 0.3,
                    taggingMode: TaggingMode.efficient.rawValue,
                    totalSentences: sentences.count,
                    sentences: sentences,
                    comparedToRunId: nil,
                    stabilityScore: nil,
                    durationSeconds: duration
                )

                try await SentenceFidelityFirebaseService.shared.saveTestRun(test)
                videoSentenceData[video.videoId] = [test]

                print("Efficient analysis complete for: \(video.title)")

            } catch {
                print("Efficient analysis failed for \(video.title): \(error)")
            }
        }

        isRunningEfficientTest = false
        efficientTestProgress = ""
    }

    // MARK: - Copy Functions

    func copyRawSentencesForVideo(_ video: YouTubeVideo) {
        guard let runs = videoSentenceData[video.videoId], let latestRun = runs.first else {
            return
        }

        var report = "TRANSCRIPT (SENTENCES): \(video.title)\n"
        report += "\(latestRun.totalSentences) sentences\n"
        report += "════════════════════════════════════════\n\n"

        for sentence in latestRun.sentences {
            report += "[\(sentence.sentenceIndex + 1)] \(sentence.text)\n"
        }

        copyToClipboard(report)
        print("Copied raw sentences for: \(video.title)")
    }

    func copyLiveParseSentencesForVideo(_ video: YouTubeVideo) {
        guard let transcript = video.transcript, !transcript.isEmpty else { return }

        let sentences = SentenceParser.parse(transcript)

        var report = "LIVE PARSE: \(video.title)\n"
        report += "\(sentences.count) sentences (current SentenceParser)\n"
        report += "════════════════════════════════════════\n\n"

        for (i, sentence) in sentences.enumerated() {
            report += "[\(i + 1)] \(sentence)\n"
        }

        copyToClipboard(report)
        print("📋 [LiveParse] Copied \(sentences.count) sentences for: \(video.title)")
    }

    func copySentenceDataForVideo(_ video: YouTubeVideo) {
        guard let runs = videoSentenceData[video.videoId], let latestRun = runs.first else {
            return
        }

        var report = """
        ════════════════════════════════════════════════════════════════
        SENTENCE TELEMETRY: \(video.title)
        Run #\(latestRun.runNumber) | \(latestRun.totalSentences) sentences
        Mode: \(latestRun.taggingMode ?? "unknown") | Model: \(latestRun.modelUsed)
        ════════════════════════════════════════════════════════════════

        """

        for sentence in latestRun.sentences {
            let flags = buildSentenceFlags(sentence)
            report += """
            [\(sentence.sentenceIndex)] \(sentence.text)
                \(flags)

            """
        }

        copyToClipboard(report)
        print("Copied sentence data for: \(video.title)")
    }

    func copyChunksDataForVideo(_ video: YouTubeVideo) {
        guard let runs = videoSentenceData[video.videoId], let latestRun = runs.first else {
            return
        }

        let service = BoundaryDetectionService.shared
        let result = service.detectBoundaries(from: latestRun)
        let moves = video.rhetoricalSequence?.moves

        var report = """
        ════════════════════════════════════════════════════════════════
        BOUNDARY CHUNKS: \(video.title)
        \(result.chunkCount) chunks from \(result.totalSentences) sentences
        ════════════════════════════════════════════════════════════════

        """

        for chunk in result.chunks {
            // Header with rhetorical move if available
            if let move = moves?.first(where: { $0.chunkIndex == chunk.chunkIndex }) {
                report += "CHUNK \(chunk.chunkIndex + 1): \(move.moveType.displayName.uppercased()) (\(move.moveType.category.rawValue)) [\(chunk.positionLabel)]\n"
            } else {
                report += "CHUNK \(chunk.chunkIndex + 1) [\(chunk.positionLabel)]\n"
            }

            // Each sentence with tags
            for sentence in chunk.sentences {
                report += "[\(sentence.sentenceIndex)] \(sentence.text)\n"
                report += "    \(buildSentenceFlags(sentence))\n"
            }

            report += "\n"
        }

        copyToClipboard(report)
        print("Copied \(result.chunkCount) chunks for: \(video.title)")
    }

    func copyAllSentenceData() {
        guard let channel = currentChannel else { return }

        var report = """
        ════════════════════════════════════════════════════════════════
        SENTENCE TELEMETRY EXPORT
        Channel: \(channel.name)
        Videos Analyzed: \(videosWithSentenceAnalysis)
        ════════════════════════════════════════════════════════════════

        """

        for video in videos {
            guard let runs = videoSentenceData[video.videoId], let latestRun = runs.first else {
                continue
            }

            report += """

            ────────────────────────────────────────────────────────────────
            VIDEO: \(video.title)
            Run #\(latestRun.runNumber) | \(latestRun.totalSentences) sentences | \(latestRun.taggingMode ?? "unknown")
            ────────────────────────────────────────────────────────────────

            """

            for sentence in latestRun.sentences {
                let flags = buildSentenceFlags(sentence)
                report += """
                [\(sentence.sentenceIndex)] \(sentence.text)
                    \(flags)

                """
            }
        }

        copyToClipboard(report)
        print("Copied sentence data for \(videosWithSentenceAnalysis) videos")
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func buildSentenceFlags(_ s: SentenceTelemetry) -> String {
        var flags: [String] = []
        if s.hasNumber { flags.append("NUM") }
        if s.hasStatistic { flags.append("STAT") }
        if s.hasNamedEntity { flags.append("ENT") }
        if s.hasQuote { flags.append("QUOTE") }
        if s.hasFirstPerson { flags.append("1P") }
        if s.hasSecondPerson { flags.append("2P") }
        if s.hasContrastMarker { flags.append("CONTRAST") }
        if s.hasRevealLanguage { flags.append("REVEAL") }
        if s.hasPromiseLanguage { flags.append("PROMISE") }
        if s.hasChallengeLanguage { flags.append("CHALLENGE") }
        if s.isTransition { flags.append("TRANS") }
        if s.isCallToAction { flags.append("CTA") }
        if s.isSponsorContent { flags.append("SPONSOR") }
        flags.append("stance:\(s.stance)")
        flags.append("persp:\(s.perspective)")
        return flags.joined(separator: " | ")
    }

    // MARK: - Batch Rhetorical Analysis

    /// Maximum concurrent API calls for rhetorical extraction
    private let rhetoricalConcurrency = 10

    func runBatchRhetoricalAnalysis() async {
        guard !isRunningRhetoricalAnalysis else { return }

        isRunningRhetoricalAnalysis = true

        // Get videos that have sentence analysis but no rhetorical sequence
        let videosToAnalyze = videos.filter { video in
            video.rhetoricalSequence == nil && videoSentenceData[video.videoId] != nil
        }

        guard !videosToAnalyze.isEmpty else {
            rhetoricalAnalysisProgress = "No videos ready for analysis"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            isRunningRhetoricalAnalysis = false
            rhetoricalAnalysisProgress = ""
            return
        }

        let total = videosToAnalyze.count
        rhetoricalAnalysisProgress = "Starting \(total) videos (up to \(rhetoricalConcurrency) parallel)..."

        print("\n========================================")
        print("BATCH RHETORICAL ANALYSIS")
        print("========================================")
        print("Videos to analyze: \(total)")
        print("Concurrency: \(rhetoricalConcurrency)")

        // Track results thread-safely
        actor ResultTracker {
            var completed = 0
            var failed = 0
            var results: [(videoId: String, sequence: RhetoricalSequence)] = []

            func markCompleted(videoId: String, sequence: RhetoricalSequence) {
                completed += 1
                results.append((videoId, sequence))
            }

            func markFailed() {
                failed += 1
            }

            func getStats() -> (completed: Int, failed: Int) {
                return (completed, failed)
            }

            func getResults() -> [(videoId: String, sequence: RhetoricalSequence)] {
                return results
            }
        }

        let tracker = ResultTracker()
        let boundaryService = BoundaryDetectionService.shared
        let rhetoricalService = RhetoricalMoveService.shared
        let firebaseService = YouTubeFirebaseService.shared

        // Prepare video data with chunks
        var videoChunkPairs: [(video: YouTubeVideo, chunks: [Chunk])] = []
        for video in videosToAnalyze {
            guard let sentenceRuns = videoSentenceData[video.videoId],
                  let latestRun = sentenceRuns.first else {
                continue
            }

            let boundaryResult = boundaryService.detectBoundaries(from: latestRun)
            if !boundaryResult.chunks.isEmpty {
                videoChunkPairs.append((video, boundaryResult.chunks))
            } else {
                print("⚠️ No chunks detected for \(video.videoId), skipping")
            }
        }

        // Process in parallel batches
        for batchStart in stride(from: 0, to: videoChunkPairs.count, by: rhetoricalConcurrency) {
            let batchEnd = min(batchStart + rhetoricalConcurrency, videoChunkPairs.count)
            let batch = Array(videoChunkPairs[batchStart..<batchEnd])

            let stats = await tracker.getStats()
            rhetoricalAnalysisProgress = "[\(stats.completed + stats.failed)/\(total)] Processing batch of \(batch.count)..."

            await withTaskGroup(of: Void.self) { group in
                for (video, chunks) in batch {
                    group.addTask {
                        do {
                            // Extract rhetorical sequence
                            let sequence = try await rhetoricalService.extractRhetoricalSequence(
                                videoId: video.videoId,
                                chunks: chunks,
                                temperature: 0.1
                            )

                            // Save to Firebase
                            try await firebaseService.saveRhetoricalSequence(
                                videoId: video.videoId,
                                sequence: sequence
                            )

                            await tracker.markCompleted(videoId: video.videoId, sequence: sequence)
                            print("✓ Rhetorical: \(video.title) (\(sequence.moves.count) moves)")

                        } catch {
                            await tracker.markFailed()
                            print("✗ Rhetorical failed for \(video.title): \(error)")
                        }
                    }
                }
            }

            // Small delay between batches to avoid rate limiting
            if batchEnd < videoChunkPairs.count {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        // Update local videos with results
        let results = await tracker.getResults()
        for (videoId, sequence) in results {
            if let index = videos.firstIndex(where: { $0.videoId == videoId }) {
                videos[index].rhetoricalSequence = sequence
            }
        }

        let finalStats = await tracker.getStats()
        rhetoricalAnalysisProgress = "Complete: \(finalStats.completed) success, \(finalStats.failed) failed"
        print("\n✅ Batch rhetorical analysis complete: \(finalStats.completed) success, \(finalStats.failed) failed")

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        isRunningRhetoricalAnalysis = false
        rhetoricalAnalysisProgress = ""
    }

    // MARK: - Individual Video Rhetorical Queue

    /// Queue a single video for rhetorical analysis
    func queueVideoForRhetorical(_ video: YouTubeVideo) {
        guard videoNeedsRhetoricalAnalysis(video) else {
            print("⚠️ Video doesn't need rhetorical analysis: \(video.title)")
            return
        }

        videosQueuedForRhetorical.insert(video.videoId)

        // Log why we're queueing
        if let mismatch = rhetoricalMismatchInfo(video) {
            print("➕ Queued for rhetorical (outdated: \(mismatch.existing) moves → \(mismatch.current) chunks): \(video.title)")
        } else {
            print("➕ Queued for rhetorical (new): \(video.title)")
        }

        // Start processing if not already running
        if !isRunningRhetoricalAnalysis {
            Task {
                await processRhetoricalQueue()
            }
        }
    }

    /// Remove a video from the queue
    func dequeueVideoFromRhetorical(_ videoId: String) {
        videosQueuedForRhetorical.remove(videoId)
        print("➖ Removed from rhetorical queue: \(videoId)")
    }

    /// Check if a video is queued or being processed
    func isVideoInRhetoricalQueue(_ videoId: String) -> Bool {
        return videosQueuedForRhetorical.contains(videoId) || videosBeingProcessed.contains(videoId)
    }

    /// Check if a video needs rhetorical analysis (no sequence or outdated sequence)
    /// Returns true if:
    /// - Video has sentence data but no rhetorical sequence, OR
    /// - Video has rhetorical sequence but move count doesn't match current chunk count
    func videoNeedsRhetoricalAnalysis(_ video: YouTubeVideo) -> Bool {
        // Must have sentence data to analyze
        guard let sentenceRuns = videoSentenceData[video.videoId],
              let latestRun = sentenceRuns.first else {
            return false
        }

        // Get current chunk count from boundary detection
        let boundaryResult = BoundaryDetectionService.shared.detectBoundaries(from: latestRun)
        let currentChunkCount = boundaryResult.chunks.count

        // No rhetorical sequence - needs analysis
        guard let sequence = video.rhetoricalSequence else {
            return true
        }

        // Has sequence but move count doesn't match chunk count - outdated
        if sequence.moves.count != currentChunkCount {
            return true
        }

        return false
    }

    /// Get the chunk count mismatch info for UI display
    func rhetoricalMismatchInfo(_ video: YouTubeVideo) -> (current: Int, existing: Int)? {
        guard let sentenceRuns = videoSentenceData[video.videoId],
              let latestRun = sentenceRuns.first,
              let sequence = video.rhetoricalSequence else {
            return nil
        }

        let boundaryResult = BoundaryDetectionService.shared.detectBoundaries(from: latestRun)
        let currentChunkCount = boundaryResult.chunks.count

        if sequence.moves.count != currentChunkCount {
            return (current: currentChunkCount, existing: sequence.moves.count)
        }

        return nil
    }

    /// Process the rhetorical queue with incremental extraction
    func processRhetoricalQueue() async {
        guard !isRunningRhetoricalAnalysis else {
            print("⚠️ Rhetorical analysis already running")
            return
        }

        isRunningRhetoricalAnalysis = true

        let boundaryService = BoundaryDetectionService.shared
        let rhetoricalService = RhetoricalMoveService.shared
        let firebaseService = YouTubeFirebaseService.shared

        while !videosQueuedForRhetorical.isEmpty {
            // Get next batch from queue (up to concurrency limit)
            let batch = Array(videosQueuedForRhetorical.prefix(rhetoricalQueueConcurrency))

            // Move to processing
            for videoId in batch {
                videosQueuedForRhetorical.remove(videoId)
                videosBeingProcessed.insert(videoId)
            }

            rhetoricalAnalysisProgress = "Processing \(videosBeingProcessed.count) videos..."

            // Process batch in parallel
            await withTaskGroup(of: Void.self) { group in
                for videoId in batch {
                    group.addTask { [weak self] in
                        await self?.processVideoRhetoricalIncremental(
                            videoId: videoId,
                            boundaryService: boundaryService,
                            rhetoricalService: rhetoricalService,
                            firebaseService: firebaseService
                        )
                    }
                }
            }

            // Clear from processing
            for videoId in batch {
                videosBeingProcessed.remove(videoId)
                rhetoricalQueueProgress.removeValue(forKey: videoId)
            }
        }

        isRunningRhetoricalAnalysis = false
        rhetoricalAnalysisProgress = ""
        print("✅ Rhetorical queue processing complete")
    }

    /// Process a single video with incremental extraction and saving
    private func processVideoRhetoricalIncremental(
        videoId: String,
        boundaryService: BoundaryDetectionService,
        rhetoricalService: RhetoricalMoveService,
        firebaseService: YouTubeFirebaseService
    ) async {
        guard let video = videos.first(where: { $0.videoId == videoId }),
              let sentenceRuns = videoSentenceData[videoId],
              let latestRun = sentenceRuns.first else {
            print("❌ Cannot find video or sentence data for: \(videoId)")
            return
        }

        print("\n🎬 Starting incremental rhetorical extraction: \(video.title)")

        // Get chunks from boundary detection
        let boundaryResult = boundaryService.detectBoundaries(from: latestRun)
        let chunks = boundaryResult.chunks

        guard !chunks.isEmpty else {
            print("⚠️ No chunks for video: \(video.title)")
            return
        }

        // Track moves as they're extracted
        var extractedMoves: [RhetoricalMove] = []

        do {
            let sequence = try await rhetoricalService.extractRhetoricalSequenceIncremental(
                videoId: videoId,
                chunks: chunks,
                existingMoves: [],
                temperature: 0.1,
                onMoveExtracted: { [weak self] move, current, total in
                    extractedMoves.append(move)

                    // Update progress
                    await MainActor.run {
                        self?.rhetoricalQueueProgress[videoId] = "Chunk \(current)/\(total)"
                    }

                    // Save partial progress every 5 chunks or at the end
                    if current % 5 == 0 || current == total {
                        let partialSequence = RhetoricalSequence(
                            videoId: videoId,
                            moves: extractedMoves.sorted { $0.chunkIndex < $1.chunkIndex },
                            extractedAt: Date()
                        )
                        do {
                            try await firebaseService.saveRhetoricalSequence(
                                videoId: videoId,
                                sequence: partialSequence
                            )
                            print("💾 Saved partial progress: \(current)/\(total) chunks")
                        } catch {
                            print("⚠️ Failed to save partial progress: \(error)")
                        }
                    }
                },
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.rhetoricalQueueProgress[videoId] = progress
                    }
                }
            )

            // Final save
            try await firebaseService.saveRhetoricalSequence(
                videoId: videoId,
                sequence: sequence
            )

            // Update local video
            await MainActor.run {
                if let index = self.videos.firstIndex(where: { $0.videoId == videoId }) {
                    self.videos[index].rhetoricalSequence = sequence
                }
            }

            print("✅ Rhetorical extraction complete: \(video.title) (\(sequence.moves.count) moves)")

        } catch {
            print("❌ Rhetorical extraction failed for \(video.title): \(error)")
        }
    }

    // MARK: - Sorting

    func sortVideos(by option: SortOption) {
        switch option {
        case .titleAZ:
            batchService.videoStatuses.sort { $0.video.title < $1.video.title }
        case .titleZA:
            batchService.videoStatuses.sort { $0.video.title > $1.video.title }
        case .status:
            batchService.videoStatuses.sort { status1, status2 in
                let order1 = statusSortOrder(status1.state)
                let order2 = statusSortOrder(status2.state)
                return order1 < order2
            }
        case .date:
            batchService.videoStatuses.sort {
                ($0.video.publishedAt ?? Date.distantPast) > ($1.video.publishedAt ?? Date.distantPast)
            }
        case .longestFirst:
            batchService.videoStatuses.sort { $0.video.durationSeconds > $1.video.durationSeconds }
        case .shortestFirst:
            batchService.videoStatuses.sort { $0.video.durationSeconds < $1.video.durationSeconds }
        case .hasRhetorical:
            batchService.videoStatuses.sort { status1, status2 in
                let has1 = status1.video.hasRhetoricalSequence
                let has2 = status2.video.hasRhetoricalSequence
                if has1 == has2 { return status1.video.title < status2.video.title }
                return has1 && !has2
            }
        case .noRhetorical:
            batchService.videoStatuses.sort { status1, status2 in
                let has1 = status1.video.hasRhetoricalSequence
                let has2 = status2.video.hasRhetoricalSequence
                if has1 == has2 { return status1.video.title < status2.video.title }
                return !has1 && has2
            }
        }
    }

    enum SortOption {
        case titleAZ, titleZA, status, date, longestFirst, shortestFirst, hasRhetorical, noRhetorical
    }

    private func statusSortOrder(_ state: VideoAnalysisState) -> Int {
        switch state {
        case .notStarted: return 0
        case .inProgress: return 1
        case .a1aComplete: return 2
        case .a1bComplete: return 3
        case .fullComplete: return 4
        case .failed: return 5
        }
    }
}
