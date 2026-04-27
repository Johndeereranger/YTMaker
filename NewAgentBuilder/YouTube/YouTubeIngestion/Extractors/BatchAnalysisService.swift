//
//  VideoAnalysisState.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/22/26.
//


import SwiftUI
import Combine

// MARK: - Video Analysis Status Model

enum VideoAnalysisState: Equatable {
    case notStarted
    case inProgress(phase: String, progress: Double)
    case a1aComplete
    case a1bComplete  // Has scriptSummary, ready for A3
    case fullComplete // All A1c done too
    case failed(error: String)
    
    var displayText: String {
        switch self {
        case .notStarted: return "Not Analyzed"
        case .inProgress(let phase, let progress): return "\(phase) (\(Int(progress * 100))%)"
        case .a1aComplete: return "Sections Only"
        case .a1bComplete: return "Ready for A3 ✓"
        case .fullComplete: return "Complete ✓✓"
        case .failed(let error): return "Failed: \(error)"
        }
    }
    
    var color: Color {
        switch self {
        case .notStarted: return .secondary
        case .inProgress: return .blue
        case .a1aComplete: return .yellow
        case .a1bComplete: return .green
        case .fullComplete: return .green
        case .failed: return .red
        }
    }
    
    var isReadyForA3: Bool {
        switch self {
        case .a1bComplete, .fullComplete: return true
        default: return false
        }
    }
}

struct VideoAnalysisStatus: Identifiable {
    let id: String
    let video: YouTubeVideo
    var state: VideoAnalysisState
    var sectionCount: Int?
    var beatCount: Int?
    var hasScriptSummary: Bool
}

// MARK: - Batch Analysis Service

@MainActor
class BatchAnalysisService: ObservableObject {
    
    // MARK: - Published State
    @Published var videoStatuses: [VideoAnalysisStatus] = []
    @Published var isRunning = false
    @Published var overallProgress: String = ""
    @Published var completedCount = 0
    @Published var failedCount = 0
    @Published var totalCount = 0
    
    // MARK: - Configuration
    private let maxConcurrent: Int = 3  // Max parallel video processing
    
    // MARK: - Load Video Statuses
    
    func loadStatuses(for videos: [YouTubeVideo]) async {
        guard let channelId = videos.first?.channelId else {
            videoStatuses = []
            return
        }

        do {
            // 2 queries total instead of N per-video round-trips
            let allSections = try await CreatorAnalysisFirebase.shared.loadAllSections(forChannel: channelId)
            let allBeatDocs = try await CreatorAnalysisFirebase.shared.loadAllBeatDocs(forChannel: channelId)

            videoStatuses = videos.map { video in
                buildStatus(video: video, allSections: allSections, allBeatDocs: allBeatDocs)
            }
        } catch {
            print("❌ Failed to bulk-load statuses: \(error)")
            // Fallback: mark everything as notStarted rather than hanging
            videoStatuses = videos.map { video in
                VideoAnalysisStatus(
                    id: video.videoId, video: video, state: .notStarted,
                    sectionCount: nil, beatCount: nil, hasScriptSummary: false
                )
            }
        }
    }

    /// Build status for one video using the pre-fetched bulk data (no Firebase calls).
    private func buildStatus(
        video: YouTubeVideo,
        allSections: [String: [SectionData]],
        allBeatDocs: [String: [BeatDoc]]
    ) -> VideoAnalysisStatus {
        let sections = allSections[video.videoId] ?? []

        guard !sections.isEmpty else {
            return VideoAnalysisStatus(
                id: video.videoId, video: video, state: .notStarted,
                sectionCount: nil, beatCount: nil, hasScriptSummary: false
            )
        }

        // Count beats across all sections for this video
        var totalBeats = 0
        var allSectionsHaveBeats = true
        var hasFullAnalysis = false

        for section in sections {
            let beats = allBeatDocs[section.id] ?? []
            totalBeats += beats.count
            if beats.isEmpty {
                allSectionsHaveBeats = false
            }
            // Check for A1c fields
            for beat in beats {
                if (beat.moveKey != "UNKNOWN" && !beat.moveKey.isEmpty) || !beat.compilerFunction.isEmpty {
                    hasFullAnalysis = true
                }
            }
        }

        // scriptSummary is already on the video object — no extra Firebase call
        let hasScriptSummary = video.scriptSummary != nil

        let state: VideoAnalysisState
        if hasScriptSummary {
            state = hasFullAnalysis ? .fullComplete : .a1bComplete
        } else if allSectionsHaveBeats && totalBeats > 0 {
            state = .a1bComplete
        } else if totalBeats > 0 {
            state = .a1aComplete
        } else {
            state = .a1aComplete
        }

        return VideoAnalysisStatus(
            id: video.videoId, video: video, state: state,
            sectionCount: sections.count, beatCount: totalBeats,
            hasScriptSummary: hasScriptSummary
        )
    }
    
    // MARK: - Batch Processing
    
    /// Process all unanalyzed videos with Fast Analysis (A1a + A1b only)
    func processAllUnanalyzed() async {
        let unanalyzed = videoStatuses.filter { $0.state == .notStarted }
        guard !unanalyzed.isEmpty else { return }
        
        await processVideos(unanalyzed.map { $0.video })
    }
    
