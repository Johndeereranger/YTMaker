//
//  SpineAlignmentFidelityTesterView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 4/2/26.
//

import SwiftUI

// MARK: - View Model

@MainActor
class SpineAlignmentFidelityViewModel: ObservableObject {
    let video: YouTubeVideo
    let channel: YouTubeChannel

    // Config
    @Published var runCount: Int = 3
    @Published var temperature: Double = 0.1

    // Progress
    @Published var isRunning = false
    @Published var currentRun = 0
    @Published var totalRuns = 0
    @Published var currentPhase = ""

    // Results
    @Published var runs: [SpineAlignmentFidelityRun] = []
    @Published var errorMessage: String?

    // History
    @Published var previousTests: [StoredAlignmentFidelityTest] = []

    init(video: YouTubeVideo, channel: YouTubeChannel) {
        self.video = video
        self.channel = channel
        loadPreviousTests()
    }

    // MARK: - Computed Metrics

    var metrics: SpineAlignmentFidelityMetrics {
        SpineAlignmentFidelityMetrics.compute(from: runs)
    }

    var hasResults: Bool { !runs.isEmpty }

    // Loaded spine (populated during fidelity test run)
    @Published var loadedSpine: NarrativeSpine?

    // MARK: - Narrative Spine Text (for copy)

    var narrativeSpineText: String {
        loadedSpine?.renderedText ?? "No narrative spine loaded"
    }

    // MARK: - Rhetorical Sequence Text (for copy)

