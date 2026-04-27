//
//  PreA0BrowseView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import SwiftUI

struct PreA0BrowseView: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel

    // MARK: - State

    @State private var currentStep: PreA0Step = .fetching
    @State private var allVideos: [BrowseVideoMetadata] = []
    @State private var existingVideoIds: Set<String> = []
    @State private var clusters: [TitleCluster] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var progressMessage = ""
    @State private var fetchProgress: Double = 0

    // Import state
    @State private var isImporting = false
    @State private var importProgress = ""

    // Review state (pause before clustering)
    @State private var isReadyToCluster = false
    @State private var isCopied = false
    @State private var isClustersCopied = false
    @State private var shortsFilteredCount = 0

    var totalSelected: Int {
        clusters.reduce(0) { $0 + $1.totalSelected }
    }

    var newVideosToImport: Int {
        clusters.reduce(0) { $0 + $1.selectedCount }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            stepIndicator
                .padding()
                .background(Color(.secondarySystemBackground))

            Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch currentStep {
                    case .fetching:
                        fetchingView
                    case .clustering:
                        clusteringView
                    case .selecting:
                        selectionView
                    case .importing:
                        importingView
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Browse \(channel.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if currentStep == .selecting {
                    Button("Import \(newVideosToImport)") {
                        Task { await importSelectedVideos() }
                    }
                    .disabled(newVideosToImport == 0 || isImporting)
                } else if currentStep == .clustering && !isReadyToCluster {
                    Button {
                        copyTitlesToClipboard()
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .task {
            await startWorkflow()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(PreA0Step.allCases, id: \.rawValue) { step in
                HStack(spacing: 8) {
                    Circle()
                        .fill(stepColor(for: step))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if step.rawValue < currentStep.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                            } else {
                                Text("\(step.rawValue + 1)")
                                    .font(.caption.bold())
                                    .foregroundColor(step == currentStep ? .white : .secondary)
                            }
                        }

                    Text(step.title)
                        .font(.caption)
                        .foregroundColor(step == currentStep ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func stepColor(for step: PreA0Step) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .green
        } else if step == currentStep {
            return .blue
        } else {
            return Color(.systemGray4)
        }
    }

    // MARK: - Fetching View

    private var fetchingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Fetching videos from YouTube...")
                .font(.headline)

            if !progressMessage.isEmpty {
                Text(progressMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if fetchProgress > 0 {
                ProgressView(value: fetchProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 100)
    }

    // MARK: - Clustering View

    private var clusteringView: some View {
        VStack(spacing: 20) {
            if isReadyToCluster {
                // Actually clustering
                ProgressView()
                    .scaleEffect(1.5)

                Text("Clustering \(allVideos.count) videos by content theme...")
                    .font(.headline)

                Text("This uses AI to identify content patterns")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                // Paused - ready to review/copy titles
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title)
                        VStack(alignment: .leading) {
                            Text("Fetched \(allVideos.count) Long-Form Videos")
                                .font(.headline)
                            Text("\(existingVideoIds.count) already in library")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if shortsFilteredCount > 0 {
                                Text("\(shortsFilteredCount) Shorts filtered out")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    Divider()

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            copyTitlesToClipboard()
                        } label: {
                            HStack {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                Text(isCopied ? "Copied!" : "Copy All Titles")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await startClustering() }
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Auto Cluster")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }

                    // Titles + Descriptions preview
                    Text("Videos (Title + Description)")
                        .font(.headline)
                        .padding(.top, 8)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(allVideos.enumerated()), id: \.element.id) { index, video in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(index + 1).")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 30, alignment: .trailing)
                                        Text(video.title)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .lineLimit(2)
                                    }
                                    if !video.description.isEmpty {
                                        Text(String(video.description.prefix(150)) + (video.description.count > 150 ? "..." : ""))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                            .padding(.leading, 38)
                                    }
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
    }

    private func copyTitlesToClipboard() {
        // Include both title and cleaned description for clustering
        let videosText = allVideos.enumerated().map { index, video in
            let cleanedDesc = cleanDescription(video.description)
            if cleanedDesc.isEmpty {
                return "\(index + 1). \(video.title)"
            }
            return "\(index + 1). \(video.title)\n   Description: \(cleanedDesc)"
        }.joined(separator: "\n\n")

        UIPasteboard.general.string = videosText
        isCopied = true

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }

    private func copyClustersToClipboard() {
        var output = "# CONTENT THEME ANALYSIS\n\n"
        output += "Found \(clusters.count) content themes across \(allVideos.count) long-form videos.\n\n"
        output += "---\n\n"

        // List all themes first
        output += "## THEMES OVERVIEW\n\n"
        for (index, cluster) in clusters.enumerated() {
            output += "\(index + 1). **\(cluster.theme)** (\(cluster.videos.count) videos)\n"
            output += "   \(cluster.description)\n\n"
        }

        output += "---\n\n"

        // Detailed breakdown by theme
        output += "## DETAILED BREAKDOWN BY THEME\n\n"

        for cluster in clusters {
            output += "### \(cluster.theme)\n"
            output += "_\(cluster.description)_\n\n"
            output += "**Videos in this theme (\(cluster.videos.count)):**\n\n"

            for video in cluster.videos {
                let existingTag = existingVideoIds.contains(video.videoId) ? " [IMPORTED]" : ""
                let cleanedDesc = cleanDescription(video.description)
                output += "- **\(video.title)**\(existingTag)\n"
                if !cleanedDesc.isEmpty {
                    output += "  \(cleanedDesc)\n"
                }
                output += "\n"
            }

            output += "---\n\n"
        }

        UIPasteboard.general.string = output
    }

    /// Clean up YouTube description to extract just the useful content summary
    /// Removes URLs, social links, sponsor sections, and other boilerplate
    private func cleanDescription(_ description: String) -> String {
        var text = description

        // Remove URLs (http/https)
        let urlPattern = #"https?://[^\s]+"#
        text = text.replacingOccurrences(of: urlPattern, with: "", options: .regularExpression)

        // Remove common social/promo lines
        let noisePatterns = [
            #"(?i)follow\s*(me\s*)?(on|at|@).*"#,
            #"(?i)subscribe.*"#,
            #"(?i)twitter[:/].*"#,
            #"(?i)instagram[:/].*"#,
            #"(?i)tiktok[:/].*"#,
            #"(?i)facebook[:/].*"#,
            #"(?i)patreon[:/].*"#,
            #"(?i)merch[:/].*"#,
            #"(?i)sponsor(ed|ship)?.*"#,
            #"(?i)use\s+code\s+.*"#,
            #"(?i)discount\s+code.*"#,
            #"(?i)links?\s*below.*"#,
            #"(?i)check\s+out\s+my.*"#,
            #"(?i)join\s+(my\s+)?(membership|channel).*"#,
            #"(?i)#\w+\s*"#,  // Hashtags
            #"@\w+\s*"#,      // @mentions
            #"\d{1,2}:\d{2}(:\d{2})?\s*-?\s*"#,  // Timestamps like "0:00 - "
        ]

        for pattern in noisePatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Collapse multiple newlines/spaces
        text = text.replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)

        // Trim and take first ~400 chars of useful content
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If still long, truncate intelligently at sentence boundary
        if text.count > 400 {
            let truncated = String(text.prefix(400))
            // Try to end at a sentence
            if let lastPeriod = truncated.lastIndex(of: ".") {
                text = String(truncated[...lastPeriod])
            } else if let lastNewline = truncated.lastIndex(of: "\n") {
                text = String(truncated[..<lastNewline])
            } else {
                text = truncated + "..."
            }
        }

        return text
    }

    private func startClustering() async {
        isReadyToCluster = true
        await clusterVideos()
    }

    /// Parse ISO 8601 duration (PT1H2M3S) to seconds
    private func parseDurationToSeconds(_ duration: String) -> Int {
        var totalSeconds = 0
        var currentNumber = ""

        for char in duration {
            if char.isNumber {
                currentNumber += String(char)
            } else if char == "H" {
                totalSeconds += (Int(currentNumber) ?? 0) * 3600
                currentNumber = ""
            } else if char == "M" {
                totalSeconds += (Int(currentNumber) ?? 0) * 60
                currentNumber = ""
            } else if char == "S" {
                totalSeconds += Int(currentNumber) ?? 0
                currentNumber = ""
            }
        }
        return totalSeconds
    }

    // MARK: - Selection View

    private var selectionView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Summary
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(clusters.count) Content Themes Found")
                            .font(.headline)
                        Text("\(allVideos.count) long-form videos, \(existingVideoIds.count) already imported")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if shortsFilteredCount > 0 {
                            Text("\(shortsFilteredCount) Shorts filtered out")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(totalSelected) selected")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Text("\(newVideosToImport) new to import")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Copy clusters button
                Button {
                    copyClustersToClipboard()
                    isClustersCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isClustersCopied = false
                    }
                } label: {
                    HStack {
                        Image(systemName: isClustersCopied ? "checkmark" : "doc.on.doc")
                        Text(isClustersCopied ? "Copied!" : "Copy Full Cluster Analysis")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // Clusters
            ForEach($clusters) { $cluster in
                ClusterSelectionCard(
                    cluster: $cluster,
                    existingVideoIds: existingVideoIds
                )
            }
        }
    }

    // MARK: - Importing View

    private var importingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Importing selected videos...")
                .font(.headline)

            Text(importProgress)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 100)
    }

    // MARK: - Workflow

    private func startWorkflow() async {
        await fetchVideos()
    }

    private func fetchVideos() async {
        isLoading = true
        currentStep = .fetching
        progressMessage = "Loading existing videos from library..."

        do {
            // First, get existing video IDs from Firebase
            existingVideoIds = try await YouTubeFirebaseService.shared.getExistingVideoIds(forChannel: channel.channelId)
            progressMessage = "Found \(existingVideoIds.count) videos in library"

            // Fetch all videos from YouTube API
            progressMessage = "Fetching from YouTube..."
            let apiService = YouTubeAPIService(apiKey: YouTubeAPIKeyManager.shared.apiKey)

            let fetchedVideos = try await apiService.fetchVideos(
                channelId: channel.channelId,
                maxVideos: nil
            ) { count in
                Task { @MainActor in
                    progressMessage = "Fetched \(count) videos..."
                    fetchProgress = min(1.0, Double(count) / Double(max(channel.videoCount, 1)))
                }
            }

            // Convert to BrowseVideoMetadata (ephemeral)
            // Filter out Shorts (duration < 60 seconds) - we only want long-form content for style analysis
            let allFetched = fetchedVideos.map { BrowseVideoMetadata(from: $0) }
            let longFormVideos = allFetched.filter { video in
                // Filter out Shorts by multiple criteria
                let seconds = parseDurationToSeconds(video.duration)
                let hasShortTag = video.title.lowercased().contains("#short")
                let isTooShort = seconds < 120  // Under 2 minutes is likely a Short or not useful for style analysis

                // Debug: Print videos near the boundary
                if seconds > 0 && seconds < 180 {
                    print("⏱️ Near boundary: \(seconds)s - \(video.title.prefix(50))")
                }

                return seconds >= 120 && !hasShortTag  // At least 2 minutes AND no #short tag
            }
            shortsFilteredCount = allFetched.count - longFormVideos.count
            allVideos = longFormVideos
            progressMessage = "Fetched \(allVideos.count) long-form videos (\(shortsFilteredCount) Shorts/short videos filtered out)"

            // Move to clustering step (paused for review)
            currentStep = .clustering
            isLoading = false

        } catch {
            errorMessage = "Failed to fetch videos: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func clusterVideos() async {
        currentStep = .clustering

        do {
            clusters = try await TitleClusteringService.shared.clusterTitles(
                videos: allVideos,
                existingVideoIds: existingVideoIds,
                targetClusters: 6
            )

            currentStep = .selecting
            isLoading = false

        } catch {
            errorMessage = "Failed to cluster videos: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func importSelectedVideos() async {
        currentStep = .importing
        isImporting = true

        // Gather all selected video IDs (new ones only)
        var videoIdsToImport: [String] = []
        for cluster in clusters {
            videoIdsToImport.append(contentsOf: cluster.selectedVideoIds)
        }

        guard !videoIdsToImport.isEmpty else {
            errorMessage = "No new videos selected to import"
            currentStep = .selecting
            isImporting = false
            return
        }

        do {
            let apiService = YouTubeAPIService(apiKey: YouTubeAPIKeyManager.shared.apiKey)
            var importedCount = 0

            for videoId in videoIdsToImport {
                importProgress = "Importing \(importedCount + 1)/\(videoIdsToImport.count)..."

                // Fetch full video details
                let video = try await apiService.fetchVideoDetails(videoId: videoId)

                // Save with taxonomy purpose flag
                var videoToSave = video
                videoToSave.forTaxonomyBuilding = true

                try await YouTubeFirebaseService.shared.saveVideo(videoToSave)
                importedCount += 1
            }

            importProgress = "Imported \(importedCount) videos!"

            // Brief pause to show completion
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            // Navigate back
            nav.pop()

        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
            currentStep = .selecting
            isImporting = false
        }
    }
}

// MARK: - Cluster Selection Card

struct ClusterSelectionCard: View {
    @Binding var cluster: TitleCluster
    let existingVideoIds: Set<String>

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cluster.theme)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(cluster.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            if cluster.existingCount > 0 {
                                Text("\(cluster.existingCount) imported")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            Text("\(cluster.selectedCount) selected")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }

                        Text("\(cluster.totalVideos) total")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()

                // Quick actions
                HStack {
                    Button("Select Suggested (\(cluster.suggestedCount))") {
                        selectSuggested()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)

                    Button("Clear Selection") {
                        cluster.selectedVideoIds.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                // Video list
                LazyVStack(spacing: 4) {
                    // Existing videos first
                    if !cluster.existingVideos.isEmpty {
                        Text("Already Imported")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        ForEach(cluster.existingVideos) { video in
                            VideoSelectionRow(
                                video: video,
                                isSelected: true,
                                isExisting: true,
                                onToggle: { }
                            )
                        }
                    }

                    // New videos
                    if !cluster.newVideos.isEmpty {
                        Text("Available to Import")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        ForEach(cluster.newVideos) { video in
                            VideoSelectionRow(
                                video: video,
                                isSelected: cluster.selectedVideoIds.contains(video.videoId),
                                isExisting: false,
                                onToggle: {
                                    toggleSelection(video.videoId)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func toggleSelection(_ videoId: String) {
        if cluster.selectedVideoIds.contains(videoId) {
            cluster.selectedVideoIds.remove(videoId)
        } else {
            cluster.selectedVideoIds.insert(videoId)
        }
    }

    private func selectSuggested() {
        // Select top N new videos by view count
        let suggested = cluster.newVideos
            .sorted { $0.viewCount > $1.viewCount }
            .prefix(cluster.suggestedCount)
            .map { $0.videoId }

        cluster.selectedVideoIds = Set(suggested)
    }
}

// MARK: - Video Selection Row

struct VideoSelectionRow: View {
    let video: BrowseVideoMetadata
    let isSelected: Bool
    let isExisting: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isExisting ? .green : (isSelected ? .blue : .secondary))
                    .font(.title3)

                // Thumbnail
                AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 60, height: 34)
                .cornerRadius(4)

                // Title
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundColor(.primary)

                    Text("\(video.viewCount.formatted()) views")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isExisting {
                    Text("Imported")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(isExisting)
    }
}

#Preview {
    NavigationStack {
        PreA0BrowseView(channel: YouTubeChannel(
            channelId: "test",
            name: "Johnny Harris",
            handle: "johnnyharris",
            thumbnailUrl: "",
            videoCount: 500,
            lastSynced: Date()
        ))
    }
    .environmentObject(NavigationViewModel())
}
