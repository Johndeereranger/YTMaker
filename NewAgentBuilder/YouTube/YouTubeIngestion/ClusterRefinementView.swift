//
//  ClusterRefinementView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/24/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Main view for refining clusters through outlier detection and comparison
struct ClusterRefinementView: View {
    let channel: YouTubeChannel
    let initialClusters: [RefinableCluster]

    @State private var clusters: [RefinableCluster]
    @State private var outliers: [ClusterVideoSummary] = []
    @State private var currentClusterIndex = 0
    @State private var refinementMode: RefinementMode = .outlierDetection

    // Analysis state
    @State private var isAnalyzing = false
    @State private var currentAnalysis: OutlierAnalysisResult?
    @State private var executionTraceAnalysis: ExecutionTraceOutlierResult?
    @State private var comparisonAnalysis: ClusterComparisonResult?
    @State private var outlierGroupingAnalysis: OutlierGroupingResult?
    @State private var errorMessage: String?
    @State private var analysisDepth: ClusterRefinementService.AnalysisDepth = .lightweight
    @State private var lastPromptUsed: String = ""  // For copying
    @State private var channelVideos: [YouTubeVideo] = []  // For execution trace analysis

    // Comparison mode state
    @State private var clusterAIndex = 0
    @State private var clusterBIndex = 1

    init(channel: YouTubeChannel, initialClusters: [RefinableCluster]) {
        self.channel = channel
        self.initialClusters = initialClusters
        self._clusters = State(initialValue: initialClusters)
    }