    var rhetoricalSequenceText: String {
        guard let sequence = video.rhetoricalSequence else { return "No rhetorical sequence" }
        var lines: [String] = []

        lines.append("RHETORICAL MOVE SEQUENCE")
        lines.append("Video: \(video.title)")
        lines.append("Moves: \(sequence.moves.count)")
        lines.append("")

        for move in sequence.moves {
            let conf = String(format: "%.0f%%", move.confidence * 100)
            lines.append("[\(move.chunkIndex)] \(move.moveType.rawValue) (\(conf))")
            lines.append("  \(move.briefDescription)")

            if let gistA = move.gistA {
                lines.append("  gistA: \(gistA.premise)")
            }
            if let gistB = move.gistB {
                lines.append("  gistB: \(gistB.premise)")
            }
            if let expanded = move.expandedDescription {
                lines.append("  expanded: \(expanded)")
            }

            if let alt = move.alternateType, let altConf = move.alternateConfidence {
                lines.append("  alt: \(alt.rawValue) (\(String(format: "%.0f%%", altConf * 100)))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Run Fidelity Test

    func runFidelityTest() async {
        guard !isRunning else { return }

        isRunning = true
        runs = []
        errorMessage = nil
        currentRun = 0
        totalRuns = runCount
        currentPhase = "Starting \(runCount) runs..."

        // Load spine
        guard let spine = try? await NarrativeSpineFirebaseService.shared.loadSpine(videoId: video.videoId) else {
            errorMessage = "Could not load narrative spine"
            isRunning = false
            return
        }
        loadedSpine = spine

        let capturedVideo = video
        let capturedSpine = spine
        let capturedTemp = temperature
        let totalRunCount = runCount

        // Run with concurrency limit of 3
        let maxConcurrency = 3
        let collectedRuns = await withTaskGroup(of: (Int, SpineRhetoricalAlignment)?.self) { group in
            var inFlight = 0
            var nextRun = 1
            var results: [(Int, SpineRhetoricalAlignment)] = []

            while nextRun <= totalRunCount && inFlight < maxConcurrency {
                let runNum = nextRun
                group.addTask {
                    do {
                        let alignment = try await SpineAlignmentService.alignParallel(
                            for: capturedVideo,
                            spine: capturedSpine,
                            runNumber: runNum,
                            temperature: capturedTemp
                        )
                        return (runNum, alignment)
                    } catch {
                        return nil
                    }
                }
                nextRun += 1
                inFlight += 1
            }

            for await result in group {
                if let result {
                    results.append(result)
                }
                inFlight -= 1

                self.currentRun = results.count
                self.currentPhase = "\(results.count)/\(totalRunCount) runs complete"

                if nextRun <= totalRunCount {
                    let runNum = nextRun
                    group.addTask {
                        do {
                            let alignment = try await SpineAlignmentService.alignParallel(
                                for: capturedVideo,
                                spine: capturedSpine,
                                runNumber: runNum,
                                temperature: capturedTemp
                            )
                            return (runNum, alignment)
                        } catch {
                            return nil
                        }
                    }
                    nextRun += 1
                    inFlight += 1
                }
            }

            return results.sorted { $0.0 < $1.0 }
        }

        runs = collectedRuns.map { SpineAlignmentFidelityRun(runNumber: $0.0, alignment: $0.1) }

        if runs.count < totalRunCount {
            errorMessage = "\(totalRunCount - runs.count) run(s) failed"
        }

        if !runs.isEmpty {
            saveTestResult()
        }

        isRunning = false
        currentPhase = runs.isEmpty ? "All runs failed" : "Complete: \(runs.count) runs"
    }

    // MARK: - Summary Text for Copy

    var summaryText: String {
        guard hasResults else { return "No results" }
        let m = metrics
        var lines: [String] = []

        lines.append("SPINE-RHETORICAL ALIGNMENT FIDELITY TEST")
        lines.append("Video: \(video.title)")
        lines.append("Runs: \(runs.count) | Temperature: \(String(format: "%.2f", temperature))")
        lines.append("")
        lines.append("MAPPING CONSISTENCY: \(String(format: "%.1f%%", m.mappingConsistencyRate * 100))")
        lines.append("ORPHAN BEAT AGREEMENT: \(m.orphanBeatAgreement == 1 ? "✓ All agree" : "✗ Diverged")")
        lines.append("UNMAPPED MOVE AGREEMENT: \(m.unmappedMoveAgreement == 1 ? "✓ All agree" : "✗ Diverged")")
        lines.append("")
        lines.append("AVG MOVES/BEAT: min=\(String(format: "%.1f", m.avgMovesPerBeat.min)), max=\(String(format: "%.1f", m.avgMovesPerBeat.max)), mean=\(String(format: "%.1f", m.avgMovesPerBeat.mean))")

        if !m.perFunctionAgreement.isEmpty {
            lines.append("")
            lines.append("PER-FUNCTION AGREEMENT:")
            for detail in m.perFunctionAgreement {
                let stableStr = detail.stableMoves.isEmpty ? "none" : detail.stableMoves.joined(separator: ", ")
                let unstableStr = detail.unstableMoves.isEmpty ? "none" : detail.unstableMoves.joined(separator: ", ")
                lines.append("  \(detail.function): \(String(format: "%.0f%%", detail.agreementRate * 100)) — stable: [\(stableStr)] unstable: [\(unstableStr)]")
            }
        }

        if !m.confusableMappings.isEmpty {
            lines.append("")
            lines.append("CONFUSABLE MAPPINGS:")
            for cm in m.confusableMappings {
                lines.append("  \(cm.function): \(cm.moveA) (stable) ↔ \(cm.moveB) (in \(cm.includedRuns)/\(runs.count) runs)")
            }
        }

        return lines.joined(separator: "\n")
    }

    var detailText: String {
        guard hasResults else { return "No results" }
        let minBeats = runs.map { $0.alignment.beatAlignments.count }.min() ?? 0
        let rhetoricalMoves = video.rhetoricalSequence?.moves ?? []
        var lines: [String] = []

        lines.append("BEAT-BY-BEAT ALIGNMENT DETAIL")
        lines.append("Video: \(video.title)")
        lines.append("")

        for pos in 0..<minBeats {
            lines.append("--- Beat \(pos + 1) ---")

            // Spine beat context
            if let spine = loadedSpine, pos < spine.beats.count {
                let beat = spine.beats[pos]
                lines.append("  SPINE: \(beat.beatSentence)")
                lines.append("  TAG: \(beat.contentTag)")
            }
            if let first = runs.first, pos < first.alignment.beatAlignments.count {
                lines.append("  CONTENT TAG (alignment): \(first.alignment.beatAlignments[pos].contentTag)")
            }
            lines.append("")

            for run in runs {
                guard pos < run.alignment.beatAlignments.count else { continue }
                let ba = run.alignment.beatAlignments[pos]
                lines.append("  Run \(run.runNumber): [\(ba.function)]")
                for mm in ba.mappedMoves {
                    let moveDesc = rhetoricalMoves.first(where: { $0.chunkIndex == mm.chunkIndex })?.briefDescription ?? ""
                    lines.append("    [\(mm.chunkIndex)] \(mm.moveType) (\(mm.overlapStrength)) — \(moveDesc)")
                }
                lines.append("    Rationale: \(ba.rationale)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    var confusableText: String {
        guard hasResults else { return "No results" }
        let m = metrics
        var lines: [String] = []

        lines.append("CONFUSABLE ALIGNMENT MAPPINGS")
        lines.append("Runs: \(runs.count)")
        lines.append("")

        if m.confusableMappings.isEmpty {
            lines.append("No confusable mappings detected.")
            lines.append("All runs agreed on which rhetorical moves map to which spine beats.")
        } else {
            for cm in m.confusableMappings {
                let totalRuns = runs.count
                lines.append("\(cm.function): \(cm.moveA) (stable) ↔ \(cm.moveB) (in \(cm.includedRuns)/\(totalRuns) runs)")
            }
        }

        return lines.joined(separator: "\n")
    }

    var fullDebugText: String {
        let divider = String(repeating: "=", count: 60)
        return [summaryText, "", divider, "", detailText, "", divider, "", confusableText].joined(separator: "\n")
    }

    // MARK: - UserDefaults Storage

    private var storageKey: String {
        "alignment_fidelity_\(video.videoId)"
    }

    private func saveTestResult() {
        let m = metrics
        let test = StoredAlignmentFidelityTest(
            date: Date(),
            runCount: runs.count,
            temperature: temperature,
            mappingConsistencyRate: m.mappingConsistencyRate,
            avgMoveCountMean: m.avgMovesPerBeat.mean,
            orphanBeatCount: runs.first?.alignment.orphanBeats.count ?? 0
        )

        var stored = previousTests
        stored.insert(test, at: 0)
        stored = Array(stored.prefix(5))

        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        previousTests = stored
    }

    private func loadPreviousTests() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let tests = try? JSONDecoder().decode([StoredAlignmentFidelityTest].self, from: data) else {
            return
        }
        previousTests = tests
    }
}

// MARK: - Main View

struct SpineAlignmentFidelityTesterView: View {
    let video: YouTubeVideo
    let channel: YouTubeChannel

    @StateObject private var viewModel: SpineAlignmentFidelityViewModel
    @State private var selectedTab = 0
    @State private var copiedRhetorical = false
    @State private var copiedSpine = false

    init(video: YouTubeVideo, channel: YouTubeChannel) {
        self.video = video
        self.channel = channel
        _viewModel = StateObject(wrappedValue: SpineAlignmentFidelityViewModel(video: video, channel: channel))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                if !viewModel.isRunning {
                    configSection
                }

                if viewModel.isRunning {
                    progressSection
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }

                if viewModel.hasResults {
                    HStack(spacing: 8) {
                        Picker("Tab", selection: $selectedTab) {
                            Text("Summary").tag(0)
                            Text("Detail").tag(1)
                            Text("Confusable").tag(2)
                        }
                        .pickerStyle(.segmented)

                        CompactCopyButton(text: viewModel.fullDebugText)
                    }

                    switch selectedTab {
                    case 0: summaryTab
                    case 1: detailTab
                    case 2: confusableTab
                    default: EmptyView()
                    }
                }

                if !viewModel.previousTests.isEmpty && !viewModel.hasResults {
                    previousTestsSection
                }
            }
            .padding()
        }
        .navigationTitle("Alignment Fidelity Test")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
            Text("\(video.durationFormatted) | \(video.wordCount) words")
                .font(.caption)
                .foregroundColor(.secondary)

            // Source data copy buttons
            HStack(spacing: 8) {
                sourceCopyButton(
                    label: "Rhetorical Sequence",
                    icon: "list.number",
                    color: .blue,
                    isCopied: $copiedRhetorical,
                    text: viewModel.rhetoricalSequenceText
                )
                sourceCopyButton(
                    label: "Narrative Spine",
                    icon: "point.3.connected.trianglepath.dotted",
                    color: .orange,
                    isCopied: $copiedSpine,
                    text: viewModel.narrativeSpineText
                )
            }
        }
    }

    private func sourceCopyButton(label: String, icon: String, color: Color, isCopied: Binding<Bool>, text: String) -> some View {
        Button {
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #endif
            isCopied.wrappedValue = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isCopied.wrappedValue = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied.wrappedValue ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.caption2.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(isCopied.wrappedValue ? 0.25 : 0.08))
            .foregroundColor(isCopied.wrappedValue ? .green : color)
            .cornerRadius(6)
            .animation(.easeInOut(duration: 0.2), value: isCopied.wrappedValue)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Config

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Runs:")
                    .font(.subheadline)
                Stepper("\(viewModel.runCount)", value: $viewModel.runCount, in: 2...10)
                    .frame(width: 120)

                Spacer()

                Text("Temp:")
                    .font(.subheadline)
                Text(String(format: "%.2f", viewModel.temperature))
                    .font(.subheadline.monospacedDigit())
                Slider(value: $viewModel.temperature, in: 0...1, step: 0.05)
                    .frame(width: 120)
            }

            Button {
                Task { await viewModel.runFidelityTest() }
            } label: {
                Label("Run Alignment Fidelity Test", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .disabled(!video.hasNarrativeSpine || !video.hasRhetoricalSequence)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.currentPhase)
                    .font(.subheadline)
            }

            ProgressView(value: Double(viewModel.currentRun), total: Double(viewModel.totalRuns))
                .tint(.teal)
        }
        .padding(12)
        .background(Color.teal.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        let m = viewModel.metrics

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                CompactCopyButton(text: viewModel.summaryText)
            }

            // Mapping consistency
            GroupBox("Mapping Consistency") {
                VStack(alignment: .leading, spacing: 6) {
                    agreementRow("Beat-to-Move Consistency", rate: m.mappingConsistencyRate)
                    agreementRow("Orphan Beat Agreement", rate: m.orphanBeatAgreement)
                    agreementRow("Unmapped Move Agreement", rate: m.unmappedMoveAgreement)
                }
            }

            // Avg moves per beat
            GroupBox("Moves Per Beat") {
                HStack {
                    Text("Min: \(String(format: "%.1f", m.avgMovesPerBeat.min))")
                    Spacer()
                    Text("Mean: \(String(format: "%.1f", m.avgMovesPerBeat.mean))")
                    Spacer()
                    Text("Max: \(String(format: "%.1f", m.avgMovesPerBeat.max))")
                }
                .font(.subheadline.monospacedDigit())
            }

            // Per-function agreement
            if !m.perFunctionAgreement.isEmpty {
                GroupBox("Per-Function Agreement") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(m.perFunctionAgreement) { detail in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(detail.function)
                                        .font(.caption.bold())
                                    Spacer()
                                    Text(String(format: "%.0f%%", detail.agreementRate * 100))
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundColor(rateColor(detail.agreementRate))
                                    Circle()
                                        .fill(rateColor(detail.agreementRate))
                                        .frame(width: 6, height: 6)
                                }

                                if !detail.stableMoves.isEmpty {
                                    FlowLayout(spacing: 3) {
                                        ForEach(detail.stableMoves, id: \.self) { move in
                                            Text(move)
                                                .font(.system(size: 9))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.15))
                                                .cornerRadius(3)
                                        }
                                    }
                                }
                                if !detail.unstableMoves.isEmpty {
                                    FlowLayout(spacing: 3) {
                                        ForEach(detail.unstableMoves, id: \.self) { move in
                                            Text(move)
                                                .font(.system(size: 9))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.15))
                                                .cornerRadius(3)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Confusable summary
            if !m.confusableMappings.isEmpty {
                let totalRuns = viewModel.runs.count
                GroupBox("Confusable Mappings") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(m.confusableMappings.prefix(10).enumerated()), id: \.offset) { _, cm in
                            HStack {
                                Text(cm.function)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(cm.moveA)
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text(cm.moveB)
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                                Spacer()
                                let includedCount = cm.includedRuns
                                Text("\(includedCount)/\(totalRuns)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Detail Tab

    private var detailTab: some View {
        let minBeats = viewModel.runs.map { $0.alignment.beatAlignments.count }.min() ?? 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                CompactCopyButton(text: viewModel.detailText)
            }

            ForEach(0..<minBeats, id: \.self) { pos in
                beatComparisonRow(position: pos)
            }

            let maxBeats = viewModel.runs.map { $0.alignment.beatAlignments.count }.max() ?? 0
            if maxBeats > minBeats {
                Text("Note: \(maxBeats - minBeats) extra beats in some runs (positions \(minBeats + 1)-\(maxBeats) not shown)")
                    .font(.caption)
                    .foregroundColor(.teal)
                    .padding(8)
                    .background(Color.teal.opacity(0.05))
                    .cornerRadius(6)
            }
        }
    }

    @ViewBuilder
    private func beatComparisonRow(position pos: Int) -> some View {
        let moveSets = viewModel.runs.compactMap { run -> Set<String>? in
            guard pos < run.alignment.beatAlignments.count else { return nil }
            return Set(run.alignment.beatAlignments[pos].mappedMoves.map { $0.moveType })
        }
        let isUnanimous = moveSets.count >= 2 && Set(moveSets).count == 1
        let rhetoricalMoves = video.rhetoricalSequence?.moves ?? []

        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                // Spine beat context (shown once, outside per-run loop)
                spineContextBlock(pos: pos)

                // Per-run alignment detail
                ForEach(viewModel.runs, id: \.id) { run in
                    if pos < run.alignment.beatAlignments.count {
                        let ba = run.alignment.beatAlignments[pos]
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text("Run \(run.runNumber)")
                                    .font(.caption2.bold())
                                    .frame(width: 44, alignment: .leading)
                                Text(ba.function)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.teal.opacity(0.15))
                                    .cornerRadius(3)
                            }

                            // Each mapped move with its raw description
                            ForEach(ba.mappedMoves, id: \.self) { mm in
                                let moveDesc = rhetoricalMoves.first(where: { $0.chunkIndex == mm.chunkIndex })?.briefDescription
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text("[\(mm.chunkIndex)]")
                                            .font(.system(size: 9).monospacedDigit())
                                            .foregroundColor(.secondary)
                                        Text(mm.moveType)
                                            .font(.system(size: 9).bold())
                                        Text("(\(mm.overlapStrength))")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(isUnanimous ? Color.green.opacity(0.08) : Color.orange.opacity(0.08))
                                    .cornerRadius(3)

                                    if let desc = moveDesc {
                                        Text(desc)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 8)
                                    }
                                }
                            }

                            Text(ba.rationale)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.top, 2)
                        }
                        .padding(.vertical, 2)

