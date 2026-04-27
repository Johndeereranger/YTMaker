//
//  TaxonomyBatchRunnerView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 1/24/26.
//

import SwiftUI

struct TaxonomyBatchRunnerView: View {
    let channel: YouTubeChannel
    @EnvironmentObject var nav: NavigationViewModel

    // MARK: - State

    @State private var videos: [YouTubeVideo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Batch operation state
    @State private var isRunningBatch = false
    @State private var currentOperation = ""
    @State private var processedCount = 0
    @State private var totalToProcess = 0
    @State private var currentVideoTitle = ""

    // Concurrent processing state
    @State private var activeVideoTitles: [String] = []
    @State private var failedCount = 0

    // Concurrency settings
    private let maxConcurrentWorkers = 5
    private let staggerDelayNanos: UInt64 = 250_000_000 // 0.25 seconds

    // Aggregation state
    @State private var isRunningAggregation = false
    @State private var aggregationResult: TaxonomyAggregationResult?
    @State private var aggregationPrompt: String?
    @State private var aggregationRawResponse: String?
    @State private var aggregationError: String?
    @State private var showCopyConfirmation = false

    // Aggregation Fidelity Testing State
    @State private var showAggregationFidelity = false
    @State private var aggFidelityRunCount: Int = 5
    @State private var aggFidelityTemperature: Double = 0.3
    @State private var isRunningAggFidelity = false
    @State private var aggFidelityCurrentRun = 0
    @State private var aggFidelityResults: [AggregationFidelityRunResult] = []
    @State private var aggFidelityError: String?

    // Phase 0 re-run toggle
    @State private var forceRerunPhase0 = false

    // Phase 0 Fidelity Testing State
    @State private var showPhase0Fidelity = false
    @State private var phase0FidelityRunCount: Int = 5
    @State private var phase0FidelityTemperature: Double = 0.2
    @State private var isRunningPhase0Fidelity = false
    @State private var phase0FidelityCurrentRun = 0
    @State private var phase0FidelityTotalRuns = 0
    @State private var phase0FidelitySelectedVideoId: String? = nil  // nil = all videos
    @State private var phase0FidelityResults: [Phase0FidelityRunResult] = []
    @State private var phase0FidelityError: String?

    // Taxonomy Lock State
    @State private var showTaxonomyLockSection = false
    @State private var lockedTaxonomy: LockedTaxonomy?
    @State private var taxonomyPasteText: String = ""
    @State private var taxonomyValidationError: String?
    @State private var taxonomyPreview: LockedTaxonomy?   // Preview before saving
    @State private var isSavingTaxonomy = false
    @State private var showAddTemplateSheet = false
    @State private var addTemplatePasteText: String = ""
    @State private var addTemplateError: String?

    // Computed stats
    private var videosWithTranscript: Int {
        videos.filter { $0.hasTranscript }.count
    }

    private var videosWithPhase0: Int {
        videos.filter { $0.phase0Result != nil }.count
    }

    private var videosNeedingTranscript: Int {
        videos.filter { !$0.hasTranscript }.count
    }

    private var videosReadyForPhase0: Int {
        videos.filter { $0.hasTranscript && $0.phase0Result == nil }.count
    }

    private var videosWithExecutionTrace: Int {
        videos.filter { $0.phase0Result?.executionTrace != nil }.count
    }

    // MARK: - Body

    var body: some View {
        List {
            // Summary Section
            Section {
                summaryCard
            }

            // Actions Section
            Section("Batch Operations") {
                fetchTranscriptsButton
                runPhase0Button
                analyzePatternsButton
            }

            // Progress Section (if running)
            if isRunningBatch || isRunningAggregation || isRunningPhase0Fidelity {
                Section("Progress") {
                    if isRunningAggregation {
                        aggregationProgressView
                    } else if isRunningPhase0Fidelity {
                        phase0FidelityProgressView
                    } else {
                        progressView
                    }
                }
            }

            // Phase 0 Fidelity Testing Section - show whenever we have videos with transcripts
            if videosWithTranscript > 0 {
                Section("Phase 0 Prompt Fidelity") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Test structural analysis consistency")
                                .font(.caption)
                            Text("\(videosWithTranscript) videos with transcripts ready")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            showPhase0Fidelity.toggle()
                        } label: {
                            Label(
                                showPhase0Fidelity ? "Hide" : "Test Fidelity",
                                systemImage: "sparkles"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }

                    if showPhase0Fidelity {
                        phase0FidelitySection
                    }
                }
            }

            // Aggregation Fidelity Testing Section - show whenever we have enough Phase 0 videos
            if videosWithPhase0 >= 3 {
                Section("Aggregation Prompt Fidelity") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Test clustering stability")
                                .font(.caption)
                            Text("\(videosWithPhase0) videos with Phase 0 ready")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            showAggregationFidelity.toggle()
                        } label: {
                            Label(
                                showAggregationFidelity ? "Hide" : "Test Fidelity",
                                systemImage: "testtube.2"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                    }

                    if showAggregationFidelity {
                        aggregationFidelitySection
                    }
                }
            }

            // Taxonomy Lock Section - for user-created taxonomies
            Section("Taxonomy Lock") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let taxonomy = lockedTaxonomy, taxonomy.isLocked {
                            Text("Taxonomy Locked")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                            Text("\(taxonomy.templateCount) templates, \(taxonomy.totalExemplarCount) exemplars")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if let preview = taxonomyPreview {
                            Text("Preview Ready")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                            Text("\(preview.templateCount) templates")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Paste your external taxonomy")
                                .font(.caption)
                            Text("Create taxonomy in external chat, paste JSON here")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        showTaxonomyLockSection.toggle()
                    } label: {
                        Label(
                            showTaxonomyLockSection ? "Hide" : (lockedTaxonomy?.isLocked == true ? "Manage" : "Configure"),
                            systemImage: lockedTaxonomy?.isLocked == true ? "lock.fill" : "lock.open"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(lockedTaxonomy?.isLocked == true ? .green : .indigo)
                }

                if showTaxonomyLockSection {
                    taxonomyLockSection
                }
            }

            // Aggregation Results Section
            if let result = aggregationResult {
                // Creator Orientation (Phase 1)
                if let orientation = result.creatorOrientation {
                    Section("Creator Orientation") {
                        CreatorOrientationView(orientation: orientation)
                    }
                }

                Section("Content Types Discovered") {
                    creatorSignatureView(result: result)
                    copyButtonsView
                }

                ForEach(result.clusters) { cluster in
                    Section {
                        ContentTypeClusterView(
                            cluster: cluster,
                            videos: videos.filter { cluster.videoIds.contains($0.videoId) }
                        )
                    } header: {
                        Text(cluster.name)
                    }
                }

                Section("Shared Patterns (Creator Signature)") {
                    ForEach(result.sharedPatterns, id: \.self) { pattern in
                        Label(pattern, systemImage: "checkmark.seal")
                            .font(.caption)
                    }
                }

                Section {
                    refineClustersButton(result: result)
                    saveTaxonomyButton
                    viewTemplatesButton
                }
            }

            // Videos Section
            Section("Taxonomy Videos (\(videos.count))") {
                ForEach(videos) { video in
                    Phase0VideoRow(video: video)
                }
            }
        }
        .navigationTitle("Run Phase 0")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadVideos()
            await loadLockedTaxonomy()
        }
        .task {
            await loadVideos()
            await loadLockedTaxonomy()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(channel.name)
                .font(.headline)

            HStack(spacing: 20) {
                Phase0StatBox(label: "Total", value: videos.count, color: .primary)
                Phase0StatBox(label: "Transcripts", value: videosWithTranscript, color: .blue)
                Phase0StatBox(label: "Phase 0", value: videosWithPhase0, color: .green)
            }

            if videosNeedingTranscript > 0 {
                Label("\(videosNeedingTranscript) need transcripts", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if videosReadyForPhase0 > 0 {
                Label("\(videosReadyForPhase0) ready for Phase 0", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundColor(.purple)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Action Buttons

    private var fetchTranscriptsButton: some View {
        Button {
            Task { await batchFetchTranscripts() }
        } label: {
            HStack {
                Image(systemName: "doc.text.fill")
                VStack(alignment: .leading) {
                    Text("Fetch Transcripts")
                        .font(.headline)
                    Text("\(videosNeedingTranscript) videos need transcripts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if videosNeedingTranscript > 0 {
                    Text("\(videosNeedingTranscript)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
            }
        }
        .disabled(isRunningBatch || videosNeedingTranscript == 0)
    }

    private var runPhase0Button: some View {
        VStack(spacing: 8) {
            Button {
                Task { await batchRunPhase0() }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading) {
                        Text("Run Phase 0 Analysis")
                            .font(.headline)
                        Text(forceRerunPhase0 ? "\(videosWithTranscript) videos (re-run all)" : "\(videosReadyForPhase0) videos ready")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    let count = forceRerunPhase0 ? videosWithTranscript : videosReadyForPhase0
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
            }
            .disabled(isRunningBatch || isRunningAggregation || (forceRerunPhase0 ? videosWithTranscript == 0 : videosReadyForPhase0 == 0))

            HStack {
                Toggle("Force re-run all", isOn: $forceRerunPhase0)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
            }
        }
    }

    private var analyzePatternsButton: some View {
        Button {
            Task { await runAggregation() }
        } label: {
            HStack {
                Image(systemName: "rectangle.3.group")
                VStack(alignment: .leading) {
                    Text("Analyze Patterns")
                        .font(.headline)
                    Text("Cluster \(videosWithPhase0) videos into content types")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if videosWithPhase0 >= 3 {
                    Text("\(videosWithPhase0)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.indigo.opacity(0.2))
                        .cornerRadius(8)
                }
            }
        }
        .disabled(isRunningBatch || isRunningAggregation || videosWithPhase0 < 3)
    }

    private var aggregationProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Analyzing Patterns...")
                    .font(.headline)
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
            }
            Text("Clustering \(videosWithPhase0) Phase 0 results into content types")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func creatorSignatureView(result: TaxonomyAggregationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(result.clusters.count) content types identified")
                .font(.subheadline.bold())

            Text(result.creatorSignature)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var copyButtonsView: some View {
        HStack(spacing: 12) {
            // Copy Result Only
            Button {
                copyResultToClipboard()
            } label: {
                Label("Copy Result", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)

            // Copy Prompt + Result
            Button {
                copyPromptAndResultToClipboard()
            } label: {
                Label("Copy Prompt + Result", systemImage: "doc.on.doc.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func copyResultToClipboard() {
        guard let result = aggregationResult else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Build a clean result structure for copying
        let resultDict: [String: Any] = [
            "clusters": result.clusters.map { cluster -> [String: Any] in
                [
                    "name": cluster.name,
                    "coreQuestion": cluster.coreQuestion,
                    "description": cluster.description,
                    "evidenceTypes": cluster.evidenceTypes,
                    "narrativeArc": cluster.narrativeArc,
                    "videoIds": cluster.videoIds,
                    "typicalPivotMin": cluster.typicalPivotMin,
                    "typicalPivotMax": cluster.typicalPivotMax,
                    "dominantRetentionStrategy": cluster.dominantRetentionStrategy,
                    "dominantArgumentType": cluster.dominantArgumentType,
                    "dominantSectionDensity": cluster.dominantSectionDensity
                ]
            },
            "sharedPatterns": result.sharedPatterns,
            "creatorSignature": result.creatorSignature
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: resultDict, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            #if os(iOS)
            UIPasteboard.general.string = jsonString
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jsonString, forType: .string)
            #endif
            print("✅ Result copied to clipboard")
        }
    }

    private func copyPromptAndResultToClipboard() {
        guard let prompt = aggregationPrompt,
              let rawResponse = aggregationRawResponse else { return }

        let fullContent = """
        ==================== PROMPT ====================

        \(prompt)

        ==================== RESPONSE ====================

        \(rawResponse)
        """

        #if os(iOS)
        UIPasteboard.general.string = fullContent
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullContent, forType: .string)
        #endif
        print("✅ Prompt + Result copied to clipboard")
    }

    private func refineClustersButton(result: TaxonomyAggregationResult) -> some View {
        NavigationLink {
            ClusterRefinementView(
                channel: channel,
                initialClusters: result.clusters.map { cluster in
                    RefinableCluster(from: cluster, videos: videos)
                }
            )
        } label: {
            HStack {
                Image(systemName: "slider.horizontal.3")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Refine Clusters")
                        .font(.headline)
                    Text("Find outliers, compare clusters, fix misfits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var saveTaxonomyButton: some View {
        Button {
            Task { await saveTaxonomy() }
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("Save as Taxonomy")
                    .font(.headline)
                Spacer()
            }
        }
        .disabled(aggregationResult == nil)
    }

    private var viewTemplatesButton: some View {
        Button {
            nav.push(.templateDashboard(channel))
        } label: {
            HStack {
                Image(systemName: "rectangle.3.group")
                Text("View Template Dashboard")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Phase 0 Fidelity Testing Section

    private var phase0FidelityProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Testing Phase 0 Stability...")
                    .font(.headline)
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
            }
            ProgressView(value: Double(phase0FidelityCurrentRun), total: Double(max(phase0FidelityTotalRuns, 1)))
                .progressViewStyle(.linear)
            Text("\(phase0FidelityCurrentRun) / \(phase0FidelityTotalRuns) runs complete")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var phase0FidelitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run Phase 0 multiple times to test consistency")
                .font(.caption)
                .foregroundColor(.secondary)

            // Video picker
            HStack {
                Text("Test:")
                    .font(.caption)
                Picker("Video", selection: $phase0FidelitySelectedVideoId) {
                    Text("All Videos (\(videosWithTranscript))").tag(nil as String?)
                    ForEach(videos.filter { $0.hasTranscript }) { video in
                        Text(video.title).tag(video.videoId as String?)
                            .lineLimit(1)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)
            }

            // Controls row
            HStack {
                Stepper("\(phase0FidelityRunCount) runs", value: $phase0FidelityRunCount, in: 3...10, step: 1)
                    .frame(width: 130)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Temp: \(String(format: "%.1f", phase0FidelityTemperature))")
                        .font(.caption)
                    Slider(value: $phase0FidelityTemperature, in: 0...1, step: 0.1)
                        .frame(width: 100)
                }

                Spacer()

                if isRunningPhase0Fidelity {
                    HStack {
                        ProgressView()
                        Text("\(phase0FidelityCurrentRun)/\(phase0FidelityTotalRuns)")
                            .font(.caption)
                    }
                } else {
                    Button("Run Tests") {
                        Task { await runPhase0FidelityTests() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(videosWithTranscript == 0)
                }

                Button {
                    copyPhase0FidelityPrompt()
                } label: {
                    Image(systemName: "doc.text")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if let error = phase0FidelityError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Results
            if !phase0FidelityResults.isEmpty {
                phase0FidelityResultsView
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private var phase0FidelityResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Timing info
            if let firstStart = phase0FidelityResults.map({ $0.startedAt }).min(),
               let lastEnd = phase0FidelityResults.map({ $0.completedAt }).max() {
                let totalElapsed = lastEnd.timeIntervalSince(firstStart)
                let avgDuration = phase0FidelityResults.map { $0.durationSeconds }.reduce(0, +) / Double(phase0FidelityResults.count)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Timing Analysis")
                        .font(.caption.bold())
                        .foregroundColor(.orange)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("Wall Time")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", totalElapsed))s")
                                .font(.caption.monospacedDigit())
                        }

                        VStack(alignment: .leading) {
                            Text("Avg/Run")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", avgDuration))s")
                                .font(.caption.monospacedDigit())
                        }

                        VStack(alignment: .leading) {
                            Text("Parallel?")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            let expectedSequential = avgDuration * Double(phase0FidelityResults.count)
                            let isParallel = totalElapsed < expectedSequential * 0.7
                            Text(isParallel ? "YES" : "NO")
                                .font(.caption.bold())
                                .foregroundColor(isParallel ? .green : .red)
                        }
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(6)
            }

            // Copy buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        copyPhase0FidelityPrompt()
                    } label: {
                        Label("Copy Prompt", systemImage: "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyPhase0FidelityInput()
                    } label: {
                        Label("Copy Input", systemImage: "list.bullet.rectangle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyPhase0FidelityResults()
                    } label: {
                        Label("Copy Results", systemImage: "chart.bar")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyPhase0FidelityDebug()
                    } label: {
                        Label("Copy All (Debug)", systemImage: "doc.on.doc.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }

            Divider()

            // Field stability analysis
            phase0FieldStabilityView
        }
    }

    private var phase0FieldStabilityView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group results by video
            let videoGroups = Dictionary(grouping: phase0FidelityResults, by: { $0.videoId })
            let summaries = videoGroups.map { (videoId, runs) in
                Phase0FidelityVideoSummary(
                    videoId: videoId,
                    videoTitle: runs.first?.videoTitle ?? videoId,
                    runs: runs
                )
            }.sorted { $0.videoTitle < $1.videoTitle }

            // Overall stability (average across all videos)
            let overallStability = summaries.isEmpty ? 0 : summaries.map { $0.overallStability }.reduce(0, +) / Double(summaries.count)

            HStack {
                Text("Overall Field Stability")
                    .font(.caption.bold())
                Spacer()
                Text("\(Int(overallStability * 100))%")
                    .font(.headline.bold())
                    .foregroundColor(overallStability >= 0.85 ? .green : overallStability >= 0.7 ? .yellow : .orange)
            }
            .padding(8)
            .background(overallStability >= 0.85 ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            .cornerRadius(6)

            // Per-video breakdown (if multiple videos tested)
            if summaries.count > 1 {
                Text("Per-Video Stability")
                    .font(.caption.bold())

                ForEach(summaries, id: \.videoId) { summary in
                    phase0VideoStabilityRow(summary: summary)
                }
            } else if let summary = summaries.first {
                // Single video detailed view
                phase0SingleVideoDetailView(summary: summary)
            }
        }
    }

    private func phase0VideoStabilityRow(summary: Phase0FidelityVideoSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(summary.videoTitle)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(summary.overallStability * 100))%")
                    .font(.caption.bold())
                    .foregroundColor(summary.overallStability >= 0.85 ? .green : summary.overallStability >= 0.7 ? .yellow : .orange)
            }

            // Mini field breakdown
            HStack(spacing: 8) {
                fieldStabilityBadge("Pivot", summary.pivotCountStability)
                fieldStabilityBadge("Retention", summary.retentionStrategyStability)
                fieldStabilityBadge("Argument", summary.argumentTypeStability)
                fieldStabilityBadge("Narrative", summary.narrativeDeviceStability)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    private func phase0SingleVideoDetailView(summary: Phase0FidelityVideoSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Field Stability (\(summary.runs.count) runs)")
                .font(.caption.bold())

            // Detailed field breakdown
            phase0FieldRow("pivotCount", summary.pivotCountStability, summary.getDistribution(for: summary.runs.map { $0.pivotCount }))
            phase0FieldRow("retentionStrategy", summary.retentionStrategyStability, summary.getDistribution(for: summary.runs.map { $0.retentionStrategy }))
            phase0FieldRow("argumentType", summary.argumentTypeStability, summary.getDistribution(for: summary.runs.map { $0.argumentType }))
            phase0FieldRow("sectionDensity", summary.sectionDensityStability, summary.getDistribution(for: summary.runs.map { $0.sectionDensity }))
            phase0FieldRow("narrativeDevice", summary.narrativeDeviceStability, summary.getDistribution(for: summary.runs.map { $0.narrativeDevice }))
            phase0FieldRow("format", summary.formatStability, summary.getDistribution(for: summary.runs.compactMap { $0.format }))

            Divider()

            // Raw runs expandable
            DisclosureGroup("Raw Runs") {
                ForEach(summary.runs) { run in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Run \(run.runNumber)")
                            .font(.caption2.bold())
                        Text("pivot=\(run.pivotCount), \(run.retentionStrategy), \(run.argumentType), \(run.narrativeDevice)")
                            .font(.system(size: 10).monospaced())
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .font(.caption)
        }
    }

    private func phase0FieldRow<T: Hashable>(_ fieldName: String, _ stability: Double, _ distribution: [T: Int]) -> some View {
        HStack {
            Text(fieldName)
                .font(.caption)
                .frame(width: 120, alignment: .leading)

            if stability >= 1.0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else if stability >= 0.7 {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }

            Text("\(Int(stability * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 40)

            // Distribution
            let sortedDist = distribution.sorted { $0.value > $1.value }
            Text(sortedDist.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func fieldStabilityBadge(_ label: String, _ stability: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(stability * 100))%")
                .font(.system(size: 9).bold())
                .foregroundColor(stability >= 0.85 ? .green : stability >= 0.7 ? .yellow : .orange)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Taxonomy Lock Section

    private var taxonomyLockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show different UI based on state
            if let taxonomy = lockedTaxonomy, taxonomy.isLocked {
                // LOCKED STATE: Show locked taxonomy with management options
                lockedTaxonomyView(taxonomy: taxonomy)
            } else if let preview = taxonomyPreview {
                // PREVIEW STATE: Show preview and allow save/lock
                taxonomyPreviewView(preview: preview)
            } else {
                // EMPTY STATE: Show paste area
                taxonomyPasteView
            }
        }
        .padding()
        .background(Color.indigo.opacity(0.1))
        .cornerRadius(8)
        .sheet(isPresented: $showAddTemplateSheet) {
            addTemplateSheet
        }
    }

    private var taxonomyPasteView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create your taxonomy externally, then paste the JSON here")
                .font(.caption)
                .foregroundColor(.secondary)

            // Copy template buttons
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    copyBlankTaxonomyTemplate()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Copy New Taxonomy Template")
                                .font(.caption.bold())
                            Text("Start fresh - blank structure for all your templates")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    copySingleTemplateSnippet()
                } label: {
                    HStack {
                        Image(systemName: "plus.doc.on.doc")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Copy Single Template Snippet")
                                .font(.caption.bold())
                            Text("Add one more template to an existing taxonomy")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // Paste area
            VStack(alignment: .leading, spacing: 4) {
                Text("Paste Taxonomy JSON")
                    .font(.caption.bold())

                TextEditor(text: $taxonomyPasteText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 150, maxHeight: 250)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                if let error = taxonomyValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Spacer()
                    Button("Validate & Preview") {
                        validateAndPreviewTaxonomy()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(taxonomyPasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func taxonomyPreviewView(preview: LockedTaxonomy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preview header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    Text("\(preview.templateCount) templates ready to save")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button("Clear") {
                    taxonomyPreview = nil
                    taxonomyPasteText = ""
                }
                .font(.caption)
                .foregroundColor(.red)
            }

            Divider()

            // Template previews
            ForEach(preview.templates) { template in
                LockedTemplatePreviewRow(template: template, videos: videos)
            }

            Divider()

            // Action buttons
            HStack {
                Button {
                    taxonomyPreview = nil
                }  label: {
                    Label("Edit JSON", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                if isSavingTaxonomy {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button {
                        Task { await saveTaxonomyAndLock(preview) }
                    } label: {
                        Label("Save & Lock", systemImage: "lock.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
    }

    private func lockedTaxonomyView(taxonomy: LockedTaxonomy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Locked header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.green)
                        Text("Taxonomy Locked")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                    if let lockedAt = taxonomy.lockedAt {
                        Text("Locked \(lockedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()

                Button {
                    showAddTemplateSheet = true
                } label: {
                    Label("Add Template", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // Template list
            ForEach(taxonomy.templates) { template in
                LockedTemplateRow(
                    template: template,
                    videos: videos,
                    onOpenWorkbench: {
                        nav.push(.a1aPromptWorkbench(channel, template))
                    }
                )
            }

            Divider()

            // Management buttons
            HStack(spacing: 8) {
                Button {
                    copyLockedTaxonomyJSON()
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    // Unlock and allow editing
                    if var unlocked = lockedTaxonomy {
                        unlocked = LockedTaxonomy(
                            channelId: unlocked.channelId,
                            templates: unlocked.templates,
                            createdAt: unlocked.createdAt,
                            updatedAt: Date(),
                            lockedAt: nil
                        )
                        taxonomyPreview = unlocked
                        lockedTaxonomy = nil
                    }
                } label: {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
    }

    private var addTemplateSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste a single template JSON to add to your locked taxonomy")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    copySingleTemplateSnippet()
                } label: {
                    Label("Copy Template Snippet", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                TextEditor(text: $addTemplatePasteText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                if let error = addTemplateError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Add Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddTemplateSheet = false
                        addTemplatePasteText = ""
                        addTemplateError = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await addTemplateToLockedTaxonomy() }
                    }
                    .disabled(addTemplatePasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Taxonomy Lock Functions

    private func copyBlankTaxonomyTemplate() {
        let template = LockedTaxonomy.blankTemplate(channelId: channel.channelId)
        copyToClipboard(template)
        print("📋 Copied blank taxonomy template to clipboard")
    }

    private func copySingleTemplateSnippet() {
        let snippet = LockedTaxonomy.singleTemplateSnippet()
        copyToClipboard(snippet)
        print("📋 Copied single template snippet to clipboard")
    }

    private func validateAndPreviewTaxonomy() {
        taxonomyValidationError = nil

        let result = LockedTaxonomy.validate(
            json: taxonomyPasteText,
            expectedChannelId: channel.channelId
        )

        switch result {
        case .valid(let taxonomy):
            taxonomyPreview = taxonomy
            taxonomyPasteText = ""  // Clear paste area after successful validation
        case .invalidJSON(let error):
            taxonomyValidationError = "Invalid JSON: \(error)"
        case .missingFields(let fields):
            taxonomyValidationError = "Missing fields: \(fields.joined(separator: ", "))"
        case .invalidTemplates(let errors):
            taxonomyValidationError = "Template errors:\n\(errors.joined(separator: "\n"))"
        }
    }

    private func saveTaxonomyAndLock(_ taxonomy: LockedTaxonomy) async {
        await MainActor.run {
            isSavingTaxonomy = true
        }

        var lockedTax = taxonomy
        lockedTax = LockedTaxonomy(
            channelId: lockedTax.channelId,
            templates: lockedTax.templates,
            createdAt: lockedTax.createdAt,
            updatedAt: Date(),
            lockedAt: Date()  // Lock it now
        )

        do {
            try await YouTubeFirebaseService.shared.saveLockedTaxonomy(lockedTax, forChannel: channel.channelId)

            await MainActor.run {
                lockedTaxonomy = lockedTax
                taxonomyPreview = nil
                isSavingTaxonomy = false
            }
            print("✅ Locked taxonomy saved with \(lockedTax.templateCount) templates")
        } catch {
            await MainActor.run {
                taxonomyValidationError = "Save failed: \(error.localizedDescription)"
                isSavingTaxonomy = false
            }
            print("❌ Failed to save locked taxonomy: \(error)")
        }
    }

    private func copyLockedTaxonomyJSON() {
        guard let taxonomy = lockedTaxonomy else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(taxonomy),
           let jsonString = String(data: data, encoding: .utf8) {
            copyToClipboard(jsonString)
            print("📋 Copied locked taxonomy JSON to clipboard")
        }
    }

    private func addTemplateToLockedTaxonomy() async {
        guard var taxonomy = lockedTaxonomy else { return }

        addTemplateError = nil

        // Parse single template JSON
        guard let data = addTemplatePasteText.data(using: .utf8) else {
            addTemplateError = "Could not parse input"
            return
        }

        do {
            let newTemplate = try JSONDecoder().decode(LockedTemplateInput.self, from: data)

            // Check for duplicate ID
            if taxonomy.templates.contains(where: { $0.id == newTemplate.id }) {
                await MainActor.run {
                    addTemplateError = "Template ID '\(newTemplate.id)' already exists"
                }
                return
            }

            // Convert and add
            let template = LockedTemplate(
                id: newTemplate.id,
                name: newTemplate.name,
                description: newTemplate.description,
                classificationCriteria: ClassificationCriteria(
                    requiredSignals: newTemplate.classificationCriteria.requiredSignals,
                    antiSignals: newTemplate.classificationCriteria.antiSignals
                ),
                exemplarVideoIds: newTemplate.exemplarVideoIds
            )

            taxonomy.templates.append(template)
            taxonomy = LockedTaxonomy(
                channelId: taxonomy.channelId,
                templates: taxonomy.templates,
                createdAt: taxonomy.createdAt,
                updatedAt: Date(),
                lockedAt: taxonomy.lockedAt
            )

            // Save to Firebase
            try await YouTubeFirebaseService.shared.saveLockedTaxonomy(taxonomy, forChannel: channel.channelId)

            await MainActor.run {
                lockedTaxonomy = taxonomy
                showAddTemplateSheet = false
                addTemplatePasteText = ""
                addTemplateError = nil
            }
            print("✅ Added template '\(template.name)' to locked taxonomy")

        } catch {
            await MainActor.run {
                addTemplateError = "Parse error: \(error.localizedDescription)"
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    // MARK: - Aggregation Fidelity Testing Section

    private var aggregationFidelitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test how stable the content type clustering is")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Stepper("Runs: \(aggFidelityRunCount)", value: $aggFidelityRunCount, in: 3...20, step: 1)
                    .frame(width: 160)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Temp: \(String(format: "%.1f", aggFidelityTemperature))")
                        .font(.caption)
                    Slider(value: $aggFidelityTemperature, in: 0...1, step: 0.1)
                        .frame(width: 100)
                }

                Spacer()

                if isRunningAggFidelity {
                    HStack {
                        ProgressView()
                        Text("Run \(aggFidelityCurrentRun)/\(aggFidelityRunCount)")
                            .font(.caption)
                    }
                } else {
                    Button("Run \(aggFidelityRunCount) Tests") {
                        Task { await runAggregationFidelityTests() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(videosWithPhase0 < 3)
                }

                Button {
                    copyAggregationPrompt()
                } label: {
                    Image(systemName: "doc.text")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if let error = aggFidelityError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Results
            if !aggFidelityResults.isEmpty {
                aggregationFidelityResultsView
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(8)
    }

    private var aggregationFidelityResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cluster Assignment Variance (\(aggFidelityResults.count) runs)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()
            }

            // Timing info
            if let firstStart = aggFidelityResults.map({ $0.startedAt }).min(),
               let lastEnd = aggFidelityResults.map({ $0.completedAt }).max() {
                let totalElapsed = lastEnd.timeIntervalSince(firstStart)
                let avgDuration = aggFidelityResults.map { $0.durationSeconds }.reduce(0, +) / Double(aggFidelityResults.count)

                VStack(alignment: .leading, spacing: 4) {
                    Text("⏱ Timing Analysis")
                        .font(.caption.bold())
                        .foregroundColor(.purple)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("Total Wall Time")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", totalElapsed))s")
                                .font(.caption.monospacedDigit())
                        }

                        VStack(alignment: .leading) {
                            Text("Avg Per Run")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", avgDuration))s")
                                .font(.caption.monospacedDigit())
                        }

                        VStack(alignment: .leading) {
                            Text("If Sequential")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.1f", avgDuration * Double(aggFidelityResults.count)))s")
                                .font(.caption.monospacedDigit())
                        }

                        VStack(alignment: .leading) {
                            Text("Parallel?")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            let expectedSequential = avgDuration * Double(aggFidelityResults.count)
                            let isParallel = totalElapsed < expectedSequential * 0.7
                            Text(isParallel ? "✅ YES" : "❌ NO")
                                .font(.caption.bold())
                                .foregroundColor(isParallel ? .green : .red)
                        }
                    }

                    // Per-run timing
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(aggFidelityResults.sorted(by: { $0.runNumber < $1.runNumber })) { result in
                                VStack(spacing: 2) {
                                    Text("R\(result.runNumber)")
                                        .font(.caption2.bold())
                                    Text("\(result.startedAt.formatted(date: .omitted, time: .standard))")
                                        .font(.system(size: 8).monospacedDigit())
                                        .foregroundColor(.secondary)
                                    Text("→")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("\(result.completedAt.formatted(date: .omitted, time: .standard))")
                                        .font(.system(size: 8).monospacedDigit())
                                        .foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", result.durationSeconds))s")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.purple)
                                }
                                .padding(6)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }

            // Copy buttons row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        copyAggregationPrompt()
                    } label: {
                        Label("Copy Prompt", systemImage: "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyPhase0InputData()
                    } label: {
                        Label("Copy Input Data", systemImage: "list.bullet.rectangle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyAggregationFidelityResults()
                    } label: {
                        Label("Copy Variance Results", systemImage: "chart.bar")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyFullFidelityDebug()
                    } label: {
                        Label("Copy All (Debug)", systemImage: "doc.on.doc.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                }
            }

            // Cluster count variance
            clusterCountDistributionView

            Divider()

            // Per-video cluster assignment variance
            videoClusterAssignmentView
        }
    }

    private var clusterCountDistributionView: some View {
        let counts = aggFidelityResults.map { $0.clusterCount }
        var countFreq: [Int: Int] = [:]
        for c in counts {
            countFreq[c, default: 0] += 1
        }
        let sorted = countFreq.sorted { $0.key < $1.key }
        let hasVariance = countFreq.count > 1

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Cluster Count")
                    .font(.caption)
                    .fontWeight(.bold)
                Spacer()
                if hasVariance {
                    Text("variance")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Text("stable")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            HStack(spacing: 8) {
                ForEach(sorted, id: \.key) { count, freq in
                    VStack {
                        Text("\(count) clusters")
                            .font(.caption2)
                        Text("\(Int(Double(freq) / Double(aggFidelityResults.count) * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(4)
                }
            }
        }
    }

    private var videoClusterAssignmentView: some View {
        // Compute co-membership analysis
        let analysis = computeCoMembershipAnalysis()

        return VStack(alignment: .leading, spacing: 12) {
            // Overall Membership Stability Score
            HStack {
                Text("Membership Stability")
                    .font(.caption)
                    .fontWeight(.bold)
                Spacer()
                Text("\(Int(analysis.overallStability * 100))%")
                    .font(.headline.bold())
                    .foregroundColor(analysis.overallStability >= 0.85 ? .green : analysis.overallStability >= 0.7 ? .yellow : .orange)
            }
            .padding(8)
            .background(analysis.overallStability >= 0.85 ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            .cornerRadius(6)

            Text("Videos that consistently cluster together (ignoring cluster names)")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Stable Groups
            Text("Stable Groups (\(analysis.stableGroups.count))")
                .font(.caption)
                .fontWeight(.bold)

            ForEach(analysis.stableGroups.indices, id: \.self) { index in
                stableGroupRow(group: analysis.stableGroups[index], index: index + 1)
            }

            // Unstable Videos (if any)
            if !analysis.unstableVideos.isEmpty {
                Divider()
                Text("Unstable Videos (\(analysis.unstableVideos.count))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)

                ForEach(analysis.unstableVideos, id: \.videoId) { unstable in
                    unstableVideoRow(unstable: unstable)
                }
            }
        }
    }

    private func stableGroupRow(group: StableGroup, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Group \(index)")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)

                Spacer()

                Text("\(Int(group.cohesionScore * 100))% cohesion")
                    .font(.caption2)
                    .foregroundColor(group.cohesionScore >= 0.9 ? .green : .yellow)
            }

            ForEach(group.videoIds, id: \.self) { videoId in
                let title = videos.first { $0.videoId == videoId }?.title ?? videoId
                Text("• \(title)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.05))
        .cornerRadius(6)
    }

    private func unstableVideoRow(unstable: UnstableVideo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            let title = videos.first { $0.videoId == unstable.videoId }?.title ?? unstable.videoId
            Text(title)
                .font(.caption2)
                .lineLimit(1)

            Text("Clusters with: \(unstable.topPartners.prefix(3).joined(separator: ", "))")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(6)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(4)
    }

    // MARK: - Co-Membership Analysis

    struct StableGroup {
        let videoIds: [String]
        let cohesionScore: Double  // Average pairwise co-assignment rate
    }

    struct UnstableVideo {
        let videoId: String
        let topPartners: [String]  // Videos it most often clusters with
        let maxCohesion: Double    // Highest pairwise rate
    }

    struct CoMembershipAnalysis {
        let overallStability: Double
        let stableGroups: [StableGroup]
        let unstableVideos: [UnstableVideo]
        let pairwiseMatrix: [String: [String: Double]]  // videoId -> videoId -> co-assignment rate
    }

    private func computeCoMembershipAnalysis() -> CoMembershipAnalysis {
        guard !aggFidelityResults.isEmpty else {
            return CoMembershipAnalysis(overallStability: 0, stableGroups: [], unstableVideos: [], pairwiseMatrix: [:])
        }

        let totalRuns = Double(aggFidelityResults.count)
        let allVideoIds = Array(Set(aggFidelityResults.flatMap { $0.videoAssignments.keys })).sorted()

        // Step 1: Build pairwise co-assignment matrix
        var pairwiseMatrix: [String: [String: Double]] = [:]

        for videoA in allVideoIds {
            pairwiseMatrix[videoA] = [:]
            for videoB in allVideoIds where videoA != videoB {
                var coCount = 0
                for run in aggFidelityResults {
                    let clusterA = run.videoAssignments[videoA]
                    let clusterB = run.videoAssignments[videoB]
                    if let a = clusterA, let b = clusterB, a == b {
                        coCount += 1
                    }
                }
                pairwiseMatrix[videoA]![videoB] = Double(coCount) / totalRuns
            }
        }

        // Step 2: Find stable groups using union-find with threshold
        let threshold = 0.7  // Videos must co-cluster 70%+ of runs to be considered grouped
        var visited = Set<String>()
        var stableGroups: [StableGroup] = []

        for videoId in allVideoIds {
            guard !visited.contains(videoId) else { continue }

            // BFS to find all videos strongly connected to this one
            var group = [videoId]
            var queue = [videoId]
            visited.insert(videoId)

            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard let partners = pairwiseMatrix[current] else { continue }

                for (partner, rate) in partners {
                    if rate >= threshold && !visited.contains(partner) {
                        // Check if partner is strongly connected to ALL current group members
                        let allStrong = group.allSatisfy { member in
                            (pairwiseMatrix[member]?[partner] ?? 0) >= threshold
                        }
                        if allStrong {
                            group.append(partner)
                            queue.append(partner)
                            visited.insert(partner)
                        }
                    }
                }
            }

            if group.count >= 2 {
                // Calculate cohesion score (average pairwise rate within group)
                var totalRate = 0.0
                var pairCount = 0
                for i in 0..<group.count {
                    for j in (i+1)..<group.count {
                        totalRate += pairwiseMatrix[group[i]]?[group[j]] ?? 0
                        pairCount += 1
                    }
                }
                let cohesion = pairCount > 0 ? totalRate / Double(pairCount) : 0

                stableGroups.append(StableGroup(videoIds: group, cohesionScore: cohesion))
            }
        }

        // Step 3: Find unstable videos (not in any stable group)
        let groupedVideos = Set(stableGroups.flatMap { $0.videoIds })
        var unstableVideos: [UnstableVideo] = []

        for videoId in allVideoIds {
            if !groupedVideos.contains(videoId) {
                guard let partners = pairwiseMatrix[videoId] else { continue }
                let sortedPartners = partners.sorted { $0.value > $1.value }
                let topPartners = sortedPartners.prefix(3).map { partner -> String in
                    let title = videos.first { $0.videoId == partner.key }?.title ?? partner.key
                    return "\(title.prefix(20))... (\(Int(partner.value * 100))%)"
                }
                let maxCohesion = sortedPartners.first?.value ?? 0

                unstableVideos.append(UnstableVideo(
                    videoId: videoId,
                    topPartners: topPartners,
                    maxCohesion: maxCohesion
                ))
            }
        }

        // Step 4: Calculate overall stability
        // = weighted average of group cohesion scores + penalty for unstable videos
        let groupedCount = Double(groupedVideos.count)
        let totalCount = Double(allVideoIds.count)
        let groupCoverage = totalCount > 0 ? groupedCount / totalCount : 0

        let avgCohesion = stableGroups.isEmpty ? 0 :
            stableGroups.reduce(0.0) { $0 + $1.cohesionScore } / Double(stableGroups.count)

        let overallStability = avgCohesion * groupCoverage

        return CoMembershipAnalysis(
            overallStability: overallStability,
            stableGroups: stableGroups.sorted { $0.cohesionScore > $1.cohesionScore },
            unstableVideos: unstableVideos,
            pairwiseMatrix: pairwiseMatrix
        )
    }

    // MARK: - Phase 0 Fidelity Testing Functions

    private func runPhase0FidelityTests() async {
        // Determine which videos to test
        let videosToTest: [YouTubeVideo]
        if let selectedId = phase0FidelitySelectedVideoId,
           let selectedVideo = videos.first(where: { $0.videoId == selectedId && $0.hasTranscript }) {
            videosToTest = [selectedVideo]
        } else {
            videosToTest = videos.filter { $0.hasTranscript }
        }

        guard !videosToTest.isEmpty else {
            phase0FidelityError = "No videos with transcripts to test"
            return
        }

        let runsPerVideo = phase0FidelityRunCount
        let totalRuns = videosToTest.count * runsPerVideo
        let temp = phase0FidelityTemperature

        await MainActor.run {
            isRunningPhase0Fidelity = true
            phase0FidelityCurrentRun = 0
            phase0FidelityTotalRuns = totalRuns
            phase0FidelityResults = []
            phase0FidelityError = nil
        }

        var allResults: [Phase0FidelityRunResult] = []
        var completedCount = 0

        print("\n========================================")
        print("PHASE 0 FIDELITY TEST")
        print("========================================")
        print("Videos: \(videosToTest.count)")
        print("Runs per video: \(runsPerVideo)")
        print("Total runs: \(totalRuns)")
        print("Temperature: \(temp)")

        // For each video, run N times in parallel
        for video in videosToTest {
            guard let transcript = video.transcript else { continue }

            print("\nTesting: \(video.title)")

            await withTaskGroup(of: Phase0FidelityRunResult?.self) { group in
                for i in 1...runsPerVideo {
                    group.addTask {
                        do {
                            let startTime = Date()
                            print("  Run \(i) STARTED")

                            let result = try await Phase0AnalysisService.shared.analyzeTranscriptParallel(
                                transcript: transcript,
                                title: video.title,
                                duration: video.duration,
                                temperature: temp
                            )

                            let endTime = Date()

                            let fidelityResult = Phase0FidelityRunResult(
                                runNumber: i,
                                videoId: video.videoId,
                                videoTitle: video.title,
                                pivotCount: result.pivotCount,
                                retentionStrategy: result.retentionStrategy,
                                argumentType: result.argumentType,
                                sectionDensity: result.sectionDensity,
                                narrativeDevice: result.narrativeDevice,
                                format: result.format,
                                transitionMarkerCount: result.transitionMarkers.count,
                                evidenceTypeCount: result.evidenceTypes.count,
                                transitionCount: result.majorTransitions.count,
                                fullResult: result,
                                startedAt: startTime,
                                completedAt: endTime
                            )

                            print("  Run \(i) COMPLETED - \(String(format: "%.1f", fidelityResult.durationSeconds))s")
                            return fidelityResult

                        } catch {
                            print("  Run \(i) FAILED: \(error)")
                            return nil
                        }
                    }
                }

                // Collect results
                for await result in group {
                    completedCount += 1
                    await MainActor.run {
                        phase0FidelityCurrentRun = completedCount
                    }
                    if let result = result {
                        allResults.append(result)
                    }
                }
            }
        }

        print("\n========================================")
        print("PHASE 0 FIDELITY TEST COMPLETE")
        print("Successful runs: \(allResults.count)/\(totalRuns)")
        print("========================================")

        await MainActor.run {
            phase0FidelityResults = allResults.sorted { ($0.videoId, $0.runNumber) < ($1.videoId, $1.runNumber) }
            isRunningPhase0Fidelity = false
            if allResults.count < totalRuns {
                phase0FidelityError = "Only \(allResults.count)/\(totalRuns) runs succeeded"
            }
        }
    }

    private func copyPhase0FidelityPrompt() {
        // Get the prompt that Phase0AnalysisService uses
        let sampleTitle = phase0FidelitySelectedVideoId != nil
            ? (videos.first { $0.videoId == phase0FidelitySelectedVideoId }?.title ?? "Sample Video")
            : "Sample Video"

        let prompt = """
        === PHASE 0 ANALYSIS PROMPT ===
        Temperature: \(String(format: "%.1f", phase0FidelityTemperature))

        ════════════════════════════════════════
        SYSTEM PROMPT
        ════════════════════════════════════════

        You are a video structure analyst extracting the "structural DNA" of YouTube content.
        Focus on HOW the video is constructed, not WHAT it's about.
        Your analysis will be used to build style templates for script writing.
        Be precise with your classifications - these feed into a taxonomy system.
        Return only valid JSON.

        ════════════════════════════════════════
        USER PROMPT
        ════════════════════════════════════════

        Analyze this YouTube video transcript to extract its STRUCTURAL DNA - the patterns that define how this video is constructed, not what it's about.

        VIDEO TITLE: \(sampleTitle)

        TRANSCRIPT:
        [Transcript content here - truncated to 15000 chars]

        EXTRACT THE FOLLOWING STRUCTURAL CHARACTERISTICS:

        1. **PIVOT COUNT** (integer 1-10): How many major argument/narrative pivots does this video have?
        2. **RETENTION STRATEGY** (one of: "mystery-reveal", "escalating-stakes", "promise-payoff", "journey-destination", "problem-solution", "layered-revelation", "contrast-comparison")
        3. **ARGUMENT TYPE** (one of: "investigative", "explanatory", "narrative-driven", "persuasive", "analytical", "experiential")
        4. **SECTION DENSITY** (one of: "sparse", "moderate", "dense")
        5. **TRANSITION MARKERS** (array of 3-6 phrases)
        6. **EVIDENCE TYPES** (array of 2-5 types)
        7. **CORE QUESTION**: Central question/thesis (one sentence)
        8. **NARRATIVE DEVICE** (one of: "mystery-box", "origin-story", "hero-journey", "expose-reveal", "explainer-thread", "countdown", "comparison", "transformation-arc")
        9. **FORMAT** (one of: "produced", "interview", "hybrid", "personal-journey", "meta")
        10. **MAJOR TRANSITIONS** (array of 2-4 objects with approximateLocation, transitionType, description)
        11. **REASONING**: 2-3 sentences explaining WHY this video has this structure.

        Return ONLY valid JSON.
        """

        #if os(iOS)
        UIPasteboard.general.string = prompt
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #endif
        print("📋 Copied Phase 0 fidelity prompt to clipboard")
    }

    private func copyPhase0FidelityInput() {
        let videosToShow: [YouTubeVideo]
        if let selectedId = phase0FidelitySelectedVideoId,
           let video = videos.first(where: { $0.videoId == selectedId }) {
            videosToShow = [video]
        } else {
            videosToShow = videos.filter { $0.hasTranscript }
        }

        var output = """
        === PHASE 0 FIDELITY TEST INPUT ===
        Videos: \(videosToShow.count)
        Runs per video: \(phase0FidelityRunCount)
        Temperature: \(String(format: "%.1f", phase0FidelityTemperature))

        ════════════════════════════════════════
        VIDEO DATA
        ════════════════════════════════════════

        """

        for video in videosToShow {
            output += """

            --- VIDEO: "\(video.title)" ---
            ID: \(video.videoId)
            Has Transcript: \(video.hasTranscript)
            Transcript Length: \(video.transcript?.count ?? 0) chars

            """
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
        print("📋 Copied Phase 0 fidelity input to clipboard")
    }

    private func copyPhase0FidelityResults() {
        guard !phase0FidelityResults.isEmpty else { return }

        let videoGroups = Dictionary(grouping: phase0FidelityResults, by: { $0.videoId })
        let summaries = videoGroups.map { (videoId, runs) in
            Phase0FidelityVideoSummary(videoId: videoId, videoTitle: runs.first?.videoTitle ?? videoId, runs: runs)
        }

        var output = """
        === PHASE 0 FIDELITY RESULTS ===
        Videos Tested: \(summaries.count)
        Total Runs: \(phase0FidelityResults.count)
        Temperature: \(String(format: "%.1f", phase0FidelityTemperature))

        ════════════════════════════════════════
        FIELD STABILITY SUMMARY
        ════════════════════════════════════════

        """

        for summary in summaries.sorted(by: { $0.videoTitle < $1.videoTitle }) {
            output += """

            --- \(summary.videoTitle) (\(summary.runs.count) runs) ---
            Overall Stability: \(Int(summary.overallStability * 100))%
            - pivotCount: \(Int(summary.pivotCountStability * 100))%
            - retentionStrategy: \(Int(summary.retentionStrategyStability * 100))%
            - argumentType: \(Int(summary.argumentTypeStability * 100))%
            - sectionDensity: \(Int(summary.sectionDensityStability * 100))%
            - narrativeDevice: \(Int(summary.narrativeDeviceStability * 100))%
            - format: \(Int(summary.formatStability * 100))%

            Distribution:
            """

            // Pivot count distribution
            let pivotDist = summary.getDistribution(for: summary.runs.map { $0.pivotCount })
            output += "\n  pivotCount: \(pivotDist.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))"

            // Retention strategy distribution
            let retentionDist = summary.getDistribution(for: summary.runs.map { $0.retentionStrategy })
            output += "\n  retentionStrategy: \(retentionDist.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))"

            // Argument type distribution
            let argDist = summary.getDistribution(for: summary.runs.map { $0.argumentType })
            output += "\n  argumentType: \(argDist.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))"

            // Narrative device distribution
            let narrativeDist = summary.getDistribution(for: summary.runs.map { $0.narrativeDevice })
            output += "\n  narrativeDevice: \(narrativeDist.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))"

            output += "\n"
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
        print("📋 Copied Phase 0 fidelity results to clipboard")
    }

    private func copyPhase0FidelityDebug() {
        guard !phase0FidelityResults.isEmpty else { return }

        let videoGroups = Dictionary(grouping: phase0FidelityResults, by: { $0.videoId })
        let summaries = videoGroups.map { (videoId, runs) in
            Phase0FidelityVideoSummary(videoId: videoId, videoTitle: runs.first?.videoTitle ?? videoId, runs: runs)
        }

        // Get the tested videos for transcript inclusion
        let testedVideoIds = Set(phase0FidelityResults.map { $0.videoId })
        let testedVideos = videos.filter { testedVideoIds.contains($0.videoId) }

        var output = """
        ╔══════════════════════════════════════════════════════════════╗
        ║           PHASE 0 FIDELITY FULL DEBUG OUTPUT                 ║
        ╚══════════════════════════════════════════════════════════════╝

        Videos Tested: \(summaries.count)
        Total Runs: \(phase0FidelityResults.count)
        Runs Per Video: \(phase0FidelityRunCount)
        Temperature: \(String(format: "%.1f", phase0FidelityTemperature))
        Date: \(Date())

        ════════════════════════════════════════════════════════════════
        SECTION 1: FULL PROMPT SENT TO LLM
        ════════════════════════════════════════════════════════════════

        --- SYSTEM PROMPT ---

        You are a video structure analyst extracting the "structural DNA" of YouTube content.
        Focus on HOW the video is constructed, not WHAT it's about.
        Your analysis will be used to build style templates for script writing.
        Be precise with your classifications - these feed into a taxonomy system.

        --- USER PROMPT ---

        Analyze this YouTube video transcript to extract its STRUCTURAL DNA.

        VIDEO TITLE: [Video title inserted here]
        VIDEO DURATION: [Duration inserted here]
        TRANSCRIPT:
        [Transcript content - truncated to first 15000 characters]

        EXTRACT THE FOLLOWING STRUCTURAL CHARACTERISTICS:

        1. **PIVOT COUNT** (integer 1-10): Count major argument pivots.
           A pivot MUST meet this criteria: The viewer's mental model of the topic is forced to change.

           COUNT as pivots:
           - "You thought X, but actually Y" reversals
           - New framing that recontextualizes everything before it
           - Stakes/scope dramatically expanding ("this isn't just about X, it's about Y")

           DO NOT count:
           - Topic changes within the same argument ("now let's talk about the cars")
           - New examples or evidence for the same point
           - Transitions between sections

           Ask: "If I stopped watching here, would I have a fundamentally WRONG understanding vs INCOMPLETE understanding?"
           Wrong = pivot. Incomplete = not a pivot.

        2. **RETENTION STRATEGY** (exactly one):
           - "mystery-reveal": Opens with an unanswered question or puzzle, withholds key information until late
           - "escalating-stakes": Each section raises the importance/consequences higher than the last
           - "promise-payoff": Explicitly states what viewer will learn/gain, then delivers it
           - "journey-destination": Takes viewer through a process/experience with a known endpoint
           - "problem-solution": Establishes a problem, then presents resolution
           - "layered-revelation": Progressively deepens understanding through multiple layers (each section recontextualizes previous)
           - "contrast-comparison": Structures around A vs B throughout

        3. **ARGUMENT TYPE** (exactly one):
           - "investigative": Presenter discovers/uncovers information, audience follows the investigation
           - "explanatory": Presenter already knows, teaches viewer how something works
           - "narrative-driven": Story/events carry the content, facts emerge through storytelling
           - "persuasive": Actively arguing for a position, trying to change viewer's mind
           - "analytical": Breaking down components, examining evidence, drawing conclusions
           - "experiential": Presenter's personal experience IS the content

        4. **SECTION DENSITY** (exactly one):
           - "sparse": ≤2 distinct topics per 5 minutes, extended development of each idea
           - "moderate": 3-4 distinct topics per 5 minutes, balanced pacing
           - "dense": ≥5 distinct topics per 5 minutes, rapid information delivery
           Count topic shifts, not examples within a topic.

        5. **TRANSITION MARKERS** (array of 3-6 strings): Extract actual phrases used to signal shifts.
           Examples: "But here's the thing", "Now this is where it gets interesting", "Let's break this down"

        6. **EVIDENCE TYPES** (array of 2-5 strings): What types of proof/support does this video use?
           Options: "statistics", "expert-quotes", "historical-examples", "personal-anecdotes", "visual-demonstrations", "analogies", "case-studies", "primary-sources", "comparisons"

        7. **CORE QUESTION** (one sentence): The central question this video answers.
           Format as a question. Should encompass the entire video, not just the hook.

        8. **NARRATIVE DEVICE** (exactly one):
           - "mystery-box": What is X? (withholds answer)
           - "origin-story": How did X come to be?
           - "hero-journey": Following someone/something through challenges
           - "expose-reveal": Uncovering hidden truth about X
           - "explainer-thread": Here's how X works (systematic breakdown)
           - "countdown": Ranked list or sequential progression
           - "comparison": X vs Y throughout
           - "transformation-arc": How X became Y (change over time)

        9. **FORMAT** (exactly one):
           - "produced": Heavy editing, b-roll, graphics-driven
           - "interview": Conversation-based, multiple speakers as primary structure
           - "hybrid": Mix of talking head and produced segments
           - "personal-journey": Creator's experience/perspective as the frame
           - "vlog": Casual, real-time documentation style
           - "essay": Single narrator, minimal cuts, argument-driven

        10. **MAJOR TRANSITIONS** (array of 2-4 objects):
            Each object: {
              "approximatePercent": (0-100, where in the video),
              "transitionType": ("topic-shift" | "perspective-shift" | "stakes-escalation" | "revelation" | "pivot-to-resolution"),
              "fromTo": "Brief description: [from what] → [to what]"
            }

        11. **REASONING**: 2-3 sentences explaining the structural logic. Why did the creator choose this structure for this content?

        Return ONLY valid JSON matching this exact schema:
        {
          "pivotCount": integer,
          "retentionStrategy": string,
          "argumentType": string,
          "sectionDensity": string,
          "transitionMarkers": string[],
          "evidenceTypes": string[],
          "coreQuestion": string,
          "narrativeDevice": string,
          "format": string,
          "majorTransitions": [
            {
              "approximatePercent": integer,
              "transitionType": string,
              "fromTo": string
            }
          ],
          "reasoning": string
        }

        ════════════════════════════════════════════════════════════════
        SECTION 2: FIELD DEFINITIONS WITH DECISION CRITERIA
        ════════════════════════════════════════════════════════════════

        PIVOT COUNT (1-10):
          Definition: The viewer's mental model of the topic is forced to change
          COUNT: "You thought X, but actually Y" reversals, recontextualizing frames, stakes expanding
          DO NOT COUNT: Topic changes within same argument, new examples, section transitions
          Decision: "If I stopped here, would I have WRONG understanding vs INCOMPLETE?"
          Wrong = pivot. Incomplete = not a pivot.

        RETENTION STRATEGY (exactly one):
          - "mystery-reveal": WITHHOLDS answer until late (not just poses question)
          - "escalating-stakes": Each section RAISES consequences (not just continues)
          - "promise-payoff": EXPLICIT promise + delivery (not implied)
          - "journey-destination": Process/experience with KNOWN endpoint
          - "problem-solution": Problem → resolution structure
          - "layered-revelation": Each layer RECONTEXTUALIZES previous (not just adds)
          - "contrast-comparison": A vs B is the FRAME (not occasional)

        ARGUMENT TYPE (exactly one):
          - "investigative": Presenter DISCOVERS (audience follows investigation)
          - "explanatory": Presenter KNOWS, teaches how something works
          - "narrative-driven": STORY carries content (facts emerge through events)
          - "persuasive": ARGUING for a position (trying to change mind)
          - "analytical": Breaking down + examining evidence + conclusions
          - "experiential": Presenter's EXPERIENCE is the content itself

        SECTION DENSITY (exactly one):
          - "sparse": ≤2 topics per 5 min (deep dive, extended development)
          - "moderate": 3-4 topics per 5 min (balanced pacing)
          - "dense": ≥5 topics per 5 min (rapid information)
          Count TOPIC shifts, not examples within a topic.

        NARRATIVE DEVICE (exactly one):
          - "mystery-box": Central unanswered question drives the video
          - "origin-story": Tracing how X came to be
          - "hero-journey": Someone/something faces challenges
          - "expose-reveal": Uncovering hidden truth
          - "explainer-thread": Systematic "here's how X works"
          - "countdown": Ranked list / sequential progression
          - "comparison": X vs Y throughout
          - "transformation-arc": How X became Y

        FORMAT (exactly one):
          - "produced": Heavy editing, b-roll, graphics (production value)
          - "interview": Multiple speakers, conversation-based
          - "hybrid": Mix talking head + produced segments
          - "personal-journey": Creator's experience as frame
          - "vlog": Casual, real-time documentation
          - "essay": Single narrator, minimal cuts, argument-driven

        MAJOR TRANSITIONS:
          - approximatePercent: 0-100 (numeric for stability)
          - transitionType: topic-shift | perspective-shift | stakes-escalation | revelation | pivot-to-resolution
          - fromTo: "[from what] → [to what]" (concrete, specific)

        """

        // Timing analysis
        if let firstStart = phase0FidelityResults.map({ $0.startedAt }).min(),
           let lastEnd = phase0FidelityResults.map({ $0.completedAt }).max() {
            let totalElapsed = lastEnd.timeIntervalSince(firstStart)
            let avgDuration = phase0FidelityResults.map { $0.durationSeconds }.reduce(0, +) / Double(phase0FidelityResults.count)

            output += """

            ════════════════════════════════════════════════════════════════
            SECTION 3: TIMING ANALYSIS
            ════════════════════════════════════════════════════════════════

            Total Wall Time: \(String(format: "%.1f", totalElapsed))s
            Average Per Run: \(String(format: "%.1f", avgDuration))s
            Expected Sequential: \(String(format: "%.1f", avgDuration * Double(phase0FidelityResults.count)))s
            Parallel Execution: \(totalElapsed < avgDuration * Double(phase0FidelityResults.count) * 0.7 ? "YES" : "NO")

            """
        }

        output += """

        ════════════════════════════════════════════════════════════════
        SECTION 4: TRANSCRIPTS USED
        ════════════════════════════════════════════════════════════════

        """

        for video in testedVideos.sorted(by: { $0.title < $1.title }) {
            let transcript = video.transcript ?? "[No transcript]"
            let truncated = String(transcript.prefix(15000))
            let wasTruncated = transcript.count > 15000

            output += """

            ────────────────────────────────────────────────────────────────
            VIDEO: \(video.title)
            ID: \(video.videoId)
            Transcript Length: \(transcript.count) chars\(wasTruncated ? " (truncated to 15000)" : "")
            ────────────────────────────────────────────────────────────────

            \(truncated)

            """
        }

        output += """

        ════════════════════════════════════════════════════════════════
        SECTION 5: FIELD STABILITY BY VIDEO
        ════════════════════════════════════════════════════════════════

        """

        for summary in summaries.sorted(by: { $0.videoTitle < $1.videoTitle }) {
            output += """

            ────────────────────────────────────────────────────────────────
            \(summary.videoTitle)
            ────────────────────────────────────────────────────────────────
            Overall Stability: \(Int(summary.overallStability * 100))%

            Field Breakdown:
            - pivotCount: \(Int(summary.pivotCountStability * 100))% stable
            - retentionStrategy: \(Int(summary.retentionStrategyStability * 100))% stable
            - argumentType: \(Int(summary.argumentTypeStability * 100))% stable
            - sectionDensity: \(Int(summary.sectionDensityStability * 100))% stable
            - narrativeDevice: \(Int(summary.narrativeDeviceStability * 100))% stable
            - format: \(Int(summary.formatStability * 100))% stable

            Value Distributions:
            - pivotCount: \(summary.getDistribution(for: summary.runs.map { $0.pivotCount }).sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
            - retentionStrategy: \(summary.getDistribution(for: summary.runs.map { $0.retentionStrategy }).sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
            - argumentType: \(summary.getDistribution(for: summary.runs.map { $0.argumentType }).sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
            - sectionDensity: \(summary.getDistribution(for: summary.runs.map { $0.sectionDensity }).sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
            - narrativeDevice: \(summary.getDistribution(for: summary.runs.map { $0.narrativeDevice }).sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
            - format: \(summary.getDistribution(for: summary.runs.compactMap { $0.format }).sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))

            Raw Runs:
            """

            for run in summary.runs.sorted(by: { $0.runNumber < $1.runNumber }) {
                output += """

              Run \(run.runNumber) (\(String(format: "%.1f", run.durationSeconds))s):
                pivotCount: \(run.pivotCount)
                retentionStrategy: \(run.retentionStrategy)
                argumentType: \(run.argumentType)
                sectionDensity: \(run.sectionDensity)
                narrativeDevice: \(run.narrativeDevice)
                format: \(run.format ?? "nil")
                transitionMarkers: \(run.fullResult.transitionMarkers)
                evidenceTypes: \(run.fullResult.evidenceTypes)
                coreQuestion: \(run.fullResult.coreQuestion)
                reasoning: \(run.fullResult.reasoning)
            """
            }

            output += "\n"
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
        print("📋 Copied Phase 0 fidelity debug output to clipboard")
    }

    private func runAggregationFidelityTests() async {
        let analyzedVideos = videos.filter { $0.phase0Result != nil }
        guard analyzedVideos.count >= 3 else {
            aggFidelityError = "Need at least 3 videos with Phase 0 results"
            return
        }

        await MainActor.run {
            isRunningAggFidelity = true
            aggFidelityCurrentRun = 0
            aggFidelityResults = []
            aggFidelityError = nil
        }

        let totalRuns = aggFidelityRunCount
        let temp = aggFidelityTemperature
        var allResults: [AggregationFidelityRunResult] = []
        var completedCount = 0

        print("\n========================================")
        print("AGGREGATION FIDELITY TEST (ALL PARALLEL)")
        print("========================================")
        print("Videos: \(analyzedVideos.count)")
        print("Runs: \(totalRuns)")
        print("Temperature: \(temp)")
        print("Launching ALL \(totalRuns) runs simultaneously...")

        let overallStartTime = Date()

        // Run ALL at once - no batching
        await withTaskGroup(of: (Int, AggregationFidelityRunResult?).self) { group in
            for i in 1...totalRuns {
                group.addTask {
                    do {
                        let startTime = Date()
                        print("Run \(i) STARTED at \(startTime.formatted(date: .omitted, time: .standard))")

                        // Use parallel-safe method with fresh adapter for true concurrent execution
                        let result = try await TaxonomyAggregationService.shared.aggregatePhase0ResultsParallel(
                            videos: analyzedVideos,
                            temperature: temp
                        )

                        // Build video assignments map
                        var videoAssignments: [String: String] = [:]
                        for cluster in result.result.clusters {
                            for videoId in cluster.videoIds {
                                videoAssignments[videoId] = cluster.name
                            }
                        }

                        let clusterNames = result.result.clusters.map { $0.name }
                        let endTime = Date()

                        let fidelityResult = AggregationFidelityRunResult(
                            runNumber: i,
                            clusterCount: result.result.clusters.count,
                            clusterNames: clusterNames,
                            videoAssignments: videoAssignments,
                            sharedPatternCount: result.result.sharedPatterns.count,
                            startedAt: startTime,
                            completedAt: endTime
                        )

                        print("Run \(i) COMPLETED at \(endTime.formatted(date: .omitted, time: .standard)) - took \(String(format: "%.1f", fidelityResult.durationSeconds))s")
                        return (i, fidelityResult)

                    } catch {
                        print("Run \(i) failed: \(error)")
                        return (i, nil)
                    }
                }
            }

            // Collect results as they complete
            for await (runNum, fidelityResult) in group {
                completedCount += 1
                await MainActor.run {
                    aggFidelityCurrentRun = completedCount
                }
                if let fidelityResult = fidelityResult {
                    allResults.append(fidelityResult)
                }
                print("Collected run \(runNum) - \(completedCount)/\(totalRuns) complete")
            }
        }

        let overallEndTime = Date()
        print("\n========================================")
        print("ALL RUNS COMPLETE")
        print("Total wall time: \(String(format: "%.1f", overallEndTime.timeIntervalSince(overallStartTime)))s")
        print("Successful runs: \(allResults.count)/\(totalRuns)")
        print("========================================")

        await MainActor.run {
            aggFidelityResults = allResults.sorted { $0.runNumber < $1.runNumber }
            isRunningAggFidelity = false
            if allResults.count < totalRuns {
                aggFidelityError = "Only \(allResults.count)/\(totalRuns) runs succeeded"
            }
        }
    }

    private func copyAggregationFidelityResults() {
        var output = """
        === AGGREGATION FIDELITY TEST RESULTS ===
        Channel: \(channel.name)
        Videos Analyzed: \(videosWithPhase0)
        Total Runs: \(aggFidelityResults.count)
        Temperature: \(String(format: "%.1f", aggFidelityTemperature))

        ════════════════════════════════════════
        CLUSTER COUNT DISTRIBUTION
        ════════════════════════════════════════

        """

        // Cluster count distribution
        var countFreq: [Int: Int] = [:]
        for run in aggFidelityResults {
            countFreq[run.clusterCount, default: 0] += 1
        }
        for (count, freq) in countFreq.sorted(by: { $0.key < $1.key }) {
            output += "\(count) clusters: \(freq) times (\(Int(Double(freq) / Double(aggFidelityResults.count) * 100))%)\n"
        }

        output += """

        ════════════════════════════════════════
        VIDEO CLUSTER ASSIGNMENT VARIANCE
        ════════════════════════════════════════

        """

        // Per-video analysis
        let allVideoIds = Set(aggFidelityResults.flatMap { $0.videoAssignments.keys })
        for videoId in allVideoIds.sorted() {
            let videoTitle = videos.first { $0.videoId == videoId }?.title ?? videoId

            var clusterFreq: [String: Int] = [:]
            for run in aggFidelityResults {
                if let clusterName = run.videoAssignments[videoId] {
                    clusterFreq[clusterName, default: 0] += 1
                }
            }

            let hasVariance = clusterFreq.count > 1
            output += "\n--- \(videoTitle) "
            output += hasVariance ? "⚠️ VARIANCE ---\n" : "✓ STABLE ---\n"

            for (cluster, count) in clusterFreq.sorted(by: { $0.value > $1.value }) {
                output += "  \"\(cluster)\": \(count)x (\(Int(Double(count) / Double(aggFidelityResults.count) * 100))%)\n"
            }
        }

        output += """

        ════════════════════════════════════════
        RAW RUN DATA
        ════════════════════════════════════════

        """

        for run in aggFidelityResults {
            output += "Run \(run.runNumber): \(run.clusterCount) clusters - \(run.clusterNames.joined(separator: ", "))\n"
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
        print("📋 Copied aggregation fidelity results to clipboard")
    }

    private func copyAggregationPrompt() {
        let analyzedVideos = videos.filter { $0.phase0Result != nil }

        let videoSummaries = analyzedVideos.map { video -> String in
            let p = video.phase0Result!
            return """
            VIDEO: "\(video.title)"
            ID: \(video.videoId)
            - Format: \(p.format ?? "unknown")
            - Pivot Count: \(p.pivotCount)
            - Retention Strategy: \(p.retentionStrategy)
            - Argument Type: \(p.argumentType)
            - Section Density: \(p.sectionDensity)
            - Narrative Device: \(p.narrativeDevice)
            - Evidence Types: \(p.evidenceTypes.joined(separator: ", "))
            - Core Question: \(p.coreQuestion)
            - Reasoning: \(p.reasoning)
            """
        }.joined(separator: "\n\n---\n\n")

        let prompt = """
        === AGGREGATION PROMPT ===
        Temperature: \(String(format: "%.1f", aggFidelityTemperature))
        Videos: \(analyzedVideos.count)

        ════════════════════════════════════════
        SYSTEM PROMPT
        ════════════════════════════════════════

        You are a content strategist analyzing a YouTube creator's video catalog. Your goal is to identify the distinct content types THIS SPECIFIC CREATOR produces. Focus on PATTERNS and INTENT, not just surface features. Let the natural groupings emerge from the data.
        Return only valid JSON.

        ════════════════════════════════════════
        USER PROMPT
        ════════════════════════════════════════

        I have analyzed \(analyzedVideos.count) videos from a single YouTube creator. Each video has been analyzed for its structural DNA.

        HERE ARE THE PHASE 0 ANALYSES:

        \(videoSummaries)

        ---

        ## PHASE 1: Creator Orientation

        Describe this creator's overall approach. Use your own language based on what you observe - examples are provided only to clarify what we're asking, not to limit your answers.

        1. **Primary Evidence Sources**: What does this creator rely on to build credibility?
           Examples (not limited to): expert interviews, archival documents, personal experience, data visualization, location footage, physical demonstration, historical records, scientific papers, hands-on testing...

        2. **Emotional Trajectory**: What emotional experience do these videos create? How does that feeling develop across a typical video?
           Examples (not limited to): building wonder, escalating outrage, deepening curiosity, mounting tension, growing empathy, increasing urgency...

        3. **Creator Positioning**: How does the creator relate to their material and audience?
           Examples (not limited to): expert guide, investigative journalist, curious learner, passionate advocate, neutral explainer, personal witness, skeptical interrogator...

        4. **Resolution Pattern**: How do videos typically end? What state do they leave the viewer in?
           Examples (not limited to): definitive answers, productive uncertainty, moral complexity, call to action, hopeful possibility, philosophical reflection...

        ---

        ## PHASE 2: Cluster Identification

        For each video, determine its PRIMARY STRUCTURAL ENGINE — the single dominant mechanism that drives the viewer's cognitive transformation.

        If a video uses multiple mechanisms, select the dominant one. Treat all others as secondary and ignore them for clustering purposes.

        Cluster videos ONLY by their primary structural engine into 3-7 distinct content types.

        **The structural engine is NOT:**
        - The topic (history, science, politics)
        - The format (interview, produced)
        - The evidence types used

        **The structural engine IS:**
        - HOW the video transforms the viewer's understanding
        - The dominant cognitive journey the viewer takes
        - The primary mechanism that creates viewer engagement

        For each cluster, provide:

        ### Structural Features
        - **name**: Human-readable name reflecting this type of video
        - **coreQuestion**: The central question this type answers
        - **description**: 2-3 sentences describing what defines this type
        - **evidenceTypes**: Common evidence types used
        - **narrativeArc**: How these videos typically progress
        - **videoIds**: Array of video IDs in this cluster
        - **typicalPivotMin / typicalPivotMax**: Range of pivot counts
        - **dominantRetentionStrategy**: Most common retention strategy
        - **dominantArgumentType**: Most common argument type
        - **dominantSectionDensity**: Most common section density

        ### Intent Features
        - **viewerTransformation**: What does the viewer believe/feel BEFORE vs AFTER?
        - **emotionalArc**: What feeling builds throughout? Where does it peak?
        - **creatorRole**: How does the creator position themselves in this type?

        ### Signature Moves
        - **openingPattern**: How do videos in this cluster typically open?
        - **pivotMechanism**: What causes the major turns in these videos?
        - **endingPattern**: How do these videos typically resolve?

        ---

        ## CLUSTER SIZING GUIDANCE

        Your goal is to identify ROBUST content types, not to categorize every video perfectly.

        - Clusters can range from 1 video to many videos
        - A single-video cluster is valid if it represents a genuinely distinct type that differs meaningfully from other clusters
        - DO NOT force videos into ill-fitting clusters just to reduce count
        - DO NOT create separate clusters for videos that only differ by topic

        **The test:** "Does this represent a distinct APPROACH or INTENT, not just a distinct topic?"

        ---

        ## PHASE 3: Cross-Cluster Patterns

        - **sharedPatterns**: 3-5 patterns that appear ACROSS ALL clusters (this creator's signature moves)
        - **creatorSignature**: One paragraph summarizing what makes this creator's style unique

        ---

        ## OUTPUT FORMAT (JSON only)

        {
          "creatorOrientation": {
            "primaryEvidenceSources": "",
            "emotionalTrajectory": "",
            "creatorPositioning": "",
            "resolutionPattern": ""
          },
          "clusters": [
            {
              "name": "",
              "coreQuestion": "",
              "description": "",
              "evidenceTypes": [],
              "narrativeArc": "",
              "videoIds": [],
              "typicalPivotMin": 0,
              "typicalPivotMax": 0,
              "dominantRetentionStrategy": "",
              "dominantArgumentType": "",
              "dominantSectionDensity": "",
              "viewerTransformation": {
                "before": "",
                "after": ""
              },
              "emotionalArc": "",
              "creatorRole": "",
              "signatureMoves": {
                "openingPattern": "",
                "pivotMechanism": "",
                "endingPattern": ""
              }
            }
          ],
          "sharedPatterns": [],
          "creatorSignature": ""
        }

        Return ONLY valid JSON, no other text.
        """

        #if os(iOS)
        UIPasteboard.general.string = prompt
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #endif
        print("📋 Copied aggregation prompt to clipboard")
    }

    private func copyPhase0InputData() {
        let analyzedVideos = videos.filter { $0.phase0Result != nil }

        var output = """
        === PHASE 0 INPUT DATA ===
        Channel: \(channel.name)
        Videos with Phase 0: \(analyzedVideos.count)

        ════════════════════════════════════════
        VIDEO PHASE 0 ANALYSES
        ════════════════════════════════════════

        """

        for video in analyzedVideos {
            guard let p = video.phase0Result else { continue }
            output += """

            --- VIDEO: "\(video.title)" ---
            ID: \(video.videoId)
            - Format: \(p.format ?? "unknown")
            - Pivot Count: \(p.pivotCount)
            - Retention Strategy: \(p.retentionStrategy)
            - Argument Type: \(p.argumentType)
            - Section Density: \(p.sectionDensity)
            - Narrative Device: \(p.narrativeDevice)
            - Evidence Types: \(p.evidenceTypes.joined(separator: ", "))
            - Core Question: \(p.coreQuestion)
            - Reasoning: \(p.reasoning)
            - Transition Markers: \(p.transitionMarkers.joined(separator: ", "))

            """
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
        print("📋 Copied Phase 0 input data to clipboard")
    }

    private func copyFullFidelityDebug() {
        let analyzedVideos = videos.filter { $0.phase0Result != nil }

        // Build the prompt that was used (same as in TaxonomyAggregationService)
        let videoSummaries = analyzedVideos.map { video -> String in
            let p = video.phase0Result!
            return """
            VIDEO: "\(video.title)"
            ID: \(video.videoId)
            - Format: \(p.format ?? "unknown")
            - Pivot Count: \(p.pivotCount)
            - Retention Strategy: \(p.retentionStrategy)
            - Argument Type: \(p.argumentType)
            - Section Density: \(p.sectionDensity)
            - Narrative Device: \(p.narrativeDevice)
            - Evidence Types: \(p.evidenceTypes.joined(separator: ", "))
            - Core Question: \(p.coreQuestion)
            - Reasoning: \(p.reasoning)
            """
        }.joined(separator: "\n\n---\n\n")

        var output = """
        ╔══════════════════════════════════════════════════════════════╗
        ║         FULL AGGREGATION FIDELITY DEBUG OUTPUT              ║
        ╚══════════════════════════════════════════════════════════════╝

        Channel: \(channel.name)
        Videos Analyzed: \(analyzedVideos.count)
        Fidelity Runs: \(aggFidelityResults.count)
        Temperature: \(String(format: "%.1f", aggFidelityTemperature))
        Date: \(Date())

        ════════════════════════════════════════════════════════════════
        SECTION 1: RAW PROMPT USED
        ════════════════════════════════════════════════════════════════

        --- SYSTEM PROMPT ---

        You are a content strategist analyzing a YouTube creator's video catalog. Your goal is to identify the distinct content types THIS SPECIFIC CREATOR produces. Focus on PATTERNS and INTENT, not just surface features. Let the natural groupings emerge from the data.
        Return only valid JSON.

        --- USER PROMPT ---

        I have analyzed \(analyzedVideos.count) videos from a single YouTube creator. Each video has been analyzed for its structural DNA.

        HERE ARE THE PHASE 0 ANALYSES:

        \(videoSummaries)

        ---

        ## PHASE 1: Creator Orientation

        Describe this creator's overall approach. Use your own language based on what you observe - examples are provided only to clarify what we're asking, not to limit your answers.

        1. **Primary Evidence Sources**: What does this creator rely on to build credibility?
        2. **Emotional Trajectory**: What emotional experience do these videos create?
        3. **Creator Positioning**: How does the creator relate to their material and audience?
        4. **Resolution Pattern**: How do videos typically end?

        ---

        ## PHASE 2: Cluster Identification

        Cluster videos into 3-7 distinct content types based on their structural patterns AND what they're trying to accomplish.

        [Full clustering instructions...]

        ---

        ## OUTPUT FORMAT (JSON only)

        [JSON schema...]

        Return ONLY valid JSON, no other text.

        ════════════════════════════════════════════════════════════════
        SECTION 2: CLUSTER COUNT DISTRIBUTION
        ════════════════════════════════════════════════════════════════

        """

        var countFreq: [Int: Int] = [:]
        for run in aggFidelityResults {
            countFreq[run.clusterCount, default: 0] += 1
        }
        for (count, freq) in countFreq.sorted(by: { $0.key < $1.key }) {
            output += "\(count) clusters: \(freq) times (\(Int(Double(freq) / Double(aggFidelityResults.count) * 100))%)\n"
        }

        output += """

        ════════════════════════════════════════════════════════════════
        SECTION 3: RAW RUN DATA (CLUSTER NAMES PER RUN)
        ════════════════════════════════════════════════════════════════

        """

        for run in aggFidelityResults {
            output += """

            Run \(run.runNumber): \(run.clusterCount) clusters
            Cluster Names: \(run.clusterNames.joined(separator: " | "))
            Shared Patterns: \(run.sharedPatternCount)

            """
        }

        // NEW: Co-Membership Analysis (the important part!)
        let analysis = computeCoMembershipAnalysis()

        output += """

        ════════════════════════════════════════════════════════════════
        SECTION 4: CO-MEMBERSHIP ANALYSIS (THE REAL METRIC)
        ════════════════════════════════════════════════════════════════

        OVERALL MEMBERSHIP STABILITY: \(Int(analysis.overallStability * 100))%

        This measures whether the SAME VIDEOS cluster TOGETHER across runs,
        regardless of what the clusters are NAMED.

        ────────────────────────────────────────────────────────────────
        STABLE GROUPS (videos that consistently cluster together)
        ────────────────────────────────────────────────────────────────

        """

        for (index, group) in analysis.stableGroups.enumerated() {
            output += "\nGROUP \(index + 1) - Cohesion: \(Int(group.cohesionScore * 100))%\n"
            for videoId in group.videoIds {
                let title = videos.first { $0.videoId == videoId }?.title ?? videoId
                output += "  • \(title)\n"
            }
        }

        if !analysis.unstableVideos.isEmpty {
            output += """

            ────────────────────────────────────────────────────────────────
            UNSTABLE VIDEOS (don't consistently group with anyone)
            ────────────────────────────────────────────────────────────────

            """

            for unstable in analysis.unstableVideos {
                let title = videos.first { $0.videoId == unstable.videoId }?.title ?? unstable.videoId
                output += "\n\(title)\n"
                output += "  Max cohesion with any video: \(Int(unstable.maxCohesion * 100))%\n"
            }
        }

        output += """

        ════════════════════════════════════════════════════════════════
        SECTION 5: PAIRWISE CO-ASSIGNMENT MATRIX (DETAILED)
        ════════════════════════════════════════════════════════════════

        Format: Video A → Video B: X% (co-clustered in X% of runs)

        """

        let sortedVideoIds = Array(analysis.pairwiseMatrix.keys).sorted()
        for videoA in sortedVideoIds {
            let titleA = videos.first { $0.videoId == videoA }?.title ?? videoA
            output += "\n\(titleA):\n"
            if let partners = analysis.pairwiseMatrix[videoA] {
                let sortedPartners = partners.sorted { $0.value > $1.value }
                for (videoB, rate) in sortedPartners where rate > 0 {
                    let titleB = videos.first { $0.videoId == videoB }?.title ?? videoB
                    output += "  → \(titleB): \(Int(rate * 100))%\n"
                }
            }
        }

        #if os(iOS)
        UIPasteboard.general.string = output
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        #endif
        print("📋 Copied full fidelity debug output to clipboard")
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(currentOperation)
                    .font(.headline)
                Spacer()
                if !activeVideoTitles.isEmpty {
                    Text("\(activeVideoTitles.count) active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            ProgressView(value: Double(processedCount), total: Double(max(totalToProcess, 1)))
                .progressViewStyle(.linear)

            HStack {
                Text("\(processedCount) / \(totalToProcess)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if failedCount > 0 {
                    Text("(\(failedCount) failed)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Show active videos
            if !activeVideoTitles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activeVideoTitles, id: \.self) { title in
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(title)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Data Loading

    private func loadVideos() async {
        isLoading = true
        do {
            // Load ALL videos for this channel (not just those flagged for taxonomy)
            videos = try await YouTubeFirebaseService.shared.getVideos(
                forChannel: channel.channelId
            )
            videos.sort { $0.title < $1.title }
            print("📊 Loaded \(videos.count) videos for \(channel.name)")
        } catch {
            errorMessage = "Failed to load videos: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func loadLockedTaxonomy() async {
        do {
            if let taxonomy = try await YouTubeFirebaseService.shared.getLockedTaxonomy(forChannel: channel.channelId) {
                await MainActor.run {
                    lockedTaxonomy = taxonomy
                }
                print("📊 Loaded locked taxonomy with \(taxonomy.templateCount) templates")
            }
        } catch {
            print("⚠️ No locked taxonomy found or error loading: \(error)")
        }
    }

    // MARK: - Batch Operations

    private func batchFetchTranscripts() async {
        let videosToFetch = videos.filter { !$0.hasTranscript }
        guard !videosToFetch.isEmpty else { return }

        isRunningBatch = true
        currentOperation = "Fetching Transcripts"
        processedCount = 0
        failedCount = 0
        totalToProcess = videosToFetch.count
        activeVideoTitles = []

        // Use an actor to safely manage the work queue
        let workQueue = TranscriptWorkQueue(videos: videosToFetch)

        await withTaskGroup(of: Void.self) { group in
            // Launch initial workers with staggered start
            for workerIndex in 0..<min(maxConcurrentWorkers, videosToFetch.count) {
                group.addTask {
                    // Stagger the initial starts
                    if workerIndex > 0 {
                        try? await Task.sleep(nanoseconds: self.staggerDelayNanos * UInt64(workerIndex))
                    }
                    await self.runTranscriptWorker(queue: workQueue)
                }
            }

            // Wait for all workers to complete
            await group.waitForAll()
        }

        activeVideoTitles = []
        currentOperation = "Complete! (\(processedCount - failedCount) succeeded, \(failedCount) failed)"
        isRunningBatch = false
    }

    /// Worker function that fetches transcripts from the queue until empty
    private func runTranscriptWorker(queue: TranscriptWorkQueue) async {
        let transcriptService = YouTubeTranscriptService()

        while let video = await queue.getNextVideo() {
            // Add to active list
            await MainActor.run {
                activeVideoTitles.append(video.title)
            }

            do {
                let transcript = try await transcriptService.fetchTranscript(videoId: video.videoId)

                // Save transcript to Firebase
                try await YouTubeFirebaseService.shared.updateVideoTranscript(
                    videoId: video.videoId,
                    transcript: transcript
                )

                // Update local state
                await MainActor.run {
                    if let index = videos.firstIndex(where: { $0.videoId == video.videoId }) {
                        videos[index].transcript = transcript
                    }
                }

                print("✅ Transcript fetched for: \(video.title)")

            } catch {
                print("❌ Failed transcript for \(video.videoId): \(error)")
                await MainActor.run {
                    failedCount += 1
                }
            }

            // Update progress and remove from active list
            await MainActor.run {
                processedCount += 1
                activeVideoTitles.removeAll { $0 == video.title }
            }
        }
    }

    private func batchRunPhase0() async {
        let videosToAnalyze = forceRerunPhase0
            ? videos.filter { $0.hasTranscript }
            : videos.filter { $0.hasTranscript && $0.phase0Result == nil }
        guard !videosToAnalyze.isEmpty else { return }

        isRunningBatch = true
        currentOperation = "Running Phase 0 Analysis"
        processedCount = 0
        failedCount = 0
        totalToProcess = videosToAnalyze.count
        activeVideoTitles = []

        // Use an actor to safely manage the work queue
        let workQueue = Phase0WorkQueue(videos: videosToAnalyze)

        print("🔄 Launching \(min(maxConcurrentWorkers, videosToAnalyze.count)) parallel workers for \(videosToAnalyze.count) videos")

        await withTaskGroup(of: Void.self) { group in
            // Launch initial workers with staggered start
            for workerIndex in 0..<min(maxConcurrentWorkers, videosToAnalyze.count) {
                group.addTask {
                    print("👷 Worker \(workerIndex) starting")
                    // Stagger the initial starts
                    if workerIndex > 0 {
                        try? await Task.sleep(nanoseconds: self.staggerDelayNanos * UInt64(workerIndex))
                    }
                    await self.runWorker(queue: workQueue)
                    print("👷 Worker \(workerIndex) finished")
                }
            }

            // Wait for all workers to complete
            await group.waitForAll()
        }

        activeVideoTitles = []
        currentOperation = "Complete! (\(processedCount - failedCount) succeeded, \(failedCount) failed)"
        isRunningBatch = false
    }

    /// Worker function that processes videos from the queue until empty
    private func runWorker(queue: Phase0WorkQueue) async {
        while let video = await queue.getNextVideo() {
            guard let transcript = video.transcript else {
                await MainActor.run {
                    processedCount += 1
                }
                continue
            }

            // Add to active list
            await MainActor.run {
                activeVideoTitles.append(video.title)
            }

            do {
                // Create fresh service instance for true parallel execution
                let service = Phase0AnalysisService()
                print("🚀 Starting Phase 0 for: \(video.title)")
                let result = try await service.analyzeTranscriptParallel(
                    transcript: transcript,
                    title: video.title,
                    duration: video.duration
                )
                // Save Phase0 result to Firebase
                try await YouTubeFirebaseService.shared.savePhase0Result(
                    videoId: video.videoId,
                    result: result
                )

                // Update local state
                await MainActor.run {
                    if let index = videos.firstIndex(where: { $0.videoId == video.videoId }) {
                        videos[index].phase0Result = result
                    }
                }

                print("✅ Phase 0 complete for: \(video.title)")

            } catch {
                print("❌ Failed Phase 0 for \(video.videoId): \(error)")
                await MainActor.run {
                    failedCount += 1
                }
            }

            // Update progress and remove from active list
            await MainActor.run {
                processedCount += 1
                activeVideoTitles.removeAll { $0 == video.title }
            }
        }
    }

    // MARK: - Aggregation

    private func runAggregation() async {
        isRunningAggregation = true
        aggregationError = nil

        do {
            let resultWithPrompt = try await TaxonomyAggregationService.shared.aggregatePhase0Results(videos: videos)
            aggregationResult = resultWithPrompt.result
            aggregationPrompt = resultWithPrompt.promptUsed
            aggregationRawResponse = resultWithPrompt.rawResponse
            print("✅ Aggregation complete: \(resultWithPrompt.result.clusters.count) content types identified")
        } catch {
            aggregationError = error.localizedDescription
            print("❌ Aggregation failed: \(error)")
        }

        isRunningAggregation = false
    }

    // MARK: - Save Taxonomy

    private func saveTaxonomy() async {
        guard let result = aggregationResult else { return }

        // Convert clusters to StyleTemplates with new fields
        let templates = result.clusters.map { cluster in
            var template = StyleTemplate(
                id: "\(channel.channelId)_\(cluster.name.lowercased().replacingOccurrences(of: " ", with: "_"))",
                name: cluster.name,
                description: cluster.description,
                videoIds: cluster.videoIds,
                expectedPivotMin: cluster.typicalPivotMin,
                expectedPivotMax: cluster.typicalPivotMax,
                retentionStrategy: cluster.dominantRetentionStrategy,
                argumentType: cluster.dominantArgumentType,
                sectionDensity: cluster.dominantSectionDensity,
                commonTransitionMarkers: [],
                commonEvidenceTypes: cluster.evidenceTypes,
                expectedSectionsMin: 4,
                expectedSectionsMax: 8,
                turnSignals: []
            )
            // Set the aggregation-derived fields
            template.coreQuestion = cluster.coreQuestion
            template.narrativeArc = cluster.narrativeArc
            return template
        }

        var taxonomy = StyleTaxonomy(
            channelId: channel.channelId,
            templates: templates,
            videoCount: videosWithPhase0,
            minimumVideos: 15,
            createdAt: Date(),
            updatedAt: Date(),
            sharedPatterns: result.sharedPatterns,
            creatorSignature: result.creatorSignature
        )
        taxonomy.creatorOrientation = result.creatorOrientation

        do {
            try await YouTubeFirebaseService.shared.saveTaxonomy(taxonomy)
            print("✅ Taxonomy saved for \(channel.name)")
        } catch {
            errorMessage = "Failed to save taxonomy: \(error.localizedDescription)"
        }
    }
}

// MARK: - Phase 0 Stat Box

private struct Phase0StatBox: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Phase 0 Video Row

private struct Phase0VideoRow: View {
    let video: YouTubeVideo

    var body: some View {
        HStack(spacing: 12) {
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
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.caption)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Transcript status
                    HStack(spacing: 2) {
                        Image(systemName: video.hasTranscript ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(video.hasTranscript ? .blue : .gray)
                        Text("Transcript")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                    // Phase 0 status
                    HStack(spacing: 2) {
                        Image(systemName: video.phase0Result != nil ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(video.phase0Result != nil ? .green : .gray)
                        Text("Phase 0")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Phase 0 summary (if available)
            if let phase0 = video.phase0Result {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(phase0.pivotCount) pivots")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(phase0.retentionStrategy)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Work Queue Actor

/// Thread-safe work queue for concurrent video processing
private actor VideoWorkQueue {
    private var pendingVideos: [YouTubeVideo]

    init(videos: [YouTubeVideo]) {
        self.pendingVideos = videos
    }

    /// Get the next video to process, or nil if queue is empty
    func getNextVideo() -> YouTubeVideo? {
        guard !pendingVideos.isEmpty else { return nil }
        return pendingVideos.removeFirst()
    }

    /// Check if there are more videos to process
    var hasMoreWork: Bool {
        !pendingVideos.isEmpty
    }

    /// Get remaining count
    var remainingCount: Int {
        pendingVideos.count
    }
}

// Type aliases for clarity
private typealias Phase0WorkQueue = VideoWorkQueue
private typealias TranscriptWorkQueue = VideoWorkQueue

// MARK: - Content Type Cluster View

// MARK: - Creator Orientation View

private struct CreatorOrientationView: View {
    let orientation: CreatorOrientation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OrientationRow(label: "Primary Evidence Sources", value: orientation.primaryEvidenceSources, icon: "doc.text.magnifyingglass")
            OrientationRow(label: "Emotional Trajectory", value: orientation.emotionalTrajectory, icon: "heart.text.square")
            OrientationRow(label: "Creator Positioning", value: orientation.creatorPositioning, icon: "person.wave.2")
            OrientationRow(label: "Resolution Pattern", value: orientation.resolutionPattern, icon: "flag.checkered")
        }
        .padding(.vertical, 4)
    }
}

private struct OrientationRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - Content Type Cluster View

private struct ContentTypeClusterView: View {
    let cluster: ContentTypeCluster
    let videos: [YouTubeVideo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Core Question
            VStack(alignment: .leading, spacing: 4) {
                Text("Core Question")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text(cluster.coreQuestion)
                    .font(.subheadline)
                    .italic()
            }

            // Description
            Text(cluster.description)
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // Characteristics
            HStack(spacing: 16) {
                CharacteristicBadge(label: "Pivots", value: "\(cluster.typicalPivotMin)-\(cluster.typicalPivotMax)")
                CharacteristicBadge(label: "Retention", value: cluster.dominantRetentionStrategy)
                CharacteristicBadge(label: "Density", value: cluster.dominantSectionDensity)
            }

            // Evidence Types
            if !cluster.evidenceTypes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidence Types")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    FlowLayout(spacing: 4) {
                        ForEach(cluster.evidenceTypes, id: \.self) { evidence in
                            Text(evidence)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // Narrative Arc
            VStack(alignment: .leading, spacing: 4) {
                Text("Narrative Arc")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text(cluster.narrativeArc)
                    .font(.caption)
            }

            // Intent Features (NEW)
            if let transformation = cluster.viewerTransformation {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Viewer Transformation")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BEFORE")
                                .font(.caption2.bold())
                                .foregroundColor(.orange)
                            Text(transformation.before)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("AFTER")
                                .font(.caption2.bold())
                                .foregroundColor(.green)
                            Text(transformation.after)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let emotionalArc = cluster.emotionalArc {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Emotional Arc")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(emotionalArc)
                        .font(.caption)
                }
            }

            if let creatorRole = cluster.creatorRole {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Creator Role")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(creatorRole)
                        .font(.caption)
                }
            }

            // Signature Moves (NEW)
            if let moves = cluster.signatureMoves {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Signature Moves")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    SignatureMoveRow(label: "Opening", value: moves.openingPattern, color: .blue)
                    SignatureMoveRow(label: "Pivot", value: moves.pivotMechanism, color: .orange)
                    SignatureMoveRow(label: "Ending", value: moves.endingPattern, color: .green)
                }
            }

            Divider()

            // Videos in this cluster
            VStack(alignment: .leading, spacing: 4) {
                Text("\(videos.count) Videos")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                ForEach(videos.prefix(5)) { video in
                    HStack(spacing: 8) {
                        AsyncImage(url: URL(string: video.thumbnailUrl)) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 40, height: 22)
                        .cornerRadius(2)

                        Text(video.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }

                if videos.count > 5 {
                    Text("+ \(videos.count - 5) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct SignatureMoveRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.bold())
                .foregroundColor(color)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.caption2)
        }
    }
}

private struct CharacteristicBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Aggregation Fidelity Models

struct AggregationFidelityRunResult: Identifiable {
    let id = UUID()
    let runNumber: Int
    let clusterCount: Int
    let clusterNames: [String]
    let videoAssignments: [String: String]  // videoId -> clusterName
    let sharedPatternCount: Int
    let startedAt: Date
    let completedAt: Date

    var durationSeconds: Double {
        completedAt.timeIntervalSince(startedAt)
    }
}

// MARK: - Phase 0 Fidelity Models

struct Phase0FidelityRunResult: Identifiable {
    let id = UUID()
    let runNumber: Int
    let videoId: String
    let videoTitle: String

    // Categorical fields (stability focus)
    let pivotCount: Int
    let retentionStrategy: String
    let argumentType: String
    let sectionDensity: String
    let narrativeDevice: String
    let format: String?

    // Array field counts
    let transitionMarkerCount: Int
    let evidenceTypeCount: Int
    let transitionCount: Int

    // Full result for debug
    let fullResult: Phase0Result

    // Timing
    let startedAt: Date
    let completedAt: Date

    var durationSeconds: Double {
        completedAt.timeIntervalSince(startedAt)
    }
}

struct Phase0FidelityVideoSummary {
    let videoId: String
    let videoTitle: String
    let runs: [Phase0FidelityRunResult]

    // Stability scores (1.0 = perfectly stable, 0.0 = completely unstable)
    var pivotCountStability: Double {
        calculateIntStability(runs.map { $0.pivotCount })
    }

    var retentionStrategyStability: Double {
        calculateStringStability(runs.map { $0.retentionStrategy })
    }

    var argumentTypeStability: Double {
        calculateStringStability(runs.map { $0.argumentType })
    }

    var sectionDensityStability: Double {
        calculateStringStability(runs.map { $0.sectionDensity })
    }

    var narrativeDeviceStability: Double {
        calculateStringStability(runs.map { $0.narrativeDevice })
    }

    var formatStability: Double {
        calculateStringStability(runs.compactMap { $0.format })
    }

    var overallStability: Double {
        let scores = [
            pivotCountStability,
            retentionStrategyStability,
            argumentTypeStability,
            sectionDensityStability,
            narrativeDeviceStability,
            formatStability
        ]
        return scores.reduce(0, +) / Double(scores.count)
    }

    // Get distribution for a field
    func getDistribution<T: Hashable>(for values: [T]) -> [T: Int] {
        var freq: [T: Int] = [:]
        for v in values {
            freq[v, default: 0] += 1
        }
        return freq
    }

    private func calculateStringStability(_ values: [String]) -> Double {
        guard !values.isEmpty else { return 0 }
        var freq: [String: Int] = [:]
        for v in values {
            freq[v, default: 0] += 1
        }
        let maxFreq = freq.values.max() ?? 0
        return Double(maxFreq) / Double(values.count)
    }

    private func calculateIntStability(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        var freq: [Int: Int] = [:]
        for v in values {
            freq[v, default: 0] += 1
        }
        let maxFreq = freq.values.max() ?? 0
        return Double(maxFreq) / Double(values.count)
    }
}

// MARK: - Locked Template Row Views

private struct LockedTemplatePreviewRow: View {
    let template: LockedTemplate
    let videos: [YouTubeVideo]

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.caption.bold())
                        Text(template.id)
                            .font(.caption2)
                            .foregroundColor(.indigo)
                    }
                    Spacer()
                    Text("\(template.exemplarCount) exemplars")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Text(template.description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : 2)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    // Classification Criteria
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Classification Criteria")
                            .font(.system(size: 10).bold())
                            .foregroundColor(.blue)

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Required:")
                                    .font(.system(size: 9).bold())
                                    .foregroundColor(.green)
                                ForEach(template.classificationCriteria.requiredSignals, id: \.self) { signal in
                                    Text("• \(signal)")
                                        .font(.system(size: 9))
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Anti-signals:")
                                    .font(.system(size: 9).bold())
                                    .foregroundColor(.red)
                                ForEach(template.classificationCriteria.antiSignals, id: \.self) { signal in
                                    Text("• \(signal)")
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .padding(6)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(4)

                    // Exemplar Videos
                    if !template.exemplarVideoIds.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Exemplar Videos")
                                .font(.system(size: 10).bold())
                                .foregroundColor(.purple)

                            ForEach(template.exemplarVideoIds.prefix(3), id: \.self) { videoId in
                                let title = videos.first { $0.videoId == videoId }?.title ?? videoId
                                Text("• \(title)")
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                            }
                            if template.exemplarVideoIds.count > 3 {
                                Text("+ \(template.exemplarVideoIds.count - 3) more")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }
}

private struct LockedTemplateRow: View {
    let template: LockedTemplate
    let videos: [YouTubeVideo]
    let onOpenWorkbench: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text(template.name)
                                .font(.caption.bold())

                            // A1a prompt status indicator
                            if template.hasA1aPrompt {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 8))
                            }
                        }
                        Text(template.id)
                            .font(.caption2)
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.indigo.opacity(0.1))
                            .cornerRadius(2)
                    }
                    Spacer()
                    Text("\(template.exemplarCount) exemplars")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Divider()

                    // A1a Prompt Status
                    HStack {
                        if template.hasA1aPrompt {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 10))
                                    Text("A1a Prompt")
                                        .font(.system(size: 9).bold())
                                }
                                if let stability = template.a1aStabilityScore {
                                    Text("Stability: \(String(format: "%.0f%%", stability * 100))")
                                        .font(.system(size: 9))
                                        .foregroundColor(stability >= 0.8 ? .green : .orange)
                                }
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10))
                                Text("No A1a Prompt")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Workbench button
                        Button(action: onOpenWorkbench) {
                            HStack(spacing: 4) {
                                Image(systemName: "hammer.fill")
                                Text("Workbench")
                            }
                            .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }

                    Divider()

                    // Classification criteria summary
                    if !template.classificationCriteria.requiredSignals.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Required: \(template.classificationCriteria.requiredSignals.prefix(3).joined(separator: ", "))")
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                                .lineLimit(1)
                        }
                    }

                    // Exemplars
                    if !template.exemplarVideoIds.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exemplars:")
                                .font(.system(size: 9).bold())
                            ForEach(template.exemplarVideoIds.prefix(2), id: \.self) { videoId in
                                let title = videos.first { $0.videoId == videoId }?.title ?? videoId
                                Text("• \(title)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            if template.exemplarVideoIds.count > 2 {
                                Text("+ \(template.exemplarVideoIds.count - 2) more")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.05))
        .cornerRadius(6)
    }
}

#Preview {
    NavigationStack {
        TaxonomyBatchRunnerView(channel: YouTubeChannel(
            channelId: "test",
            name: "Johnny Harris",
            handle: "johnnyharris",
            thumbnailUrl: "",
            videoCount: 100,
            lastSynced: Date()
        ))
    }
    .environmentObject(NavigationViewModel())
}