    enum RefinementMode: String, CaseIterable {
        case outlierDetection = "Outlier Detection"
        case clusterComparison = "Cluster Comparison"
        case outlierReview = "Outlier Review"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Mode selector
            Picker("Mode", selection: $refinementMode) {
                ForEach(RefinementMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Main content based on mode
            switch refinementMode {
            case .outlierDetection:
                outlierDetectionView
            case .clusterComparison:
                clusterComparisonView
            case .outlierReview:
                outlierReviewView
            }

            Spacer()

            // Outlier bin (always visible)
            outlierBinView
        }
        .navigationTitle("Refine Clusters")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.headline)
                Text("\(clusters.count) clusters, \(totalVideos) videos, \(outliers.count) outliers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Export") {
                exportRefinedClusters()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var totalVideos: Int {
        clusters.reduce(0) { $0 + $1.videos.count }
    }

    // MARK: - Outlier Detection View

    private var outlierDetectionView: some View {
        VStack(spacing: 16) {
            // Cluster navigation
            HStack {
                Button(action: { currentClusterIndex = max(0, currentClusterIndex - 1) }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentClusterIndex == 0)

                Spacer()

                Text("Cluster \(currentClusterIndex + 1) of \(clusters.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { currentClusterIndex = min(clusters.count - 1, currentClusterIndex + 1) }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentClusterIndex >= clusters.count - 1)
            }
            .padding(.horizontal)

            if clusters.indices.contains(currentClusterIndex) {
                let cluster = clusters[currentClusterIndex]

                // Cluster header
                VStack(alignment: .leading, spacing: 8) {
                    Text(cluster.name)
                        .font(.title2.bold())

                    Text("\(cluster.videos.count) videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // Video list
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(cluster.videos) { video in
                            videoRow(video: video, isOutlier: currentAnalysis?.outlierTitle == video.title)
                        }
                    }
                    .padding(.horizontal)
                }

                // Analysis section
                if isAnalyzing {
                    ProgressView("Analyzing cluster...")
                        .padding()
                } else if let analysis = currentAnalysis {
                    analysisCard(analysis: analysis)
                } else if let traceAnalysis = executionTraceAnalysis {
                    executionTraceAnalysisCard(analysis: traceAnalysis)
                }

                // Analysis depth picker
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Analysis Depth:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Depth", selection: $analysisDepth) {
                            ForEach(ClusterRefinementService.AnalysisDepth.allCases, id: \.self) { depth in
                                Text(depth.rawValue).tag(depth)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()

                        // Show transcript availability for full mode
                        if analysisDepth == .fullTranscript {
                            let videosWithTranscript = cluster.videos.filter { $0.transcript != nil }.count
                            Text("\(videosWithTranscript)/\(cluster.videos.count) have transcripts")
                                .font(.caption2)
                                .foregroundColor(videosWithTranscript == cluster.videos.count ? .green : .orange)
                        }
                    }

                    Text(analysisDepth.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Action buttons
                HStack(spacing: 12) {
                    Button("Analyze Cluster") {
                        Task { await analyzeCurrentCluster() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing)

                    if let analysis = currentAnalysis, !analysis.allFitWell {
                        Button("Move to Outliers") {
                            moveToOutliers(videoTitle: analysis.outlierTitle)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)

                        if !analysis.suggestedCluster.isEmpty && analysis.suggestedCluster != "none" {
                            Button("Move to \(analysis.suggestedCluster)") {
                                moveToCluster(videoTitle: analysis.outlierTitle, targetCluster: analysis.suggestedCluster)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }

                        Button("Keep Here") {
                            currentAnalysis = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }

    private func videoRow(video: ClusterVideoSummary, isOutlier: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(isOutlier ? .bold : .regular)
                    .foregroundColor(isOutlier ? .orange : .primary)

                Text(video.oneLiner)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isOutlier {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(isOutlier ? Color.orange.opacity(0.1) : Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func analysisCard(analysis: OutlierAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with copy buttons
            HStack {
                Text("AI Analysis")
                    .font(.caption.bold())

                Spacer()

                // Copy buttons
                Button(action: { copyResultToClipboard(analysis) }) {
                    Label("Copy Result", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: { copyPromptToClipboard() }) {
                    Label("Copy Analysis", systemImage: "text.quote")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Text(analysis.confidence.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(confidenceColor(analysis.confidence).opacity(0.2))
                    .foregroundColor(confidenceColor(analysis.confidence))
                    .cornerRadius(4)
            }

            // Show video arc assignments if available
            if let arcs = analysis.videoArcs, !arcs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ARC ASSIGNMENTS:")
                        .font(.caption2.bold())
                        .foregroundColor(.blue)

                    ForEach(arcs, id: \.title) { assignment in
                        HStack(spacing: 4) {
                            Text("•")
                            Text(assignment.title)
                                .lineLimit(1)
                            Text("→")
                                .foregroundColor(.secondary)
                            Text(assignment.arc)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        .font(.caption2)
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
            }

            // Show majority arc
            if let majorityArc = analysis.majorityArc, !majorityArc.isEmpty {
                Text("MAJORITY ARC: \(majorityArc)")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            }

            Divider()

            if analysis.allFitWell {
                Text("All videos fit well - same arc pattern.")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else {
                HStack {
                    Text("\"\(analysis.outlierTitle)\"")
                        .font(.subheadline.bold())
                    if let outlierArc = analysis.outlierArc, !outlierArc.isEmpty {
                        Text("uses \(outlierArc)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Text("WHY: \(analysis.whyDoesntBelong)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Others share: \(analysis.whatOtherVideosShare)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show specific evidence if available (from full transcript analysis)
                if let evidence = analysis.specificEvidence, !evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EVIDENCE:")
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                        Text(evidence)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }

                if !analysis.suggestedCluster.isEmpty && analysis.suggestedCluster != "none" {
                    Text("Suggested home: \(analysis.suggestedCluster)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func executionTraceAnalysisCard(analysis: ExecutionTraceOutlierResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Execution Trace Analysis")
                    .font(.caption.bold())
                Spacer()

                Button(action: {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(analysis.copyableText, forType: .string)
                    #else
                    UIPasteboard.general.string = analysis.copyableText
                    #endif
                }) {
                    Label("Copy Result", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if analysis.allCompatible {
                // All videos are template-compatible
                VStack(alignment: .leading, spacing: 8) {
                    Label("All videos are template-compatible", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)

                    if let pattern = analysis.clusterExecutionPattern {
                        Text("Shared Pattern:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text(pattern)
                            .font(.caption)
                    }
                }
            } else {
                // Show outliers with break categories
                VStack(alignment: .leading, spacing: 8) {
                    Text("Template Incompatibilities Found")
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)

                    ForEach(analysis.outliers, id: \.videoId) { outlier in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(outlier.videoTitle)
                                .font(.caption.bold())
                                .lineLimit(1)

                            HStack {
                                Text("Break Category:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(outlier.breakCategory)
                                    .font(.caption2.bold())
                                    .foregroundColor(.red)
                            }

                            Text(outlier.breakExplanation)
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("Incompatible with \(Int(outlier.percentOfClusterIncompatible * 100))% of cluster")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }

            // Compatibility matrix summary
            if let matrix = analysis.compatibilityMatrix, !matrix.isEmpty {
                DisclosureGroup("Compatibility Matrix") {
                    ForEach(matrix, id: \.videoId) { entry in
                        HStack {
                            Text(entry.videoId)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.compatibleWith.count) compatible")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func copyResultToClipboard(_ analysis: OutlierAnalysisResult) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(analysis.copyableText, forType: .string)
        #else
        UIPasteboard.general.string = analysis.copyableText
        #endif
    }

    private func copyPromptToClipboard() {
        let textToCopy = """
        === PROMPT ===
        \(lastPromptUsed)

        === SYSTEM PROMPT ===
        \(ClusterRefinementService.outlierSystemPrompt)
        """

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        #else
        UIPasteboard.general.string = textToCopy
        #endif
    }

    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence.lowercased() {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }

    // MARK: - Cluster Comparison View

    private var clusterComparisonView: some View {
        VStack(spacing: 16) {
            // Cluster pair selector
            HStack {
                Picker("Cluster A", selection: $clusterAIndex) {
                    ForEach(clusters.indices, id: \.self) { index in
                        Text(clusters[index].name).tag(index)
                    }
                }
                .frame(maxWidth: 200)

                Text("vs")
                    .foregroundColor(.secondary)

                Picker("Cluster B", selection: $clusterBIndex) {
                    ForEach(clusters.indices, id: \.self) { index in
                        Text(clusters[index].name).tag(index)
                    }
                }
                .frame(maxWidth: 200)

                Button("Compare") {
                    Task { await compareClusters() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzing || clusterAIndex == clusterBIndex)
            }
            .padding()

            // Side by side clusters
            HStack(alignment: .top, spacing: 16) {
                // Cluster A
                if clusters.indices.contains(clusterAIndex) {
                    clusterColumn(cluster: clusters[clusterAIndex], label: "A")
                }

                // Cluster B
                if clusters.indices.contains(clusterBIndex) {
                    clusterColumn(cluster: clusters[clusterBIndex], label: "B")
                }
            }
            .padding(.horizontal)

            // Comparison analysis
            if isAnalyzing {
                ProgressView("Comparing clusters...")
                    .padding()
            } else if let comparison = comparisonAnalysis {
                comparisonCard(comparison: comparison)
            }
        }
    }

    private func clusterColumn(cluster: RefinableCluster, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)

                Text(cluster.name)
                    .font(.headline)
            }

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(cluster.videos) { video in
                        Text(video.title)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(4)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(maxWidth: .infinity)
    }

    private func comparisonCard(comparison: ClusterComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Analysis")
                .font(.caption.bold())

            if comparison.noChangesNeeded {
                Text("Both clusters are clean. No changes needed.")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else {
                if !comparison.swapsRecommended.isEmpty {
                    Text("SWAPS RECOMMENDED:")
                        .font(.caption.bold())

                    ForEach(comparison.swapsRecommended, id: \.videoTitle) { swap in
                        HStack {
                            Text("\"\(swap.videoTitle)\"")
                                .font(.caption.bold())
                            Text("\(swap.fromCluster) → \(swap.toCluster)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        Text(swap.reason)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Apply Swap") {
                            applySwap(swap)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }

                if !comparison.outliers.isEmpty {
                    Text("OUTLIERS (don't fit either):")
                        .font(.caption.bold())
                        .padding(.top, 8)

                    ForEach(comparison.outliers, id: \.videoTitle) { outlier in
                        Text("\"\(outlier.videoTitle)\" - \(outlier.reason)")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Button("Move to Outliers") {
                            moveToOutliers(videoTitle: outlier.videoTitle)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
            }

            Divider()

            Text("Cluster A engine: \(comparison.clusterAEngine)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Cluster B engine: \(comparison.clusterBEngine)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    // MARK: - Outlier Review View

    private var outlierReviewView: some View {
        VStack(spacing: 16) {
            if outliers.isEmpty {
                Text("No outliers yet")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Text("\(outliers.count) videos don't fit existing clusters")
                    .font(.headline)
                    .padding()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(outliers) { video in
                            outlierRow(video: video)
                        }
                    }
                    .padding(.horizontal)
                }

                // Analysis
                if isAnalyzing {
                    ProgressView("Analyzing outliers...")
                        .padding()
                } else if let grouping = outlierGroupingAnalysis {
                    outlierGroupingCard(grouping: grouping)
                }

                // Actions
                HStack {
                    Button("Analyze Outliers") {
                        Task { await analyzeOutliers() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing || outliers.isEmpty)

                    Button("Create Cluster from Selected") {
                        // TODO: Implement selection and cluster creation
                    }
                    .buttonStyle(.bordered)
                    .disabled(outliers.isEmpty)

                    Button("Leave as Uncategorized") {
                        // Mark as final
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
    }

    private func outlierRow(video: ClusterVideoSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)

                Text(video.oneLiner)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Quick assign menu
            Menu {
                ForEach(clusters) { cluster in
                    Button(cluster.name) {
                        moveOutlierToCluster(video: video, targetCluster: cluster.name)
                    }
                }
            } label: {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.blue)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func outlierGroupingCard(grouping: OutlierGroupingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Analysis")
                .font(.caption.bold())

            if !grouping.potentialGroups.isEmpty {
                Text("POTENTIAL GROUPS:")
                    .font(.caption.bold())

                ForEach(grouping.potentialGroups, id: \.suggestedName) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(group.suggestedName)
                                .font(.caption.bold())
                            Text("(\(group.confidence) confidence)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text(group.videoTitles.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Engine: \(group.sharedEngine)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
            }

            if !grouping.trueOrphans.isEmpty {
                Text("TRUE ORPHANS:")
                    .font(.caption.bold())
                    .padding(.top, 8)

                ForEach(grouping.trueOrphans, id: \.videoTitle) { orphan in
                    Text("\"\(orphan.videoTitle)\" - \(orphan.reason)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()

            Text("Recommendation: \(grouping.recommendation)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    // MARK: - Outlier Bin

    private var outlierBinView: some View {
        VStack(spacing: 8) {
            Divider()

            HStack {
                Text("OUTLIERS")
                    .font(.caption.bold())
                    .foregroundColor(.orange)

                Text("(\(outliers.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !outliers.isEmpty {
                    Button("Review") {
                        refinementMode = .outlierReview
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal)

            if !outliers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(outliers) { video in
                            Text(video.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func analyzeCurrentCluster() async {
        guard clusters.indices.contains(currentClusterIndex) else { return }

        await MainActor.run {
            isAnalyzing = true
            currentAnalysis = nil
            executionTraceAnalysis = nil
            errorMessage = nil
        }

        let cluster = clusters[currentClusterIndex]
        let allClusterNames = clusters.map { $0.name }
        let depth = analysisDepth

        // Build video list for prompt
        let videoList = cluster.videos.enumerated().map { index, video in
            "\(index + 1). \"\(video.title)\" - \(video.oneLiner)"
        }.joined(separator: "\n")

        let otherClusters = allClusterNames.filter { $0 != cluster.name }.joined(separator: ", ")

        // Save prompt for copying (lightweight mode)
        let prompt = ClusterRefinementService.buildOutlierPrompt(
            videoList: videoList,
            clusterName: cluster.name,
            otherClusters: otherClusters
        )

        await MainActor.run {
            lastPromptUsed = prompt
        }

        do {
            let result: OutlierAnalysisResult

            switch depth {
            case .lightweight:
                result = try await ClusterRefinementService.shared.findOutlier(
                    clusterName: cluster.name,
                    videos: cluster.videos,
                    allClusterNames: allClusterNames
                )
            case .fullTranscript:
                result = try await ClusterRefinementService.shared.findOutlierWithFullTranscripts(
                    clusterName: cluster.name,
                    videos: cluster.videos,
                    allClusterNames: allClusterNames
                )
            case .executionTrace:
                // Load videos if needed to get execution traces
                if channelVideos.isEmpty {
                    channelVideos = (try? await YouTubeFirebaseService.shared.getVideos(forChannel: channel.channelId)) ?? []
                }

                // Build execution traces dictionary from videos
                var traces: [String: ExecutionTrace] = [:]
                for video in channelVideos {
                    if let trace = video.phase0Result?.executionTrace {
                        traces[video.videoId] = trace
                    }
                }

                guard !traces.isEmpty else {
                    throw NSError(domain: "ClusterRefinement", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "No execution traces available. Run Execution Trace Extraction first."
                    ])
                }

                let traceResult = try await ClusterRefinementService.shared.findOutlierWithExecutionTraces(
                    clusterName: cluster.name,
                    videos: cluster.videos,
                    executionTraces: traces
                )

                await MainActor.run {
                    executionTraceAnalysis = traceResult
                    isAnalyzing = false
                }
                return  // Skip setting currentAnalysis since this uses different result type
            }

            await MainActor.run {
                currentAnalysis = result
                isAnalyzing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isAnalyzing = false
            }
        }
    }

    private func compareClusters() async {
        guard clusters.indices.contains(clusterAIndex),
              clusters.indices.contains(clusterBIndex) else { return }

        await MainActor.run {
            isAnalyzing = true
            comparisonAnalysis = nil
            errorMessage = nil
        }

        let clusterA = ClusterForComparison(
            name: clusters[clusterAIndex].name,
            videos: clusters[clusterAIndex].videos
        )
        let clusterB = ClusterForComparison(
            name: clusters[clusterBIndex].name,
            videos: clusters[clusterBIndex].videos
        )

        do {
            let result = try await ClusterRefinementService.shared.compareClusterPair(
                clusterA: clusterA,
                clusterB: clusterB
            )

            await MainActor.run {
                comparisonAnalysis = result
                isAnalyzing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isAnalyzing = false
            }
        }
    }

    private func analyzeOutliers() async {
        guard !outliers.isEmpty else { return }

        await MainActor.run {
            isAnalyzing = true
            outlierGroupingAnalysis = nil
            errorMessage = nil
        }

        do {
            let result = try await ClusterRefinementService.shared.analyzeOutliers(outliers: outliers)

            await MainActor.run {
                outlierGroupingAnalysis = result
                isAnalyzing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isAnalyzing = false
            }
        }
    }

    private func moveToOutliers(videoTitle: String) {
        for i in clusters.indices {
            if let videoIndex = clusters[i].videos.firstIndex(where: { $0.title == videoTitle }) {
                let video = clusters[i].videos[videoIndex]
                clusters[i].videos.remove(at: videoIndex)
                outliers.append(video)
                currentAnalysis = nil
                break
            }
        }
    }

    private func moveToCluster(videoTitle: String, targetCluster: String) {
        // Find and remove from current location
        var videoToMove: ClusterVideoSummary?

        for i in clusters.indices {
            if let videoIndex = clusters[i].videos.firstIndex(where: { $0.title == videoTitle }) {
                videoToMove = clusters[i].videos[videoIndex]
                clusters[i].videos.remove(at: videoIndex)
                break
            }
        }

        // Also check outliers
        if videoToMove == nil {
            if let outlierIndex = outliers.firstIndex(where: { $0.title == videoTitle }) {
                videoToMove = outliers[outlierIndex]
                outliers.remove(at: outlierIndex)
            }
        }

        // Add to target cluster
        if let video = videoToMove,
           let targetIndex = clusters.firstIndex(where: { $0.name == targetCluster }) {
            clusters[targetIndex].videos.append(video)
        }

        currentAnalysis = nil
    }

    private func moveOutlierToCluster(video: ClusterVideoSummary, targetCluster: String) {
        if let outlierIndex = outliers.firstIndex(where: { $0.id == video.id }) {
            outliers.remove(at: outlierIndex)

            if let targetIndex = clusters.firstIndex(where: { $0.name == targetCluster }) {
                clusters[targetIndex].videos.append(video)
            }
        }
    }

    private func applySwap(_ swap: SwapRecommendation) {
        moveToCluster(
            videoTitle: swap.videoTitle,
            targetCluster: swap.toCluster == "A" ? clusters[clusterAIndex].name : clusters[clusterBIndex].name
        )
        comparisonAnalysis = nil
    }

    private func exportRefinedClusters() {
        // TODO: Export to JSON or save to Firebase
        print("Exporting \(clusters.count) clusters and \(outliers.count) outliers")
    }
}

// MARK: - Supporting Models

struct RefinableCluster: Identifiable {
    let id = UUID()
    var name: String
    var videos: [ClusterVideoSummary]

    init(name: String, videos: [ClusterVideoSummary]) {
        self.name = name
        self.videos = videos
    }

    init(from cluster: ContentTypeCluster, videos: [YouTubeVideo]) {
        self.name = cluster.name
        self.videos = cluster.videoIds.compactMap { videoId in
            guard let video = videos.first(where: { $0.videoId == videoId }) else { return nil }
            return ClusterVideoSummary(from: video, includeTranscript: true)
        }
    }
}