                        if run.runNumber < viewModel.runs.count {
                            Divider()
                        }
                    }
                }
            }
            .padding(.leading, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isUnanimous ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isUnanimous ? .green : .orange)
                    .font(.caption)
                Text("Beat \(pos + 1)")
                    .font(.subheadline.bold())
                if let firstRun = viewModel.runs.first, pos < firstRun.alignment.beatAlignments.count {
                    Text(firstRun.alignment.beatAlignments[pos].function)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("→ \(firstRun.alignment.beatAlignments[pos].mappedMoves.count) moves")
                        .font(.caption2)
                        .foregroundColor(.teal)
                }
            }
        }
    }

    /// Spine beat context block — beatSentence + contentTag
    @ViewBuilder
    private func spineContextBlock(pos: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let spine = viewModel.loadedSpine, pos < spine.beats.count {
                let beat = spine.beats[pos]
                Text(beat.beatSentence)
                    .font(.caption)
                    .foregroundColor(.primary)
                Text("Tag: \(beat.contentTag)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if let firstRun = viewModel.runs.first, pos < firstRun.alignment.beatAlignments.count {
                Text("Tag: \(firstRun.alignment.beatAlignments[pos].contentTag)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Confusable Tab

    private var confusableTab: some View {
        let m = viewModel.metrics

        return VStack(alignment: .leading, spacing: 12) {
            if !m.confusableMappings.isEmpty {
                HStack {
                    Spacer()
                    CompactCopyButton(text: viewModel.confusableText)
                }
            }

            if m.confusableMappings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("No confusable alignment mappings detected")
                        .font(.subheadline)
                    Text("All runs agreed on which rhetorical moves map to which spine beats")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                let totalRuns = viewModel.runs.count
                ForEach(Array(m.confusableMappings.enumerated()), id: \.offset) { _, cm in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(cm.function)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.teal.opacity(0.12))
                                .foregroundColor(.teal)
                                .cornerRadius(4)

                            Text(cm.moveA)
                                .font(.caption.bold())
                                .foregroundColor(.green)
                            Text("(stable)")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Image(systemName: "arrow.left.arrow.right")
                                .font(.caption2)
                                .foregroundColor(.orange)

                            Text(cm.moveB)
                                .font(.caption.bold())
                                .foregroundColor(.orange)

                            Spacer()

                            let includedCount = cm.includedRuns
                            Text("in \(includedCount)/\(totalRuns) runs")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Previous Tests

    private var previousTestsSection: some View {
        GroupBox("Previous Tests") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(viewModel.previousTests.enumerated()), id: \.offset) { _, test in
                    HStack {
                        Text(test.date, style: .date)
                            .font(.caption)
                        Text("\(test.runCount) runs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Consistency: \(String(format: "%.0f%%", test.mappingConsistencyRate * 100))")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(rateColor(test.mappingConsistencyRate))
                        Text("Avg: \(String(format: "%.1f", test.avgMoveCountMean)) mv/bt")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func agreementRow(_ label: String, rate: Double) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(String(format: "%.1f%%", rate * 100))
                .font(.subheadline.monospacedDigit().bold())
                .foregroundColor(rateColor(rate))
            Circle()
                .fill(rateColor(rate))
                .frame(width: 8, height: 8)
        }
    }

    private func rateColor(_ rate: Double) -> Color {
        if rate >= 0.9 { return .green }
        if rate >= 0.7 { return .orange }
        return .red
    }
}
