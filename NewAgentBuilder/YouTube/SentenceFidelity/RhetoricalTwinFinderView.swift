//
//  RhetoricalTwinFinderView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/28/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Main view for finding "rhetorical twins" - videos that follow
/// the same argumentative script but with different topics
struct RhetoricalTwinFinderView: View {
    let channelId: String
    let templateId: String

    @ObservedObject private var extractionService = TemplateExtractionService.shared
    @State private var sequences: [String: RhetoricalSequence] = [:]
    @State private var twinResults: [MultiStageTwinResult] = []
    @State private var isExtracting = false
    @State private var extractionProgress: (current: Int, total: Int) = (0, 0)
    @State private var extractionStatus: String = ""
    @State private var selectedPair: MultiStageTwinResult?
    @State private var errorMessage: String?

    // Loading state
    @State private var isLoadingFromFirebase = false
    @State private var videosWithExistingSequences: Set<String> = []
    @State private var forceReExtract = false

    // Multi-stage settings
    @State private var runStage3: Bool = false
    @State private var minParentScore: Double = 0.6

    private let firebaseService = YouTubeFirebaseService.shared

    // Fidelity testing state
    @State private var showFidelityTest = false
    @State private var fidelityTestVideoId: String?
    @State private var fidelityTestRuns: [(run: Int, temperature: Double, sequence: RhetoricalSequence)] = []
    @State private var isFidelityTesting = false
    @State private var fidelityProgress: (completed: Int, total: Int) = (0, 0)

    // Fidelity test configuration
    @State private var fidelityRunCount: Int = 3
    @State private var fidelityTemperature: Double = 0.1

    // Clear sequences state
    @State private var isClearingSequences = false
    @State private var clearedCount: Int? = nil

    private let service = RhetoricalMoveService.shared

    // Get the cluster from the service
    private var cluster: StructuralTemplate? {
        extractionService.currentClusteringResult?.templates.first { $0.id == templateId }
    }

    // Get videos that belong to this cluster
    private var clusterVideoIds: [String] {
        cluster?.videoIds ?? []
    }

    // Get boundary results for cluster videos
    private var boundaryResults: [String: BoundaryDetectionResult] {
        extractionService.currentBoundaryResults.filter { clusterVideoIds.contains($0.key) }
    }

    // Videos with boundary detection results
    private var videosWithChunks: [(videoId: String, chunks: [Chunk])] {
        boundaryResults.compactMap { videoId, result in
            result.chunks.isEmpty ? nil : (videoId, result.chunks)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content - single scrollable view with all sections
            if isLoadingFromFirebase {
                loadingView
            } else if showFidelityTest {
                fidelityTestView
            } else if sequences.isEmpty && !isExtracting {
                startExtractionView
            } else if sequences.isEmpty && isExtracting {
                extractionProgressView
            } else {
                // Main analysis view - settings + results together
                mainAnalysisView
            }
        }
        .navigationTitle("Rhetorical Twin Finder")
        .sheet(item: $selectedPair) { pair in
            MultiStageAlignmentView(result: pair)
        }
        .onAppear {
            loadExistingSequences()
        }
    }

    // MARK: - Main Analysis View (Settings + Results Together)

    private var mainAnalysisView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status bar
                statusSection

                Divider()

                // Settings (always visible)
                settingsSection

                // Run button with inline progress
                runButtonSection

