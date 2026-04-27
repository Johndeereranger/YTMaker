//
//  NarrativeSpineFidelityTesterView.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 3/30/26.
//

import SwiftUI

// MARK: - View Model

@MainActor
class NarrativeSpineFidelityViewModel: ObservableObject {
    let video: YouTubeVideo
    let channel: YouTubeChannel
    private let service = NarrativeSpineService.shared

    // Config
    @Published var runCount: Int = 3
    @Published var temperature: Double = 0.1

    // Progress
    @Published var isRunning = false
    @Published var currentRun = 0
    @Published var totalRuns = 0
    @Published var currentPhase = ""

    // Results
    @Published var runs: [NarrativeSpineFidelityRun] = []
    @Published var errorMessage: String?

    // History
    @Published var previousTests: [StoredSpineFidelityTest] = []

    init(video: YouTubeVideo, channel: YouTubeChannel) {
        self.video = video
        self.channel = channel
        loadPreviousTests()
    }

    // MARK: - Computed Metrics

    var metrics: SpineFidelityMetrics {
        SpineFidelityMetrics.compute(from: runs)
    }

    var hasResults: Bool { !runs.isEmpty }

    // MARK: - Run Fidelity Test

    func runFidelityTest() async {
        guard !isRunning else { return }

        isRunning = true
        runs = []
        errorMessage = nil
        currentRun = 0
        totalRuns = runCount
        currentPhase = "Starting \(runCount) runs..."

        // Load existing spines for corpus examples
        let existingSpines = (try? await NarrativeSpineFirebaseService.shared.loadSpines(channelId: channel.channelId)) ?? []

        // Pre-capture values for @Sendable task closures
        let capturedVideo = video
        let capturedTemp = temperature
        let capturedSpines = existingSpines
        let totalRunCount = runCount

        // Run with concurrency limit of 3
        let maxConcurrency = 3
        let collectedRuns = await withTaskGroup(of: (Int, NarrativeSpine)?.self) { group in
            var inFlight = 0
            var nextRun = 1
            var results: [(Int, NarrativeSpine)] = []

            // Seed initial tasks up to concurrency limit
            while nextRun <= totalRunCount && inFlight < maxConcurrency {
                let runNum = nextRun
                group.addTask {
                    do {
                        let spine = try await NarrativeSpineService.extractSpineParallel(
                            for: capturedVideo,
                            existingSpines: capturedSpines,
                            temperature: capturedTemp
                        )
                        return (runNum, spine)
                    } catch {
                        return nil
                    }
                }
                nextRun += 1
                inFlight += 1
            }

            // As tasks complete, launch new ones
            for await result in group {
                if let result {
                    results.append(result)
                }
                inFlight -= 1

                self.currentRun = results.count
                self.currentPhase = "\(results.count)/\(totalRunCount) runs complete"

                // Launch next task if available
                if nextRun <= totalRunCount {
                    let runNum = nextRun
                    group.addTask {
                        do {
                            let spine = try await NarrativeSpineService.extractSpineParallel(
                                for: capturedVideo,
                                existingSpines: capturedSpines,
                                temperature: capturedTemp
                            )
                            return (runNum, spine)
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

        // Build fidelity runs
        runs = collectedRuns.map { NarrativeSpineFidelityRun(runNumber: $0.0, spine: $0.1) }

        if runs.count < totalRunCount {
            errorMessage = "\(totalRunCount - runs.count) run(s) failed"
        }

        // Save test result
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

        lines.append("NARRATIVE SPINE FIDELITY TEST")
        lines.append("Video: \(video.title)")
        lines.append("Runs: \(runs.count) | Temperature: \(String(format: "%.2f", temperature))")
        lines.append("")
        lines.append("BEAT COUNT: min=\(m.beatCountSpread.min), max=\(m.beatCountSpread.max), mode=\(m.beatCountSpread.mode)")
        let spread = m.beatCountSpread.max - m.beatCountSpread.min
        lines.append("  Spread: \(spread) \(spread >= 4 ? "⚠️ HIGH VARIANCE" : "✓")")
        lines.append("")
        lines.append("FUNCTION LABEL AGREEMENT: \(String(format: "%.1f%%", m.functionAgreementRate * 100))")
        lines.append("CONTENT SCOPE AGREEMENT: \(String(format: "%.1f%%", m.contentScopeAgreementRate * 100))")
        lines.append("PHASE BOUNDARY AGREEMENT: \(String(format: "%.1f%%", m.phaseBoundaryAgreementRate * 100))")
        lines.append("DEPENDS-ON AGREEMENT: \(String(format: "%.1f%%", m.dependsOnAgreementRate * 100))")

        if !m.confusablePairs.isEmpty {
            lines.append("")
            lines.append("CONFUSABLE FUNCTION PAIRS:")
            for pair in m.confusablePairs {
                let positions = pair.beatPositions.map(String.init).joined(separator: ", ")
                lines.append("  \(pair.labelA) <-> \(pair.labelB) (\(pair.swapCount)x at beats \(positions))")
            }
        }

        return lines.joined(separator: "\n")
    }

    var detailText: String {
        guard hasResults else { return "No results" }
        let minBeats = runs.map { $0.spine.beats.count }.min() ?? 0
        var lines: [String] = []

        lines.append("BEAT-BY-BEAT DETAIL")
        lines.append("")

        for pos in 0..<minBeats {
            lines.append("--- Beat \(pos + 1) ---")
            for run in runs {
                guard pos < run.spine.beats.count else { continue }
                let beat = run.spine.beats[pos]
                lines.append("  Run \(run.runNumber): [\(beat.function)] \(beat.beatSentence)")
                lines.append("    Content: \(beat.contentTag)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    var confusableText: String {
        guard hasResults else { return "No results" }
        let m = metrics
        var lines: [String] = []

        lines.append("CONFUSABLE FUNCTION PAIRS")
        lines.append("")

        if m.confusablePairs.isEmpty {
            lines.append("No confusable function pairs detected.")
            lines.append("All runs agreed on function labels at every beat position.")
        } else {
            for pair in m.confusablePairs {
                let positions = pair.beatPositions.map(String.init).joined(separator: ", ")
                lines.append("--- \(pair.labelA) <-> \(pair.labelB) (\(pair.swapCount) swap\(pair.swapCount == 1 ? "" : "s")) ---")
                lines.append("At beats: \(positions)")

                for beatPos in pair.beatPositions {
                    let pos = beatPos - 1
                    guard pos >= 0 else { continue }
                    lines.append("  Beat \(beatPos):")
                    for run in runs {
                        guard pos < run.spine.beats.count else { continue }
                        let beat = run.spine.beats[pos]
                        lines.append("    R\(run.runNumber): \(beat.function) | \(beat.contentTag)")
                    }
                }
                lines.append("")
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
        "spine_fidelity_\(video.videoId)"
    }

    private func saveTestResult() {
        let m = metrics
        let test = StoredSpineFidelityTest(
            date: Date(),
            runCount: runs.count,
            temperature: temperature,
            beatCountMin: m.beatCountSpread.min,
            beatCountMax: m.beatCountSpread.max,
            beatCountMode: m.beatCountSpread.mode,
            functionAgreementRate: m.functionAgreementRate,
            contentScopeAgreementRate: m.contentScopeAgreementRate,
            phaseBoundaryAgreementRate: m.phaseBoundaryAgreementRate
        )

        var stored = previousTests
        stored.insert(test, at: 0)
        stored = Array(stored.prefix(5)) // Keep last 5

        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        previousTests = stored
    }

    private func loadPreviousTests() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let tests = try? JSONDecoder().decode([StoredSpineFidelityTest].self, from: data) else {
            return
        }
        previousTests = tests
    }
}

// MARK: - Main View

struct NarrativeSpineFidelityTesterView: View {
    let video: YouTubeVideo
    let channel: YouTubeChannel

    @StateObject private var viewModel: NarrativeSpineFidelityViewModel
    @State private var selectedTab = 0

    init(video: YouTubeVideo, channel: YouTubeChannel) {
        self.video = video
        self.channel = channel
        _viewModel = StateObject(wrappedValue: NarrativeSpineFidelityViewModel(video: video, channel: channel))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection

                // Config
                if !viewModel.isRunning {
                    configSection
                }

                // Progress
                if viewModel.isRunning {
                    progressSection
                }

                // Error
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }

                // Results
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

                // Previous Tests
                if !viewModel.previousTests.isEmpty && !viewModel.hasResults {
                    previousTestsSection
                }
            }
            .padding()
        }
        .navigationTitle("Spine Fidelity Test")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(video.title)
                .font(.headline)
            Text("\(video.durationFormatted) | \(video.wordCount) words")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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
                Label("Run Fidelity Test", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!video.hasTranscript)
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
                .tint(.orange)
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        let m = viewModel.metrics
        let spread = m.beatCountSpread.max - m.beatCountSpread.min

        return VStack(alignment: .leading, spacing: 12) {
            // Copy button
            HStack {
                Spacer()
                CompactCopyButton(text: viewModel.summaryText)
            }

            // Beat count spread
            GroupBox("Beat Count") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Min: \(m.beatCountSpread.min)")
                        Spacer()
                        Text("Mode: \(m.beatCountSpread.mode)")
                        Spacer()
                        Text("Max: \(m.beatCountSpread.max)")
                    }
                    .font(.subheadline.monospacedDigit())

                    HStack {
                        Text("Spread: \(spread)")
                            .font(.caption.bold())
                        if spread >= 4 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("HIGH VARIANCE")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            }

            // Agreement rates
            GroupBox("Agreement Rates") {
                VStack(spacing: 6) {
                    agreementRow("Function Labels", rate: m.functionAgreementRate)
                    agreementRow("Content Scope", rate: m.contentScopeAgreementRate)
                    agreementRow("Phase Boundaries", rate: m.phaseBoundaryAgreementRate)
                    agreementRow("DependsOn Chains", rate: m.dependsOnAgreementRate)
                }
            }

            // Confusable pairs summary
            if !m.confusablePairs.isEmpty {
                GroupBox("Confusable Function Pairs") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(m.confusablePairs.prefix(10).enumerated()), id: \.offset) { _, pair in
                            HStack {
                                Text("\(pair.labelA)")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption2)
                                Text("\(pair.labelB)")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                                Spacer()
                                Text("\(pair.swapCount)x")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Signature names overlap
            if viewModel.runs.count >= 2 {
                GroupBox("Structural Signature Names") {
                    let allNames = viewModel.runs.map { run in
                        Set(run.spine.structuralSignatures.map { $0.name.lowercased() })
                    }
                    let intersection = allNames.reduce(allNames.first ?? []) { $0.intersection($1) }
                    let union = allNames.reduce(Set<String>()) { $0.union($1) }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shared across all runs: \(intersection.count)/\(union.count)")
                            .font(.caption)
                        if !intersection.isEmpty {
                            FlowLayout(spacing: 4) {
                                ForEach(Array(intersection).sorted(), id: \.self) { name in
                                    Text(name)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        let uniqueToSome = union.subtracting(intersection)
                        if !uniqueToSome.isEmpty {
                            FlowLayout(spacing: 4) {
                                ForEach(Array(uniqueToSome).sorted(), id: \.self) { name in
                                    Text(name)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Detail Tab

    private var detailTab: some View {
        let minBeats = viewModel.runs.map { $0.spine.beats.count }.min() ?? 0

        return VStack(alignment: .leading, spacing: 8) {
            // Copy button
            HStack {
                Spacer()
                CompactCopyButton(text: viewModel.detailText)
            }

            ForEach(0..<minBeats, id: \.self) { pos in
                beatComparisonRow(position: pos)
            }

            // Show if runs have different beat counts
            let maxBeats = viewModel.runs.map { $0.spine.beats.count }.max() ?? 0
            if maxBeats > minBeats {
                Text("Note: \(maxBeats - minBeats) extra beats in some runs (positions \(minBeats + 1)-\(maxBeats) not shown)")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(8)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(6)
            }
        }
    }

    @ViewBuilder
    private func beatComparisonRow(position pos: Int) -> some View {
        let functions = viewModel.runs.compactMap { run -> String? in
            guard pos < run.spine.beats.count else { return nil }
            return run.spine.beats[pos].function
        }
        let isUnanimous = Set(functions).count == 1

        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.runs, id: \.id) { run in
                    if pos < run.spine.beats.count {
                        let beat = run.spine.beats[pos]
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Run \(run.runNumber)")
                                    .font(.caption2.bold())
                                    .frame(width: 44, alignment: .leading)
                                Text(beat.function)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(isUnanimous ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                    .cornerRadius(3)
                            }
                            Text(beat.beatSentence)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Content: \(beat.contentTag)")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
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
                if let first = functions.first {
                    Text(first)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !isUnanimous {
                    Text("(\(Set(functions).count) labels)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Confusable Tab

    private var confusableTab: some View {
        let m = viewModel.metrics

        return VStack(alignment: .leading, spacing: 12) {
            if !m.confusablePairs.isEmpty {
                HStack {
                    Spacer()
                    CompactCopyButton(text: viewModel.confusableText)
                }
            }

            if m.confusablePairs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("No confusable function pairs detected")
                        .font(.subheadline)
                    Text("All runs agreed on function labels at every beat position")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                ForEach(Array(m.confusablePairs.enumerated()), id: \.offset) { _, pair in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(pair.labelA, systemImage: "tag")
                                .font(.subheadline.bold())
                            Image(systemName: "arrow.left.arrow.right")
                                .foregroundColor(.orange)
                            Label(pair.labelB, systemImage: "tag")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(pair.swapCount) swap\(pair.swapCount == 1 ? "" : "s")")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(4)
                        }

                        Text("At beat positions: \(pair.beatPositions.map(String.init).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Show the actual beat content at those positions
                        ForEach(pair.beatPositions, id: \.self) { beatPos in
                            let pos = beatPos - 1 // 0-indexed
                            if pos >= 0 {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(viewModel.runs, id: \.id) { run in
                                        if pos < run.spine.beats.count {
                                            let beat = run.spine.beats[pos]
                                            HStack(spacing: 4) {
                                                Text("R\(run.runNumber):")
                                                    .font(.caption2.bold())
                                                    .frame(width: 24, alignment: .leading)
                                                Text(beat.function)
                                                    .font(.caption2.bold())
                                                    .foregroundColor(.orange)
                                                Text(beat.contentTag)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                                .padding(6)
                                .background(Color(.systemGray6).opacity(0.3))
                                .cornerRadius(4)
                            }
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
                        Text("Beats: \(test.beatCountMin)-\(test.beatCountMax)")
                            .font(.caption.monospacedDigit())
                        Text("Fn: \(String(format: "%.0f%%", test.functionAgreementRate * 100))")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(rateColor(test.functionAgreementRate))
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
