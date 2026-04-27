//
//  NarrativeSpineService.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import Foundation

@MainActor
class NarrativeSpineService: ObservableObject {
    static let shared = NarrativeSpineService()

    private let firebase = NarrativeSpineFirebaseService.shared

    @Published var isRunning = false
    @Published var progress = ""
    @Published var completedVideos = 0
    @Published var totalVideos = 0
    @Published var perVideoProgress: [String: String] = [:]

    private init() {}

    // MARK: - Parallel-Safe Extraction (no MainActor involvement)

    /// Creates its own adapter per call — safe for concurrent use from task groups.
    nonisolated static func extractSpineParallel(
        for video: YouTubeVideo,
        existingSpines: [NarrativeSpine]?,
        temperature: Double
    ) async throws -> NarrativeSpine {
        guard video.hasTranscript else {
            throw NarrativeSpineError.missingTranscript
        }

        let adapter = ClaudeModelAdapter(model: .claude4Sonnet)

        let (systemPrompt, userPrompt) = NarrativeSpinePromptEngine.generatePrompt(
            video: video,
            existingSpines: existingSpines
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
            throw NarrativeSpineError.apiError(response.isEmpty ? "Empty response from LLM" : response)
        }

        return try NarrativeSpinePromptEngine.parseResponse(response, video: video)
    }

    // MARK: - Batch Extraction (parallel with concurrency limit of 3)

    func runSpineExtraction(videos: [YouTubeVideo], limit: Int? = nil) async {
        // 1. Filter eligible
        let eligible = videos.filter { video in
            video.hasTranscript && video.narrativeSpineStatus?.complete != true
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
        progress = "Processing 0/\(totalVideos) videos"
        perVideoProgress = [:]

        // 4. Load existing spines for corpus examples
        let channelId = toProcess.first?.channelId ?? ""
        var existingSpines: [NarrativeSpine] = []
        do {
            existingSpines = try await firebase.loadSpines(channelId: channelId)
        } catch {
            print("⚠️ Could not load existing spines for corpus examples: \(error.localizedDescription)")
        }

        // 5. Process videos in parallel (concurrency limit of 3)
        let maxConcurrency = 3
        var videoQueue = toProcess[...]  // Slice for efficient dequeue

        // Mark initial batch as in-flight
        for video in videoQueue.prefix(maxConcurrency) {
            perVideoProgress[video.videoId] = "Extracting spine..."
        }

        await withTaskGroup(of: (YouTubeVideo, Result<NarrativeSpine, Error>).self) { group in
            var inFlight = 0

            // Seed initial tasks
            while !videoQueue.isEmpty && inFlight < maxConcurrency {
                let video = videoQueue.removeFirst()
                let corpusSnapshot = existingSpines
                group.addTask {
                    do {
                        let spine = try await Self.extractSpineParallel(
                            for: video,
                            existingSpines: corpusSnapshot,
                            temperature: 0.1
                        )
                        return (video, .success(spine))
                    } catch {
                        return (video, .failure(error))
                    }
                }
                inFlight += 1
            }

            // As tasks complete, save results and launch new ones
            for await (video, result) in group {
                inFlight -= 1

                switch result {
                case .success(let spine):
                    // Save to Firebase
                    do {
                        try await firebase.saveSpine(spine)
                        try await firebase.markSpineComplete(videoId: video.videoId, beatCount: spine.beats.count)
                    } catch {
                        print("❌ Firebase save failed for \(video.title): \(error)")
                    }

                    // Grow corpus for subsequent tasks
                    existingSpines.append(spine)

                    completedVideos += 1
                    perVideoProgress[video.videoId] = "✓ \(spine.beats.count) beats"

                case .failure(let error):
                    perVideoProgress[video.videoId] = "✗ \(error.localizedDescription)"
                    print("❌ Spine extraction failed for \(video.title): \(error)")
                }

                progress = "Processing \(completedVideos)/\(totalVideos) videos"

                // Launch next task if available
                if !videoQueue.isEmpty {
                    let nextVideo = videoQueue.removeFirst()
                    let corpusSnapshot = existingSpines
                    perVideoProgress[nextVideo.videoId] = "Extracting spine..."

                    group.addTask {
                        do {
                            let spine = try await Self.extractSpineParallel(
                                for: nextVideo,
                                existingSpines: corpusSnapshot,
                                temperature: 0.1
                            )
                            return (nextVideo, .success(spine))
                        } catch {
                            return (nextVideo, .failure(error))
                        }
                    }
                    inFlight += 1
                }
            }
        }

        // 6. Done
        isRunning = false
        progress = "Done: \(completedVideos)/\(totalVideos) videos"
    }

    // MARK: - Single Extraction (legacy — uses shared adapter on MainActor)

    /// For cases that don't need parallelism.
    func extractSingleSpine(
        for video: YouTubeVideo,
        existingSpines: [NarrativeSpine]? = nil,
        temperature: Double = 0.1
    ) async throws -> NarrativeSpine {
        return try await Self.extractSpineParallel(
            for: video,
            existingSpines: existingSpines,
            temperature: temperature
        )
    }
}

// MARK: - DonorServiceProgress Conformance

extension NarrativeSpineService: DonorServiceProgress {}