                // Results (if any)
                if !twinResults.isEmpty {
                    Divider()
                    resultsSection
                } else if lastComparisonStats != nil {
                    // Show "no results" message after running
                    noResultsMessage
                }
            }
            .padding()
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 12) {
            // Cluster name
            if let cluster = cluster {
                HStack {
                    Text(cluster.templateName)
                        .font(.headline)
                    Spacer()

                    // Copy raw data button
                    Button(action: copyRawVideoData) {
                        Label("Copy Raw", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Text("\(cluster.videoCount) videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack(spacing: 16) {
                // Sequences count
                VStack {
                    Text("\(sequences.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Sequences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if videosNeedingExtraction.count > 0 {
                    VStack {
                        Text("\(videosNeedingExtraction.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        Text("Need Extract")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !twinResults.isEmpty {
                    VStack {
                        Text("\(twinResults.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        Text("Twins Found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Extract missing button
                if videosNeedingExtraction.count > 0 {
                    Button(action: startExtraction) {
                        Label("Extract \(videosNeedingExtraction.count)", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExtracting)
                }

                // Fidelity test button
                Button(action: { showFidelityTest = true }) {
                    Image(systemName: "checkmark.shield")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Copy Raw Video Data

    private func copyRawVideoData() {
        var report = """
        ═══════════════════════════════════════════════════════════════════════════════
        RAW VIDEO DATA FOR COMPARISON
        ═══════════════════════════════════════════════════════════════════════════════

        Cluster: \(cluster?.templateName ?? "Unknown")
        Total Videos in Cluster: \(clusterVideoIds.count)
        Videos with Chunks (Boundary Detection): \(videosWithChunks.count)
        Videos with Rhetorical Sequences: \(sequences.count)

        ═══════════════════════════════════════════════════════════════════════════════
        CHUNK COUNT SUMMARY
        ═══════════════════════════════════════════════════════════════════════════════

        """

        // Show chunk counts for comparison
        let chunkCounts = videosWithChunks.map { (videoId: $0.videoId, chunkCount: $0.chunks.count) }
            .sorted { $0.chunkCount < $1.chunkCount }

        let countGroups = Dictionary(grouping: chunkCounts, by: { $0.chunkCount })
        for (count, videos) in countGroups.sorted(by: { $0.key < $1.key }) {
            report += "\(count) chunks: \(videos.count) videos\n"
        }

        report += """

        ═══════════════════════════════════════════════════════════════════════════════
        ALL VIDEOS WITH CHUNK & SEQUENCE DATA
        ═══════════════════════════════════════════════════════════════════════════════

        """

        for video in videosWithChunks.sorted(by: { $0.videoId < $1.videoId }) {
            let sequence = sequences[video.videoId]
            let hasSequence = sequence != nil

            report += """

        ───────────────────────────────────────────────────────────────────────────────
        VIDEO: \(video.videoId)
        ───────────────────────────────────────────────────────────────────────────────

        Chunk Count (from Boundary Detection): \(video.chunks.count)
        Has Rhetorical Sequence: \(hasSequence ? "YES" : "NO")
        """

            if let seq = sequence {
                report += """

        Sequence Move Count: \(seq.moves.count)
        Avg Confidence: \(Int(seq.averageConfidence * 100))%
        Low Confidence: \(seq.lowConfidenceCount)

        Parent Sequence: \(seq.parentSequenceString)
        Full Sequence: \(seq.moveSequenceString)

        CHUNKS:
        """
                for (index, chunk) in video.chunks.enumerated() {
                    let move = seq.moves.first { $0.chunkIndex == index }
                    let label = move?.moveType.displayName ?? "NO LABEL"
                    let parent = move?.moveType.category.rawValue ?? "-"
                    let conf = move.map { Int($0.confidence * 100) } ?? 0

                    report += """

          [\(index + 1)] \(label) (\(parent)) - \(conf)% conf
              Position: \(String(format: "%.0f%%", chunk.positionInVideo * 100)) | Sentences: \(chunk.sentenceCount)
              Text (first 200 chars): \(String(chunk.fullText.prefix(200)).replacingOccurrences(of: "\n", with: " "))...
        """
                }
            } else {
                report += """


        CHUNKS (no rhetorical labels):
        """
                for (index, chunk) in video.chunks.enumerated() {
                    report += """

          [\(index + 1)] Position: \(String(format: "%.0f%%", chunk.positionInVideo * 100)) | Sentences: \(chunk.sentenceCount)
              Text (first 200 chars): \(String(chunk.fullText.prefix(200)).replacingOccurrences(of: "\n", with: " "))...
        """
                }
            }

            report += "\n"
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Comparison Settings")
                    .font(.headline)
                Spacer()
                if let stats = lastComparisonStats {
                    Text("Last run: \(stats.pairsFound) pairs from \(stats.pairsCompared) comparisons")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Min parent score - this is the key filter
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Minimum Parent-Level Match:")
                    Spacer()
                    Text("\(Int(minParentScore * 100))%")
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                Slider(value: $minParentScore, in: 0.4...0.9, step: 0.1)
                Text("Only pairs where parent categories (HOOK→SETUP→TENSION etc.) match at least this well")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Stage 3 toggle
            Toggle(isOn: $runStage3) {
                VStack(alignment: .leading) {
                    Text("AI Verification (Stage 3)")
                    Text("Have AI check if same-parent mismatches are functionally equivalent")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Run Button Section

    private var runButtonSection: some View {
        VStack(spacing: 8) {
            Button(action: findTwins) {
                HStack {
                    if isExtracting {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(extractionStatus)
                    } else {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Find Twins")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExtracting || sequences.count < 2)

            if sequences.count < 2 {
                Text("Need at least 2 videos with sequences to compare")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Twin Pairs Found")
                    .font(.headline)
                Spacer()

                Button(action: copyAllResults) {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Text("\(twinResults.count) pairs")
                    .foregroundColor(.secondary)
            }

            ForEach(twinResults) { result in
                MultiStageTwinPairRow(result: result)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPair = result
                    }
                    .padding()
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Copy Results

    private func copyAllResults() {
        var report = """
        ═══════════════════════════════════════════════════════════════════════════════
        RHETORICAL TWIN FINDER RESULTS
        ═══════════════════════════════════════════════════════════════════════════════

        Cluster: \(cluster?.templateName ?? "Unknown")
        Videos Analyzed: \(sequences.count)
        Min Parent Match Threshold: \(Int(minParentScore * 100))%
        Stage 3 AI Verification: \(runStage3 ? "Enabled" : "Disabled")

        """

        if let stats = lastComparisonStats {
            report += """
        Total Pairs Compared: \(stats.pairsCompared)
        Pairs Meeting Threshold: \(twinResults.count)

        """
        }

        report += """

        ═══════════════════════════════════════════════════════════════════════════════
        TWIN PAIRS (sorted by score)
        ═══════════════════════════════════════════════════════════════════════════════

        """

        for (index, result) in twinResults.enumerated() {
            report += """

        ───────────────────────────────────────────────────────────────────────────────
        PAIR #\(index + 1): \(Int(result.finalScore * 100))% Match
        ───────────────────────────────────────────────────────────────────────────────

        Video A: \(result.video1Id)
        Video B: \(result.video2Id)

        SCORES:
          Stage 1 (Parent-Level): \(Int(result.stage1ParentScore * 100))%
          Stage 2 (Fine-Grained): \(Int(result.stage2FineScore * 100))%
        \(result.stage3AdjustedScore != nil ? "  Stage 3 (AI-Adjusted): \(Int(result.stage3AdjustedScore! * 100))%\n" : "")
        MATCH BREAKDOWN:
          Exact Matches: \(result.exactMatchCount)
          Same Parent (different child): \(result.sameParentCount)
          Different Parent: \(result.differentParentCount)
        \(result.aiResolvedCount > 0 ? "  AI Verified: \(result.aiResolvedCount)\n" : "")
        SEQUENCE A (Parent): \(result.sequence1.parentSequenceString)
        SEQUENCE B (Parent): \(result.sequence2.parentSequenceString)

        SEQUENCE A (Full): \(result.sequence1.moveSequenceString)
        SEQUENCE B (Full): \(result.sequence2.moveSequenceString)

        CHUNK-BY-CHUNK COMPARISON:
        """

            for comp in result.chunkComparisons {
                let label1 = comp.move1?.moveType.displayName ?? "(gap)"
                let label2 = comp.move2?.moveType.displayName ?? "(gap)"
                let parent1 = comp.move1?.moveType.category.rawValue ?? "-"
                let parent2 = comp.move2?.moveType.category.rawValue ?? "-"

                let status: String
                switch comp.matchStatus {
                case .exactMatch: status = "✓ EXACT"
                case .sameParent: status = "~ SAME PARENT"
                case .aiConfirmedSame: status = "✓ AI:SAME"
                case .aiMaybeSame: status = "? AI:MAYBE"
                case .aiConfirmedDifferent: status = "✗ AI:DIFF"
                case .differentParent: status = "✗ DIFFERENT"
                case .gap: status = "- GAP"
                }

                report += """

          [Chunk \(comp.chunkIndex + 1)] \(status) (\(Int(comp.finalScore * 100))%)
            A: \(label1) (\(parent1))
            B: \(label2) (\(parent2))
        """

                if let verdict = comp.aiVerdict {
                    report += """

            AI Says: \(verdict.verdict.rawValue) (\(verdict.confidence.rawValue))
            Reason: \(verdict.reasoning)
        """
                }
            }

            report += "\n"
        }

        // Add raw sequence data for each video
        report += """

        ═══════════════════════════════════════════════════════════════════════════════
        RAW SEQUENCE DATA (All Videos)
        ═══════════════════════════════════════════════════════════════════════════════

        """

        for (videoId, sequence) in sequences.sorted(by: { $0.key < $1.key }) {
            report += """

        VIDEO: \(videoId)
        Parent Sequence: \(sequence.parentSequenceString)
        Full Sequence: \(sequence.moveSequenceString)
        Chunks: \(sequence.moves.count)
        Avg Confidence: \(Int(sequence.averageConfidence * 100))%
        Low Confidence Chunks: \(sequence.lowConfidenceCount)

        """
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
    }

    private var noResultsMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundColor(.secondary)
            Text("No twin pairs found")
                .font(.headline)
            if let stats = lastComparisonStats {
                Text("Compared \(stats.pairsCompared) pairs, none met the \(Int(minParentScore * 100))% threshold")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("Try lowering the minimum parent match")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    // Stats from last comparison run
    @State private var lastComparisonStats: ComparisonStats?

    struct ComparisonStats {
        let pairsCompared: Int
        let pairsFound: Int
        let duration: TimeInterval
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Loading saved rhetorical sequences...")
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // Helper computed properties
    private var videosNeedingExtraction: [(videoId: String, chunks: [Chunk])] {
        if forceReExtract {
            return videosWithChunks
        }
        return videosWithChunks.filter { !videosWithExistingSequences.contains($0.videoId) }
    }

    private var videosAlreadyExtracted: Int {
        videosWithChunks.filter { videosWithExistingSequences.contains($0.videoId) }.count
    }

    // MARK: - Start Extraction

    private var startExtractionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Fidelity Test Section
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "checkmark.shield")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("Step 1: Test Fidelity")
                            .font(.headline)
                        Spacer()
                    }

                    Text("Select a video to test the AI's rhetorical move classifications before running batch extraction.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !videosWithChunks.isEmpty {
                        Picker("Select Video", selection: $fidelityTestVideoId) {
                            Text("Choose a video...").tag(nil as String?)
                            ForEach(videosWithChunks, id: \.videoId) { item in
                                Text(item.videoId.prefix(40) + "...")
                                    .tag(item.videoId as String?)
                            }
                        }
                        .pickerStyle(.menu)

                        Button(action: { showFidelityTest = true }) {
                            Label("Test Single Video", systemImage: "play.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(fidelityTestVideoId == nil)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)

                Divider()

                // Batch Extraction Section
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Step 2: Extract Rhetorical Sequences")
                            .font(.headline)
                        Spacer()
                    }

                    // Status of existing data
                    VStack(alignment: .leading, spacing: 8) {
                        if videosAlreadyExtracted > 0 {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\(videosAlreadyExtracted) videos already have sequences (saved)")
                            }
                        }

                        if videosNeedingExtraction.count > 0 {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle")
                                    .foregroundColor(.blue)
                                Text("\(videosNeedingExtraction.count) videos need extraction")
                            }
                        }

                        if videosWithChunks.count < clusterVideoIds.count {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.orange)
                                Text("\(clusterVideoIds.count - videosWithChunks.count) videos missing boundary detection")
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    // Re-extract toggle
                    if videosAlreadyExtracted > 0 {
                        Toggle(isOn: $forceReExtract) {
                            Text("Re-extract all (overwrite saved)")
                                .font(.caption)
                        }
                    }

                    // Clear all sequences button
                    if videosAlreadyExtracted > 0 {
                        Button(action: clearAllSequences) {
                            if isClearingSequences {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Clear All Sequences from DB", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(isClearingSequences)

                        if let count = clearedCount {
                            Text("Cleared \(count) sequences")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    Text("Extracts rhetorical moves from each chunk using 25-move codebook. Results are saved to Firebase for future use.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: startExtraction) {
                        if videosNeedingExtraction.isEmpty && !forceReExtract {
                            Label("All Videos Extracted ✓", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Extract \(videosNeedingExtraction.count) Videos", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(videosNeedingExtraction.isEmpty && !forceReExtract)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    // MARK: - Extraction Progress

    private var extractionProgressView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView(value: Double(extractionProgress.current), total: Double(extractionProgress.total))
                .progressViewStyle(.linear)
                .frame(width: 200)

            Text(extractionStatus.isEmpty ? "Extracting rhetorical moves..." : extractionStatus)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("\(extractionProgress.current) of \(extractionProgress.total) videos")
                .foregroundColor(.secondary)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Fidelity Test View

    private var fidelityTestView: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button(action: {
                    showFidelityTest = false
                    fidelityTestRuns = []
                    fidelityProgress = (0, 0)
                }) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Fidelity Test (\(fidelityTestRuns.count) runs)")
                    .font(.headline)

                Spacer()

                // Copy button
                if !fidelityTestRuns.isEmpty {
                    Button(action: copyFidelityReport) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.primary.opacity(0.05))

            Divider()

            if isFidelityTesting {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView(value: Double(fidelityProgress.completed), total: Double(fidelityProgress.total))
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    Text("Running fidelity tests in parallel...")
                        .font(.headline)
                    Text("\(fidelityProgress.completed) of \(fidelityProgress.total) runs completed")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if !fidelityTestRuns.isEmpty {
                fidelityResultsView
            } else {
                // Ready to run - show configuration
                ScrollView {
                    VStack(spacing: 20) {
                        if let videoId = fidelityTestVideoId,
                           let videoData = videosWithChunks.first(where: { $0.videoId == videoId }) {

                            // Video info
                            VStack(spacing: 8) {
                                Text("Video: \(videoId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(videoData.chunks.count) chunks to analyze")
                                    .font(.subheadline)
                            }
                            .padding()

                            // Configuration Section
                            VStack(spacing: 16) {
                                HStack {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundColor(.blue)
                                    Text("Test Configuration")
                                        .font(.headline)
                                    Spacer()
                                }

                                Divider()

                                // Run count picker
                                HStack {
                                    Text("Number of runs:")
                                    Spacer()
                                    Picker("Runs", selection: $fidelityRunCount) {
                                        Text("1").tag(1)
                                        Text("3").tag(3)
                                        Text("5").tag(5)
                                        Text("10").tag(10)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 200)
                                }

                                // Temperature slider
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Temperature:")
                                        Spacer()
                                        Text(String(format: "%.2f", fidelityTemperature))
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                    }
                                    Slider(value: $fidelityTemperature, in: 0...1, step: 0.05)
                                    HStack {
                                        Text("Deterministic")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("Creative")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Text("Lower temperature = more consistent results. Use 0.1 for stability testing, higher for variety testing.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)

                            // Run button
                            Button(action: runFidelityTest) {
                                Label("Run \(fidelityRunCount)x Fidelity Test", systemImage: "play.fill")
                                    .frame(maxWidth: 280)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top)

                        } else {
                            Text("No video selected")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // Computed stability metrics
    private var stabilityScore: Double {
        guard fidelityTestRuns.count > 1 else { return 1.0 }
        let chunkCount = fidelityTestRuns.first?.sequence.moves.count ?? 0
        guard chunkCount > 0 else { return 1.0 }

        var agreements = 0
        for chunkIndex in 0..<chunkCount {
            let labels = fidelityTestRuns.compactMap { runData -> RhetoricalMoveType? in
                runData.sequence.moves.first { $0.chunkIndex == chunkIndex }?.moveType
            }
            // Check if all runs agree
            if Set(labels).count == 1 {
                agreements += 1
            }
        }
        return Double(agreements) / Double(chunkCount)
    }

    private var disagreements: [(chunkIndex: Int, labels: [RhetoricalMoveType])] {
        guard fidelityTestRuns.count > 1 else { return [] }
        let chunkCount = fidelityTestRuns.first?.sequence.moves.count ?? 0

        var results: [(Int, [RhetoricalMoveType])] = []
        for chunkIndex in 0..<chunkCount {
            let labels = fidelityTestRuns.compactMap { runData -> RhetoricalMoveType? in
                runData.sequence.moves.first { $0.chunkIndex == chunkIndex }?.moveType
            }
            if Set(labels).count > 1 {
                results.append((chunkIndex, labels))
            }
        }
        return results
    }

    private var fidelityResultsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Run more tests section
                HStack {
                    Button(action: {
                        fidelityRunCount = 1
                        runFidelityTest()
                    }) {
                        Label("+1 Run", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        fidelityRunCount = 3
                        runFidelityTest()
                    }) {
                        Label("+3 Runs", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    // Temperature indicator
                    if let lastTemp = fidelityTestRuns.last?.temperature {
                        Text("Temp: \(String(format: "%.2f", lastTemp))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Stability summary (if multiple runs)
                if fidelityTestRuns.count > 1 {
                    VStack(spacing: 12) {
                        HStack {
                            Text("STABILITY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        HStack(spacing: 20) {
                            VStack {
                                Text(String(format: "%.0f%%", stabilityScore * 100))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(stabilityScore >= 0.8 ? .green : stabilityScore >= 0.6 ? .orange : .red)
                                Text("Agreement")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack {
                                Text("\(fidelityTestRuns.count)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                Text("Runs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            VStack {
                                Text("\(disagreements.count)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(disagreements.isEmpty ? .green : .orange)
                                Text("Disagreements")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Show disagreements
                        if !disagreements.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Chunks with different labels across runs:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                ForEach(disagreements, id: \.chunkIndex) { item in
                                    HStack {
                                        Text("Chunk \(item.chunkIndex + 1):")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text(item.labels.map { $0.displayName }.joined(separator: " vs "))
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }

                // Show latest run details
                if let latestRunData = fidelityTestRuns.last {
                    let latestRun = latestRunData.sequence

                    // Run metadata
                    HStack {
                        Text("Latest: Run #\(latestRunData.run)")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("• Temp: \(String(format: "%.2f", latestRunData.temperature))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    // Summary stats
                    HStack(spacing: 20) {
                        VStack {
                            Text("\(latestRun.moves.count)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Moves")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack {
                            Text(String(format: "%.0f%%", latestRun.averageConfidence * 100))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(latestRun.averageConfidence >= 0.7 ? .green : .orange)
                            Text("Avg Conf")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack {
                            Text("\(latestRun.lowConfidenceCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(latestRun.lowConfidenceCount > 0 ? .orange : .green)
                            Text("Low Conf")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)

                    // Sequence preview
                    Text(latestRun.moveSequenceString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)

                    Divider()

                    // Each chunk with its classification
                    ForEach(latestRun.moves) { move in
                        fidelityMoveCard(move: move, allRuns: fidelityTestRuns.map { $0.sequence })
                    }
                }
            }
            .padding()
        }
    }

    private func fidelityMoveCard(move: RhetoricalMove, allRuns: [RhetoricalSequence]) -> some View {
        // Check if this chunk has disagreements across runs
        let labelsAcrossRuns = allRuns.compactMap { run -> RhetoricalMoveType? in
            run.moves.first { $0.chunkIndex == move.chunkIndex }?.moveType
        }
        let hasDisagreement = Set(labelsAcrossRuns).count > 1

        return VStack(alignment: .leading, spacing: 12) {
            // Header: Chunk index + Move type
            HStack {
                HStack(spacing: 4) {
                    Text("Chunk \(move.chunkIndex + 1)")
                        .font(.caption)
                        .fontWeight(.bold)

                    if hasDisagreement {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(hasDisagreement ? Color.red.opacity(0.2) : Color.secondary.opacity(0.2))
                .cornerRadius(6)

                Spacer()

                // Move type badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(categoryColor(move.moveType.category))
                        .frame(width: 8, height: 8)
                    Text(move.moveType.displayName)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(categoryColor(move.moveType.category).opacity(0.15))
                .cornerRadius(8)
            }

            // Show all labels if disagreement
            if hasDisagreement {
                HStack {
                    Text("Across runs:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(labelsAcrossRuns.map { $0.displayName }.joined(separator: " → "))
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            // Confidence
            HStack {
                Text("Confidence:")
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f%%", move.confidence * 100))
                    .fontWeight(.medium)
                    .foregroundColor(move.confidence >= 0.7 ? .green : .orange)

                if move.isLowConfidence {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                Spacer()

                if let alt = move.alternateType, let altConf = move.alternateConfidence {
                    Text("Alt: \(alt.displayName) (\(Int(altConf * 100))%)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)

            // AI's description
            if !move.briefDescription.isEmpty {
                Text("AI says: \"\(move.briefDescription)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }

            // Chunk text preview
            if let videoId = fidelityTestVideoId,
               let videoData = videosWithChunks.first(where: { $0.videoId == videoId }),
               move.chunkIndex < videoData.chunks.count {
                let chunk = videoData.chunks[move.chunkIndex]
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chunk Text:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(chunk.fullText)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(hasDisagreement ? Color.red.opacity(0.5) : move.isLowConfidence ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }

    private func categoryColor(_ category: RhetoricalCategory) -> Color {
        switch category {
        case .hook: return .blue
        case .setup: return .green
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .gray
        case .closing: return .red
        }
    }

    private func runFidelityTest() {
        guard let videoId = fidelityTestVideoId,
              let videoData = videosWithChunks.first(where: { $0.videoId == videoId }) else {
            return
        }

        isFidelityTesting = true
        let startingRunNumber = fidelityTestRuns.count
        let runsToExecute = fidelityRunCount
        let temperature = fidelityTemperature

        fidelityProgress = (0, runsToExecute)

        Task {
            // Run all tests in parallel using TaskGroup
            await withTaskGroup(of: (Int, Double, RhetoricalSequence?).self) { group in
                for runOffset in 0..<runsToExecute {
                    let runNumber = startingRunNumber + runOffset + 1

                    group.addTask {
                        do {
                            let result = try await self.service.extractRhetoricalSequence(
                                videoId: videoId,
                                chunks: videoData.chunks,
                                temperature: temperature
                            )
                            return (runNumber, temperature, result)
                        } catch {
                            return (runNumber, temperature, nil)
                        }
                    }
                }

                // Collect results as they complete
                for await (runNumber, temp, maybeResult) in group {
                    await MainActor.run {
                        fidelityProgress.completed += 1

                        if let result = maybeResult {
                            fidelityTestRuns.append((run: runNumber, temperature: temp, sequence: result))
                            // Sort by run number to maintain order
                            fidelityTestRuns.sort { $0.run < $1.run }
                        } else {
                            errorMessage = "Run \(runNumber) failed"
                        }
                    }
                }
            }

            await MainActor.run {
                isFidelityTesting = false
            }
        }
    }

    private func copyFidelityReport() {
        guard let videoId = fidelityTestVideoId,
              let videoData = videosWithChunks.first(where: { $0.videoId == videoId }) else {
            return
        }

        // Get unique temperatures used
        let temperaturesUsed = Set(fidelityTestRuns.map { $0.temperature }).sorted()
        let tempString = temperaturesUsed.map { String(format: "%.2f", $0) }.joined(separator: ", ")

        var report = """
        ═══════════════════════════════════════════════════════════════════════════════
        RHETORICAL MOVE FIDELITY TEST
        ═══════════════════════════════════════════════════════════════════════════════
        Video ID: \(videoId)
        Chunks: \(videoData.chunks.count)
        Total Runs: \(fidelityTestRuns.count)
        Temperature(s): \(tempString)
        Stability Score: \(String(format: "%.0f%%", stabilityScore * 100))
        Disagreements: \(disagreements.count)

        """

        // Add run metadata
        report += """

        ───────────────────────────────────────────────────────────────────────────────
        RUN METADATA
        ───────────────────────────────────────────────────────────────────────────────

        """
        for runData in fidelityTestRuns {
            report += "Run #\(runData.run) | Temp: \(String(format: "%.2f", runData.temperature)) | Moves: \(runData.sequence.moves.count) | Avg Conf: \(String(format: "%.0f%%", runData.sequence.averageConfidence * 100))\n"
        }

        // Add disagreement details
        if !disagreements.isEmpty {
            report += """

        ───────────────────────────────────────────────────────────────────────────────
        DISAGREEMENTS
        ───────────────────────────────────────────────────────────────────────────────

        """
            for item in disagreements {
                report += "Chunk \(item.chunkIndex + 1): \(item.labels.map { $0.displayName }.joined(separator: " vs "))\n"
            }
        }

        // Add each run's sequence
        report += """

        ───────────────────────────────────────────────────────────────────────────────
        RUN SEQUENCES
        ───────────────────────────────────────────────────────────────────────────────

        """
        for runData in fidelityTestRuns {
            report += "Run #\(runData.run) (T=\(String(format: "%.2f", runData.temperature))): \(runData.sequence.moveSequenceString)\n"
        }

        // Add detailed chunk analysis from latest run
        if let latestRunData = fidelityTestRuns.last {
            let latestRun = latestRunData.sequence
            report += """

        ───────────────────────────────────────────────────────────────────────────────
        DETAILED CHUNK ANALYSIS (Run #\(latestRunData.run), Temp: \(String(format: "%.2f", latestRunData.temperature)))
        ───────────────────────────────────────────────────────────────────────────────

        """
            for move in latestRun.moves {
                let chunk = videoData.chunks[move.chunkIndex]
                let labelsAcrossRuns = fidelityTestRuns.compactMap { runData -> String? in
                    runData.sequence.moves.first { $0.chunkIndex == move.chunkIndex }?.moveType.displayName
                }
                let hasDisagreement = Set(labelsAcrossRuns).count > 1

                report += """

        [CHUNK \(move.chunkIndex + 1)] \(hasDisagreement ? "⚠️ UNSTABLE" : "✓")
        Move: \(move.moveType.displayName) (\(move.moveType.category.rawValue))
        Confidence: \(Int(move.confidence * 100))%\(move.alternateType != nil ? " | Alt: \(move.alternateType!.displayName) (\(Int((move.alternateConfidence ?? 0) * 100))%)" : "")
        AI Description: \(move.briefDescription)
        \(hasDisagreement ? "Across runs: \(labelsAcrossRuns.joined(separator: " → "))\n" : "")
        Position: \(String(format: "%.0f%%", chunk.positionInVideo * 100)) (\(chunk.positionLabel))
        Text:
        \(chunk.fullText)

        """
            }
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
    }

    // MARK: - Actions

    /// Clear all rhetorical sequences from Firebase
    private func clearAllSequences() {
        isClearingSequences = true
        clearedCount = nil

        Task {
            do {
                let count = try await firebaseService.clearAllRhetoricalSequences()

                await MainActor.run {
                    clearedCount = count
                    sequences = [:]
                    videosWithExistingSequences = []
                    isClearingSequences = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to clear: \(error.localizedDescription)"
                    isClearingSequences = false
                }
            }
        }
    }

    /// Load existing rhetorical sequences from Firebase
    private func loadExistingSequences() {
        isLoadingFromFirebase = true

        Task {
            do {
                // Fetch videos for this cluster
                var loadedSequences: [String: RhetoricalSequence] = [:]
                var existingIds: Set<String> = []

                for videoId in clusterVideoIds {
                    if let video = try await firebaseService.fetchVideo(videoId: videoId),
                       let sequence = video.rhetoricalSequence {
                        loadedSequences[videoId] = sequence
                        existingIds.insert(videoId)
                    }
                }

                await MainActor.run {
                    sequences = loadedSequences
                    videosWithExistingSequences = existingIds
                    isLoadingFromFirebase = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load sequences: \(error.localizedDescription)"
                    isLoadingFromFirebase = false
                }
            }
        }
    }

    /// Extract sequences for videos that need it
    private func startExtraction() {
        isExtracting = true
        errorMessage = nil
        extractionStatus = "Extracting rhetorical sequences..."

        let videosToProcess = videosNeedingExtraction
        extractionProgress = (0, videosToProcess.count)

        Task {
            do {
                // Extract sequences
                let extractedSequences = try await service.extractSequencesBatch(
                    videos: videosToProcess,
                    temperature: 0.1,
                    onProgress: { current, total in
                        Task { @MainActor in
                            extractionProgress = (current, total)
                        }
                    }
                )

                await MainActor.run {
                    extractionStatus = "Saving to Firebase..."
                }

                // Save to Firebase
                try await firebaseService.saveRhetoricalSequencesBatch(sequences: extractedSequences)

                await MainActor.run {
                    // Merge with existing sequences
                    for (videoId, seq) in extractedSequences {
                        sequences[videoId] = seq
                        videosWithExistingSequences.insert(videoId)
                    }
                    forceReExtract = false
                    isExtracting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExtracting = false
                }
            }
        }
    }

    /// Run multi-stage twin finding on existing sequences
    private func findTwins() {
        isExtracting = true
        extractionStatus = "Comparing sequences..."
        twinResults = []  // Clear previous results
        lastComparisonStats = nil

        let startTime = Date()
        let totalPairs = (sequences.count * (sequences.count - 1)) / 2

        Task {
            await MainActor.run {
                extractionStatus = "Comparing \(totalPairs) pairs..."
            }

            // Build chunk texts for Stage 3 if enabled
            var chunkTexts: [String: [String]]? = nil
            if runStage3 {
                var texts: [String: [String]] = [:]
                for video in videosWithChunks {
                    texts[video.videoId] = video.chunks.map { $0.fullText }
                }
                chunkTexts = texts
            }

            // Run multi-stage twin finding
            let results = await service.findTwinsMultiStage(
                sequences: sequences,
                topKCoarse: 100,  // Get all pairs that pass the threshold
                minParentScore: minParentScore,
                runStage3: runStage3,
                chunkTexts: chunkTexts,
                onProgress: { status in
                    Task { @MainActor in
                        extractionStatus = status
                    }
                }
            )

            let duration = Date().timeIntervalSince(startTime)

            await MainActor.run {
                twinResults = results
                lastComparisonStats = ComparisonStats(
                    pairsCompared: totalPairs,
                    pairsFound: results.count,
                    duration: duration
                )
                isExtracting = false
            }
        }
    }
}

// MARK: - Twin Pair Row

struct TwinPairRow: View {
    let result: RhetoricalTwinResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Match score badge
            HStack {
                matchScoreBadge
                Spacer()
                Text("\(result.editDistance) edit distance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Video 1
            HStack {
                Text("A:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Text(result.video1Id)
                    .lineLimit(1)
            }
            .font(.subheadline)

            // Video 2
            HStack {
                Text("B:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                Text(result.video2Id)
                    .lineLimit(1)
            }
            .font(.subheadline)

            // Sequence preview
            Text(result.sequence1.moveSequenceString)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var matchScoreBadge: some View {
        let percentage = Int(result.matchScore * 100)
        let color: Color = percentage >= 80 ? .green : percentage >= 60 ? .orange : .red

        return HStack(spacing: 4) {
            Image(systemName: "percent")
            Text("\(percentage)% match")
        }
        .font(.caption)
        .fontWeight(.semibold)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .cornerRadius(8)
    }
}

// MARK: - Multi-Stage Twin Pair Row

struct MultiStageTwinPairRow: View {
    let result: MultiStageTwinResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Score badges
            HStack(spacing: 8) {
                // Final score
                scoreBadge(
                    score: result.finalScore,
                    label: "Final",
                    color: scoreColor(result.finalScore)
                )

                // Stage breakdown
                HStack(spacing: 4) {
                    Text("S1: \(Int(result.stage1ParentScore * 100))%")
                    Text("→")
                    Text("S2: \(Int(result.stage2FineScore * 100))%")
                    if let s3 = result.stage3AdjustedScore {
                        Text("→")
                        Text("S3: \(Int(s3 * 100))%")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                Spacer()

                // Confidence badge
                Text(result.confidence.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceColor(result.confidence).opacity(0.2))
                    .foregroundColor(confidenceColor(result.confidence))
                    .cornerRadius(4)
            }

            // Video IDs
            HStack {
                Text("A:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Text(result.video1Id)
                    .lineLimit(1)
            }
            .font(.subheadline)

            HStack {
                Text("B:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                Text(result.video2Id)
                    .lineLimit(1)
            }
            .font(.subheadline)

            // Match breakdown
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("\(result.exactMatchCount) exact")
                }
                HStack(spacing: 2) {
                    Circle().fill(Color.yellow).frame(width: 6, height: 6)
                    Text("\(result.sameParentCount) same-parent")
                }
                HStack(spacing: 2) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("\(result.differentParentCount) different")
                }
                if result.aiResolvedCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                        Text("\(result.aiResolvedCount) AI-verified")
                    }
                    .foregroundColor(.purple)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func scoreBadge(score: Double, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(Int(score * 100))%")
                .fontWeight(.bold)
            Text(label)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .cornerRadius(8)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.85 { return .green }
        if score >= 0.7 { return .orange }
        return .red
    }

    private func confidenceColor(_ confidence: MultiStageTwinResult.TwinConfidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}

// MARK: - Multi-Stage Alignment View

struct MultiStageAlignmentView: View {
    let result: MultiStageTwinResult

    @Environment(\.dismiss) private var dismiss
    @State private var showText = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Summary header
                    summaryHeader

                    Divider()

                    // Chunk-by-chunk comparison
                    chunkComparisonList
                }
            }
            .navigationTitle("Twin Alignment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $showText) {
                        Image(systemName: "text.quote")
                    }
                }
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        VStack(spacing: 12) {
            // Scores
            HStack(spacing: 20) {
                VStack {
                    Text(String(format: "%.0f%%", result.finalScore * 100))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(result.finalScore >= 0.85 ? .green : result.finalScore >= 0.7 ? .orange : .red)
                    Text("Final Score")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Stage 1 (Parent):")
                        Text("\(Int(result.stage1ParentScore * 100))%")
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Stage 2 (Fine):")
                        Text("\(Int(result.stage2FineScore * 100))%")
                            .fontWeight(.semibold)
                    }
                    if let s3 = result.stage3AdjustedScore {
                        HStack {
                            Text("Stage 3 (AI):")
                            Text("\(Int(s3 * 100))%")
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                        }
                    }
                }
                .font(.caption)
            }

            Divider()

            // Video IDs
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    Label("Video A", systemImage: "a.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(result.video1Id)
                        .font(.caption2)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading) {
                    Label("Video B", systemImage: "b.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(result.video2Id)
                        .font(.caption2)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .green, label: "Exact Match")
                legendItem(color: .yellow, label: "Same Parent")
                legendItem(color: .purple, label: "AI Verified")
                legendItem(color: .red, label: "Different")
            }
            .font(.caption2)
        }
        .padding()
        .background(Color.primary.opacity(0.05))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - Chunk Comparison List

    private var chunkComparisonList: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 30)
                Text("Video A")
                    .frame(maxWidth: .infinity)
                Text("Score")
                    .frame(width: 50)
                Text("Video B")
                    .frame(maxWidth: .infinity)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color.secondary.opacity(0.1))

            // Comparison rows
            ForEach(result.chunkComparisons) { comp in
                ChunkComparisonRow(comparison: comp, showText: showText)

                if comp.id != result.chunkComparisons.last?.id {
                    Divider().padding(.leading, 30)
                }
            }
        }
    }
}

// MARK: - Chunk Comparison Row

struct ChunkComparisonRow: View {
    let comparison: ChunkComparison
    let showText: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Chunk number
            Text("\(comparison.chunkIndex + 1)")
                .frame(width: 30)
                .font(.caption)
                .foregroundColor(.secondary)

            // Move 1 (Video A)
            moveCell(comparison.move1, isVideoA: true)
                .frame(maxWidth: .infinity)

            // Score indicator
            scoreIndicator
                .frame(width: 50)

            // Move 2 (Video B)
            moveCell(comparison.move2, isVideoA: false)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(backgroundColor)
    }

    @ViewBuilder
    private func moveCell(_ move: RhetoricalMove?, isVideoA: Bool) -> some View {
        if let move = move {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(categoryColor(move.moveType.category))
                        .frame(width: 8, height: 8)
                    Text(move.moveType.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }

                Text(move.moveType.category.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if showText && !move.briefDescription.isEmpty {
                    Text(move.briefDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        } else {
            VStack {
                Image(systemName: "minus")
                    .foregroundColor(.secondary)
                Text("(gap)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var scoreIndicator: some View {
        VStack(spacing: 2) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)

            Text(String(format: "%.0f%%", comparison.finalScore * 100))
                .font(.caption2)
                .foregroundColor(statusColor)

            if comparison.aiVerdict != nil {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundColor(.purple)
            }
        }
    }

    private var statusIcon: String {
        switch comparison.matchStatus {
        case .exactMatch: return "checkmark.circle.fill"
        case .sameParent: return "equal.circle"
        case .aiConfirmedSame: return "checkmark.seal.fill"
        case .aiMaybeSame: return "questionmark.circle"
        case .aiConfirmedDifferent: return "xmark.seal.fill"
        case .differentParent: return "xmark.circle.fill"
        case .gap: return "arrow.left.arrow.right"
        }
    }

    private var statusColor: Color {
        switch comparison.matchStatus {
        case .exactMatch: return .green
        case .sameParent: return .yellow
        case .aiConfirmedSame: return .green
        case .aiMaybeSame: return .yellow
        case .aiConfirmedDifferent: return .red
        case .differentParent: return .red
        case .gap: return .gray
        }
    }

    private var backgroundColor: Color {
        switch comparison.matchStatus {
        case .exactMatch: return .green.opacity(0.05)
        case .sameParent, .aiMaybeSame: return .yellow.opacity(0.05)
        case .aiConfirmedSame: return .green.opacity(0.08)
        case .aiConfirmedDifferent, .differentParent: return .red.opacity(0.05)
        case .gap: return .clear
        }
    }

    private func categoryColor(_ category: RhetoricalCategory) -> Color {
        switch category {
        case .hook: return .blue
        case .setup: return .green
        case .tension: return .orange
        case .revelation: return .purple
        case .evidence: return .gray
        case .closing: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        Text("Preview requires data")
    }
}
