//
//  SentenceFidelityTestView.swift
//  NewAgentBuilder
//
//  Created by Claude on 1/26/26.
//

import SwiftUI

/// View for running and comparing sentence-level fidelity tests
/// Isolated from main ingestion - testing harness only
struct SentenceFidelityTestView: View {
    let video: YouTubeVideo
    let channel: YouTubeChannel

    // Shared State
    @State private var testRuns: [SentenceFidelityTest] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Per-Sentence Mode State
    @State private var perSentenceRunning = false
    @State private var perSentenceProgress: (completed: Int, total: Int) = (0, 0)
    @State private var perSentenceRunCount: Int = 3
    @State private var perSentenceTemperature: Double = 0.1
    @State private var perSentenceStatus: String = ""

    // Batched Mode State
    @State private var batchedRunning = false
    @State private var batchedProgress: (completed: Int, total: Int) = (0, 0)
    @State private var batchedRunCount: Int = 3
    @State private var batchedTemperature: Double = 0.1
    @State private var batchedStatus: String = ""

    // Bulk Mode State (for comparison)
    @State private var bulkRunning = false
    @State private var bulkRunCount: Int = 3
    @State private var bulkTemperature: Double = 0.1
    @State private var bulkStatus: String = ""

    // Comparison
    @State private var selectedRun1: SentenceFidelityTest?
    @State private var selectedRun2: SentenceFidelityTest?
    @State private var comparisonResult: FidelityComparisonResult?
    @State private var showComparison = false

    // Detail view
    @State private var selectedRunForDetail: SentenceFidelityTest?

    // Failure debugging
    @State private var showFailureDebugSheet = false
    @State private var failureDebugText = ""

    // Aggregate stability
    @State private var showAggregateDetail = false

    // Computed: Filter runs by mode
    private var perSentenceRuns: [SentenceFidelityTest] {
        testRuns.filter { $0.taggingMode == TaggingMode.perSentence.rawValue }
    }

    private var batchedRuns: [SentenceFidelityTest] {
        testRuns.filter { $0.taggingMode == TaggingMode.batched.rawValue }
    }

    // Computed: Separate summaries for each mode
    private var perSentenceSummary: SentenceFidelityAggregateSummary? {
        guard perSentenceRuns.count >= 2 else { return nil }
        let sentenceCount = perSentenceRuns.first?.totalSentences ?? 0
        return SentenceFidelityAggregateSummary(
            videoId: video.videoId,
            videoTitle: video.title,
            runs: perSentenceRuns,
            sentenceCount: sentenceCount
        )
    }

