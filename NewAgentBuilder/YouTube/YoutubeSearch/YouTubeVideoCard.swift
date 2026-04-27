//
//  YouTubeVideoCard.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 10/18/25.
//


import SwiftUI

struct YouTubeVideoCard: View {
    let video: YouTubeVideo
    let onTranscriptUpdated: () -> Void
    let onTapped: () -> Void
    
    @EnvironmentObject var viewModel: VideoSearchViewModel
    @State private var isLoadingTranscript = false
    @State private var transcriptError: String?
    @State private var isLoadingFacts = false
    @State private var factsError: String?
    @State private var isLoadingSummary = false
    @State private var summaryError: String?
    @State private var isUpdatingStats = false
    @State private var isSavingPastedTranscript = false

    // Sentence Analysis State
    @State private var hasSentenceAnalysis = false
    @State private var sentenceTestRuns: [SentenceFidelityTest] = []
    @State private var isLoadingSentenceData = false

    var currentVideo: YouTubeVideo {
        viewModel.allVideos.first(where: { $0.videoId == video.videoId }) ?? video
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail with overlays
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(16/9, contentMode: .fill)
                }
                .clipped()
                
                // Overlays
                HStack {
                    // SHORT badge (bottom left)
                    if isShort(video) {
                        Text("SHORT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // Duration (bottom right)
                    Text(formatDuration(video.duration))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(4)
                }
                .padding(8)
            }
            .onTapGesture {
                onTapped()
            }
            
            // Content section
            VStack(alignment: .leading, spacing: 8) {
                // Title (2 lines max)
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Stats row
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.caption2)
                        Text(formatNumber(video.stats.viewCount))
                            .font(.caption)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.caption2)
                        Text(formatNumber(video.stats.likeCount))
                            .font(.caption)
                    }
                    
                    Text(video.publishedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                // Action buttons row
                HStack(spacing: 8) {
                    TranscriptButton()
                    FactsButton()
                    SummaryButton()
                }
                HStack(spacing: 8) {
                    copyHookButton()
                    copyHookwTitleButton()
                    copyScriptWTitleButton()
                    UpdateStatsButton()
                }

                // Sentence Analysis Row
                HStack(spacing: 8) {
                    SentenceAnalysisButton()
                }
                
                
                // Bottom buttons row
                HStack(spacing: 8) {
                    Button(action: onTapped) {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                            Text("See Details")
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                    }
                    
                    Button(action: { /* TODO: Hide functionality */ }) {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.gray)
                            .cornerRadius(6)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .task {
            await checkSentenceAnalysis()
        }
    }

    // MARK: - Sentence Analysis Check

    private func checkSentenceAnalysis() async {
        do {
            let runs = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
            await MainActor.run {
                sentenceTestRuns = runs
                hasSentenceAnalysis = !runs.isEmpty
            }
        } catch {
            print("❌ Error checking sentence analysis: \(error)")
        }
    }

    // MARK: - Button Components
    @ViewBuilder
    private func UpdateStatsButton() -> some View {
        Button(action: { Task { await updateVideoStats() } }) {
            HStack(spacing: 4) {
                Image(systemName: isUpdatingStats ? "arrow.clockwise" : "chart.xyaxis.line")
                //Text(isUpdatingStats ? "Updating..." : "Update Stats")
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.purple.opacity(0.1))
            .foregroundColor(.purple)
            .cornerRadius(6)
        }
        .disabled(isUpdatingStats)
    }
    @ViewBuilder
    private func TranscriptButton() -> some View {
        if let transcript = currentVideo.transcript {
            CopyButton(label: "Transcript", valueToCopy: transcript, font: .caption,includesCopyPrefix: false)
                .foregroundColor(.green)
        } else if isLoadingTranscript {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading")
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        } else {
            HStack(spacing: 4) {
                Button(action: { Task { await fetchTranscript() } }) {
                    Text("Get")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }

                Button(action: { Task { await pasteTranscriptFromClipboard() } }) {
                    Image(systemName: isSavingPastedTranscript ? "arrow.clockwise" : "doc.on.clipboard")
                        .font(.caption)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.secondary)
                        .cornerRadius(6)
                }
                .disabled(isSavingPastedTranscript)
            }
        }
    }
    
    @ViewBuilder
    private func copyHookButton() -> some View {
        if let transcript = currentVideo.transcript {
            let opening = transcript.prefix(250)
            CopyButton(label: "Opening", valueToCopy: String(opening), font: .caption, includesCopyPrefix: false)
                .foregroundColor(.blue)
        } else {
            EmptyView()
        }
    }
    @ViewBuilder
    private func copyHookwTitleButton() -> some View {
        if let transcript = currentVideo.transcript {
            let title = currentVideo.title
        
            let opening = transcript.prefix(400)
            let copyString = "\(title)\n\n\(String(opening))"
            CopyButton(label: "Title N Open", valueToCopy: String(copyString), font: .caption, showIcon: false, includesCopyPrefix: false)
                .foregroundColor(.gray)
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func copyScriptWTitleButton() -> some View {
        if let transcript = currentVideo.transcript {
            let title = currentVideo.title
        
            let opening = transcript.prefix(400)
            let copyString = "Title:\(title)\n\nScript:\(String(transcript))"
            CopyButton(label: "Title N Script", valueToCopy: String(copyString), font: .caption, showIcon: false, includesCopyPrefix: false)
                .foregroundColor(.gray)
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func FactsButton() -> some View {
        if currentVideo.hasFacts {
            CopyButton(label: "Facts", valueToCopy: currentVideo.factsText ?? "", font: .caption, showIcon: false, includesCopyPrefix: false)
                .foregroundColor(.blue)
        } else if isLoadingFacts {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Facts")
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        } else {
            Button(action: { Task { await fetchFacts() } }) {
                Text("Get Facts")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }
        }
    }
    
    @ViewBuilder
    private func SummaryButton() -> some View {
        if currentVideo.hasSummary {
            CopyButton(label: "Summary", valueToCopy: currentVideo.summaryText ?? "", font: .caption)
                .foregroundColor(.purple)
        } else if isLoadingSummary {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Summary")
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        } else {
            Button(action: { Task { await fetchSummary() } }) {
                Text("Get Summary")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.1))
                    .foregroundColor(.purple)
                    .cornerRadius(6)
            }
        }
    }

    @ViewBuilder
    private func SentenceAnalysisButton() -> some View {
        let wc = currentVideo.wordCount
        let isShortVideo = currentVideo.durationSeconds < 60
        let isBadWordCount = wc < 100

        if hasSentenceAnalysis {
            // Has sentence analysis - show copy button with word count & duration
            let latestRun = sentenceTestRuns.sorted { $0.createdAt > $1.createdAt }.first
            let sentenceCount = latestRun?.totalSentences ?? 0
            let runCount = sentenceTestRuns.count

            Button(action: { copySentenceAnalysis() }) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                    Text("\(sentenceCount)s · \(runCount)r ·")
                    Text("\(wc)w")
                        .foregroundColor(isBadWordCount ? .red : .green)
                    Text("·")
                    Text(currentVideo.durationFormatted)
                        .foregroundColor(isShortVideo ? .red : .green)
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(6)
            }
        } else if isLoadingSentenceData {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Sentences")
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        } else if currentVideo.transcript != nil {
            // Has transcript but no analysis yet - show word count & duration
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                Text("No Analysis ·")
                Text("\(wc)w")
                    .foregroundColor(isBadWordCount ? .red : .secondary)
                Text("·")
                Text(currentVideo.durationFormatted)
                    .foregroundColor(isShortVideo ? .red : .secondary)
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .foregroundColor(.secondary)
            .cornerRadius(6)
        } else {
            // No transcript - show 0 word count & duration
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                Text("0w")
                    .foregroundColor(.red)
                Text("·")
                Text(currentVideo.durationFormatted)
                    .foregroundColor(isShortVideo ? .red : .secondary)
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .foregroundColor(.secondary)
            .cornerRadius(6)
        }
    }

    private func copySentenceAnalysis() {
        guard let latestRun = sentenceTestRuns.sorted(by: { $0.createdAt > $1.createdAt }).first else { return }

        var output = """
        ════════════════════════════════════════════════════════════════
        SENTENCE TELEMETRY: \(video.title)
        ════════════════════════════════════════════════════════════════

        Video ID: \(video.videoId)
        Total Sentences: \(latestRun.totalSentences)
        Analysis Date: \(latestRun.createdAt.formatted())
        Mode: \(latestRun.taggingMode ?? "unknown")
        Temperature: \(String(format: "%.1f", latestRun.temperature ?? 0))

        ────────────────────────────────────────────────────────────────
        SENTENCES
        ────────────────────────────────────────────────────────────────

        """

        for sentence in latestRun.sentences {
            output += "\n[\(sentence.sentenceIndex)] \(sentence.text)\n"

            // Core attributes
            output += "   pos=\(String(format: "%.2f", sentence.positionPercentile)) words=\(sentence.wordCount)\n"
            output += "   stance=\(sentence.stance) perspective=\(sentence.perspective)\n"

            // Flags
            var flags: [String] = []
            if sentence.hasNumber { flags.append("number") }
            if sentence.hasStatistic { flags.append("statistic") }
            if sentence.hasQuote { flags.append("quote") }
            if sentence.hasNamedEntity { flags.append("entity") }
            if sentence.hasContrastMarker { flags.append("contrast") }
            if sentence.hasTemporalMarker { flags.append("temporal") }
            if sentence.hasFirstPerson { flags.append("1st-person") }
            if sentence.hasSecondPerson { flags.append("2nd-person") }
            if sentence.hasRevealLanguage { flags.append("reveal") }
            if sentence.hasPromiseLanguage { flags.append("promise") }
            if sentence.hasChallengeLanguage { flags.append("challenge") }
            if sentence.isTransition { flags.append("transition") }
            if sentence.isCallToAction { flags.append("CTA") }
            if sentence.isSponsorContent { flags.append("sponsor") }
            if sentence.endsWithQuestion { flags.append("question") }
            if sentence.endsWithExclamation { flags.append("exclamation") }

            if !flags.isEmpty {
                output += "   flags: \(flags.joined(separator: ", "))\n"
            }
        }

        output += "\n════════════════════════════════════════════════════════════════\n"

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif

        print("✅ Copied sentence analysis for \(video.title)")
    }

    // MARK: - Helper Functions
    
    private func isShort(_ video: YouTubeVideo) -> Bool {
        parseDuration(video.duration) < 60
    }
    
    private func parseDuration(_ duration: String) -> Double {
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
    
    private func formatDuration(_ duration: String) -> String {
        let seconds = parseDuration(duration)
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchTranscript() async {
        isLoadingTranscript = true
        transcriptError = nil
        
        do {
            let service = YouTubeTranscriptService()
            let transcript = try await service.fetchTranscript(videoId: video.videoId)
            
            viewModel.updateTranscript(videoId: video.videoId, transcript: transcript)
            
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.updateVideoTranscript(videoId: video.videoId, transcript: transcript)
            
            print("✅ Fetched transcript for \(video.videoId)")
        } catch {
            transcriptError = "Failed"
            print("❌ Transcript error: \(error)")
        }

        isLoadingTranscript = false
    }

    private func pasteTranscriptFromClipboard() async {
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

    private func updateVideoStats() async {
        isUpdatingStats = true
        
        do {
            let firebaseService = YouTubeFirebaseService()
            // You'll need to pass API key - could store in UserDefaults or keychain
            let apiKey = "YOUR_API_KEY" // TODO: Get from secure storage
            
            let updatedVideo = try await firebaseService.updateVideoStats(
                videoId: video.videoId
            )
            
            // Update the ViewModel
            viewModel.updateVideo(updatedVideo)
            
            print("✅ Updated stats for: \(video.title)")
        } catch {
            print("❌ Failed to update stats: \(error)")
        }
        
        isUpdatingStats = false
    }
    
    private func fetchFacts() async {
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
            
            viewModel.updateFacts(videoId: video.videoId, facts: facts)
            
            let firebaseService = YouTubeFirebaseService()
            try await firebaseService.saveVideoFacts(videoId: video.videoId, facts: facts)
            
            print("✅ Generated facts for \(video.videoId)")
        } catch {
            factsError = "Failed"
            print("❌ Facts error: \(error)")
        }
        
        isLoadingFacts = false
    }
    
    private func fetchSummary() async {
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
            
            viewModel.updateSummary(videoId: video.videoId, summary: summary)
            
            print("✅ Generated summary for \(video.videoId)")
        } catch {
            summaryError = "Failed"
            print("❌ Summary error: \(error)")
        }
        
        isLoadingSummary = false
    }
}