    /// Process specific videos with Fast Analysis
    func processVideos(_ videos: [YouTubeVideo]) async {
        isRunning = true
        totalCount = videos.count
        completedCount = 0
        failedCount = 0
        overallProgress = "Starting batch analysis..."
        
        // Process in parallel batches
        await withTaskGroup(of: (String, Result<Void, Error>).self) { group in
            var activeCount = 0
            var videoIndex = 0
            
            while videoIndex < videos.count || activeCount > 0 {
                // Add tasks up to max concurrent
                while activeCount < maxConcurrent && videoIndex < videos.count {
                    let video = videos[videoIndex]
                    videoIndex += 1
                    activeCount += 1
                    
                    group.addTask {
                        do {
                            try await self.processSingleVideo(video)
                            return (video.videoId, .success(()))
                        } catch {
                            return (video.videoId, .failure(error))
                        }
                    }
                }
                
                // Wait for one to complete
                if let result = await group.next() {
                    activeCount -= 1
                    
                    switch result.1 {
                    case .success:
                        completedCount += 1
                        updateVideoStatus(videoId: result.0, state: .a1bComplete)
                    case .failure(let error):
                        failedCount += 1
                        updateVideoStatus(videoId: result.0, state: .failed(error: error.localizedDescription))
                    }
                    
                    overallProgress = "Processed \(completedCount + failedCount) of \(totalCount) videos"
                }
            }
        }
        
        isRunning = false
        overallProgress = "Complete: \(completedCount) succeeded, \(failedCount) failed"
        
        // Refresh all statuses
        let videos = videoStatuses.map { $0.video }
        await loadStatuses(for: videos)
    }
    
    private func processSingleVideo(_ video: YouTubeVideo) async throws {
        print("🚀 processSingleVideo starting: \(video.videoId)")
        
        updateVideoStatus(videoId: video.videoId, state: .inProgress(phase: "A1a", progress: 0))
        
        let viewModel = ManualIngestionViewModel(video: video)
        
        // Run A1a
        viewModel.generateSectionPrompt()
        print("📝 A1a prompt generated, running AI...")
        
        await viewModel.autoRunA1a()
        
        print("🔍 After autoRunA1a:")
        print("   - a1aStep: \(viewModel.a1aStep)")
        print("   - autoRunError: \(viewModel.autoRunError?.error ?? "none")")
        print("   - processedAlignment sections: \(viewModel.processedAlignment?.sections.count ?? -1)")
        
        if let error = viewModel.autoRunError {
            throw NSError(domain: "BatchAnalysis", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "A1a failed: \(error.error)"])
        }
        
        // Save A1a
        print("🔍 Checking if should save: a1aStep == .review? \(viewModel.a1aStep == .review)")
        
        if viewModel.a1aStep == .review {
            print("💾 Calling saveAlignment()...")
            await viewModel.saveAlignment()
            print("💾 saveAlignment() complete, savedAlignment: \(viewModel.savedAlignment != nil)")
        } else {
            print("⚠️ NOT saving - a1aStep is \(viewModel.a1aStep), not .review")
        }
        
        guard let alignment = viewModel.savedAlignment else {
            print("❌ No savedAlignment after save attempt!")
            throw NSError(domain: "BatchAnalysis", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to save alignment"])
        }
        
        print("✅ A1a complete with \(alignment.sections.count) sections, proceeding to A1b...")
        print(("======================================================================================== \n======================================================================================== \n======================================================================================== \n======================================================================================== \n======================================================================================== \n======================================================================================== \n======================================================================================== \n======================================================================================== \n======================================================================================== \n======================================================================================== \n======================================================================================== \n======================================================================================== \n"))
        
        
        // Run A1b for all sections
        let totalSections = alignment.sections.count
        
        for sectionIdx in 0..<totalSections {
            updateVideoStatus(
                videoId: video.videoId,
                state: .inProgress(phase: "A1b S\(sectionIdx + 1)/\(totalSections)", progress: Double(sectionIdx) / Double(totalSections))
            )
            
            viewModel.currentSectionIndex = sectionIdx
            viewModel.currentPhase = .a1b_beats
            viewModel.a1bStep = .showPrompt
            viewModel.beatResponse = ""
            viewModel.currentSectionBeatData = nil
            
            viewModel.generateBeatPrompt()
            await viewModel.autoRunA1b()
            
            if let error = viewModel.autoRunError {
                throw NSError(domain: "BatchAnalysis", code: 3,
                             userInfo: [NSLocalizedDescriptionKey: "A1b failed at section \(sectionIdx + 1): \(error.error)"])
            }
            
            // Save beats
            if viewModel.a1bStep == .review {
                await viewModel.saveBeatsOnly()
            }
        }
        
        // Compute and save scriptSummary
        updateVideoStatus(videoId: video.videoId, state: .inProgress(phase: "Saving Summary", progress: 0.95))
        await viewModel.computeAndSaveScriptSummary()
    }
    
    private func updateVideoStatus(videoId: String, state: VideoAnalysisState) {
        if let index = videoStatuses.firstIndex(where: { $0.id == videoId }) {
            videoStatuses[index].state = state
        }
    }
    
    // MARK: - Helpers
    
    var readyForA3Count: Int {
        videoStatuses.filter { $0.state.isReadyForA3 }.count
    }
    
    var unanalyzedCount: Int {
        videoStatuses.filter { $0.state == .notStarted }.count
    }
}