    private var batchedSummary: SentenceFidelityAggregateSummary? {
        guard batchedRuns.count >= 2 else { return nil }
        let sentenceCount = batchedRuns.first?.totalSentences ?? 0
        return SentenceFidelityAggregateSummary(
            videoId: video.videoId,
            videoTitle: video.title,
            runs: batchedRuns,
            sentenceCount: sentenceCount
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video Info Header
            videoHeaderSection

            Divider()

            if isLoading {
                ProgressView("Loading test history...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Side-by-side mode testers
                        HStack(alignment: .top, spacing: 16) {
                            perSentenceModeSection
                            batchedModeSection
                        }

                        // Mode Comparison (when both modes have 2+ runs)
                        if perSentenceSummary != nil && batchedSummary != nil {
                            modeComparisonSection
                        }

                        // Per-Sentence Stability Section
                        if perSentenceRuns.count >= 2 {
                            perSentenceStabilitySection
                        }

                        // Batched Stability Section
                        if batchedRuns.count >= 2 {
                            batchedStabilitySection
                        }

                        // Previous Runs by Mode
                        if !testRuns.isEmpty {
                            previousRunsByModeSection
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Sentence Fidelity Test")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTestRuns()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
            if !failureDebugText.isEmpty {
                Button("View Failures") {
                    errorMessage = nil
                    showFailureDebugSheet = true
                }
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showComparison) {
            if let result = comparisonResult {
                FidelityComparisonView(result: result)
            }
        }
        .sheet(isPresented: $showFailureDebugSheet) {
            FailureDebugView(debugText: failureDebugText)
        }
    }

    // MARK: - Report Generation

    private func generateFullStabilityReport(_ summary: SentenceFidelityAggregateSummary) -> String {
        var output = """
        ════════════════════════════════════════════════════════════════
        SENTENCE FIDELITY STABILITY REPORT
        ════════════════════════════════════════════════════════════════

        Video: \(summary.videoTitle)
        Video ID: \(summary.videoId)
        Total Runs: \(summary.runs.count)
        Total Sentences: \(summary.sentenceCount)
        Fields Analyzed: \(SentenceTelemetryField.allCases.count)

        ────────────────────────────────────────────────────────────────
        OVERALL STABILITY: \(Int(summary.overallStability * 100))%
        ────────────────────────────────────────────────────────────────

        """

        // Run metadata
        output += "\n═══ RUN METADATA ═══\n"
        for (i, run) in summary.runs.enumerated() {
            output += """
            Run \(i + 1): #\(run.runNumber) | \(run.taggingMode ?? "unknown") | temp=\(String(format: "%.1f", run.temperature ?? 0)) | \(run.totalSentences) sentences
            """
            output += "\n"
        }

        // Field stability by category
        output += "\n═══ FIELD STABILITY BY CATEGORY ═══\n"
        for category in SentenceTelemetryField.FieldCategory.allCases {
            let fieldsInCategory = SentenceTelemetryField.allCases.filter { $0.category == category }
            let avgStability = fieldsInCategory.compactMap { summary.fieldStability[$0] }.reduce(0, +) / Double(fieldsInCategory.count)

            output += "\n\(category.rawValue.uppercased()) (\(Int(avgStability * 100))% avg)\n"
            output += String(repeating: "-", count: 40) + "\n"

            for field in fieldsInCategory {
                if let stability = summary.fieldStability[field] {
                    let indicator = stability >= 0.9 ? "✓" : stability >= 0.7 ? "⚠" : "✗"
                    output += "  \(indicator) \(field.displayName): \(Int(stability * 100))%\n"

                    // Add distribution
                    let dist = summary.getOverallDistribution(for: field)
                    let total = dist.values.reduce(0, +)
                    let sorted = dist.sorted { $0.value > $1.value }
                    let distStr = sorted.prefix(4).map { "\($0.key)=\(Int(Double($0.value)/Double(total)*100))%" }.joined(separator: ", ")
                    output += "      Distribution: \(distStr)\n"
                }
            }
        }

        // Least stable fields
        output += "\n═══ LEAST STABLE FIELDS ═══\n"
        for item in summary.leastStableFields {
            output += "  ✗ \(item.field.displayName): \(Int(item.stability * 100))%\n"
        }

        // Least stable sentences
        output += "\n═══ LEAST STABLE SENTENCES (Top 20) ═══\n"
        for item in summary.leastStableSentences.prefix(20) {
            output += "\n[\(item.index)] Stability: \(Int(item.stability * 100))%\n"
            output += "   \"\(item.text)...\"\n"

            // Show which fields disagreed for this sentence
            let unstableFields = getUnstableFieldsForSentence(summary: summary, index: item.index)
            if !unstableFields.isEmpty {
                output += "   Unstable fields: \(unstableFields.joined(separator: ", "))\n"
            }
        }

        // Per-sentence raw data
        output += "\n═══ ALL SENTENCES STABILITY ═══\n"
        for i in 0..<min(summary.sentenceCount, 150) {
            if let stability = summary.sentenceStability[i] {
                let indicator = stability >= 0.9 ? "✓" : stability >= 0.7 ? "⚠" : "✗"
                let text = summary.runs.first.map { $0.sentences.count > i ? String($0.sentences[i].text.prefix(60)) : "?" } ?? "?"
                output += "[\(String(format: "%3d", i))] \(indicator) \(Int(stability * 100))% | \(text)\n"
            }
        }

        output += "\n════════════════════════════════════════════════════════════════\n"
        output += "END OF REPORT\n"
        output += "════════════════════════════════════════════════════════════════\n"

        return output
    }

    private func getUnstableFieldsForSentence(summary: SentenceFidelityAggregateSummary, index: Int) -> [String] {
        var unstable: [String] = []
        for field in SentenceTelemetryField.allCases {
            let values = summary.runs.compactMap { run -> String? in
                guard index < run.sentences.count else { return nil }
                return run.sentences[index].value(for: field)
            }
            guard values.count > 1 else { continue }

            var freq: [String: Int] = [:]
            for v in values { freq[v, default: 0] += 1 }
            let maxFreq = freq.values.max() ?? 0
            let stability = Double(maxFreq) / Double(values.count)

            if stability < 0.8 {
                unstable.append(field.displayName)
            }
        }
        return unstable
    }

    // MARK: - Video Header

    private var videoHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 16) {
                Label(channel.name, systemImage: "person.circle")
                if video.hasTranscript {
                    Label("Has Transcript", systemImage: "doc.text.fill")
                        .foregroundColor(.green)
                } else {
                    Label("No Transcript", systemImage: "doc.text")
                        .foregroundColor(.red)
                }
                Label("\(testRuns.count) runs", systemImage: "testtube.2")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Per-Sentence Mode Section

    private var perSentenceModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .foregroundColor(.blue)
                Text("Per-Sentence")
                    .font(.headline)
                Spacer()
                if perSentenceRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Text("One LLM call per sentence. 5 concurrent calls (sliding window).")
                .font(.caption)
                .foregroundColor(.secondary)

            // Settings
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Stepper("\(perSentenceRunCount)", value: $perSentenceRunCount, in: 1...10)
                        .frame(width: 90)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Temp")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Slider(value: $perSentenceTemperature, in: 0...1, step: 0.1)
                            .frame(width: 60)
                        Text(String(format: "%.1f", perSentenceTemperature))
                            .font(.caption2.monospaced())
                    }
                }
            }

            // Progress
            if perSentenceRunning && perSentenceProgress.total > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(perSentenceProgress.completed), total: Double(perSentenceProgress.total))
                    Text("\(perSentenceProgress.completed)/\(perSentenceProgress.total) sentences")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !perSentenceStatus.isEmpty {
                Text(perSentenceStatus)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Run button
            Button {
                Task { await runPerSentenceTests() }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Run \(perSentenceRunCount)x")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(perSentenceRunning || !video.hasTranscript)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Batched Mode Section

    private var batchedModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .foregroundColor(.purple)
                Text("Batched (10)")
                    .font(.headline)
                Spacer()
                if batchedRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Text("10 sentences per LLM call. 5 concurrent batches.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Settings
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Stepper("\(batchedRunCount)", value: $batchedRunCount, in: 1...10)
                        .frame(width: 90)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Temp")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Slider(value: $batchedTemperature, in: 0...1, step: 0.1)
                            .frame(width: 60)
                        Text(String(format: "%.1f", batchedTemperature))
                            .font(.caption2.monospaced())
                    }
                }
            }

