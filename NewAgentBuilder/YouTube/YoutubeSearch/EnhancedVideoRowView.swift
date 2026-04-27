//
//  EnhancedVideoRowView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/17/25.
//

import SwiftUI
import SwiftUI

// MARK: - Enhanced Video Row
struct EnhancedVideoRowView: View {
    let video: YouTubeVideo
    let onTranscriptUpdated: () -> Void
    
    //@ObservedObject private var viewModel = VideoSearchViewModel.shared
    @EnvironmentObject var viewModel: VideoSearchViewModel
    @State private var isLoadingTranscript = false
    @State private var transcriptError: String?
    @State private var isLoadingFacts = false
    @State private var factsError: String?
    @State private var isLoadingSummary = false
    @State private var summaryError: String?
    @State private var isSavingPastedTranscript = false
    
    // Get current video from global state
    var currentVideo: YouTubeVideo {
        viewModel.allVideos.first(where: { $0.videoId == video.videoId }) ?? video
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 120, height: 68)
            .cornerRadius(8)
            .overlay(
                Group {
                    if isShort(video) {
                        Text("SHORT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                },
                alignment: .bottomTrailing
            )
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                
                HStack {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                    Text("\(video.stats.viewCount.formatted())")
                        .font(.caption)
                    
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.caption2)
                        .padding(.leading, 8)
                    Text("\(video.stats.likeCount.formatted())")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                Text(video.publishedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Transcript Button
                if let transcript = currentVideo.transcript {
                    CopyButton(label: "Transcript", valueToCopy: transcript, font: .caption)
                        .foregroundColor(.green)
                } else if !isLoadingTranscript {
                    HStack(spacing: 4) {
                        Button(action: {
                            Task { await fetchTranscript() }
                        }) {
                            Text("Get")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.green)

                        Button(action: { Task { await pasteTranscriptFromClipboard() } }) {
                            Image(systemName: isSavingPastedTranscript ? "arrow.clockwise" : "doc.on.clipboard")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isSavingPastedTranscript)
                    }
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                            .font(.caption2)
                    }
                }
                
                // Facts Button
                if currentVideo.hasFacts {
                    CopyButton(label: "Facts", valueToCopy: currentVideo.factsText ?? "", font: .caption)
                        .foregroundColor(.blue)
                } else if !isLoadingFacts {
                    Button(action: { Task { await fetchFacts() } }) {
                        Label("Get Facts", systemImage: "sparkles")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Analyzing...")
                            .font(.caption2)
                    }
                }
                
                // Summary Button
                if currentVideo.hasSummary {
                    CopyButton(label: "Summary", valueToCopy: currentVideo.summaryText ?? "", font: .caption)
                        .foregroundColor(.purple)
                } else if !isLoadingSummary {
                    Button(action: { Task { await fetchSummary() } }) {
                        Label("Get Summary", systemImage: "doc.plaintext")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Summarizing...")
                            .font(.caption2)
                    }
                }
                
                if let error = transcriptError ?? factsError ?? summaryError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    func isShort(_ video: YouTubeVideo) -> Bool {
        let seconds = parseDuration(video.duration)
        return seconds < 60
    }
    
    func fetchTranscript() async {
        isLoadingTranscript = true
        transcriptError = nil
        
        do {
            let service = YouTubeTranscriptService()
            let transcript = try await service.fetchTranscript(videoId: video.videoId)
            
            // UPDATE GLOBAL VIEWMODEL FIRST (instant UI update!)
            viewModel.updateTranscript(videoId: video.videoId, transcript: transcript)
            
            // Then save to Firebase
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.updateVideoTranscript(videoId: video.videoId, transcript: transcript)
            
            print("✅ Fetched transcript for \(video.videoId)")
        } catch {
            transcriptError = "Failed"
            print("❌ Transcript error: \(error)")
        }

        isLoadingTranscript = false
    }

    func pasteTranscriptFromClipboard() async {
        #if os(iOS)
        guard let clipboard = UIPasteboard.general.string else {
            transcriptError = "Nothing on clipboard"
            return
        }
        #elseif os(macOS)
        guard let clipboard = NSPasteboard.general.string(forType: .string) else {
            transcriptError = "Nothing on clipboard"
            return
        }
        #endif

        let transcript = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)

        guard transcript.count >= 1000 else {
            transcriptError = "Too short (<1000)"
            return
        }

        isSavingPastedTranscript = true

        do {
            viewModel.updateTranscript(videoId: video.videoId, transcript: transcript)

            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.updateVideoTranscript(videoId: video.videoId, transcript: transcript)

            print("✅ Pasted transcript for \(video.videoId) (\(transcript.count) chars)")
            onTranscriptUpdated()
        } catch {
            transcriptError = "Failed to save"
            print("❌ Save transcript error: \(error)")
        }

        isSavingPastedTranscript = false
    }

    func fetchFacts() async {
        guard let transcript = currentVideo.transcript else {
            factsError = "Need transcript first"
            return
        }
        
        isLoadingFacts = true
        factsError = nil
        
        do {
            let factsAgentId = UUID(uuidString: "A9F2810D-C4DD-42BA-84DB-EC44B90EBC6F")!
            
            guard let agent = try await AgentManager().fetchAgent(with: factsAgentId) else {
                factsError = "Agent not found"
                isLoadingFacts = false
                return
            }
            
            let session = ChatSession(
                id: UUID(),
                agentId: agent.id,
                title: "Facts: \(video.title)",
                createdAt: Date()
            )
            
            let runner = AgentRunnerViewModel(agent: agent, session: session)
            
            let run = try await runner.runPromptStep(
                stepId: agent.promptSteps.first!.id,
                input: transcript,
                chatSessionId: session.id,
                purpose: .normal
            )
            
            let facts = run.response.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // UPDATE GLOBAL VIEWMODEL FIRST (instant UI update!)
            viewModel.updateFacts(videoId: video.videoId, facts: facts)
            
            // Then save to Firebase in background
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.saveVideoFacts(videoId: video.videoId, facts: facts)
            
            print("✅ Generated facts for \(video.videoId)")
        } catch {
            factsError = "Failed"
            print("❌ Facts error: \(error)")
        }
        
        isLoadingFacts = false
    }
    
    func fetchSummary() async {
        guard let transcript = currentVideo.transcript else {
            summaryError = "Need transcript first"
            return
        }
        
        isLoadingSummary = true
        summaryError = nil
        
        do {
            // TODO: Replace with your actual summary agent ID
            let summaryAgentId = UUID(uuidString: "YOUR-SUMMARY-AGENT-ID")!
            
            guard let agent = try await AgentManager().fetchAgent(with: summaryAgentId) else {
                summaryError = "Agent not found"
                isLoadingSummary = false
                return
            }
            
            let session = ChatSession(
                id: UUID(),
                agentId: agent.id,
                title: "Summary: \(video.title)",
                createdAt: Date()
            )
            
            let runner = AgentRunnerViewModel(agent: agent, session: session)
            
            let run = try await runner.runPromptStep(
                stepId: agent.promptSteps.first!.id,
                input: transcript,
                chatSessionId: session.id,
                purpose: .normal
            )
            
            let summary = run.response.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // UPDATE GLOBAL VIEWMODEL FIRST (instant UI update!)
            viewModel.updateSummary(videoId: video.videoId, summary: summary)
            
            // Then save to Firebase
            let firebaseService = YouTubeFirebaseService()
           // try await firebaseService.saveVideoSummary(videoId: video.videoId, summary: summary)
            
            print("✅ Generated summary for \(video.videoId)")
        } catch {
            summaryError = "Failed"
            print("❌ Summary error: \(error)")
        }
        
        isLoadingSummary = false
    }
    
    func parseDuration(_ duration: String) -> Double {
        var result: Double = 0
        var current = ""
        
        for char in duration {
            if char.isNumber {
                current += String(char)
            } else if char == "H" {
                result += (Double(current) ?? 0) * 3600
                current = ""
            } else if char == "M" {
                result += (Double(current) ?? 0) * 60
                current = ""
            } else if char == "S" {
                result += Double(current) ?? 0
                current = ""
            }
        }
        
        return result
    }
}
// MARK: - Enhanced Video Row
struct EnhancedVideoRowView2: View {
    let video: YouTubeVideo
    let onTranscriptUpdated: () -> Void
    @EnvironmentObject var viewModel: VideoSearchViewModel

   // @ObservedObject private var viewModel = VideoSearchViewModel.shared
    @State private var isLoadingTranscript = false
    @State private var transcriptError: String?
    @State private var localTranscript: String?
    @State private var localFacts: String?
    @State private var localSummary: String?
    @State private var isLoadingFacts = false
    @State private var factsError: String?
    @State private var isLoadingSummary = false
    @State private var summaryError: String?
    @State private var isSavingPastedTranscript = false
    var currentVideo: YouTubeVideo {
          viewModel.allVideos.first(where: { $0.videoId == video.videoId }) ?? video
      }
    
    
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 120, height: 68)
            .cornerRadius(8)
            .overlay(
                // Short badge
                Group {
                    if isShort(video) {
                        Text("SHORT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                },
                alignment: .bottomTrailing
            )
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                
                HStack {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                    Text("\(video.stats.viewCount.formatted())")
                        .font(.caption)
                    
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.caption2)
                        .padding(.leading, 8)
                    Text("\(video.stats.likeCount.formatted())")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                Text(video.publishedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Transcript Button or Copy Button
                if let transcript = video.transcript ?? localTranscript {
                    CopyButton(label: "Transcript", valueToCopy: transcript, font: .caption)
                        .foregroundColor(.green)
                } else if !isLoadingTranscript {
                    HStack(spacing: 4) {
                        Button(action: {
                            Task { await fetchTranscript() }
                        }) {
                            Text("Get")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.green)

                        Button(action: { Task { await pasteTranscriptFromClipboard() } }) {
                            Image(systemName: isSavingPastedTranscript ? "arrow.clockwise" : "doc.on.clipboard")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isSavingPastedTranscript)
                    }
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                            .font(.caption2)
                    }
                }
                
//                if let facts = video.factsText ?? localFacts{
//                    CopyButton(label: "Facts", valueToCopy: facts, font: .caption)
//                        .foregroundColor(.blue)
//                } else if !isLoadingFacts {
//                    Button(action: {
//                        Task { await fetchFacts() }
//                    }) {
//                        Label("Get Facts", systemImage: "sparkles")
//                            .font(.caption)
//                    }
//                    .buttonStyle(.bordered)
//                    .controlSize(.small)
//                } else {
//                    HStack {
//                        ProgressView()
//                            .scaleEffect(0.7)
//                        Text("Analyzing...")
//                            .font(.caption2)
//                    }
                if let transcript = currentVideo.transcript, !transcript.isEmpty{
                    
                    
                    if let facts = currentVideo.factsText {
                        CopyButton(label: "Facts", valueToCopy: facts, font: .caption)
                            .foregroundColor(.blue)
                    } else if !isLoadingFacts {
                        Button(action: { Task { await fetchFacts() } }) {
                            Label("Get Facts", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Analyzing...")
                                .font(.caption2)
                        }
                    }
                    
                    // In your body, change this:
                    if let summary = currentVideo.summaryText {  // ← Use currentVideo not video
                        CopyButton(label: "Summary", valueToCopy: summary, font: .caption)
                            .foregroundColor(.purple)
                    } else if !isLoadingSummary {
                        Button(action: {
                            Task { await fetchSummary() }  // ← Changed from fetchFacts()!
                        }) {
                            Label("Get Summary", systemImage: "doc.plaintext")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Analyzing...")
                                .font(.caption2)
                        }
                    }
                }
                if let error = transcriptError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    func isShort(_ video: YouTubeVideo) -> Bool {
        let seconds = parseDuration(video.duration)
        return seconds < 60
    }

    func pasteTranscriptFromClipboard() async {
        #if os(iOS)
        guard let clipboard = UIPasteboard.general.string else {
            transcriptError = "Nothing on clipboard"
            return
        }
        #elseif os(macOS)
        guard let clipboard = NSPasteboard.general.string(forType: .string) else {
            transcriptError = "Nothing on clipboard"
            return
        }
        #endif

        let transcript = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)

        guard transcript.count >= 1000 else {
            transcriptError = "Too short (<1000)"
            return
        }

        isSavingPastedTranscript = true

        do {
            viewModel.updateTranscript(videoId: video.videoId, transcript: transcript)

            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.updateVideoTranscript(videoId: video.videoId, transcript: transcript)

            print("✅ Pasted transcript for \(video.videoId) (\(transcript.count) chars)")
            onTranscriptUpdated()
        } catch {
            transcriptError = "Failed to save"
            print("❌ Save transcript error: \(error)")
        }

        isSavingPastedTranscript = false
    }

    func fetchFacts() async {
        guard let transcript = currentVideo.transcript else {  // ← Use currentVideo
            factsError = "Need transcript first"
            return
        }
        
        isLoadingFacts = true
        factsError = nil
        
        do {
            let factsAgentId = UUID(uuidString: "A9F2810D-C4DD-42BA-84DB-EC44B90EBC6F")!
            
            guard let agent = try await AgentManager().fetchAgent(with: factsAgentId) else {
                factsError = "Agent not found"
                isLoadingFacts = false
                return
            }
            
            let session = ChatSession(
                id: UUID(),
                agentId: agent.id,
                title: "Facts: \(video.title)",
                createdAt: Date()
            )
            
            let runner = AgentRunnerViewModel(agent: agent, session: session)
            
            let run = try await runner.runPromptStep(
                stepId: agent.promptSteps.first!.id,
                input: transcript,
                chatSessionId: session.id,
                purpose: .normal
            )
            
            let facts = run.response.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // ✅ UPDATE GLOBAL VIEWMODEL FIRST (instant UI update!)
            viewModel.updateFacts(videoId: video.videoId, facts: facts)
            
            // Then save to Firebase in background
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.saveVideoFacts(videoId: video.videoId, facts: facts)
            
            print("✅ Generated facts for \(video.videoId)")
        } catch {
            factsError = "Failed"
            print("❌ Facts error: \(error)")
        }
        
        isLoadingFacts = false
    }
    
    func fetchSummary() async {
        guard let transcript = currentVideo.transcript else {
            summaryError = "Need transcript first"
            return
        }
        
        isLoadingSummary = true
        summaryError = nil
        
        do {
            // TODO: Replace with your actual agent ID for summary
            let summaryAgentId = UUID(uuidString: "YOUR-SUMMARY-AGENT-ID")!
            
            guard let agent = try await AgentManager().fetchAgent(with: summaryAgentId) else {
                summaryError = "Agent not found"
                isLoadingSummary = false
                return
            }
            
            let session = ChatSession(
                id: UUID(),
                agentId: agent.id,
                title: "Summary: \(video.title)",
                createdAt: Date()
            )
            
            let runner = AgentRunnerViewModel(agent: agent, session: session)
            
            let run = try await runner.runPromptStep(
                stepId: agent.promptSteps.first!.id,
                input: transcript,
                chatSessionId: session.id,
                purpose: .normal
            )
            
            let summary = run.response.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // ✅ UPDATE GLOBAL VIEWMODEL FIRST
            viewModel.updateSummary(videoId: video.videoId, summary: summary)
            
            // Then save to Firebase
            let firebaseService = YouTubeFirebaseService()
            //try await firebaseService.saveVideoSummary(videoId: video.videoId, summary: summary)
            
            print("✅ Generated summary for \(video.videoId)")
        } catch {
            summaryError = "Failed"
            print("❌ Summary error: \(error)")
        }
        
        isLoadingSummary = false
    }
    
    func parseDuration(_ duration: String) -> Double {
        var result: Double = 0
        var current = ""
        
        for char in duration {
            if char.isNumber {
                current += String(char)
            } else if char == "H" {
                result += (Double(current) ?? 0) * 3600
                current = ""
            } else if char == "M" {
                result += (Double(current) ?? 0) * 60
                current = ""
            } else if char == "S" {
                result += Double(current) ?? 0
                current = ""
            }
        }
        
        return result
    }
    
    func fetchTranscript() async {
        isLoadingTranscript = true
        transcriptError = nil
        
        do {
            let service = YouTubeTranscriptService()
            let transcript = try await service.fetchTranscript(videoId: video.videoId)
            //localTranscript = transcript
            viewModel.updateTranscript(videoId: video.videoId, transcript: transcript)
            
            // Save to Firebase
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.updateVideoTranscript(videoId: video.videoId, transcript: transcript)
            
            onTranscriptUpdated()
            print("✅ Fetched transcript for \(video.videoId)")
        } catch {
            transcriptError = "Failed"
            print("❌ Transcript error: \(error)")
        }

        isLoadingTranscript = false
    }
}

