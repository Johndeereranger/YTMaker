//
//  BatchVideoAnalysisService.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import Foundation

/// Service for batch analyzing multiple videos' sentence telemetry
/// Processes videos in parallel with configurable concurrency
class BatchVideoAnalysisService: ObservableObject {

    // MARK: - Published State

    @Published var isRunning = false
    @Published var currentVideoIndex = 0
    @Published var totalVideos = 0
    @Published var currentVideoTitle = ""
    @Published var completedVideos: [String] = []  // Video IDs that completed successfully
    @Published var failedVideos: [(videoId: String, title: String, error: String)] = []
    @Published var statusMessage = ""

    // MARK: - Configuration

    let maxConcurrentVideos = 4  // Process 4 videos at a time

    // MARK: - Services

    private let taggingService = SentenceTaggingService()
    private let firebaseService = SentenceFidelityFirebaseService.shared

    // MARK: - Public Methods

    /// Analyze multiple videos using batched sentence tagging
    /// - Parameters:
    ///   - videos: List of videos to analyze (must have transcripts)
    ///   - temperature: LLM temperature setting
    ///   - onProgress: Callback for progress updates
    func analyzeVideos(
        _ videos: [YouTubeVideo],
        temperature: Double = 0.3,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async {
        // Filter to only videos with transcripts
        let videosWithTranscripts = videos.filter { !($0.transcript?.isEmpty ?? true) }

        guard !videosWithTranscripts.isEmpty else {
            await MainActor.run {
                statusMessage = "No videos with transcripts to analyze"
            }
            return
        }

        await MainActor.run {
            isRunning = true
            totalVideos = videosWithTranscripts.count
            currentVideoIndex = 0
            completedVideos = []
            failedVideos = []
            statusMessage = "Starting batch analysis of \(videosWithTranscripts.count) videos..."
        }

        // Process videos with limited concurrency
        await withTaskGroup(of: (String, String, Bool, String?).self) { group in
            var runningCount = 0
            var videoIterator = videosWithTranscripts.makeIterator()

            // Start initial batch
            for _ in 0..<maxConcurrentVideos {
                if let video = videoIterator.next() {
                    group.addTask {
                        await self.analyzeVideo(video, temperature: temperature)
                    }
                    runningCount += 1
                }
            }

            // Process results and add new tasks
            for await (videoId, title, success, errorMessage) in group {
                await MainActor.run {
                    currentVideoIndex += 1
                    if success {
                        completedVideos.append(videoId)
                        statusMessage = "Completed: \(title)"
                    } else {
                        failedVideos.append((videoId, title, errorMessage ?? "Unknown error"))
                        statusMessage = "Failed: \(title)"
                    }
                    onProgress?(currentVideoIndex, totalVideos, title)
                }

                // Add next video if available
                if let video = videoIterator.next() {
                    group.addTask {
                        await self.analyzeVideo(video, temperature: temperature)
                    }
                }
            }
        }

        await MainActor.run {
            isRunning = false
            statusMessage = "Completed: \(completedVideos.count)/\(totalVideos) videos analyzed successfully"
        }
    }

    /// Analyze a single video and save results
    private func analyzeVideo(
        _ video: YouTubeVideo,
        temperature: Double
    ) async -> (String, String, Bool, String?) {
        await MainActor.run {
            currentVideoTitle = video.title
        }

        guard let transcript = video.transcript, !transcript.isEmpty else {
            return (video.videoId, video.title, false, "No transcript")
        }

        do {
            // Get existing run count for this video
            let existingRuns = try await firebaseService.getTestRuns(forVideoId: video.videoId)
            let nextRunNumber = (existingRuns.map { $0.runNumber }.max() ?? 0) + 1

            // Run batched tagging (10 batches of 10 sentences concurrently)
            let startTime = Date()
            let sentences = try await taggingService.tagTranscript(
                transcript: transcript,
                temperature: temperature,
                mode: .batched,
                onProgress: nil
            )
            let duration = Date().timeIntervalSince(startTime)

            // Create test result
            let test = SentenceFidelityTest(
                id: UUID().uuidString,
                videoId: video.videoId,
                channelId: video.channelId,
                videoTitle: video.title,
                createdAt: Date(),
                runNumber: nextRunNumber,
                promptVersion: "v2-deterministic",
                modelUsed: "claude-sonnet-4-20250514",
                temperature: temperature,
                taggingMode: TaggingMode.batched.rawValue,
                totalSentences: sentences.count,
                sentences: sentences,
                comparedToRunId: nil,
                stabilityScore: nil,
                durationSeconds: duration
            )

            // Save to Firebase
            try await firebaseService.saveTestRun(test)

            print("✅ Analyzed \(video.title): \(sentences.count) sentences in \(String(format: "%.1fs", duration))")
            return (video.videoId, video.title, true, nil)

        } catch {
            print("❌ Failed to analyze \(video.title): \(error)")
            return (video.videoId, video.title, false, error.localizedDescription)
        }
    }

    /// Generate a summary report of the batch analysis
    func generateReport() -> String {
        var report = """
        ════════════════════════════════════════════════════════════════
        BATCH VIDEO ANALYSIS REPORT
        ════════════════════════════════════════════════════════════════

        Total Videos: \(totalVideos)
        Completed: \(completedVideos.count)
        Failed: \(failedVideos.count)
        Success Rate: \(totalVideos > 0 ? Int(Double(completedVideos.count) / Double(totalVideos) * 100) : 0)%

        """

        if !failedVideos.isEmpty {
            report += "\n────────────────────────────────────────────────────────────────\n"
            report += "FAILED VIDEOS\n"
            report += "────────────────────────────────────────────────────────────────\n\n"

            for (_, title, error) in failedVideos {
                report += "• \(title)\n  Error: \(error)\n\n"
            }
        }

        report += "════════════════════════════════════════════════════════════════\n"
        return report
    }
}