            // Progress
            if batchedRunning && batchedProgress.total > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(batchedProgress.completed), total: Double(batchedProgress.total))
                    Text("\(batchedProgress.completed)/\(batchedProgress.total) sentences")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !batchedStatus.isEmpty {
                Text(batchedStatus)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Run button
            Button {
                Task { await runBatchedTests() }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Run \(batchedRunCount)x")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(batchedRunning || !video.hasTranscript)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bulk Mode Section

    private var bulkModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.gray)
                Text("Bulk (Baseline)")
                    .font(.headline)
                Spacer()
                if bulkRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Text("All sentences in one LLM call. Fast but may hit token limits.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Stepper("\(bulkRunCount)", value: $bulkRunCount, in: 1...10)
                        .frame(width: 90)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Temp")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Slider(value: $bulkTemperature, in: 0...1, step: 0.1)
                            .frame(width: 60)
                        Text(String(format: "%.1f", bulkTemperature))
                            .font(.caption2.monospaced())
                    }
                }

                Spacer()

                Button {
                    Task { await runBulkTests() }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run \(bulkRunCount)x")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(bulkRunning || !video.hasTranscript)
            }

            if !bulkStatus.isEmpty {
                Text(bulkStatus)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !video.hasTranscript {
                Label("Video needs a transcript first", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Previous Runs by Mode Section

    private var previousRunsByModeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Per-Sentence Runs
            if !perSentenceRuns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .foregroundColor(.blue)
                        Text("Per-Sentence Runs (\(perSentenceRuns.count))")
                            .font(.subheadline.bold())
                    }

                    ForEach(perSentenceRuns) { run in
                        NavigationLink {
                            SentenceRunDetailView(run: run)
                        } label: {
                            previousRunRowContent(run, modeColor: .blue)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await deleteRun(run) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            // Batched Runs
            if !batchedRuns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.purple)
                        Text("Batched Runs (\(batchedRuns.count))")
                            .font(.subheadline.bold())
                    }

                    ForEach(batchedRuns) { run in
                        NavigationLink {
                            SentenceRunDetailView(run: run)
                        } label: {
                            previousRunRowContent(run, modeColor: .purple)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await deleteRun(run) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            // Other Runs (bulk, etc.)
            let otherRuns = testRuns.filter {
                $0.taggingMode != TaggingMode.perSentence.rawValue &&
                $0.taggingMode != TaggingMode.batched.rawValue
            }
            if !otherRuns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.gray)
                        Text("Other Runs (\(otherRuns.count))")
                            .font(.subheadline.bold())
                    }

                    ForEach(otherRuns) { run in
                        NavigationLink {
                            SentenceRunDetailView(run: run)
                        } label: {
                            previousRunRowContent(run, modeColor: .gray)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await deleteRun(run) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private func previousRunRowContent(_ run: SentenceFidelityTest, modeColor: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Run #\(run.runNumber)")
                        .font(.subheadline.bold())

                    if let score = run.stabilityScore {
                        Text("\(Int(score * 100))% stable")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(stabilityColor(score).opacity(0.2))
                            .foregroundColor(stabilityColor(score))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 12) {
                    Text("\(run.totalSentences) sentences")
                    if let temp = run.temperature {
                        Text("t=\(String(format: "%.1f", temp))")
                    }
                    if let duration = run.durationSeconds {
                        Text("\(String(format: "%.1fs", duration))")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Text(run.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    // MARK: - Mode Comparison Section

    private var modeComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(.green)
                Text("Mode Comparison")
                    .font(.headline)
                Spacer()
            }

            if let perSentence = perSentenceSummary, let batched = batchedSummary {
                // Side-by-side comparison
                HStack(spacing: 16) {
                    // Per-Sentence
                    VStack(spacing: 8) {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .foregroundColor(.blue)
                            .font(.title2)
                        Text("Per-Sentence")
                            .font(.caption.bold())
                        Text("\(Int(perSentence.overallStability * 100))%")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(stabilityColor(perSentence.overallStability))
                        Text("\(perSentenceRuns.count) runs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(perSentence.overallStability >= batched.overallStability ? Color.blue.opacity(0.1) : Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(perSentence.overallStability >= batched.overallStability ? Color.blue : Color.clear, lineWidth: 2)
                    )

                    Text("vs")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Batched
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.purple)
                            .font(.title2)
                        Text("Batched (10)")
                            .font(.caption.bold())
                        Text("\(Int(batched.overallStability * 100))%")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(stabilityColor(batched.overallStability))
                        Text("\(batchedRuns.count) runs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(batched.overallStability > perSentence.overallStability ? Color.purple.opacity(0.1) : Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(batched.overallStability > perSentence.overallStability ? Color.purple : Color.clear, lineWidth: 2)
                    )
                }

                // Winner badge
                let diff = abs(perSentence.overallStability - batched.overallStability)
                let winner = perSentence.overallStability >= batched.overallStability ? "Per-Sentence" : "Batched"
                let winnerColor: Color = perSentence.overallStability >= batched.overallStability ? .blue : .purple

                if diff >= 0.01 {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(winnerColor)
                        Text("\(winner) is \(Int(diff * 100))% more stable")
                            .font(.caption.bold())
                            .foregroundColor(winnerColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(winnerColor.opacity(0.1))
                    .cornerRadius(6)
                } else {
                    Text("Both modes perform similarly")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }

                // Copy comparison report
                Button {
                    UIPasteboard.general.string = generateModeComparisonReport(perSentence: perSentence, batched: batched)
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Comparison Report")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private func generateModeComparisonReport(perSentence: SentenceFidelityAggregateSummary, batched: SentenceFidelityAggregateSummary) -> String {
        var output = """
        ════════════════════════════════════════════════════════════════
        MODE COMPARISON REPORT
        ════════════════════════════════════════════════════════════════

        Video: \(video.title)

        ────────────────────────────────────────────────────────────────
        OVERALL COMPARISON
        ────────────────────────────────────────────────────────────────

        Per-Sentence Mode:
          Overall Stability: \(Int(perSentence.overallStability * 100))%
          Runs: \(perSentenceRuns.count)
          Sentences: \(perSentence.sentenceCount)

        Batched (10) Mode:
          Overall Stability: \(Int(batched.overallStability * 100))%
          Runs: \(batchedRuns.count)
          Sentences: \(batched.sentenceCount)

        Winner: \(perSentence.overallStability >= batched.overallStability ? "Per-Sentence" : "Batched") (+\(Int(abs(perSentence.overallStability - batched.overallStability) * 100))%)

        ────────────────────────────────────────────────────────────────
        FIELD-BY-FIELD COMPARISON
        ────────────────────────────────────────────────────────────────

        """

        for field in SentenceTelemetryField.allCases {
            let ps = perSentence.fieldStability[field] ?? 0
            let b = batched.fieldStability[field] ?? 0
            let winner = ps >= b ? "PS" : "B"
            let diff = abs(ps - b)
            output += "\(field.displayName): PS=\(Int(ps * 100))% vs B=\(Int(b * 100))% [\(winner) +\(Int(diff * 100))%]\n"
        }

        output += "\n════════════════════════════════════════════════════════════════\n"
        output += "END OF COMPARISON\n"
        output += "════════════════════════════════════════════════════════════════\n"

        return output
    }

    // MARK: - Per-Sentence Stability Section

    private var perSentenceStabilitySection: some View {
        stabilitySection(
            summary: perSentenceSummary,
            title: "Per-Sentence Stability",
            icon: "text.line.first.and.arrowtriangle.forward",
            color: .blue,
            runCount: perSentenceRuns.count
        )
    }

    // MARK: - Batched Stability Section

    private var batchedStabilitySection: some View {
        stabilitySection(
            summary: batchedSummary,
            title: "Batched Stability",
            icon: "square.stack.3d.up",
            color: .purple,
            runCount: batchedRuns.count
        )
    }

    // MARK: - Reusable Stability Section

    @ViewBuilder
    private func stabilitySection(
        summary: SentenceFidelityAggregateSummary?,
        title: String,
        icon: String,
        color: Color,
        runCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text("\(title) (\(runCount) runs)")
                    .font(.headline)
                Spacer()
            }

            if let summary = summary {
                // Overall Stability Score
                HStack {
                    VStack(alignment: .leading) {
                        Text("Overall Stability")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(summary.overallStability * 100))%")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(stabilityColor(summary.overallStability))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(runCount) runs")
                            .font(.caption.bold())
                        Text("\(summary.sentenceCount) sentences")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(SentenceTelemetryField.allCases.count) fields")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(summary.overallStability >= 0.85 ? color.opacity(0.1) : Color.orange.opacity(0.1))
                .cornerRadius(8)

                // Field Stability Breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Field Stability")
                        .font(.subheadline.bold())

                    ForEach(SentenceTelemetryField.FieldCategory.allCases, id: \.self) { category in
                        fieldCategoryRow(category: category, summary: summary)
                    }
                }

                // Least Stable Fields
                if !summary.leastStableFields.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("⚠️ Least Stable Fields")
                            .font(.caption.bold())
                            .foregroundColor(.orange)

                        ForEach(summary.leastStableFields.prefix(3), id: \.field) { item in
                            HStack {
                                Text(item.field.displayName)
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(item.stability * 100))%")
                                    .font(.caption.bold())
                                    .foregroundColor(stabilityColor(item.stability))
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }

                // Action Buttons
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = generateFullStabilityReport(summary)
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Report")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        AggregateStabilityDetailView(summary: summary)
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("View Details")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(color)
                }
            } else {
                Text("Need at least 2 runs to calculate stability")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private func fieldCategoryRow(category: SentenceTelemetryField.FieldCategory, summary: SentenceFidelityAggregateSummary) -> some View {
        let fieldsInCategory = SentenceTelemetryField.allCases.filter { $0.category == category }
        let avgStability = fieldsInCategory.compactMap { summary.fieldStability[$0] }.reduce(0, +) / Double(fieldsInCategory.count)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(category.rawValue)
                    .font(.caption.bold())
                Spacer()
                Text("\(Int(avgStability * 100))%")
                    .font(.caption.bold())
                    .foregroundColor(stabilityColor(avgStability))
            }

            // Mini field badges
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(fieldsInCategory, id: \.self) { field in
                        if let stability = summary.fieldStability[field] {
                            fieldStabilityBadge(field.displayName, stability)
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(Color(.systemBackground))
        .cornerRadius(6)
    }

    private func fieldStabilityBadge(_ label: String, _ stability: Double) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(stability * 100))%")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(stabilityColor(stability))
            Text(label)
                .font(.system(size: 7))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(stabilityColor(stability).opacity(0.1))
        .cornerRadius(4)
    }

    // MARK: - Legacy Comparison Section (kept for 2-run comparison)

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare Two Runs")
                .font(.headline)

            Text("Select two specific runs to compare side-by-side.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                // Run 1 Picker
                VStack(alignment: .leading) {
                    Text("Run 1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Run 1", selection: $selectedRun1) {
                        Text("Select...").tag(nil as SentenceFidelityTest?)
                        ForEach(testRuns) { run in
                            Text("Run #\(run.runNumber)").tag(run as SentenceFidelityTest?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Text("vs")
                    .foregroundColor(.secondary)

                // Run 2 Picker
                VStack(alignment: .leading) {
                    Text("Run 2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Run 2", selection: $selectedRun2) {
                        Text("Select...").tag(nil as SentenceFidelityTest?)
                        ForEach(testRuns) { run in
                            Text("Run #\(run.runNumber)").tag(run as SentenceFidelityTest?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Spacer()

                Button("Compare") {
                    compareSelectedRuns()
                }
                .buttonStyle(.bordered)
                .disabled(selectedRun1 == nil || selectedRun2 == nil || selectedRun1?.id == selectedRun2?.id)
            }

            if let result = comparisonResult {
                comparisonSummary(result)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private func comparisonSummary(_ result: FidelityComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                VStack(alignment: .leading) {
                    Text("Overall Stability")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(result.overallStability * 100))%")
                        .font(.title.bold())
                        .foregroundColor(stabilityColor(result.overallStability))
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Disagreements")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(result.disagreements.count)")
                        .font(.title2.bold())
                        .foregroundColor(result.disagreements.isEmpty ? .green : .orange)
                }
            }

            if !result.unstableFields.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unstable Fields (<80%):")
                        .font(.caption.bold())
                        .foregroundColor(.orange)

                    ForEach(result.unstableFields, id: \.self) { field in
                        if let score = result.fieldStability[field] {
                            HStack {
                                Text(SentenceTelemetryField(rawValue: field)?.displayName ?? field)
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(score * 100))%")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            Button("View Full Comparison") {
                showComparison = true
            }
            .font(.caption)
        }
    }

    // MARK: - Actions

    private func loadTestRuns() async {
        isLoading = true
        do {
            testRuns = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
        } catch {
            errorMessage = "Failed to load test runs: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Per-Sentence Tests

    private func runPerSentenceTests() async {
        guard let transcript = video.transcript else {
            errorMessage = "No transcript available"
            return
        }

        perSentenceRunning = true
        perSentenceProgress = (0, 0)
        let startTime = Date()

        do {
            for i in 1...perSentenceRunCount {
                perSentenceStatus = "Run \(i)/\(perSentenceRunCount)..."

                let runStartTime = Date()
                let runNumber = try await SentenceFidelityFirebaseService.shared.getNextRunNumber(forVideoId: video.videoId)

                let sentences = try await SentenceTaggingService.shared.tagTranscript(
                    transcript: transcript,
                    temperature: perSentenceTemperature,
                    mode: .perSentence,
                    onProgress: { completed, total in
                        perSentenceProgress = (completed, total)
                    }
                )

                let duration = Date().timeIntervalSince(runStartTime)

                let test = SentenceFidelityTest(
                    id: UUID().uuidString,
                    videoId: video.videoId,
                    channelId: channel.channelId,
                    videoTitle: video.title,
                    createdAt: Date(),
                    runNumber: runNumber,
                    promptVersion: SentenceTaggingService.currentPromptVersion,
                    modelUsed: "claude-4-sonnet",
                    temperature: perSentenceTemperature,
                    taggingMode: TaggingMode.perSentence.rawValue,
                    totalSentences: sentences.count,
                    sentences: sentences,
                    durationSeconds: duration
                )

                try await SentenceFidelityFirebaseService.shared.saveTestRun(test)
            }

            let totalDuration = Date().timeIntervalSince(startTime)
            perSentenceStatus = "Done: \(perSentenceRunCount) runs in \(String(format: "%.1fs", totalDuration))"
            await loadTestRuns()

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            perSentenceStatus = ""
            perSentenceProgress = (0, 0)
        } catch let error as SentenceTaggingError {
            if case .partialFailure(let successes, let failures) = error {
                errorMessage = "Partial failure: \(successes) succeeded, \(failures.count) failed. Tap 'View Failures' to see details."
                failureDebugText = SentenceTaggingDebugStore.shared.allFailuresText
            } else {
                errorMessage = "Per-sentence test failed: \(error.localizedDescription)"
                // Still collect any failures that were stored
                failureDebugText = SentenceTaggingDebugStore.shared.allFailuresText
            }
            perSentenceStatus = "Error"
        } catch {
            errorMessage = "Per-sentence test failed: \(error.localizedDescription)"
            failureDebugText = SentenceTaggingDebugStore.shared.allFailuresText
            perSentenceStatus = "Error"
        }

        perSentenceRunning = false
    }

    // MARK: - Batched Tests

    private func runBatchedTests() async {
        guard let transcript = video.transcript else {
            errorMessage = "No transcript available"
            return
        }

        batchedRunning = true
        batchedProgress = (0, 0)
        let startTime = Date()

        do {
            for i in 1...batchedRunCount {
                batchedStatus = "Run \(i)/\(batchedRunCount)..."

                let runStartTime = Date()
                let runNumber = try await SentenceFidelityFirebaseService.shared.getNextRunNumber(forVideoId: video.videoId)

                let sentences = try await SentenceTaggingService.shared.tagTranscript(
                    transcript: transcript,
                    temperature: batchedTemperature,
                    mode: .batched,
                    onProgress: { completed, total in
                        batchedProgress = (completed, total)
                    }
                )

                let duration = Date().timeIntervalSince(runStartTime)

                let test = SentenceFidelityTest(
                    id: UUID().uuidString,
                    videoId: video.videoId,
                    channelId: channel.channelId,
                    videoTitle: video.title,
                    createdAt: Date(),
                    runNumber: runNumber,
                    promptVersion: SentenceTaggingService.currentPromptVersion,
                    modelUsed: "claude-4-sonnet",
                    temperature: batchedTemperature,
                    taggingMode: TaggingMode.batched.rawValue,
                    totalSentences: sentences.count,
                    sentences: sentences,
                    durationSeconds: duration
                )

                try await SentenceFidelityFirebaseService.shared.saveTestRun(test)
            }

            let totalDuration = Date().timeIntervalSince(startTime)
            batchedStatus = "Done: \(batchedRunCount) runs in \(String(format: "%.1fs", totalDuration))"
            await loadTestRuns()

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            batchedStatus = ""
            batchedProgress = (0, 0)
        } catch let error as SentenceTaggingError {
            if case .partialFailure(let successes, let failures) = error {
                errorMessage = "Partial failure: \(successes) succeeded, \(failures.count) batches failed. Tap 'View Failures' to see details."
                failureDebugText = SentenceTaggingDebugStore.shared.allFailuresText
            } else {
                errorMessage = "Batched test failed: \(error.localizedDescription)"
                failureDebugText = SentenceTaggingDebugStore.shared.allFailuresText
            }
            batchedStatus = "Error"
        } catch {
            errorMessage = "Batched test failed: \(error.localizedDescription)"
            failureDebugText = SentenceTaggingDebugStore.shared.allFailuresText
            batchedStatus = "Error"
        }

        batchedRunning = false
    }

    // MARK: - Bulk Tests

    private func runBulkTests() async {
        guard let transcript = video.transcript else {
            errorMessage = "No transcript available"
            return
        }

        bulkRunning = true
        let startTime = Date()

        do {
            for i in 1...bulkRunCount {
                bulkStatus = "Run \(i)/\(bulkRunCount)..."

                let runStartTime = Date()
                let runNumber = try await SentenceFidelityFirebaseService.shared.getNextRunNumber(forVideoId: video.videoId)

                let sentences = try await SentenceTaggingService.shared.tagTranscript(
                    transcript: transcript,
                    temperature: bulkTemperature,
                    mode: .bulk
                )

                let duration = Date().timeIntervalSince(runStartTime)

                let test = SentenceFidelityTest(
                    id: UUID().uuidString,
                    videoId: video.videoId,
                    channelId: channel.channelId,
                    videoTitle: video.title,
                    createdAt: Date(),
                    runNumber: runNumber,
                    promptVersion: SentenceTaggingService.currentPromptVersion,
                    modelUsed: "claude-4-sonnet",
                    temperature: bulkTemperature,
                    taggingMode: TaggingMode.bulk.rawValue,
                    totalSentences: sentences.count,
                    sentences: sentences,
                    durationSeconds: duration
                )

                try await SentenceFidelityFirebaseService.shared.saveTestRun(test)
            }

            let totalDuration = Date().timeIntervalSince(startTime)
            bulkStatus = "Done: \(bulkRunCount) runs in \(String(format: "%.1fs", totalDuration))"
            await loadTestRuns()

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            bulkStatus = ""
        } catch let error as SentenceTaggingError {
            if case .partialFailure(let successes, let failures) = error {
                errorMessage = "Partial failure: \(successes) succeeded, \(failures.count) failed. Tap 'View Failures' to see details."
                failureDebugText = SentenceTaggingDebugStore.shared.allFailuresText
            } else {
                errorMessage = "Bulk test failed: \(error.localizedDescription)"
                failureDebugText = SentenceTaggingDebugStore.shared.allFailuresText
            }
            bulkStatus = "Error"
        } catch {
            errorMessage = "Bulk test failed: \(error.localizedDescription)"
            failureDebugText = SentenceTaggingDebugStore.shared.allFailuresText
            bulkStatus = "Error"
        }

        bulkRunning = false
    }

    private func deleteRun(_ run: SentenceFidelityTest) async {
        do {
            try await SentenceFidelityFirebaseService.shared.deleteTestRun(id: run.id)
            await loadTestRuns()
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }

    private func compareSelectedRuns() {
        guard let run1 = selectedRun1, let run2 = selectedRun2 else { return }
        comparisonResult = SentenceTaggingService.shared.compareRuns(run1, run2)
    }

    private func stabilityColor(_ score: Double) -> Color {
        if score >= 0.9 { return .green }
        if score >= 0.8 { return .yellow }
        if score >= 0.6 { return .orange }
        return .red
    }
}

// MARK: - Comparison Detail View

struct FidelityComparisonView: View {
    let result: FidelityComparisonResult

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: SentenceTelemetryField.FieldCategory?
    @State private var showOnlyDisagreements = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Overall Score Header
                overallScoreHeader

                Divider()

                // Field Stability by Category
                ScrollView {
                    VStack(spacing: 16) {
                        // Category filter
                        categoryFilterSection

                        // Field stability breakdown
                        fieldStabilitySection

                        // Disagreements
                        if !result.disagreements.isEmpty {
                            disagreementsSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Comparison: Run #\(result.run1.runNumber) vs #\(result.run2.runNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var overallScoreHeader: some View {
        HStack(spacing: 32) {
            VStack {
                Text("\(Int(result.overallStability * 100))%")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(stabilityColor(result.overallStability))
                Text("Overall Stability")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("\(result.stableFields.count) stable fields")
                        .font(.caption)
                }
                HStack {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text("\(result.unstableFields.count) unstable fields")
                        .font(.caption)
                }
                HStack {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("\(result.disagreements.count) disagreements")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private var categoryFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button {
                    selectedCategory = nil
                } label: {
                    Text("All")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedCategory == nil ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(selectedCategory == nil ? .white : .primary)
                        .cornerRadius(16)
                }

                ForEach(SentenceTelemetryField.FieldCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == category ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                            .cornerRadius(16)
                    }
                }
            }
        }
    }

    private var fieldStabilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Field Stability")
                .font(.headline)

            ForEach(filteredFields, id: \.self) { field in
                if let score = result.fieldStability[field.rawValue] {
                    fieldStabilityRow(field: field, score: score)
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private var filteredFields: [SentenceTelemetryField] {
        SentenceTelemetryField.allCases.filter { field in
            if let category = selectedCategory {
                return field.category == category
            }
            return true
        }
    }

    private func fieldStabilityRow(field: SentenceTelemetryField, score: Double) -> some View {
        HStack {
            Text(field.displayName)
                .font(.caption)

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(stabilityColor(score))
                        .frame(width: geo.size.width * score, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(width: 100, height: 8)

            Text("\(Int(score * 100))%")
                .font(.caption.monospaced())
                .foregroundColor(stabilityColor(score))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var disagreementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Disagreements (\(result.disagreements.count))")
                    .font(.headline)

                Spacer()

                Toggle("Show only first 50", isOn: $showOnlyDisagreements)
                    .font(.caption)
            }

            let disagreementsToShow = showOnlyDisagreements
                ? Array(result.disagreements.prefix(50))
                : result.disagreements

            ForEach(disagreementsToShow) { disagreement in
                disagreementRow(disagreement)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private func disagreementRow(_ d: SentenceDisagreement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("[\(d.sentenceIndex)]")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Text(d.fieldName)
                    .font(.caption.bold())
                    .foregroundColor(.orange)
            }

            Text("\"\(d.sentenceText)...\"")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack {
                Text("Run 1: \(d.run1Value)")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)

                Text("→")
                    .foregroundColor(.secondary)

                Text("Run 2: \(d.run2Value)")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(6)
    }

    private func stabilityColor(_ score: Double) -> Color {
        if score >= 0.9 { return .green }
        if score >= 0.8 { return .yellow }
        if score >= 0.6 { return .orange }
        return .red
    }
}

// MARK: - Run Detail View

struct SentenceRunDetailView: View {
    let run: SentenceFidelityTest

    @State private var searchText = ""
    @State private var selectedFilter: FilterOption = .all

    enum FilterOption: String, CaseIterable {
        case all = "All"
        case withStatistic = "Has Statistic"
        case withQuote = "Has Quote"
        case withReveal = "Reveal Language"
        case challenging = "Challenging"
        case transitions = "Transitions"
    }

    var filteredSentences: [SentenceTelemetry] {
        run.sentences.filter { sentence in
            // Search filter
            if !searchText.isEmpty {
                guard sentence.text.localizedCaseInsensitiveContains(searchText) else {
                    return false
                }
            }

            // Category filter
            switch selectedFilter {
            case .all: return true
            case .withStatistic: return sentence.hasStatistic
            case .withQuote: return sentence.hasQuote
            case .withReveal: return sentence.hasRevealLanguage
            case .challenging: return sentence.stance == "challenging"
            case .transitions: return sentence.isTransition
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Run metadata header
            runMetadataHeader

            Divider()

            // Filters
            filterSection

            Divider()

            // Sentences list
            List(filteredSentences) { sentence in
                sentenceRow(sentence)
            }
            .listStyle(.plain)
        }
        .navigationTitle("Run #\(run.runNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = generateRunReport()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search sentences...")
    }

    private func generateRunReport() -> String {
        var output = """
        ════════════════════════════════════════════════════════════════
        RUN #\(run.runNumber) DETAILS
        ════════════════════════════════════════════════════════════════

        Video: \(run.videoTitle)
        Mode: \(run.taggingMode ?? "unknown")
        Temperature: \(String(format: "%.1f", run.temperature ?? 0))
        Model: \(run.modelUsed)
        Prompt Version: \(run.promptVersion)
        Created: \(run.createdAt)
        Duration: \(String(format: "%.1fs", run.durationSeconds ?? 0))
        Total Sentences: \(run.totalSentences)

        ────────────────────────────────────────────────────────────────
        SENTENCES
        ────────────────────────────────────────────────────────────────

        """

        for sentence in run.sentences {
            output += "\n[\(sentence.sentenceIndex)] \(sentence.text)\n"
            output += "   stance=\(sentence.stance) perspective=\(sentence.perspective)\n"

            var flags: [String] = []
            if sentence.hasStatistic { flags.append("stat") }
            if sentence.hasQuote { flags.append("quote") }
            if sentence.hasNamedEntity { flags.append("entity") }
            if sentence.hasRevealLanguage { flags.append("reveal") }
            if sentence.hasPromiseLanguage { flags.append("promise") }
            if sentence.hasChallengeLanguage { flags.append("challenge") }
            if sentence.hasContrastMarker { flags.append("contrast") }
            if sentence.isTransition { flags.append("transition") }
            if sentence.isCallToAction { flags.append("CTA") }
            if sentence.isSponsorContent { flags.append("sponsor") }
            if sentence.hasNumber { flags.append("number") }

            if !flags.isEmpty {
                output += "   flags: \(flags.joined(separator: ", "))\n"
            }
        }

        output += "\n════════════════════════════════════════════════════════════════\n"
        return output
    }

    private var runMetadataHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text("\(run.totalSentences)")
                    .font(.title2.bold())
                Text("sentences")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 40)

            VStack(alignment: .leading) {
                Text(run.modelUsed)
                    .font(.caption.bold())
                Text("v\(run.promptVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let mode = run.taggingMode {
                Divider().frame(height: 40)

                VStack(alignment: .leading) {
                    Text(mode)
                        .font(.caption.bold())
                    Text("mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let temp = run.temperature {
                Divider().frame(height: 40)

                VStack(alignment: .leading) {
                    Text(String(format: "%.1f", temp))
                        .font(.caption.bold())
                    Text("temperature")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider().frame(height: 40)

            VStack(alignment: .leading) {
                Text(run.createdAt, style: .date)
                    .font(.caption.bold())
                Text(run.createdAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let duration = run.durationSeconds {
                Divider().frame(height: 40)

                VStack(alignment: .leading) {
                    Text(String(format: "%.1fs", duration))
                        .font(.caption.bold())
                    Text("duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    Button {
                        selectedFilter = option
                    } label: {
                        Text(option.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedFilter == option ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(selectedFilter == option ? .white : .primary)
                            .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func sentenceRow(_ sentence: SentenceTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Index and text
            HStack(alignment: .top) {
                Text("[\(sentence.sentenceIndex)]")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Text(sentence.text)
                    .font(.caption)
            }

            // Tags row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // Stance
                    stanceTag(sentence.stance)

                    // Perspective
                    perspectiveTag(sentence.perspective)

                    // Boolean flags
                    if sentence.hasStatistic { flagTag("stat", .blue) }
                    if sentence.hasQuote { flagTag("quote", .purple) }
                    if sentence.hasNamedEntity { flagTag("entity", .green) }
                    if sentence.hasRevealLanguage { flagTag("reveal", .orange) }
                    if sentence.hasPromiseLanguage { flagTag("promise", .cyan) }
                    if sentence.hasChallengeLanguage { flagTag("challenge", .red) }
                    if sentence.hasContrastMarker { flagTag("contrast", .gray) }
                    if sentence.isTransition { flagTag("transition", .indigo) }
                    if sentence.isSponsorContent { flagTag("sponsor", .yellow) }
                    if sentence.isCallToAction { flagTag("CTA", .pink) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stanceTag(_ stance: String) -> some View {
        Text(stance)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(stanceColor(stance).opacity(0.2))
            .foregroundColor(stanceColor(stance))
            .cornerRadius(4)
    }

    private func perspectiveTag(_ perspective: String) -> some View {
        Text(perspective)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.2))
            .foregroundColor(.secondary)
            .cornerRadius(4)
    }

    private func flagTag(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private func stanceColor(_ stance: String) -> Color {
        switch stance {
        case "asserting": return .blue
        case "questioning": return .purple
        case "challenging": return .red
        default: return .gray
        }
    }
}

// MARK: - Aggregate Stability Detail View

struct AggregateStabilityDetailView: View {
    let summary: SentenceFidelityAggregateSummary

    @State private var selectedTab = 0
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with overall stats
            aggregateHeader

            Divider()

            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Fields").tag(0)
                Text("Sentences").tag(1)
                Text("Raw Data").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            switch selectedTab {
            case 0:
                fieldStabilityList
            case 1:
                sentenceStabilityList
            case 2:
                rawDataView
            default:
                EmptyView()
            }
        }
        .navigationTitle("Stability Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = generateFullReportText()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search sentences...")
    }

    private func generateFullReportText() -> String {
        var output = """
        ════════════════════════════════════════════════════════════════
        SENTENCE FIDELITY STABILITY REPORT
        ════════════════════════════════════════════════════════════════

        Video: \(summary.videoTitle)
        Video ID: \(summary.videoId)
        Total Runs: \(summary.runs.count)
        Total Sentences: \(summary.sentenceCount)
        Fields Analyzed: \(SentenceTelemetryField.allCases.count)

        ────────────────────────────────────────────────────────────────
        OVERALL STABILITY: \(Int(summary.overallStability * 100))%
        ────────────────────────────────────────────────────────────────

        """

        // Run metadata
        output += "\n═══ RUN METADATA ═══\n"
        for (i, run) in summary.runs.enumerated() {
            output += """
            Run \(i + 1): #\(run.runNumber) | \(run.taggingMode ?? "unknown") | temp=\(String(format: "%.1f", run.temperature ?? 0)) | \(run.totalSentences) sentences
            """
            output += "\n"
        }

        // Field stability by category
        output += "\n═══ FIELD STABILITY BY CATEGORY ═══\n"
        for category in SentenceTelemetryField.FieldCategory.allCases {
            let fieldsInCategory = SentenceTelemetryField.allCases.filter { $0.category == category }
            let avgStability = fieldsInCategory.compactMap { summary.fieldStability[$0] }.reduce(0, +) / Double(fieldsInCategory.count)

            output += "\n\(category.rawValue.uppercased()) (\(Int(avgStability * 100))% avg)\n"
            output += String(repeating: "-", count: 40) + "\n"

            for field in fieldsInCategory {
                if let stability = summary.fieldStability[field] {
                    let indicator = stability >= 0.9 ? "✓" : stability >= 0.7 ? "⚠" : "✗"
                    output += "  \(indicator) \(field.displayName): \(Int(stability * 100))%\n"

                    // Add distribution
                    let dist = summary.getOverallDistribution(for: field)
                    let total = dist.values.reduce(0, +)
                    if total > 0 {
                        let sorted = dist.sorted { $0.value > $1.value }
                        let distStr = sorted.prefix(4).map { "\($0.key)=\(Int(Double($0.value)/Double(total)*100))%" }.joined(separator: ", ")
                        output += "      Distribution: \(distStr)\n"
                    }
                }
            }
        }

        // Least stable fields
        output += "\n═══ LEAST STABLE FIELDS ═══\n"
        for item in summary.leastStableFields {
            output += "  ✗ \(item.field.displayName): \(Int(item.stability * 100))%\n"
        }

        // Least stable sentences
        output += "\n═══ LEAST STABLE SENTENCES (Top 20) ═══\n"
        for item in summary.leastStableSentences.prefix(20) {
            output += "\n[\(item.index)] Stability: \(Int(item.stability * 100))%\n"
            output += "   \"\(item.text)...\"\n"
        }

        // Per-sentence raw data
        output += "\n═══ ALL SENTENCES STABILITY ═══\n"
        for i in 0..<min(summary.sentenceCount, 150) {
            if let stability = summary.sentenceStability[i] {
                let indicator = stability >= 0.9 ? "✓" : stability >= 0.7 ? "⚠" : "✗"
                let text = summary.runs.first.map { $0.sentences.count > i ? String($0.sentences[i].text.prefix(60)) : "?" } ?? "?"
                output += "[\(String(format: "%3d", i))] \(indicator) \(Int(stability * 100))% | \(text)\n"
            }
        }

        output += "\n════════════════════════════════════════════════════════════════\n"
        output += "END OF REPORT\n"
        output += "════════════════════════════════════════════════════════════════\n"

        return output
    }

    private var aggregateHeader: some View {
        HStack(spacing: 20) {
            VStack {
                Text("\(Int(summary.overallStability * 100))%")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(stabilityColor(summary.overallStability))
                Text("Overall")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "doc.text").foregroundColor(.blue)
                    Text("\(summary.runs.count) runs")
                        .font(.caption)
                }
                HStack {
                    Image(systemName: "text.alignleft").foregroundColor(.green)
                    Text("\(summary.sentenceCount) sentences")
                        .font(.caption)
                }
                HStack {
                    Image(systemName: "tag").foregroundColor(.purple)
                    Text("\(SentenceTelemetryField.allCases.count) fields")
                        .font(.caption)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private var fieldStabilityList: some View {
        List {
            ForEach(SentenceTelemetryField.FieldCategory.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    let fieldsInCategory = SentenceTelemetryField.allCases.filter { $0.category == category }
                    ForEach(fieldsInCategory, id: \.self) { field in
                        if let stability = summary.fieldStability[field] {
                            fieldDetailRow(field: field, stability: stability)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func fieldDetailRow(field: SentenceTelemetryField, stability: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.displayName)
                    .font(.subheadline)
                Spacer()
                stabilityIndicator(stability)
                Text("\(Int(stability * 100))%")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundColor(stabilityColor(stability))
            }

            // Distribution preview
            let distribution = summary.getOverallDistribution(for: field)
            if !distribution.isEmpty {
                distributionBar(distribution: distribution)
            }
        }
        .padding(.vertical, 4)
    }

    private func distributionBar(distribution: [String: Int]) -> some View {
        let total = distribution.values.reduce(0, +)
        let sorted = distribution.sorted { $0.value > $1.value }

        return HStack(spacing: 2) {
            ForEach(sorted.prefix(4), id: \.key) { key, value in
                let pct = Double(value) / Double(total)
                VStack(spacing: 1) {
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(key)
                        .font(.system(size: 7))
                        .lineLimit(1)
                }
                .frame(width: CGFloat(pct) * 100, alignment: .center)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(2)
            }
            Spacer()
        }
    }

    private var sentenceStabilityList: some View {
        List {
            // Show least stable sentences first
            Section("Least Stable Sentences") {
                ForEach(summary.leastStableSentences.prefix(20), id: \.index) { item in
                    sentenceStabilityRow(index: item.index, stability: item.stability, text: item.text)
                }
            }

            // All sentences (filtered by search)
            Section("All Sentences") {
                let allSentences = (0..<summary.sentenceCount).compactMap { index -> (Int, Double, String)? in
                    guard let stability = summary.sentenceStability[index],
                          let firstRun = summary.runs.first,
                          index < firstRun.sentences.count else { return nil }
                    let text = firstRun.sentences[index].text
                    if !searchText.isEmpty && !text.localizedCaseInsensitiveContains(searchText) {
                        return nil
                    }
                    return (index, stability, text)
                }

                ForEach(allSentences, id: \.0) { item in
                    sentenceStabilityRow(index: item.0, stability: item.1, text: item.2)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sentenceStabilityRow(index: Int, stability: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("[\(index)]")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Spacer()
                stabilityIndicator(stability)
                Text("\(Int(stability * 100))%")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundColor(stabilityColor(stability))
            }
            Text(text)
                .font(.caption)
                .lineLimit(2)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
    }

    private var rawDataView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Copy this data for debugging:")
                    .font(.caption.bold())

                let text = generateRawDataText()
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)

                Button {
                    UIPasteboard.general.string = text
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy All")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func generateRawDataText() -> String {
        var output = """
        SENTENCE FIDELITY STABILITY REPORT
        ==================================
        Video: \(summary.videoTitle)
        Runs: \(summary.runs.count)
        Sentences: \(summary.sentenceCount)
        Overall Stability: \(Int(summary.overallStability * 100))%

        FIELD STABILITY
        ---------------
        """

        for category in SentenceTelemetryField.FieldCategory.allCases {
            output += "\n\n\(category.rawValue):"
            let fields = SentenceTelemetryField.allCases.filter { $0.category == category }
            for field in fields {
                if let stability = summary.fieldStability[field] {
                    output += "\n  \(field.displayName): \(Int(stability * 100))%"
                }
            }
        }

        output += "\n\nLEAST STABLE SENTENCES\n----------------------"
        for item in summary.leastStableSentences {
            output += "\n[\(item.index)] \(Int(item.stability * 100))%: \(item.text)"
        }

        return output
    }

    private func stabilityIndicator(_ stability: Double) -> some View {
        Image(systemName: stability >= 0.9 ? "checkmark.circle.fill" :
                stability >= 0.7 ? "exclamationmark.circle.fill" : "xmark.circle.fill")
            .foregroundColor(stabilityColor(stability))
            .font(.caption)
    }

    private func stabilityColor(_ score: Double) -> Color {
        if score >= 0.9 { return .green }
        if score >= 0.8 { return .yellow }
        if score >= 0.6 { return .orange }
        return .red
    }
}

// MARK: - Failure Debug View

struct FailureDebugView: View {
    let debugText: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with copy button
                HStack {
                    VStack(alignment: .leading) {
                        Text("Tagging Failures")
                            .font(.headline)
                        Text("Copy this text to share for debugging")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        UIPasteboard.general.string = debugText
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied!" : "Copy All")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(copied ? .green : .blue)
                }
                .padding()
                .background(Color(.secondarySystemBackground))

                Divider()

                // Scrollable text view
                ScrollView {
                    Text(debugText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SentenceFidelityTestView(
        video: YouTubeVideo(
            videoId: "test123",
            channelId: "channel123",
            title: "Test Video Title That Is Long Enough",
            description: "Test description",
            publishedAt: Date(),
            duration: "PT15M30S",
            thumbnailUrl: "",
            stats: VideoStats(viewCount: 1000000, likeCount: 50000, commentCount: 1000),
            createdAt: Date()
        ),
        channel: YouTubeChannel(
            channelId: "channel123",
            name: "Test Channel",
            handle: "testchannel",
            thumbnailUrl: "",
            videoCount: 100,
            lastSynced: Date()
        )
    )
}
