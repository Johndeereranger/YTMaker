//
//  SectionSplitterFidelityView.swift
//  NewAgentBuilder
//
//  Created by Claude on 2/20/26.
//

import SwiftUI

// MARK: - Persistence Model

struct SectionSplitterFidelityStorage: Codable {
    let videoId: String
    let savedAt: Date
    let temperature: Double
    let runCount: Int
    let windowSize: Int
    let stepSize: Int
    let sentences: [String]
    let runs: [SectionSplitterRunResult]
    let baselineRuns: [SectionSplitterRunResult]?
    let experimentalRuns: [SectionSplitterRunResult]?
}

// MARK: - Cross-Run Comparison Model

struct CrossRunBoundaryComparison: Identifiable {
    let id: Int
    let sentenceNumber: Int
    let sentenceText: String
    let runsWithBoundary: [Int]
    let runsWithoutBoundary: [Int]
    let totalRuns: Int
    let consistency: Double
    var isUnanimous: Bool { runsWithBoundary.count == totalRuns }
    var isDivergent: Bool { !runsWithBoundary.isEmpty && !runsWithoutBoundary.isEmpty }
}

// MARK: - Pass 1 vs Merged Comparison Model

struct PassComparison: Identifiable {
    let id: Int  // sentenceNumber
    let sentenceNumber: Int
    let sentenceText: String
    let type: PassComparisonType

    let pass1Boundary: SectionBoundary?   // nil if only in merged
    let mergedBoundary: SectionBoundary?  // nil if only in pass1

    let avgPass1Confidence: Double?
    let avgMergedConfidence: Double?

    enum PassComparisonType: String, CaseIterable {
        case unchanged = "Unchanged"
        case strengthened = "Strengthened"
        case weakened = "Weakened"
        case added = "Added by P2"
        case removed = "Removed by P2"

        var color: Color {
            switch self {
            case .unchanged: return .gray
            case .strengthened: return .green
            case .weakened: return .orange
            case .added: return .blue
            case .removed: return .red
            }
        }
    }
}

// MARK: - Prompt Variant Comparison

struct PromptVariantBoundaryComparison: Identifiable {
    let id: Int
    let sentenceNumber: Int
    let sentenceText: String
    let baselineRunsWithBoundary: [Int]
    let experimentalRunsWithBoundary: [Int]
    let baselineConsistency: Double
    let experimentalConsistency: Double

    var delta: Double { experimentalConsistency - baselineConsistency }
    var isDifferent: Bool { abs(delta) > 0.001 }

    var label: String {
        if baselineConsistency == 0 && experimentalConsistency > 0 {
            return "Experimental Only"
        }
        if experimentalConsistency == 0 && baselineConsistency > 0 {
            return "Baseline Only"
        }
        if delta > 0 {
            return "Experimental Stronger"
        }
        if delta < 0 {
            return "Baseline Stronger"
        }
        return "Same"
    }

    var color: Color {
        switch label {
        case "Experimental Only": return .blue
        case "Baseline Only": return .red
        case "Experimental Stronger": return .green
        case "Baseline Stronger": return .orange
        default: return .gray
        }
    }
}

struct PromptVariantWindowComparison: Identifiable {
    let id: String
    let runNumber: Int
    let windowIndex: Int
    let startSentence: Int
    let endSentence: Int
    let baseline: WindowSplitResult?
    let experimental: WindowSplitResult?

    var changed: Bool {
        baseline?.splitAfterSentence != experimental?.splitAfterSentence ||
        baseline?.outgoingMove != experimental?.outgoingMove ||
        baseline?.incomingMove != experimental?.incomingMove
    }

    var changeLabel: String {
        let baselineSplit = baseline?.splitAfterSentence
        let experimentalSplit = experimental?.splitAfterSentence

        switch (baselineSplit, experimentalSplit) {
        case (nil, nil):
            return "Same decision, different move labels"
        case (nil, _?):
            return "Experimental added split"
        case (_?, nil):
            return "Experimental removed split"
        case let (lhs?, rhs?) where lhs != rhs:
            return "Split moved"
        default:
            return "Same split, different moves"
        }
    }
}

struct PromptVariantRunPair: Identifiable {
    let id: Int
    let runNumber: Int
    let baseline: SectionSplitterRunResult
    let experimental: SectionSplitterRunResult

    var boundaryDifferenceCount: Int {
        let baselineBoundaries = Set(baseline.boundaries.map(\.sentenceNumber))
        let experimentalBoundaries = Set(experimental.boundaries.map(\.sentenceNumber))
        return baselineBoundaries.symmetricDifference(experimentalBoundaries).count
    }

    var changedWindowCount: Int {
        let baselineMap = Dictionary(uniqueKeysWithValues: baseline.mergedResults.map { ($0.windowIndex, $0) })
        let experimentalMap = Dictionary(uniqueKeysWithValues: experimental.mergedResults.map { ($0.windowIndex, $0) })
        let windowIds = Set(baselineMap.keys).union(experimentalMap.keys)

        return windowIds.filter { windowIndex in
            let lhs = baselineMap[windowIndex]
            let rhs = experimentalMap[windowIndex]
            return lhs?.splitAfterSentence != rhs?.splitAfterSentence ||
                lhs?.outgoingMove != rhs?.outgoingMove ||
                lhs?.incomingMove != rhs?.incomingMove
        }.count
    }
}

// MARK: - Boundary Alignment Model (Section Splitter vs Rhetorical Sequence)

struct BoundaryAlignment: Identifiable {
    let id = UUID()
    let displaySentence: Int  // primary sentence number for sorting (1-indexed)
    let type: AlignmentType

    // Section Splitter side (nil if sequence-only)
    let splitterBoundary: CrossRunBoundaryComparison?

    // Rhetorical Sequence side (nil if splitter-only)
    let rhetoricalBoundarySentence: Int?  // 1-indexed sentence after which boundary occurs
    let outgoingMove: RhetoricalMove?
    let incomingMove: RhetoricalMove?
    let outgoingChunkRange: String?  // e.g. "[1]-[8]"
    let incomingChunkRange: String?  // e.g. "[9]-[15]"
    let outgoingChunkIndex: Int?
    let incomingChunkIndex: Int?

    enum AlignmentType: String, CaseIterable {
        case matched = "Matched"
        case shifted = "Shifted"
        case splitterOnly = "Splitter Only"
        case sequenceOnly = "Sequence Only"

        var color: Color {
            switch self {
            case .matched: return .green
            case .shifted: return .yellow
            case .splitterOnly: return .orange
            case .sequenceOnly: return .blue
            }
        }
    }
}

// MARK: - View Model

enum ABRunMode: String, CaseIterable {
    case both = "A + B"
    case baselineOnly = "A Only"
    case experimentalOnly = "B Only"

    var buttonLabel: String {
        switch self {
        case .both: return "Run A/B"
        case .baselineOnly: return "Run A"
        case .experimentalOnly: return "Run B"
        }
    }
}

@MainActor
class SectionSplitterFidelityViewModel: ObservableObject {
    // Configuration
    @Published var temperature: Double = 0.3
    @Published var runCount: Int = 3
    @Published var windowSize: Int = 5
    @Published var stepSize: Int = 2
    @Published var excludeDigressions: Bool = false
    @Published var abRunMode: ABRunMode = .both

    // Digression exclusion
    @Published var isLoadingDigressions: Bool = false
    @Published var digressionLoadStatus: String = ""
    @Published var digressionExcludeSet: Set<Int>?
    @Published var digressionLoadError: String?
    @Published var digressionCount: Int = 0

    // Progress
    @Published var isRunning: Bool = false
    @Published var currentRun: Int = 0
    @Published var windowsCompletedInCurrentRun: Int = 0
    @Published var totalWindowsPerRun: Int = 0
    @Published var currentPhase: String = ""

    // Results
    @Published var runs: [SectionSplitterRunResult] = []
    @Published var baselineRuns: [SectionSplitterRunResult] = []
    @Published var experimentalRuns: [SectionSplitterRunResult] = []
    @Published var sentences: [String] = []
    @Published var errorMessage: String?

    // Comparison (Rhetorical Sequence)
    @Published var rhetoricalSequence: RhetoricalSequence?
    @Published var chunks: [Chunk] = []
    @Published var alignments: [BoundaryAlignment] = []
    @Published var isLoadingRhetoricalData: Bool = false
    @Published var rhetoricalLoadError: String?

    // Input
    let video: YouTubeVideo

    let baselinePromptVariant: SectionSplitterPromptVariant = .legacy
    let experimentalPromptVariant: SectionSplitterPromptVariant = .classification

    init(video: YouTubeVideo) {
        self.video = video
    }

    // MARK: - Computed Properties

    var crossRunComparison: [CrossRunBoundaryComparison] {
        comparisonForRuns(runs)
    }

    private func comparisonForRuns(_ runs: [SectionSplitterRunResult]) -> [CrossRunBoundaryComparison] {
        guard !runs.isEmpty else { return [] }

        var allBoundaryNums = Set<Int>()
        for run in runs {
            for boundary in run.boundaries {
                allBoundaryNums.insert(boundary.sentenceNumber)
            }
        }

        let totalRuns = runs.count
        var comparisons: [CrossRunBoundaryComparison] = []

        for sentenceNum in allBoundaryNums.sorted() {
            var withBoundary: [Int] = []
            var withoutBoundary: [Int] = []

            for run in runs {
                if run.boundaries.contains(where: { $0.sentenceNumber == sentenceNum }) {
                    withBoundary.append(run.runNumber)
                } else {
                    withoutBoundary.append(run.runNumber)
                }
            }

            let sentenceText = sentenceNum > 0 && sentenceNum <= sentences.count
                ? sentences[sentenceNum - 1]
                : "(unknown)"

            comparisons.append(CrossRunBoundaryComparison(
                id: sentenceNum,
                sentenceNumber: sentenceNum,
                sentenceText: sentenceText,
                runsWithBoundary: withBoundary.sorted(),
                runsWithoutBoundary: withoutBoundary.sorted(),
                totalRuns: totalRuns,
                consistency: Double(withBoundary.count) / Double(totalRuns)
            ))
        }

        return comparisons.sorted { $0.sentenceNumber < $1.sentenceNumber }
    }

    var baselineCrossRunComparison: [CrossRunBoundaryComparison] {
        comparisonForRuns(baselineRuns)
    }

    var experimentalCrossRunComparison: [CrossRunBoundaryComparison] {
        comparisonForRuns(experimentalRuns)
    }

    var hasABResults: Bool {
        !baselineRuns.isEmpty && !experimentalRuns.isEmpty
    }

    var hasAnySingleVariantResults: Bool {
        !baselineRuns.isEmpty || !experimentalRuns.isEmpty
    }

    private var activeVariantLabel: String {
        if !baselineRuns.isEmpty && experimentalRuns.isEmpty { return "Baseline" }
        if !experimentalRuns.isEmpty && baselineRuns.isEmpty { return "Experimental" }
        return "A/B"
    }

    private var activeVariantRuns: [SectionSplitterRunResult] {
        if !baselineRuns.isEmpty && experimentalRuns.isEmpty { return baselineRuns }
        if !experimentalRuns.isEmpty && baselineRuns.isEmpty { return experimentalRuns }
        return runs
    }

    private var activeVariantComparison: [CrossRunBoundaryComparison] {
        comparisonForRuns(activeVariantRuns)
    }

    var singleVariantSummaryText: String {
        let variantRuns = activeVariantRuns
        guard !variantRuns.isEmpty else { return "No results" }
        let comparison = comparisonForRuns(variantRuns)
        let unanimous = comparison.filter { $0.isUnanimous }.count
        let divergent = comparison.filter { $0.isDivergent }.count

        var lines: [String] = []
        lines.append("=== \(activeVariantLabel.uppercased()) SUMMARY ===")
        lines.append("Video: \(video.title)")
        lines.append("Variant: \(activeVariantLabel == "Baseline" ? baselinePromptVariant.name : experimentalPromptVariant.name)")
        lines.append("Config: window=\(windowSize), step=\(stepSize), temp=\(String(format: "%.2f", temperature)), runs=\(variantRuns.count)")
        lines.append("")
        lines.append("Total boundaries: \(comparison.count)")
        lines.append("  Unanimous (\(variantRuns.count)/\(variantRuns.count)): \(unanimous)")
        lines.append("  Divergent: \(divergent)")
        return lines.joined(separator: "\n")
    }

    var singleVariantReportText: String {
        let variantRuns = activeVariantRuns
        guard !variantRuns.isEmpty else { return "No results" }
        let comparison = comparisonForRuns(variantRuns)

        var lines: [String] = []
        lines.append("=== \(activeVariantLabel.uppercased()) FULL REPORT ===")
        lines.append("Video: \(video.title)")
        lines.append("Variant: \(activeVariantLabel == "Baseline" ? baselinePromptVariant.name : experimentalPromptVariant.name)")
        lines.append("Config: window=\(windowSize), step=\(stepSize), temp=\(String(format: "%.2f", temperature)), runs=\(variantRuns.count)")
        lines.append("")

        let unanimous = comparison.filter { $0.isUnanimous }.count
        let divergent = comparison.filter { $0.isDivergent }.count
        lines.append("Total boundaries: \(comparison.count)")
        lines.append("  Unanimous: \(unanimous)")
        lines.append("  Divergent: \(divergent)")
        lines.append("")

        lines.append("BOUNDARIES:")
        for b in comparison {
            let consistency = Int(b.consistency * 100)
            let runList = b.runsWithBoundary.map { "R\($0)" }.joined(separator: ", ")
            lines.append("  [\(b.sentenceNumber)] \(consistency)% (\(runList))")
            lines.append("    \(b.sentenceText)")
        }
        lines.append("")

        lines.append("PER-RUN DETAIL:")
        for run in variantRuns {
            let boundaryNums = run.boundaries.map { "\($0.sentenceNumber)" }.joined(separator: ", ")
            lines.append("  Run \(run.runNumber): \(run.boundaries.count) boundaries [\(boundaryNums)]")
        }

        return lines.joined(separator: "\n")
    }

    var pairedRuns: [PromptVariantRunPair] {
        let experimentalByRun = Dictionary(uniqueKeysWithValues: experimentalRuns.map { ($0.runNumber, $0) })
        return baselineRuns.compactMap { baseline in
            guard let experimental = experimentalByRun[baseline.runNumber] else { return nil }
            return PromptVariantRunPair(
                id: baseline.runNumber,
                runNumber: baseline.runNumber,
                baseline: baseline,
                experimental: experimental
            )
        }
    }

    var promptVariantComparison: [PromptVariantBoundaryComparison] {
        guard hasABResults else { return [] }

        let baselineMap = Dictionary(uniqueKeysWithValues: baselineCrossRunComparison.map { ($0.sentenceNumber, $0) })
        let experimentalMap = Dictionary(uniqueKeysWithValues: experimentalCrossRunComparison.map { ($0.sentenceNumber, $0) })
        let sentenceNumbers = Set(baselineMap.keys).union(experimentalMap.keys)

        return sentenceNumbers.sorted().map { sentenceNumber in
            let baseline = baselineMap[sentenceNumber]
            let experimental = experimentalMap[sentenceNumber]
            let sentenceText = sentenceNumber > 0 && sentenceNumber <= sentences.count
                ? sentences[sentenceNumber - 1]
                : "(unknown)"

            return PromptVariantBoundaryComparison(
                id: sentenceNumber,
                sentenceNumber: sentenceNumber,
                sentenceText: sentenceText,
                baselineRunsWithBoundary: baseline?.runsWithBoundary ?? [],
                experimentalRunsWithBoundary: experimental?.runsWithBoundary ?? [],
                baselineConsistency: baseline?.consistency ?? 0,
                experimentalConsistency: experimental?.consistency ?? 0
            )
        }
    }

    var promptVariantDifferences: [PromptVariantBoundaryComparison] {
        promptVariantComparison.filter(\.isDifferent)
    }

    var promptVariantWindowComparisons: [PromptVariantWindowComparison] {
        pairedRuns.flatMap { pair in
            let baselineMap = Dictionary(uniqueKeysWithValues: pair.baseline.mergedResults.map { ($0.windowIndex, $0) })
            let experimentalMap = Dictionary(uniqueKeysWithValues: pair.experimental.mergedResults.map { ($0.windowIndex, $0) })
            let windowIds = Set(baselineMap.keys).union(experimentalMap.keys)

            return windowIds.sorted().map { windowIndex in
                let baselineResult = baselineMap[windowIndex]
                let experimentalResult = experimentalMap[windowIndex]
                return PromptVariantWindowComparison(
                    id: "r\(pair.runNumber)-w\(windowIndex)",
                    runNumber: pair.runNumber,
                    windowIndex: windowIndex,
                    startSentence: baselineResult?.startSentence ?? experimentalResult?.startSentence ?? 0,
                    endSentence: baselineResult?.endSentence ?? experimentalResult?.endSentence ?? 0,
                    baseline: baselineResult,
                    experimental: experimentalResult
                )
            }
        }
    }

    var abWindowChangeCount: Int {
        promptVariantWindowComparisons.filter(\.changed).count
    }

    var abWindowTotals: Int {
        promptVariantWindowComparisons.count
    }

    var abBoundaryOnlyExperimentalCount: Int {
        promptVariantDifferences.filter { $0.baselineConsistency == 0 && $0.experimentalConsistency > 0 }.count
    }

    var abBoundaryOnlyBaselineCount: Int {
        promptVariantDifferences.filter { $0.experimentalConsistency == 0 && $0.baselineConsistency > 0 }.count
    }

    var abExperimentalStrongerCount: Int {
        promptVariantDifferences.filter { $0.delta > 0 && $0.baselineConsistency > 0 }.count
    }

    var abBaselineStrongerCount: Int {
        promptVariantDifferences.filter { $0.delta < 0 && $0.experimentalConsistency > 0 }.count
    }

    var abChangedRunCount: Int {
        pairedRuns.filter { $0.boundaryDifferenceCount > 0 || $0.changedWindowCount > 0 }.count
    }

    var abVerdictSummary: String {
        guard hasABResults else { return "No A/B results" }

        let changedWindows = abWindowChangeCount
        let totalWindows = max(1, abWindowTotals)
        let changedPct = Int((Double(changedWindows) / Double(totalWindows)) * 100)

        if promptVariantDifferences.isEmpty && changedWindows == 0 {
            return "No measurable difference. The experimental prompt matched the baseline on all paired runs."
        }

        return "Material difference detected: \(promptVariantDifferences.count) boundary deltas across \(abChangedRunCount)/\(pairedRuns.count) paired runs, with \(changedWindows)/\(totalWindows) windows changed (\(changedPct)%)."
    }

    var promptVariantSummaryText: String {
        guard hasABResults else { return "No A/B results" }

        var lines: [String] = []
        lines.append("=== A/B COMPARISON SUMMARY ===")
        lines.append("Video: \(video.title)")
        lines.append("Baseline: \(baselinePromptVariant.name)")
        lines.append("Experimental: \(experimentalPromptVariant.name)")
        lines.append("Config: window=\(windowSize), step=\(stepSize), temp=\(String(format: "%.2f", temperature)), runs=\(runCount)")
        lines.append("")
        lines.append("VERDICT: \(abVerdictSummary)")
        lines.append("  Baseline boundaries: \(baselineCrossRunComparison.count)")
        lines.append("  Experimental boundaries: \(experimentalCrossRunComparison.count)")
        lines.append("  Different boundaries: \(promptVariantDifferences.count)")
        lines.append("  Experimental only: \(abBoundaryOnlyExperimentalCount)")
        lines.append("  Baseline only: \(abBoundaryOnlyBaselineCount)")
        lines.append("  Experimental stronger: \(abExperimentalStrongerCount)")
        lines.append("  Baseline stronger: \(abBaselineStrongerCount)")
        lines.append("  Changed windows: \(abWindowChangeCount)/\(abWindowTotals)")
        return lines.joined(separator: "\n")
    }

    var promptVariantReportText: String {
        guard hasABResults else { return "No A/B results" }

        var lines: [String] = []
        lines.append("=== SECTION SPLITTER PROMPT A/B ===")
        lines.append("Video: \(video.title)")
        lines.append("Baseline: \(baselinePromptVariant.name)")
        lines.append("Experimental: \(experimentalPromptVariant.name)")
        lines.append("Config: window=\(windowSize), step=\(stepSize), temp=\(String(format: "%.2f", temperature)), runs=\(runCount)")
        lines.append("")
        lines.append("VERDICT:")
        lines.append("  \(abVerdictSummary)")
        lines.append("  Baseline boundaries: \(baselineCrossRunComparison.count)")
        lines.append("  Experimental boundaries: \(experimentalCrossRunComparison.count)")
        lines.append("  Different boundaries: \(promptVariantDifferences.count)")
        lines.append("  Experimental only: \(abBoundaryOnlyExperimentalCount)")
        lines.append("  Baseline only: \(abBoundaryOnlyBaselineCount)")
        lines.append("  Experimental stronger: \(abExperimentalStrongerCount)")
        lines.append("  Baseline stronger: \(abBaselineStrongerCount)")
        lines.append("  Changed windows: \(abWindowChangeCount)/\(abWindowTotals)")
        lines.append("")

        lines.append("PAIRED RUNS:")
        for pair in pairedRuns {
            lines.append("  Run \(pair.runNumber): boundary deltas=\(pair.boundaryDifferenceCount), changed windows=\(pair.changedWindowCount)")
        }
        lines.append("")

        for comparison in promptVariantDifferences {
            lines.append("[\(comparison.sentenceNumber)] \(comparison.label)")
            lines.append("  Baseline: \(Int(comparison.baselineConsistency * 100))% \(comparison.baselineRunsWithBoundary.map { "R\($0)" }.joined(separator: ", "))")
            lines.append("  Experimental: \(Int(comparison.experimentalConsistency * 100))% \(comparison.experimentalRunsWithBoundary.map { "R\($0)" }.joined(separator: ", "))")
            lines.append("  Text: \(comparison.sentenceText)")
        }

        let changedWindows = promptVariantWindowComparisons.filter(\.changed)
        if !changedWindows.isEmpty {
            lines.append("")
            lines.append("WINDOW-LEVEL DIFFERENCES:")
            for window in changedWindows {
                let baselineDesc = formatWindowResult(window.baseline)
                let experimentalDesc = formatWindowResult(window.experimental)
                lines.append("R\(window.runNumber) W\(window.windowIndex) [\(window.startSentence)-\(window.endSentence)] \(window.changeLabel): \(baselineDesc) -> \(experimentalDesc)")
            }
        }

        return lines.joined(separator: "\n")
    }

    func formatWindowResult(_ result: WindowSplitResult?) -> String {
        guard let result else { return "missing" }
        if let split = result.splitAfterSentence {
            let before = result.outgoingMove ?? result.reason ?? "?"
            let after = result.incomingMove ?? "?"
            return "SPLIT[\(split)] \(before) -> \(after)"
        }
        return "NO SPLIT \(result.outgoingMove ?? result.reason ?? "")".trimmingCharacters(in: .whitespaces)
    }

    var unanimousBoundaries: [Int] {
        crossRunComparison.filter { $0.isUnanimous }.map { $0.sentenceNumber }
    }

    var divergentBoundaries: [Int] {
        crossRunComparison.filter { $0.isDivergent }.map { $0.sentenceNumber }
    }

    // MARK: - Pass 1 vs Merged Comparison

    var passComparison: [PassComparison] {
        guard !runs.isEmpty else { return [] }

        var allSentenceNums = Set<Int>()
        for run in runs {
            for b in run.pass1Boundaries { allSentenceNums.insert(b.sentenceNumber) }
            for b in run.boundaries { allSentenceNums.insert(b.sentenceNumber) }
        }

        var results: [PassComparison] = []

        for sentenceNum in allSentenceNums.sorted() {
            let pass1Confidences = runs.compactMap { run in
                run.pass1Boundaries.first { $0.sentenceNumber == sentenceNum }?.confidence
            }
            let mergedConfidences = runs.compactMap { run in
                run.boundaries.first { $0.sentenceNumber == sentenceNum }?.confidence
            }

            let avgP1 = pass1Confidences.isEmpty ? nil : pass1Confidences.reduce(0, +) / Double(pass1Confidences.count)
            let avgMerged = mergedConfidences.isEmpty ? nil : mergedConfidences.reduce(0, +) / Double(mergedConfidences.count)

            let inPass1 = !pass1Confidences.isEmpty
            let inMerged = !mergedConfidences.isEmpty

            let type: PassComparison.PassComparisonType
            if inPass1 && inMerged {
                if let p1 = avgP1, let m = avgMerged {
                    if abs(p1 - m) < 0.01 {
                        type = .unchanged
                    } else if m > p1 {
                        type = .strengthened
                    } else {
                        type = .weakened
                    }
                } else {
                    type = .unchanged
                }
            } else if inMerged && !inPass1 {
                type = .added
            } else {
                type = .removed
            }

            let p1Boundary = runs.compactMap { $0.pass1Boundaries.first { $0.sentenceNumber == sentenceNum } }.first
            let mergedBoundary = runs.compactMap { $0.boundaries.first { $0.sentenceNumber == sentenceNum } }.first

            let sentenceText = sentenceNum > 0 && sentenceNum <= sentences.count
                ? sentences[sentenceNum - 1]
                : "(unknown)"

            results.append(PassComparison(
                id: sentenceNum,
                sentenceNumber: sentenceNum,
                sentenceText: sentenceText,
                type: type,
                pass1Boundary: p1Boundary,
                mergedBoundary: mergedBoundary,
                avgPass1Confidence: avgP1,
                avgMergedConfidence: avgMerged
            ))
        }

        return results
    }

    var passComparisonStats: (unchanged: Int, strengthened: Int, weakened: Int, added: Int, removed: Int) {
        let pc = passComparison
        return (
            unchanged: pc.filter { $0.type == .unchanged }.count,
            strengthened: pc.filter { $0.type == .strengthened }.count,
            weakened: pc.filter { $0.type == .weakened }.count,
            added: pc.filter { $0.type == .added }.count,
            removed: pc.filter { $0.type == .removed }.count
        )
    }

    // MARK: - Copy Text Generators

    /// Summary: WHAT was decided, WHAT the raw data showed, WHY
    var summaryText: String {
        guard !runs.isEmpty else { return "No results" }

        var lines: [String] = []
        lines.append("=== SECTION SPLITTER FIDELITY REPORT ===")
        lines.append("Video: \(video.title)")
        lines.append("Sentences: \(sentences.count)\(excludeDigressions ? " (excluding \(digressionCount) digression sentences)" : "")")
        lines.append("Config: window=\(windowSize), step=\(stepSize), temp=\(String(format: "%.2f", temperature)), runs=\(runs.count), excludeDigressions=\(excludeDigressions)")
        lines.append("")

        // WHAT: Final results
        lines.append("FINAL RESULTS:")
        lines.append("  Total unique boundaries: \(crossRunComparison.count)")
        lines.append("  Unanimous (all runs agree): \(unanimousBoundaries.count)")
        lines.append("  Divergent (runs disagree): \(divergentBoundaries.count)")
        lines.append("")

        // WHAT: Per-run pass 1 vs pass 2 comparison
        lines.append("PASS 1 → PASS 2 COMPARISON (per run):")
        for run in runs {
            lines.append("  Run \(run.runNumber): Pass 1 found \(run.pass1SplitCount) splits → Pass 2 refined \(run.pass2Results.count) windows → \(run.pass2SplitCount) confirmed, \(run.pass2RevokedCount) revoked, \(run.pass2MovedCount) moved")

            // Show each window that was refined
            let refined = run.windowComparisons.filter { $0.wasRefined }
            if !refined.isEmpty {
                for wc in refined {
                    let p1 = wc.pass1Result
                    let p2 = wc.pass2Result!
                    let p1Desc = p1.splitAfterSentence.map { "SPLIT AFTER [\($0)]" } ?? "NO SPLIT"
                    let p2Desc = p2.splitAfterSentence.map { "SPLIT AFTER [\($0)]" } ?? "NO SPLIT"
                    lines.append("    W\(String(format: "%02d", wc.windowIndex)) [\(wc.startSentence)-\(wc.endSentence)]: \(p1Desc) → \(p2Desc) (\(wc.changeDescription))")
                    if let r1 = p1.reason { lines.append("      pass 1 reason: \(r1)") }
                    if let r2 = p2.reason { lines.append("      pass 2 reason: \(r2)") }
                }
            } else {
                lines.append("    (no windows refined — pass 1 had no splits)")
            }
        }
        lines.append("")

        // WHY: Consensus scoring for each boundary
        if !crossRunComparison.isEmpty {
            lines.append("CONSENSUS SCORING (how boundaries were determined):")
            lines.append("  Rule: confidence = (windows voting SPLIT at sentence N) / (windows overlapping sentence N)")
            lines.append("  A boundary appears if ANY window votes for it (confidence > 0%)")
            lines.append("")
            for comp in crossRunComparison {
                let status = comp.isUnanimous ? "UNANIMOUS" : "DIVERGENT"
                lines.append("  [\(comp.sentenceNumber)] — \(status) \(Int(comp.consistency * 100))%")
                lines.append("    Text: \"\(String(comp.sentenceText.prefix(80)))\"")
                lines.append("    Runs with boundary: \(comp.runsWithBoundary.map { "R\($0)" }.joined(separator: ", "))")
                if !comp.runsWithoutBoundary.isEmpty {
                    lines.append("    Runs WITHOUT boundary: \(comp.runsWithoutBoundary.map { "R\($0)" }.joined(separator: ", "))")
                }

                // Show the consensus math per run
                for run in runs {
                    if let boundary = run.boundaries.first(where: { $0.sentenceNumber == comp.sentenceNumber }) {
                        lines.append("    R\(run.runNumber) consensus: \(boundary.windowVotes)/\(boundary.windowsOverlapping) windows voted (\(String(format: "%.0f%%", boundary.confidence * 100)))")
                        if !boundary.reasons.isEmpty {
                            for reason in boundary.reasons {
                                lines.append("      → \(reason)")
                            }
                        }
                    }
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Full annotated transcript with all runs combined — shows decisions at every boundary
    var combinedTranscriptText: String {
        guard !runs.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("=== COMBINED TRANSCRIPT (all \(runs.count) runs) ===")
        lines.append("Video: \(video.title)")
        lines.append("Config: window=\(windowSize), step=\(stepSize), temp=\(String(format: "%.2f", temperature))")
        lines.append("")

        for (index, sentence) in sentences.enumerated() {
            let sentenceNum = index + 1
            lines.append("[\(sentenceNum)] \(sentence)")

            if let comp = crossRunComparison.first(where: { $0.sentenceNumber == sentenceNum }) {
                let status = comp.isUnanimous ? "UNANIMOUS" : "DIVERGENT"
                lines.append("  ┌─ SPLIT AFTER [\(sentenceNum)] — \(status) \(Int(comp.consistency * 100))%")
                lines.append("  │  runs with: \(comp.runsWithBoundary.map { "R\($0)" }.joined(separator: ", "))\(comp.runsWithoutBoundary.isEmpty ? "" : " | without: \(comp.runsWithoutBoundary.map { "R\($0)" }.joined(separator: ", "))")")

                // Per-run detail: WHAT decided, WHAT raw data showed, WHY
                for run in runs {
                    if let boundary = run.boundaries.first(where: { $0.sentenceNumber == sentenceNum }) {
                        lines.append("  │  R\(run.runNumber) WHAT: \(boundary.windowVotes)/\(boundary.windowsOverlapping) windows voted SPLIT here")

                        // Show which specific windows voted and their pass 1 vs pass 2 history
                        let relevantWindows = run.windowComparisons.filter {
                            $0.finalResult.splitAfterSentence == sentenceNum
                        }
                        for wc in relevantWindows {
                            var windowLine = "  │    W\(String(format: "%02d", wc.windowIndex)) [\(wc.startSentence)-\(wc.endSentence)]"
                            if wc.wasRefined {
                                let p1 = wc.pass1Result.splitAfterSentence.map { "[\($0)]" } ?? "none"
                                let p2 = wc.pass2Result!.splitAfterSentence.map { "[\($0)]" } ?? "none"
                                windowLine += " pass1=\(p1) pass2=\(p2) (\(wc.changeDescription))"
                            } else {
                                windowLine += " pass1 only (no refinement needed)"
                            }
                            lines.append(windowLine)
                        }

                        if !boundary.reasons.isEmpty {
                            lines.append("  │  R\(run.runNumber) WHY: \(boundary.reasons.joined(separator: " | "))")
                        }
                    }
                }
                lines.append("  └───")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Window detail text for a single run — shows pass 1 vs pass 2 per window
    func windowDetailText(for run: SectionSplitterRunResult) -> String {
        var lines: [String] = []
        lines.append("=== WINDOW DETAIL — Run \(run.runNumber) ===")
        lines.append("Windows: \(run.totalWindows)")
        lines.append("Pass 1: \(run.pass1SplitCount) splits found")
        lines.append("Pass 2: \(run.pass2Results.count) refined → \(run.pass2SplitCount) confirmed, \(run.pass2RevokedCount) revoked, \(run.pass2MovedCount) moved")
        lines.append("Final boundaries: \(run.boundaries.count)")
        lines.append("")

        for wc in run.windowComparisons {
            let range = "[\(wc.startSentence)-\(wc.endSentence)]"
            let p1 = wc.pass1Result

            // WHAT: Pass 1 decision
            if let split = p1.splitAfterSentence {
                lines.append("W\(String(format: "%02d", wc.windowIndex)) \(range)")
                lines.append("  PASS 1: SPLIT AFTER [\(split)]")
                if let reason = p1.reason { lines.append("    reason: \(reason)") }
                lines.append("    raw: \(p1.rawResponse)")

                // WHAT: Pass 2 decision (if refined)
                if let p2 = wc.pass2Result {
                    if let split2 = p2.splitAfterSentence {
                        lines.append("  PASS 2: SPLIT AFTER [\(split2)] (\(wc.changeDescription))")
                    } else {
                        lines.append("  PASS 2: NO SPLIT (\(wc.changeDescription))")
                    }
                    if let reason = p2.reason { lines.append("    reason: \(reason)") }
                    lines.append("    raw: \(p2.rawResponse)")
                }
            } else {
                // NO SPLIT — compact single line
                let reason = p1.reason.map { ": \($0)" } ?? ""
                lines.append("W\(String(format: "%02d", wc.windowIndex)) \(range) → NO SPLIT\(reason)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// All window details across all runs
    var allWindowDetailsText: String {
        runs.map { windowDetailText(for: $0) }.joined(separator: "\n\n")
    }

    /// Pass 1 vs Pass 1+2 comparison text
    var passComparisonText: String {
        guard !runs.isEmpty else { return "No results" }

        var lines: [String] = []
        lines.append("=== PASS 1 vs PASS 1+2 COMPARISON ===")
        lines.append("Video: \(video.title)")
        lines.append("Config: window=\(windowSize), step=\(stepSize), temp=\(String(format: "%.2f", temperature)), runs=\(runs.count), excludeDigressions=\(excludeDigressions)")
        lines.append("")

        // WHAT: Aggregate verdict
        let stats = passComparisonStats
        let totalBoundaries = passComparison.count
        let pass1Count = passComparison.filter { $0.pass1Boundary != nil }.count
        let mergedCount = passComparison.filter { $0.mergedBoundary != nil }.count

        lines.append("VERDICT:")
        lines.append("  Pass 1 alone: \(pass1Count) boundaries")
        lines.append("  Pass 1+2 merged: \(mergedCount) boundaries")
        lines.append("  Unchanged: \(stats.unchanged), Strengthened: \(stats.strengthened), Weakened: \(stats.weakened)")
        lines.append("  Added by P2: \(stats.added), Removed by P2: \(stats.removed)")
        if stats.unchanged == totalBoundaries {
            lines.append("  >>> Pass 2 had NO EFFECT on final boundaries <<<")
        }
        lines.append("")

        // WHY: Per-boundary detail
        lines.append("BOUNDARY-BY-BOUNDARY:")
        for comp in passComparison {
            let p1Conf = comp.avgPass1Confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
            let mConf = comp.avgMergedConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
            lines.append("  [\(comp.sentenceNumber)] \(comp.type.rawValue.uppercased()) — P1: \(p1Conf) -> Merged: \(mConf)")
            lines.append("    Text: \"\(String(comp.sentenceText.prefix(80)))\"")

            for run in runs {
                let p1 = run.pass1Boundaries.first { $0.sentenceNumber == comp.sentenceNumber }
                let merged = run.boundaries.first { $0.sentenceNumber == comp.sentenceNumber }
                let p1Desc = p1.map { "\($0.windowVotes)/\($0.windowsOverlapping)" } ?? "absent"
                let mDesc = merged.map { "\($0.windowVotes)/\($0.windowsOverlapping)" } ?? "absent"
                lines.append("    R\(run.runNumber): P1 \(p1Desc) -> Merged \(mDesc)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Digression Data Loading

    /// Check Firebase for existing digression data — does NOT generate
    func loadDigressionData() async {
        print("🔍 [Digression] Checking Firebase for video: \(video.videoId)")
        isLoadingDigressions = true
        digressionLoadStatus = "Checking..."
        digressionLoadError = nil
        digressionExcludeSet = nil
        digressionCount = 0

        do {
            let existing = try await DigressionFirebaseService.shared.getLatestResult(forVideoId: video.videoId)
            if let existing = existing {
                let excludeSet = DigressionDetectionService.shared.buildExcludeSet(from: existing.digressions)
                digressionExcludeSet = excludeSet
                digressionCount = excludeSet.count
                print("🔍 [Digression] Found: \(existing.digressions.count) digressions, \(excludeSet.count) sentences")
            } else {
                digressionLoadError = "none"
                print("🔍 [Digression] No data found")
            }
        } catch {
            digressionLoadError = "Load failed: \(error.localizedDescription)"
            print("🔍 [Digression] ERROR: \(error)")
        }

        digressionLoadStatus = ""
        isLoadingDigressions = false
    }

    /// Generate digression data from sentence telemetry, save to Firebase, then apply
    func generateDigressionData() async {
        print("🔍 [Digression] Generating for video: \(video.videoId)")
        isLoadingDigressions = true
        digressionLoadStatus = "Loading sentence telemetry..."
        digressionLoadError = nil

        do {
            let testRuns = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
            guard let latestRun = testRuns.first, !latestRun.sentences.isEmpty else {
                digressionLoadError = "No sentence telemetry — run sentence fidelity test first"
                print("🔍 [Digression] No telemetry for videoId: \(video.videoId)")
                isLoadingDigressions = false
                digressionLoadStatus = ""
                return
            }

            digressionLoadStatus = "Detecting digressions in \(latestRun.sentences.count) sentences..."
            let detected = await DigressionDetectionService.shared.detectDigressions(
                videoId: video.videoId,
                from: latestRun.sentences
            )

            digressionLoadStatus = "Saving..."
            try await DigressionFirebaseService.shared.saveResult(detected)
            print("🔍 [Digression] Saved: \(detected.digressions.count) digressions")

            let excludeSet = DigressionDetectionService.shared.buildExcludeSet(from: detected.digressions)
            digressionExcludeSet = excludeSet
            digressionCount = excludeSet.count
            digressionLoadError = nil
        } catch {
            digressionLoadError = "Generate failed: \(error.localizedDescription)"
            print("🔍 [Digression] ERROR: \(error)")
        }

        digressionLoadStatus = ""
        isLoadingDigressions = false
    }

    // MARK: - Main Test Function

    func runFidelityTest() async {
        guard let transcript = video.transcript else {
            errorMessage = "Video has no transcript"
            return
        }

        isRunning = true
        currentRun = 0
        runs = []
        baselineRuns = []
        experimentalRuns = []
        errorMessage = nil

        sentences = SentenceParser.parse(transcript)

        let service = SectionSplitterService.shared
        let windows = service.generateWindows(
            sentences: sentences,
            windowSize: windowSize,
            stepSize: stepSize
        )
        totalWindowsPerRun = windows.count

        print("\n========================================")
        print("SECTION SPLITTER FIDELITY TEST")
        print("========================================")
        print("Video: \(video.title)")
        print("Sentences: \(sentences.count), Windows: \(windows.count)")
        print("Config: window=\(windowSize), step=\(stepSize), temp=\(temperature), runs=\(runCount), excludeDigressions=\(excludeDigressions)\(excludeDigressions ? " (\(digressionCount) excluded)" : "")")

        for i in 1...runCount {
            currentRun = i
            windowsCompletedInCurrentRun = 0
            currentPhase = "Pass 1: Windows"

            do {
                let result = try await service.runSplitter(
                    transcript: transcript,
                    windowSize: windowSize,
                    stepSize: stepSize,
                    temperature: temperature,
                    excludeIndices: excludeDigressions ? digressionExcludeSet : nil,
                    onProgress: { [weak self] completed, total, phase in
                        self?.windowsCompletedInCurrentRun = completed
                        self?.totalWindowsPerRun = total
                        self?.currentPhase = phase
                    }
                )

                let numberedResult = SectionSplitterRunResult(
                    runNumber: i,
                    promptVariant: SectionSplitterPromptVariant(
                        id: result.promptVariantId,
                        name: result.promptVariantName,
                        systemPrompt: baselinePromptVariant.systemPrompt
                    ),
                    pass1Results: result.pass1Results,
                    pass2Results: result.pass2Results,
                    mergedResults: result.mergedResults,
                    windowComparisons: result.windowComparisons,
                    boundaries: result.boundaries,
                    pass1Boundaries: result.pass1Boundaries,
                    totalSentences: result.totalSentences,
                    totalWindows: result.totalWindows,
                    timestamp: result.timestamp,
                    temperature: temperature,
                    windowSize: windowSize,
                    stepSize: stepSize
                )
                runs.append(numberedResult)

                print("Run \(i) complete: \(numberedResult.boundaries.count) boundaries")
            } catch {
                errorMessage = "Run \(i) failed: \(error.localizedDescription)"
                print("Run \(i) failed: \(error)")
            }

            if i < runCount {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        isRunning = false
        currentRun = 0

        print("\n========================================")
        print("FIDELITY TEST COMPLETE")
        print("========================================")
        print("Runs: \(runs.count), Unanimous: \(unanimousBoundaries.count), Divergent: \(divergentBoundaries.count)")

        // Auto-save results
        saveToDefaults()
    }

    func runABFidelityTest() async {
        guard let transcript = video.transcript else {
            errorMessage = "Video has no transcript"
            return
        }

        isRunning = true
        currentRun = 0
        errorMessage = nil
        sentences = SentenceParser.parse(transcript)

        let service = SectionSplitterService.shared
        let windows = service.generateWindows(
            sentences: sentences,
            windowSize: windowSize,
            stepSize: stepSize
        )
        totalWindowsPerRun = windows.count

        do {
            switch abRunMode {
            case .both:
                currentPhase = "Baseline: Pass 1"
                runs = []
                baselineRuns = []
                experimentalRuns = []
                let paired = try await runPairedPromptVariantSeries(transcript: transcript)
                baselineRuns = paired.baseline
                experimentalRuns = paired.experimental
                runs = experimentalRuns

            case .baselineOnly:
                currentPhase = "Baseline: Pass 1"
                baselineRuns = []
                let results = try await runPromptVariantSeries(
                    transcript: transcript,
                    variant: baselinePromptVariant,
                    phasePrefix: "Baseline"
                )
                baselineRuns = results
                runs = baselineRuns

            case .experimentalOnly:
                currentPhase = "Experimental: Pass 1"
                experimentalRuns = []
                let results = try await runPromptVariantSeries(
                    transcript: transcript,
                    variant: experimentalPromptVariant,
                    phasePrefix: "Experimental"
                )
                experimentalRuns = results
                runs = experimentalRuns
            }

            saveToDefaults()
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
        currentRun = 0
    }

    private func runPairedPromptVariantSeries(
        transcript: String
    ) async throws -> (baseline: [SectionSplitterRunResult], experimental: [SectionSplitterRunResult]) {
        var baselineOutput: [SectionSplitterRunResult] = []
        var experimentalOutput: [SectionSplitterRunResult] = []
        let baseWindowCount = max(1, totalWindowsPerRun)

        for i in 1...runCount {
            currentRun = i
            windowsCompletedInCurrentRun = 0
            totalWindowsPerRun = baseWindowCount * 2
            currentPhase = "Paired Run \(i): starting"

            let baselineResult: SectionSplitterRunResult
            let experimentalResult: SectionSplitterRunResult

            async let baselineRun = runPromptVariantRun(
                transcript: transcript,
                variant: baselinePromptVariant,
                runNumber: i,
                phasePrefix: "Run \(i) Baseline",
                progressOffset: 0,
                progressScale: 2
            )

            async let experimentalRun = runPromptVariantRun(
                transcript: transcript,
                variant: experimentalPromptVariant,
                runNumber: i,
                phasePrefix: "Run \(i) Experimental",
                progressOffset: baseWindowCount,
                progressScale: 2
            )

            (baselineResult, experimentalResult) = try await (baselineRun, experimentalRun)

            baselineOutput.append(baselineResult)
            experimentalOutput.append(experimentalResult)

            if i < runCount {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        totalWindowsPerRun = baseWindowCount
        return (baselineOutput, experimentalOutput)
    }

    private func runPromptVariantRun(
        transcript: String,
        variant: SectionSplitterPromptVariant,
        runNumber: Int,
        phasePrefix: String,
        progressOffset: Int = 0,
        progressScale: Int = 1
    ) async throws -> SectionSplitterRunResult {
        let service = SectionSplitterService.shared

        let result = try await service.runSplitter(
            transcript: transcript,
            windowSize: windowSize,
            stepSize: stepSize,
            temperature: temperature,
            promptVariant: variant,
            excludeIndices: excludeDigressions ? digressionExcludeSet : nil,
            onProgress: { [weak self] completed, total, phase in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.windowsCompletedInCurrentRun = progressOffset + completed
                    self.totalWindowsPerRun = max(1, total * progressScale)
                    self.currentPhase = "\(phasePrefix): \(phase)"
                }
            }
        )

        return SectionSplitterRunResult(
            runNumber: runNumber,
            promptVariant: variant,
            pass1Results: result.pass1Results,
            pass2Results: result.pass2Results,
            mergedResults: result.mergedResults,
            windowComparisons: result.windowComparisons,
            boundaries: result.boundaries,
            pass1Boundaries: result.pass1Boundaries,
            totalSentences: result.totalSentences,
            totalWindows: result.totalWindows,
            timestamp: result.timestamp,
            temperature: temperature,
            windowSize: windowSize,
            stepSize: stepSize
        )
    }

    private func runPromptVariantSeries(
        transcript: String,
        variant: SectionSplitterPromptVariant,
        phasePrefix: String
    ) async throws -> [SectionSplitterRunResult] {
        var output: [SectionSplitterRunResult] = []
        let service = SectionSplitterService.shared

        for i in 1...runCount {
            currentRun = i
            windowsCompletedInCurrentRun = 0
            currentPhase = "\(phasePrefix): Pass 1"

            let result = try await service.runSplitter(
                transcript: transcript,
                windowSize: windowSize,
                stepSize: stepSize,
                temperature: temperature,
                promptVariant: variant,
                excludeIndices: excludeDigressions ? digressionExcludeSet : nil,
                onProgress: { [weak self] completed, total, phase in
                    self?.windowsCompletedInCurrentRun = completed
                    self?.totalWindowsPerRun = total
                    self?.currentPhase = "\(phasePrefix): \(phase)"
                }
            )

            output.append(SectionSplitterRunResult(
                runNumber: i,
                promptVariant: variant,
                pass1Results: result.pass1Results,
                pass2Results: result.pass2Results,
                mergedResults: result.mergedResults,
                windowComparisons: result.windowComparisons,
                boundaries: result.boundaries,
                pass1Boundaries: result.pass1Boundaries,
                totalSentences: result.totalSentences,
                totalWindows: result.totalWindows,
                timestamp: result.timestamp,
                temperature: temperature,
                windowSize: windowSize,
                stepSize: stepSize
            ))

            if i < runCount {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        return output
    }

    // MARK: - Persistence (UserDefaults)

    private var defaultsKey: String {
        "section_splitter_\(video.videoId)"
    }

    var hasSavedResults: Bool {
        UserDefaults.standard.data(forKey: defaultsKey) != nil
    }

    func saveToDefaults() {
        guard !runs.isEmpty || !baselineRuns.isEmpty || !experimentalRuns.isEmpty else { return }

        let storage = SectionSplitterFidelityStorage(
            videoId: video.videoId,
            savedAt: Date(),
            temperature: temperature,
            runCount: runCount,
            windowSize: windowSize,
            stepSize: stepSize,
            sentences: sentences,
            runs: runs,
            baselineRuns: baselineRuns.isEmpty ? nil : baselineRuns,
            experimentalRuns: experimentalRuns.isEmpty ? nil : experimentalRuns
        )

        do {
            let data = try JSONEncoder().encode(storage)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            print("Section splitter results saved (\(data.count) bytes)")
        } catch {
            print("Failed to save section splitter results: \(error)")
        }
    }

    func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            errorMessage = "No saved results for this video"
            return
        }

        do {
            let storage = try JSONDecoder().decode(SectionSplitterFidelityStorage.self, from: data)
            self.temperature = storage.temperature
            self.runCount = storage.runCount
            self.windowSize = storage.windowSize
            self.stepSize = storage.stepSize
            self.sentences = storage.sentences
            self.runs = storage.runs
            self.baselineRuns = storage.baselineRuns ?? []
            self.experimentalRuns = storage.experimentalRuns ?? []
            if self.runs.isEmpty && !self.experimentalRuns.isEmpty {
                self.runs = self.experimentalRuns
            }
            self.errorMessage = nil

            print("Loaded saved results: \(runs.count) runs, \(sentences.count) sentences (saved \(storage.savedAt))")
        } catch {
            errorMessage = "Failed to load saved results: \(error.localizedDescription)"
            print("Failed to decode section splitter results: \(error)")
        }
    }

    // MARK: - Rhetorical Sequence Comparison

    var hasRhetoricalData: Bool {
        rhetoricalSequence != nil && !chunks.isEmpty
    }

    var matchedCount: Int { alignments.filter { $0.type == .matched }.count }
    var shiftedCount: Int { alignments.filter { $0.type == .shifted }.count }
    var splitterOnlyCount: Int { alignments.filter { $0.type == .splitterOnly }.count }
    var sequenceOnlyCount: Int { alignments.filter { $0.type == .sequenceOnly }.count }
    var divergenceCount: Int { alignments.filter { $0.type != .matched }.count }

    func loadRhetoricalData() async {
        isLoadingRhetoricalData = true
        rhetoricalLoadError = nil

        // Load rhetorical sequence from video
        rhetoricalSequence = video.rhetoricalSequence

        if rhetoricalSequence == nil {
            rhetoricalLoadError = "No rhetorical sequence found for this video"
            isLoadingRhetoricalData = false
            return
        }

        // Load chunks via Firebase test → BoundaryDetectionService
        do {
            let tests = try await SentenceFidelityFirebaseService.shared.getTestRuns(forVideoId: video.videoId)
            if let latestTest = tests.first {
                let boundaryResult = BoundaryDetectionService.shared.detectBoundaries(from: latestTest)
                chunks = boundaryResult.chunks
            } else {
                rhetoricalLoadError = "No sentence analysis available — run sentence fidelity test first"
            }
        } catch {
            rhetoricalLoadError = "Failed to load sentence data: \(error.localizedDescription)"
        }

        if !chunks.isEmpty {
            computeAlignments()
        }

        isLoadingRhetoricalData = false
    }

    func computeAlignments() {
        guard !crossRunComparison.isEmpty || !chunks.isEmpty else { return }

        // Derive rhetorical boundaries from chunks
        // Chunk.endSentence uses SentenceTelemetry.sentenceIndex (0-indexed)
        // Section splitter uses 1-indexed. So rhetorical boundary = chunk.endSentence + 1
        var rhetoricalBoundaries: [(sentence: Int, outgoingChunkIdx: Int)] = []
        let sortedChunks = chunks.sorted { $0.chunkIndex < $1.chunkIndex }
        for (i, chunk) in sortedChunks.enumerated() {
            if i < sortedChunks.count - 1 {
                let boundarySentence = chunk.endSentence + 1  // convert 0-indexed to 1-indexed
                rhetoricalBoundaries.append((sentence: boundarySentence, outgoingChunkIdx: chunk.chunkIndex))
            }
        }

        let splitterBoundaries = crossRunComparison

        // Track which rhetorical boundaries get matched
        var matchedRhetoricalIndices = Set<Int>()
        var results: [BoundaryAlignment] = []

        // For each splitter boundary, find closest rhetorical match
        for splitterBound in splitterBoundaries {
            let sNum = splitterBound.sentenceNumber

            var bestMatch: (index: Int, distance: Int)?
            for (rIdx, rBound) in rhetoricalBoundaries.enumerated() {
                let dist = abs(sNum - rBound.sentence)
                if dist <= 2 {
                    if bestMatch == nil || dist < bestMatch!.distance {
                        bestMatch = (rIdx, dist)
                    }
                }
            }

            if let match = bestMatch {
                matchedRhetoricalIndices.insert(match.index)
                let rBound = rhetoricalBoundaries[match.index]
                let type: BoundaryAlignment.AlignmentType = match.distance == 0 ? .matched : .shifted
                let moves = movesForChunkBoundary(chunkIndex: rBound.outgoingChunkIdx)
                let ranges = chunkRangesForBoundary(chunkIndex: rBound.outgoingChunkIdx)

                results.append(BoundaryAlignment(
                    displaySentence: sNum,
                    type: type,
                    splitterBoundary: splitterBound,
                    rhetoricalBoundarySentence: rBound.sentence,
                    outgoingMove: moves.outgoing,
                    incomingMove: moves.incoming,
                    outgoingChunkRange: ranges.outgoing,
                    incomingChunkRange: ranges.incoming,
                    outgoingChunkIndex: rBound.outgoingChunkIdx,
                    incomingChunkIndex: rBound.outgoingChunkIdx + 1
                ))
            } else {
                // Splitter-only: find nearest rhetorical boundary for context
                let nearest = rhetoricalBoundaries.min(by: { abs($0.sentence - sNum) < abs($1.sentence - sNum) })
                let nearestMoves = nearest.map { movesForChunkBoundary(chunkIndex: $0.outgoingChunkIdx) }

                results.append(BoundaryAlignment(
                    displaySentence: sNum,
                    type: .splitterOnly,
                    splitterBoundary: splitterBound,
                    rhetoricalBoundarySentence: nearest?.sentence,
                    outgoingMove: nearestMoves?.outgoing,
                    incomingMove: nearestMoves?.incoming,
                    outgoingChunkRange: nearest.map { chunkRangesForBoundary(chunkIndex: $0.outgoingChunkIdx).outgoing } ?? nil,
                    incomingChunkRange: nearest.map { chunkRangesForBoundary(chunkIndex: $0.outgoingChunkIdx).incoming } ?? nil,
                    outgoingChunkIndex: nearest?.outgoingChunkIdx,
                    incomingChunkIndex: nearest.map { $0.outgoingChunkIdx + 1 }
                ))
            }
        }

        // Remaining unmatched rhetorical boundaries → sequenceOnly
        for (rIdx, rBound) in rhetoricalBoundaries.enumerated() {
            if !matchedRhetoricalIndices.contains(rIdx) {
                let moves = movesForChunkBoundary(chunkIndex: rBound.outgoingChunkIdx)
                let ranges = chunkRangesForBoundary(chunkIndex: rBound.outgoingChunkIdx)

                results.append(BoundaryAlignment(
                    displaySentence: rBound.sentence,
                    type: .sequenceOnly,
                    splitterBoundary: nil,
                    rhetoricalBoundarySentence: rBound.sentence,
                    outgoingMove: moves.outgoing,
                    incomingMove: moves.incoming,
                    outgoingChunkRange: ranges.outgoing,
                    incomingChunkRange: ranges.incoming,
                    outgoingChunkIndex: rBound.outgoingChunkIdx,
                    incomingChunkIndex: rBound.outgoingChunkIdx + 1
                ))
            }
        }

        alignments = results.sorted { $0.displaySentence < $1.displaySentence }
    }

    private func movesForChunkBoundary(chunkIndex: Int) -> (outgoing: RhetoricalMove?, incoming: RhetoricalMove?) {
        guard let sequence = rhetoricalSequence else { return (nil, nil) }
        let sortedMoves = sequence.moves.sorted { $0.chunkIndex < $1.chunkIndex }
        let outgoing = sortedMoves.first { $0.chunkIndex == chunkIndex }
        let incoming = sortedMoves.first { $0.chunkIndex == chunkIndex + 1 }
        return (outgoing, incoming)
    }

    private func chunkRangesForBoundary(chunkIndex: Int) -> (outgoing: String?, incoming: String?) {
        let sortedChunks = chunks.sorted { $0.chunkIndex < $1.chunkIndex }
        let outChunk = sortedChunks.first { $0.chunkIndex == chunkIndex }
        let inChunk = sortedChunks.first { $0.chunkIndex == chunkIndex + 1 }
        // Convert 0-indexed to 1-indexed for display
        let outRange = outChunk.map { "[\($0.startSentence + 1)]-[\($0.endSentence + 1)]" }
        let inRange = inChunk.map { "[\($0.startSentence + 1)]-[\($0.endSentence + 1)]" }
        return (outRange, inRange)
    }

    // MARK: - Divergence Copy Text

    func copyDivergenceBlock(for alignment: BoundaryAlignment) -> String {
        var lines: [String] = []
        let sep = String(repeating: "═", count: 75)
        let thin = String(repeating: "─", count: 75)

        lines.append(sep)
        lines.append("BOUNDARY DISAGREEMENT at sentence ~[\(alignment.displaySentence)]")
        lines.append("Type: \(alignment.type.rawValue)")
        lines.append(sep)
        lines.append("")

        // Section Splitter side
        lines.append("─── SECTION SPLITTER (LLM Window Consensus) \(String(repeating: "─", count: 30))")
        if let sb = alignment.splitterBoundary {
            lines.append("Split after sentence [\(sb.sentenceNumber)]")

            // Find consensus details from first run
            if let firstRun = runs.first,
               let boundary = firstRun.boundaries.first(where: { $0.sentenceNumber == sb.sentenceNumber }) {
                lines.append("Confidence: \(String(format: "%.0f%%", boundary.confidence * 100)) (\(boundary.windowVotes)/\(boundary.windowsOverlapping) windows voted)")
            }

            let status = sb.isUnanimous ? "UNANIMOUS" : "DIVERGENT"
            lines.append("Cross-run: \(status) \(sb.runsWithBoundary.count)/\(sb.totalRuns) runs")

            // Collect all reasons across runs
            var allReasons = Set<String>()
            for run in runs {
                if let boundary = run.boundaries.first(where: { $0.sentenceNumber == sb.sentenceNumber }) {
                    for reason in boundary.reasons { allReasons.insert(reason) }
                }
            }
            if !allReasons.isEmpty {
                lines.append("Reasons:")
                for reason in allReasons {
                    lines.append("  - \"\(reason)\"")
                }
            }
        } else {
            lines.append("Section splitter did not detect a break near sentence [\(alignment.displaySentence)]")
        }
        lines.append("")

        // Rhetorical Sequence side
        lines.append("─── RHETORICAL SEQUENCE (Existing Chunk Analysis) \(String(repeating: "─", count: 25))")
        if let rSentence = alignment.rhetoricalBoundarySentence {
            switch alignment.type {
            case .matched, .shifted:
                lines.append("Boundary after sentence [\(rSentence)]")
                if let outMove = alignment.outgoingMove {
                    let outRange = alignment.outgoingChunkRange ?? "?"
                    lines.append("  Outgoing: CHUNK \(outMove.chunkIndex + 1) — \(outMove.moveType.displayName) (\(outMove.moveType.category.rawValue)) — sentences \(outRange)")
                    lines.append("    Gist: \"\(outMove.briefDescription)\"")
                }
                if let inMove = alignment.incomingMove {
                    let inRange = alignment.incomingChunkRange ?? "?"
                    lines.append("  Incoming: CHUNK \(inMove.chunkIndex + 1) — \(inMove.moveType.displayName) (\(inMove.moveType.category.rawValue)) — sentences \(inRange)")
                    lines.append("    Gist: \"\(inMove.briefDescription)\"")
                }
            case .splitterOnly:
                lines.append("No chunk boundary near sentence [\(alignment.displaySentence)]")
                lines.append("Nearest: after sentence [\(rSentence)]")
                if let outMove = alignment.outgoingMove, let inMove = alignment.incomingMove {
                    lines.append("  \(outMove.moveType.displayName) → \(inMove.moveType.displayName)")
                }
            case .sequenceOnly:
                lines.append("Chunk boundary after sentence [\(rSentence)]")
                if let outMove = alignment.outgoingMove, let inMove = alignment.incomingMove {
                    lines.append("  \(outMove.moveType.displayName) (\(outMove.moveType.category.rawValue)) → \(inMove.moveType.displayName) (\(inMove.moveType.category.rawValue))")
                    lines.append("  Outgoing gist: \"\(outMove.briefDescription)\"")
                    lines.append("  Incoming gist: \"\(inMove.briefDescription)\"")
                }
                lines.append("Section splitter did not detect a break here")
            }
        } else {
            lines.append("No rhetorical sequence data available")
        }
        lines.append("")

        // Transcript context (±3 sentences around boundary)
        lines.append("─── TRANSCRIPT CONTEXT \(String(repeating: "─", count: 52))")
        let center = alignment.displaySentence
        let contextStart = max(1, center - 3)
        let contextEnd = min(sentences.count, center + 3)
        for i in contextStart...contextEnd {
            let text = sentences[i - 1]  // convert 1-indexed to array index
            if i == center {
                lines.append("[\(i)]   >>> SPLIT POINT <<<  \(text)")
            } else {
                lines.append("[\(i)] \(text)")
            }
        }
        lines.append("")
        lines.append(sep)

        return lines.joined(separator: "\n")
    }

    var allDivergencesText: String {
        let divergent = alignments.filter { $0.type != .matched }
        guard !divergent.isEmpty else { return "No divergences found — all boundaries match." }

        var lines: [String] = []
        lines.append("=== SECTION SPLITTER vs RHETORICAL SEQUENCE ===")
        lines.append("Video: \(video.title)")
        lines.append("Splitter: \(crossRunComparison.count) boundaries (window=\(windowSize), step=\(stepSize), temp=\(String(format: "%.2f", temperature)), \(runs.count) runs)")
        lines.append("Sequence: \(chunks.count) chunks, \(chunks.count > 1 ? chunks.count - 1 : 0) boundaries")
        lines.append("Alignment: \(matchedCount) matched, \(shiftedCount) shifted, \(splitterOnlyCount) splitter-only, \(sequenceOnlyCount) sequence-only")
        lines.append("")

        for alignment in divergent {
            lines.append(copyDivergenceBlock(for: alignment))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Rich Copy (Full Debug of Both Paths)

    func chunkForIndex(_ index: Int) -> Chunk? {
        chunks.first { $0.chunkIndex == index }
    }

    func windowsVotingForBoundary(sentenceNum: Int, run: SectionSplitterRunResult) -> [WindowPassComparison] {
        run.windowComparisons.filter { $0.finalResult.splitAfterSentence == sentenceNum }
    }

    func triggerDescription(for trigger: BoundaryTrigger) -> String {
        switch trigger.type {
        case .transition:
            return "current.isTransition == true"
        case .sponsor:
            return "sponsor content boundary (start or exit)"
        case .cta:
            return "current.isCallToAction && !previous.isCallToAction"
        case .contrastQuestion:
            return "current.hasContrastMarker && current.stance == \"questioning\""
        case .reveal:
            return "current.hasRevealLanguage && (current.hasFirstPerson || current.isTransition) && position > 10%"
        case .perspectiveShift:
            return "previous.perspective == \"third\" && current.perspective == \"first\" && current.stance == \"questioning\""
        }
    }

    func sentenceTelemetrySummary(for sent: SentenceTelemetry) -> String {
        var parts: [String] = []
        parts.append("stance=\(sent.stance), perspective=\(sent.perspective)")
        if sent.isTransition { parts.append("isTransition=true") }
        if sent.hasContrastMarker { parts.append("hasContrastMarker=true") }
        if sent.hasRevealLanguage { parts.append("hasRevealLanguage=true") }
        if sent.hasChallengeLanguage { parts.append("hasChallengeLanguage=true") }
        if sent.hasFirstPerson { parts.append("hasFirstPerson=true") }
        if sent.hasSecondPerson { parts.append("hasSecondPerson=true") }
        if sent.hasPromiseLanguage { parts.append("hasPromiseLanguage=true") }
        if sent.isSponsorContent { parts.append("isSponsorContent=true") }
        if sent.isCallToAction { parts.append("isCallToAction=true") }
        if sent.endsWithQuestion { parts.append("endsWithQuestion=true") }
        return parts.joined(separator: ", ")
    }

    func richCopyDivergenceBlock(for alignment: BoundaryAlignment) -> String {
        var lines: [String] = []
        let sep = String(repeating: "=", count: 75)

        lines.append(sep)
        lines.append("BOUNDARY DIVERGENCE — Sentence ~[\(alignment.displaySentence)] — \(alignment.type.rawValue)")
        lines.append("Video: \(video.title)")
        lines.append(sep)
        lines.append("")

        // ─── PATH A: SECTION SPLITTER ───
        lines.append("--- PATH A: SECTION SPLITTER (LLM Window Consensus) ---")
        lines.append("")

        if let sb = alignment.splitterBoundary {
            lines.append("Split after sentence: [\(sb.sentenceNumber)]")
            let status = sb.isUnanimous ? "UNANIMOUS" : "DIVERGENT"
            lines.append("Cross-run: \(status) — \(sb.runsWithBoundary.count)/\(sb.totalRuns) runs")
            lines.append("")

            for run in runs {
                if let boundary = run.boundaries.first(where: { $0.sentenceNumber == sb.sentenceNumber }) {
                    lines.append("Run \(run.runNumber): \(boundary.windowVotes)/\(boundary.windowsOverlapping) windows voted SPLIT at [\(sb.sentenceNumber)]")

                    let votingWindows = windowsVotingForBoundary(sentenceNum: sb.sentenceNumber, run: run)
                    for wc in votingWindows {
                        var windowLine = "  W\(String(format: "%02d", wc.windowIndex)) [\(wc.startSentence)-\(wc.endSentence)]:"
                        let p1Split = wc.pass1Result.splitAfterSentence.map { "SPLIT[\($0)]" } ?? "NO SPLIT"
                        windowLine += " pass1=\(p1Split)"

                        if let p2 = wc.pass2Result {
                            let p2Split = p2.splitAfterSentence.map { "SPLIT[\($0)]" } ?? "NO SPLIT"
                            windowLine += " pass2=\(p2Split) (\(wc.changeDescription))"
                        } else {
                            windowLine += " (pass1 only)"
                        }
                        lines.append(windowLine)

                        // Raw responses
                        lines.append("    pass1 raw: \"\(wc.pass1Result.rawResponse)\"")
                        if let p2 = wc.pass2Result {
                            lines.append("    pass2 raw: \"\(p2.rawResponse)\"")
                        }
                    }
                }
            }

            // Collect all unique reasons
            var allReasons = Set<String>()
            for run in runs {
                if let boundary = run.boundaries.first(where: { $0.sentenceNumber == sb.sentenceNumber }) {
                    for reason in boundary.reasons { allReasons.insert(reason) }
                }
            }
            if !allReasons.isEmpty {
                lines.append("")
                lines.append("All reasons:")
                for reason in allReasons {
                    lines.append("  - \"\(reason)\"")
                }
            }
        } else {
            lines.append("Section splitter did not detect a boundary near sentence [\(alignment.displaySentence)]")
        }

        lines.append("")

        // ─── PATH B: BOUNDARY DETECTION SERVICE ───
        lines.append("--- PATH B: BOUNDARY DETECTION SERVICE (Deterministic) ---")
        lines.append("")

        if let rSentence = alignment.rhetoricalBoundarySentence {
            switch alignment.type {
            case .matched:
                lines.append("Boundary after sentence: [\(rSentence)] (exact match with splitter)")
            case .shifted:
                let delta = alignment.splitterBoundary.map { abs($0.sentenceNumber - rSentence) } ?? 0
                let direction = alignment.splitterBoundary.map { rSentence < $0.sentenceNumber ? "earlier" : "later" } ?? ""
                lines.append("Boundary after sentence: [\(rSentence)] (delta: \(delta) sentences \(direction) than splitter)")
            case .splitterOnly:
                lines.append("No chunk boundary near sentence [\(alignment.displaySentence)]")
                lines.append("Nearest rhetorical boundary: after sentence [\(rSentence)]")
            case .sequenceOnly:
                lines.append("Chunk boundary after sentence: [\(rSentence)]")
                lines.append("Section splitter did not detect a boundary here")
            }

            // Show trigger info from the incoming chunk
            if let inChunkIdx = alignment.incomingChunkIndex,
               let inChunk = chunkForIndex(inChunkIdx),
               let trigger = inChunk.profile.boundaryTrigger {
                lines.append("Trigger: \(trigger.type.displayName) — confidence: \(trigger.confidence.rawValue.uppercased())")
                lines.append("Rule: \(triggerDescription(for: trigger))")
            } else if let outChunkIdx = alignment.outgoingChunkIndex,
                      let outChunk = chunkForIndex(outChunkIdx) {
                // First chunk after boundary might not have trigger if it's the outgoing side
                if outChunk.chunkIndex + 1 < chunks.count,
                   let nextChunk = chunkForIndex(outChunk.chunkIndex + 1),
                   let trigger = nextChunk.profile.boundaryTrigger {
                    lines.append("Trigger: \(trigger.type.displayName) — confidence: \(trigger.confidence.rawValue.uppercased())")
                    lines.append("Rule: \(triggerDescription(for: trigger))")
                }
            }

            // Show sentence telemetry at the boundary
            let boundaryIdx0 = rSentence - 1  // convert 1-indexed to 0-indexed
            if let inChunkIdx = alignment.incomingChunkIndex,
               let inChunk = chunkForIndex(inChunkIdx),
               let firstSentence = inChunk.sentences.first {
                lines.append("")
                lines.append("Evidence (sentence telemetry at boundary):")
                lines.append("  Sentence [\(firstSentence.sentenceIndex + 1)] (incoming — triggered the split):")
                lines.append("    \(sentenceTelemetrySummary(for: firstSentence))")

                // Also show the outgoing sentence
                if let outChunkIdx = alignment.outgoingChunkIndex,
                   let outChunk = chunkForIndex(outChunkIdx),
                   let lastSentence = outChunk.sentences.last {
                    lines.append("  Sentence [\(lastSentence.sentenceIndex + 1)] (outgoing — last of previous chunk):")
                    lines.append("    \(sentenceTelemetrySummary(for: lastSentence))")
                }
            }

            // Show chunk summary
            lines.append("")
            if let outMove = alignment.outgoingMove {
                let outRange = alignment.outgoingChunkRange ?? "?"
                lines.append("Outgoing: Chunk \(outMove.chunkIndex + 1) — \(outMove.moveType.rawValue) (\(outMove.moveType.category.rawValue)) — sentences \(outRange)")
            }
            if let inMove = alignment.incomingMove {
                let inRange = alignment.incomingChunkRange ?? "?"
                lines.append("Incoming: Chunk \(inMove.chunkIndex + 1) — \(inMove.moveType.rawValue) (\(inMove.moveType.category.rawValue)) — sentences \(inRange)")
            }
        } else {
            lines.append("No rhetorical sequence data available")
        }

        lines.append("")

        // ─── TRANSCRIPT ───
        lines.append("--- TRANSCRIPT ---")
        lines.append("")

        let center = alignment.displaySentence
        let contextBefore = 15
        let contextAfter = 15
        let contextStart = max(1, center - contextBefore)
        let contextEnd = min(sentences.count, center + contextAfter)

        // Gather annotation points
        let splitterSentence = alignment.splitterBoundary?.sentenceNumber
        let rhetoricalSentence = alignment.rhetoricalBoundarySentence

        // Find incoming chunk trigger info for annotation
        var triggerAnnotation = ""
        if let inChunkIdx = alignment.incomingChunkIndex,
           let inChunk = chunkForIndex(inChunkIdx),
           let trigger = inChunk.profile.boundaryTrigger {
            triggerAnnotation = " | Trigger: \(trigger.type.displayName) \(trigger.confidence.rawValue.uppercased())"
        }

        for i in contextStart...contextEnd {
            let text = sentences[i - 1]
            var annotation = ""

            if i == rhetoricalSentence && i == splitterSentence {
                annotation = "  ← BOTH SPLIT HERE"
            } else if i == rhetoricalSentence {
                let outMove = alignment.outgoingMove
                let chunkLabel = outMove.map { "Chunk \($0.chunkIndex + 1) ends" } ?? "chunk ends"
                annotation = "  ← rhetorical boundary (\(chunkLabel)\(triggerAnnotation))"
            } else if i == splitterSentence {
                let voteInfo: String
                if let sb = alignment.splitterBoundary,
                   let firstRun = runs.first,
                   let boundary = firstRun.boundaries.first(where: { $0.sentenceNumber == sb.sentenceNumber }) {
                    voteInfo = "\(sb.runsWithBoundary.count)/\(sb.totalRuns) runs, \(boundary.windowVotes)/\(boundary.windowsOverlapping) windows"
                } else {
                    voteInfo = ""
                }
                annotation = "  ← SPLITTER SPLIT (\(voteInfo))"
            }

            lines.append("[\(i)] \(text)\(annotation)")
        }

        lines.append("")

        // ─── QUESTION ───
        lines.append("--- QUESTION ---")
        lines.append("")

        switch alignment.type {
        case .matched:
            lines.append("Both systems agree on a boundary here. Does the placement feel right given the transcript flow?")
        case .shifted:
            let delta = alignment.splitterBoundary.map { abs($0.sentenceNumber - (alignment.rhetoricalBoundarySentence ?? 0)) } ?? 0
            lines.append("Both systems detect a boundary but disagree by \(delta) sentence(s).")
            lines.append("Splitter places it at [\(alignment.splitterBoundary?.sentenceNumber ?? 0)], rhetorical sequence at [\(alignment.rhetoricalBoundarySentence ?? 0)].")
            lines.append("Which sentence is the better split point, and why?")
        case .splitterOnly:
            lines.append("The section splitter (LLM window consensus) detects a section break here that the deterministic boundary detection missed.")
            lines.append("Is this a real rhetorical shift that the deterministic rules don't cover, or is the splitter detecting surface-level transitions?")
        case .sequenceOnly:
            lines.append("The deterministic boundary detection found a chunk boundary here that the section splitter's window consensus missed.")
            lines.append("Is this a meaningful section break, or did the deterministic rule fire on a false signal?")
        }

        lines.append("")
        lines.append(sep)

        return lines.joined(separator: "\n")
    }

    var allRichDivergencesText: String {
        let divergent = alignments.filter { $0.type != .matched }
        guard !divergent.isEmpty else { return "No divergences found — all boundaries match." }

        var lines: [String] = []
        lines.append("=== FULL BOUNDARY DEBUG: SECTION SPLITTER vs DETERMINISTIC BOUNDARY DETECTION ===")
        lines.append("Video: \(video.title)")
        lines.append("Splitter: \(crossRunComparison.count) boundaries (window=\(windowSize), step=\(stepSize), temp=\(String(format: "%.2f", temperature)), \(runs.count) runs)")
        lines.append("Rhetorical: \(chunks.count) chunks, \(chunks.count > 1 ? chunks.count - 1 : 0) boundaries")
        lines.append("Alignment: \(matchedCount) matched, \(shiftedCount) shifted, \(splitterOnlyCount) splitter-only, \(sequenceOnlyCount) sequence-only")
        lines.append("")

        for alignment in divergent {
            lines.append(richCopyDivergenceBlock(for: alignment))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Main View

struct SectionSplitterFidelityView: View {
    @StateObject private var viewModel: SectionSplitterFidelityViewModel

    init(video: YouTubeVideo) {
        _viewModel = StateObject(wrappedValue: SectionSplitterFidelityViewModel(video: video))
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsSection
            Divider()

            if viewModel.isRunning {
                progressSection
            } else if !viewModel.runs.isEmpty {
                resultsSection
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Section Splitter Fidelity")
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(viewModel.video.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if !viewModel.sentences.isEmpty {
                    Text("\(viewModel.sentences.count) sentences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Temperature: \(viewModel.temperature, specifier: "%.2f")")
                        .font(.caption)
                    Slider(value: $viewModel.temperature, in: 0.0...1.0, step: 0.05)
                        .frame(width: 150)
                }

                Stepper("Window: \(viewModel.windowSize)", value: $viewModel.windowSize, in: 3...20)
                    .frame(width: 160)

                Stepper("Step: \(viewModel.stepSize)", value: $viewModel.stepSize, in: 1...5)
                    .frame(width: 140)

                Stepper("Runs: \(viewModel.runCount)", value: $viewModel.runCount, in: 1...10)
                    .frame(width: 140)

                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Digressions", isOn: $viewModel.excludeDigressions)
                        .frame(width: 160)
                        .disabled(viewModel.isLoadingDigressions)
                        .onChange(of: viewModel.excludeDigressions) { newValue in
                            if newValue && (viewModel.digressionExcludeSet == nil || viewModel.digressionLoadError != nil) {
                                Task { await viewModel.loadDigressionData() }
                            }
                        }
                    if viewModel.isLoadingDigressions {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(viewModel.digressionLoadStatus.isEmpty ? "Loading..." : viewModel.digressionLoadStatus)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else if viewModel.excludeDigressions {
                        if viewModel.digressionLoadError == "none" {
                            // No data exists — show generate button
                            Button {
                                Task { await viewModel.generateDigressionData() }
                            } label: {
                                Label("Generate Digression Data", systemImage: "wand.and.stars")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        } else if let error = viewModel.digressionLoadError {
                            Label(error, systemImage: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                        } else if viewModel.digressionCount > 0 {
                            Label("Excluding \(viewModel.digressionCount) sentences", systemImage: "minus.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    } else {
                        Label("Full transcript", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                Button {
                    viewModel.loadFromDefaults()
                } label: {
                    Label("Load Saved", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRunning || !viewModel.hasSavedResults)

                Button {
                    Task { await viewModel.runFidelityTest() }
                } label: {
                    Label("Run Test", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunning || viewModel.video.transcript == nil)

                Picker("Mode", selection: $viewModel.abRunMode) {
                    ForEach(ABRunMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Button {
                    Task { await viewModel.runABFidelityTest() }
                } label: {
                    Label(viewModel.abRunMode.buttonLabel, systemImage: "square.split.2x1")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRunning || viewModel.video.transcript == nil)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Run \(viewModel.currentRun) of \(viewModel.runCount)")
                .font(.headline)

            Text(viewModel.currentPhase)
                .font(.subheadline)
                .foregroundColor(.orange)

            ProgressView(
                value: Double(viewModel.windowsCompletedInCurrentRun),
                total: Double(max(1, viewModel.totalWindowsPerRun))
            )
            .frame(width: 300)

            Text("\(viewModel.windowsCompletedInCurrentRun) / \(viewModel.totalWindowsPerRun) chunks")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "scissors")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Section Splitter Fidelity Test")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Sends overlapping windows of sentences to the LLM, asks if there's a rhetorical section break, then compares results across multiple runs.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    @State private var selectedTab: ResultsTab = .summary
    @State private var selectedRunIndex: Int = 0
    @State private var compareSubTab: CompareSubTab = .overview

    private enum ResultsTab: String, CaseIterable {
        case summary = "Summary"
        case passCompare = "P1 vs P1+2"
        case abCompare = "Prompt A/B"
        case windowDetail = "Window Detail"
        case transcript = "Transcript"
        case compare = "Compare"
    }

    private enum CompareSubTab: String, CaseIterable {
        case overview = "Alignment Overview"
        case divergences = "Divergence Detail"
    }

    private var resultsSection: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                ForEach(ResultsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .summary:
                summaryView
            case .passCompare:
                passCompareView
            case .abCompare:
                abCompareView
            case .windowDetail:
                windowDetailView
            case .transcript:
                transcriptView
            case .compare:
                compareView
            }
        }
    }

    // MARK: - Summary Tab

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stats header with copy buttons
            HStack {
                Text("Boundaries: \(viewModel.crossRunComparison.count)")
                    .font(.headline)

                Label("\(viewModel.unanimousBoundaries.count) unanimous", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Label("\(viewModel.divergentBoundaries.count) divergent", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                Spacer()

                FadeOutCopyButton(text: viewModel.summaryText, label: "Copy Summary", systemImage: "doc.on.doc")
                FadeOutCopyButton(text: viewModel.combinedTranscriptText, label: "Copy All", systemImage: "doc.on.doc.fill")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Per-run summary line showing pass 1 → pass 2 pipeline
            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.runs, id: \.id) { run in
                    let splitNums = run.boundaries.map { "[\($0.sentenceNumber)]" }.joined(separator: ", ")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Run \(run.runNumber): P1 \(run.pass1SplitCount) splits → P2 \(run.pass2SplitCount) confirmed, \(run.pass2RevokedCount) revoked, \(run.pass2MovedCount) moved → \(run.boundaries.count) boundaries (P1-only: \(run.pass1Boundaries.count))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if !splitNums.isEmpty {
                            Text("  at \(splitNums)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            Divider()

            // Comparison table
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Sentence")
                            .font(.caption.bold())
                            .frame(width: 70, alignment: .leading)

                        Text("Text")
                            .font(.caption.bold())
                            .frame(width: 200, alignment: .leading)

                        ForEach(1...max(1, viewModel.runs.count), id: \.self) { runNum in
                            Text("R\(runNum)")
                                .font(.caption.bold())
                                .frame(width: 40)
                        }

                        Text("Match")
                            .font(.caption.bold())
                            .frame(width: 60)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))

                    ForEach(viewModel.crossRunComparison) { comparison in
                        summaryRow(comparison)
                    }
                }
            }
        }
    }

    private func summaryRow(_ comparison: CrossRunBoundaryComparison) -> some View {
        HStack(spacing: 0) {
            Text("[\(comparison.sentenceNumber)]")
                .font(.caption.monospaced())
                .frame(width: 70, alignment: .leading)

            Text(String(comparison.sentenceText.prefix(40)))
                .font(.caption)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)

            ForEach(1...max(1, viewModel.runs.count), id: \.self) { runNum in
                let hasBoundary = comparison.runsWithBoundary.contains(runNum)
                Image(systemName: hasBoundary ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundColor(hasBoundary ? .green : .gray.opacity(0.3))
                    .frame(width: 40)
            }

            Text("\(Int(comparison.consistency * 100))%")
                .font(.caption.monospaced())
                .foregroundColor(comparison.isUnanimous ? .green : .orange)
                .frame(width: 60)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(comparison.isDivergent ? Color.orange.opacity(0.1) : Color.clear)
    }

    // MARK: - Pass Compare Tab (P1 vs P1+2)

    private var passCompareView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stats header
            HStack(spacing: 8) {
                let stats = viewModel.passComparisonStats

                Text("Pass 1 vs Pass 1+2")
                    .font(.headline)

                statBadge("\(stats.unchanged) unchanged", color: .gray)
                statBadge("\(stats.strengthened) strengthened", color: .green)
                statBadge("\(stats.weakened) weakened", color: .orange)
                statBadge("\(stats.added) added", color: .blue)
                statBadge("\(stats.removed) removed", color: .red)

                Spacer()

                FadeOutCopyButton(
                    text: viewModel.passComparisonText,
                    label: "Copy",
                    systemImage: "doc.on.doc"
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Verdict line
            let p1Count = viewModel.passComparison.filter { $0.pass1Boundary != nil }.count
            let mergedCount = viewModel.passComparison.filter { $0.mergedBoundary != nil }.count
            HStack(spacing: 16) {
                Text("Pass 1 alone: \(p1Count) boundaries")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Pass 1+2 merged: \(mergedCount) boundaries")
                    .font(.caption)
                    .foregroundColor(.purple)
                if viewModel.passComparisonStats.unchanged == viewModel.passComparison.count
                    && !viewModel.passComparison.isEmpty {
                    Text("Pass 2 had NO EFFECT")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            Divider()

            // Comparison table
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Sentence")
                            .frame(width: 70, alignment: .leading)
                        Text("Text")
                            .frame(width: 180, alignment: .leading)
                        Text("Effect")
                            .frame(width: 100, alignment: .leading)
                        Text("P1 Conf")
                            .frame(width: 70)
                        Text("Merged")
                            .frame(width: 70)
                        Text("Delta")
                            .frame(width: 60)
                        Text("P1 Votes")
                            .frame(width: 70)
                        Text("Merged Votes")
                            .frame(width: 85)
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))

                    if viewModel.passComparison.isEmpty {
                        Text("Run the fidelity test to see Pass 1 vs Pass 1+2 comparison")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(viewModel.passComparison) { comp in
                            passCompareRow(comp)
                        }
                    }
                }
            }
        }
    }

    private func passCompareRow(_ comp: PassComparison) -> some View {
        HStack(spacing: 0) {
            Text("[\(comp.sentenceNumber)]")
                .font(.caption.monospaced())
                .frame(width: 70, alignment: .leading)

            Text(String(comp.sentenceText.prefix(35)))
                .font(.caption)
                .frame(width: 180, alignment: .leading)
                .lineLimit(1)

            // Effect badge
            Text(comp.type.rawValue)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(comp.type.color.opacity(0.2))
                .foregroundColor(comp.type.color)
                .cornerRadius(3)
                .frame(width: 100, alignment: .leading)

            // Pass 1 confidence
            Text(comp.avgPass1Confidence.map { String(format: "%.0f%%", $0 * 100) } ?? "--")
                .font(.caption.monospaced())
                .foregroundColor(.blue)
                .frame(width: 70)

            // Merged confidence
            Text(comp.avgMergedConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "--")
                .font(.caption.monospaced())
                .foregroundColor(.purple)
                .frame(width: 70)

            // Delta
            if let p1 = comp.avgPass1Confidence, let m = comp.avgMergedConfidence {
                let delta = m - p1
                let sign = delta > 0 ? "+" : ""
                Text("\(sign)\(String(format: "%.0f%%", delta * 100))")
                    .font(.caption.monospaced())
                    .foregroundColor(delta > 0 ? .green : (delta < 0 ? .red : .secondary))
                    .frame(width: 60)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 60)
            }

            // P1 votes
            if let p1b = comp.pass1Boundary {
                Text("\(p1b.windowVotes)/\(p1b.windowsOverlapping)")
                    .font(.caption.monospaced())
                    .frame(width: 70)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 70)
            }

            // Merged votes
            if let mb = comp.mergedBoundary {
                Text("\(mb.windowVotes)/\(mb.windowsOverlapping)")
                    .font(.caption.monospaced())
                    .frame(width: 85)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 85)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
        .background(comp.type.color.opacity(0.05))
    }

    // MARK: - Window Detail Tab

    private var windowDetailView: some View {
        VStack(spacing: 0) {
            if !viewModel.runs.isEmpty {
                // Run picker + copy buttons
                HStack {
                    Picker("Run", selection: $selectedRunIndex) {
                        ForEach(viewModel.runs.indices, id: \.self) { index in
                            Text("Run \(viewModel.runs[index].runNumber)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedRunIndex < viewModel.runs.count {
                        FadeOutCopyButton(
                            text: viewModel.windowDetailText(for: viewModel.runs[selectedRunIndex]),
                            label: "Copy Run",
                            systemImage: "doc.on.doc"
                        )
                        FadeOutCopyButton(
                            text: viewModel.allWindowDetailsText,
                            label: "Copy All Runs",
                            systemImage: "doc.on.doc.fill"
                        )
                    }
                }
                .padding()

                Divider()

                if selectedRunIndex < viewModel.runs.count {
                    let run = viewModel.runs[selectedRunIndex]

                    HStack(spacing: 12) {
                        Text("\(run.totalWindows) windows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Pass 1: \(run.pass1SplitCount) splits")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Pass 2: \(run.pass2SplitCount) confirmed, \(run.pass2RevokedCount) revoked, \(run.pass2MovedCount) moved")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(run.boundaries.count) final boundaries")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(run.windowComparisons) { comparison in
                                windowComparisonRow(comparison)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    private func windowComparisonRow(_ comparison: WindowPassComparison) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                Text("W\(String(format: "%02d", comparison.windowIndex))")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)

                Text("[\(comparison.startSentence)-\(comparison.endSentence)]")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 50)

                // Pass 1 result
                let p1 = comparison.pass1Result
                if let split = p1.splitAfterSentence {
                    HStack(spacing: 4) {
                        Text("P1:")
                            .font(.caption2.bold())
                            .foregroundColor(.blue)
                        Image(systemName: "scissors")
                            .font(.caption2)
                        Text("SPLIT [\(split)]")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.orange)
                } else {
                    HStack(spacing: 4) {
                        Text("P1:")
                            .font(.caption2.bold())
                            .foregroundColor(.blue)
                        Text("NO SPLIT")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                // Pass 2 result (if refined)
                if let p2 = comparison.pass2Result {
                    Text("|")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let split2 = p2.splitAfterSentence {
                        HStack(spacing: 4) {
                            Text("P2:")
                                .font(.caption2.bold())
                                .foregroundColor(.purple)
                            Text("SPLIT [\(split2)]")
                                .font(.caption.bold())
                        }
                        .foregroundColor(.orange)
                    } else {
                        HStack(spacing: 4) {
                            Text("P2:")
                                .font(.caption2.bold())
                                .foregroundColor(.purple)
                            Text("NO SPLIT")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    // Change badge
                    if comparison.pass2Changed {
                        Text(comparison.changeDescription)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(3)
                            .foregroundColor(.red)
                    } else {
                        Text("confirmed")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(3)
                            .foregroundColor(.green)
                    }
                }

                Spacer()
            }

            // Reasons (compact)
            if comparison.wasRefined {
                if let r1 = comparison.pass1Result.reason {
                    Text("  P1: \(r1)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 88)
                }
                if let r2 = comparison.pass2Result?.reason {
                    Text("  P2: \(r2)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 88)
                }
            } else if let reason = comparison.pass1Result.reason {
                Text("  \(reason)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 88)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(windowComparisonBackground(comparison))
        .cornerRadius(4)
    }

    private func windowComparisonBackground(_ comparison: WindowPassComparison) -> Color {
        if comparison.pass2Changed {
            return Color.red.opacity(0.05)  // pass 2 changed the decision
        } else if comparison.finalResult.splitAfterSentence != nil {
            return Color.orange.opacity(0.05)  // split (confirmed or pass 1 only)
        }
        return Color.clear  // no split
    }

    // MARK: - Prompt A/B Tab

    private var abCompareView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Baseline: \(viewModel.baselinePromptVariant.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Experimental: \(viewModel.experimentalPromptVariant.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.hasABResults {
                    FadeOutCopyButton(
                        text: viewModel.promptVariantSummaryText,
                        label: "Copy Summary",
                        systemImage: "doc.plaintext"
                    )
                    FadeOutCopyButton(
                        text: viewModel.promptVariantReportText,
                        label: "Copy Full",
                        systemImage: "doc.on.doc"
                    )
                } else if viewModel.hasAnySingleVariantResults {
                    FadeOutCopyButton(
                        text: viewModel.singleVariantSummaryText,
                        label: "Copy Summary",
                        systemImage: "doc.plaintext"
                    )
                    FadeOutCopyButton(
                        text: viewModel.singleVariantReportText,
                        label: "Copy Full",
                        systemImage: "doc.on.doc"
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if !viewModel.hasABResults {
                VStack(spacing: 12) {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(viewModel.abRunMode == .both
                         ? "Run `Run A/B` to compare the legacy splitter against the classification-first prompt on the same windows."
                         : "Run both A + B to compare variants. Currently set to \(viewModel.abRunMode.rawValue).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 16) {
                    Text("Baseline boundaries: \(viewModel.baselineCrossRunComparison.count)")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text("Experimental boundaries: \(viewModel.experimentalCrossRunComparison.count)")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Different: \(viewModel.promptVariantDifferences.count)")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    Text("Changed windows: \(viewModel.abWindowChangeCount)/\(viewModel.abWindowTotals)")
                        .font(.caption)
                        .foregroundColor(.purple)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 6)

                Text(viewModel.abVerdictSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("Run")
                                .frame(width: 50)
                            Text("Sentence")
                                .frame(width: 70, alignment: .leading)
                            Text("Text")
                                .frame(width: 170, alignment: .leading)
                            Text("Baseline")
                                .frame(width: 70)
                            Text("Experiment")
                                .frame(width: 80)
                            Text("Delta")
                                .frame(width: 60)
                            Text("Label")
                                .frame(width: 140, alignment: .leading)
                        }
                        .font(.caption2.bold())
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))

                        ForEach(viewModel.promptVariantComparison) { comparison in
                            abBoundaryRow(comparison)
                        }

                        if !viewModel.promptVariantWindowComparisons.isEmpty {
                            Divider()
                                .padding(.vertical, 8)

                            Text("Window-level differences (all paired runs)")
                                .font(.caption.bold())
                                .padding(.horizontal)
                                .padding(.bottom, 4)

                            ForEach(viewModel.promptVariantWindowComparisons.filter(\.changed)) { comparison in
                                abWindowRow(comparison)
                            }
                        }
                    }
                }
            }
        }
    }

    private func abBoundaryRow(_ comparison: PromptVariantBoundaryComparison) -> some View {
        HStack(spacing: 0) {
            Text("All")
                .font(.caption2.monospaced())
                .frame(width: 50)

            Text("[\(comparison.sentenceNumber)]")
                .font(.caption.monospaced())
                .frame(width: 70, alignment: .leading)

            Text(String(comparison.sentenceText.prefix(42)))
                .font(.caption)
                .frame(width: 170, alignment: .leading)
                .lineLimit(1)

            Text("\(Int(comparison.baselineConsistency * 100))%")
                .font(.caption.monospaced())
                .foregroundColor(.red)
                .frame(width: 70)

            Text("\(Int(comparison.experimentalConsistency * 100))%")
                .font(.caption.monospaced())
                .foregroundColor(.blue)
                .frame(width: 80)

            let delta = comparison.delta
            Text("\(delta > 0 ? "+" : "")\(Int(delta * 100))%")
                .font(.caption.monospaced())
                .foregroundColor(delta > 0 ? .green : (delta < 0 ? .orange : .secondary))
                .frame(width: 60)

            Text(comparison.label)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(comparison.color.opacity(0.15))
                .foregroundColor(comparison.color)
                .cornerRadius(3)
                .frame(width: 140, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
        .background(comparison.isDifferent ? comparison.color.opacity(0.05) : Color.clear)
    }

    private func abWindowRow(_ comparison: PromptVariantWindowComparison) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("R\(comparison.runNumber) W\(String(format: "%02d", comparison.windowIndex)) [\(comparison.startSentence)-\(comparison.endSentence)]")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)

            Text("Baseline: \(viewModel.formatWindowResult(comparison.baseline))")
                .font(.caption2)
                .foregroundColor(.red)

            Text("Experimental: \(viewModel.formatWindowResult(comparison.experimental))")
                .font(.caption2)
                .foregroundColor(.blue)

            Text(comparison.changeLabel)
                .font(.caption2)
                .foregroundColor(.orange)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(4)
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    // MARK: - Transcript Tab

    private var transcriptView: some View {
        VStack(spacing: 0) {
            // Copy buttons for transcript
            HStack {
                Text("Full Transcript — All Runs Combined")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                FadeOutCopyButton(text: viewModel.combinedTranscriptText, label: "Copy Transcript", systemImage: "doc.on.doc")
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.sentences.enumerated()), id: \.offset) { index, sentence in
                        let sentenceNum = index + 1
                        let comparison = viewModel.crossRunComparison.first { $0.sentenceNumber == sentenceNum }

                        transcriptRow(sentenceNum: sentenceNum, text: sentence, comparison: comparison)

                        // Boundary annotation block
                        if let comp = comparison {
                            boundaryAnnotation(comp)

                            Divider()
                                .overlay(comp.isUnanimous ? Color.green : Color.orange)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func transcriptRow(sentenceNum: Int, text: String, comparison: CrossRunBoundaryComparison?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("[\(sentenceNum)]")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            Text(text)
                .font(.caption)

            Spacer()

            if let comp = comparison {
                HStack(spacing: 2) {
                    Image(systemName: "scissors")
                        .font(.caption2)
                    Text("\(Int(comp.consistency * 100))%")
                        .font(.caption2.monospaced())
                }
                .foregroundColor(comp.isUnanimous ? .green : .orange)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            comparison != nil
                ? (comparison!.isUnanimous ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                : Color.clear
        )
        .cornerRadius(4)
    }

    /// Shows which runs split here, pass 1 vs pass 2 detail, and reasons
    private func boundaryAnnotation(_ comp: CrossRunBoundaryComparison) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "scissors")
                    .font(.caption2)
                Text("SPLIT AFTER [\(comp.sentenceNumber)]")
                    .font(.caption2.bold())

                Text(comp.isUnanimous ? "UNANIMOUS" : "DIVERGENT")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(comp.isUnanimous ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .cornerRadius(3)

                Text("runs: \(comp.runsWithBoundary.map { "R\($0)" }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if !comp.runsWithoutBoundary.isEmpty {
                    Text("missing: \(comp.runsWithoutBoundary.map { "R\($0)" }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(comp.isUnanimous ? .green : .orange)

            // Per-run detail: consensus math + pass 1 vs pass 2
            ForEach(viewModel.runs, id: \.id) { run in
                if let boundary = run.boundaries.first(where: { $0.sentenceNumber == comp.sentenceNumber }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("R\(run.runNumber): \(boundary.windowVotes)/\(boundary.windowsOverlapping) windows voted")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Show pass 1 → pass 2 for windows that voted here
                        let relevant = run.windowComparisons.filter {
                            $0.finalResult.splitAfterSentence == comp.sentenceNumber
                        }
                        ForEach(relevant) { wc in
                            HStack(spacing: 4) {
                                Text("W\(String(format: "%02d", wc.windowIndex))")
                                    .font(.caption2.monospaced())
                                if wc.wasRefined {
                                    let p1 = wc.pass1Result.splitAfterSentence.map { "[\($0)]" } ?? "none"
                                    let p2 = wc.pass2Result!.splitAfterSentence.map { "[\($0)]" } ?? "none"
                                    Text("P1:\(p1) P2:\(p2)")
                                        .font(.caption2.monospaced())
                                    Text(wc.changeDescription)
                                        .font(.caption2)
                                        .foregroundColor(wc.pass2Changed ? .red : .green)
                                } else {
                                    Text("P1 only")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(.secondary)
                        }

                        // Reasons
                        if !boundary.reasons.isEmpty {
                            Text(boundary.reasons.joined(separator: "; "))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
        .padding(.horizontal, 44)  // align with sentence text (past the number column)
        .padding(.vertical, 4)
    }

    // MARK: - Compare Tab

    private var compareView: some View {
        VStack(spacing: 0) {
            // Header with stats and actions
            compareHeader

            Divider()

            if viewModel.isLoadingRhetoricalData {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading rhetorical sequence...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.hasRhetoricalData {
                compareEmptyState
            } else if viewModel.alignments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No alignments computed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Inner sub-tab picker
                Picker("Compare View", selection: $compareSubTab) {
                    ForEach(CompareSubTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)

                Divider()

                switch compareSubTab {
                case .overview:
                    alignmentOverviewTable
                case .divergences:
                    divergenceDetailView
                }
            }
        }
    }

    // MARK: - Alignment Overview Table

    private var alignmentOverviewTable: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("Sentence")
                        .frame(width: 70, alignment: .leading)
                    Text("Type")
                        .frame(width: 90, alignment: .leading)

                    ForEach(1...max(1, viewModel.runs.count), id: \.self) { runNum in
                        Text("R\(runNum)")
                            .frame(width: 35)
                    }

                    Text("Cons.")
                        .frame(width: 50)
                    Text("Trigger")
                        .frame(width: 120, alignment: .leading)
                    Text("Rhetorical Transition")
                        .frame(width: 180, alignment: .leading)
                    Text("Category")
                        .frame(width: 140, alignment: .leading)
                }
                .font(.caption2.bold())
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemBackground))

                ForEach(viewModel.alignments) { alignment in
                    alignmentOverviewRow(alignment)
                }
            }
        }
    }

    private func alignmentOverviewRow(_ alignment: BoundaryAlignment) -> some View {
        HStack(spacing: 0) {
            // Sentence number
            Text("[\(alignment.displaySentence)]")
                .font(.caption.monospaced())
                .frame(width: 70, alignment: .leading)

            // Type badge
            Text(alignment.type.rawValue)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(alignment.type.color.opacity(0.2))
                .foregroundColor(alignment.type.color == .yellow ? .primary : alignment.type.color)
                .cornerRadius(3)
                .frame(width: 90, alignment: .leading)

            // Per-run checkmarks
            ForEach(1...max(1, viewModel.runs.count), id: \.self) { runNum in
                if let sb = alignment.splitterBoundary {
                    let hasBoundary = sb.runsWithBoundary.contains(runNum)
                    Image(systemName: hasBoundary ? "checkmark.circle.fill" : "minus.circle")
                        .font(.caption2)
                        .foregroundColor(hasBoundary ? .green : .gray.opacity(0.3))
                        .frame(width: 35)
                } else {
                    Text("--")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 35)
                }
            }

            // Consensus
            if let sb = alignment.splitterBoundary {
                Text("\(Int(sb.consistency * 100))%")
                    .font(.caption.monospaced())
                    .foregroundColor(sb.isUnanimous ? .green : .orange)
                    .frame(width: 50)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 50)
            }

            // Trigger (from incoming chunk's boundary trigger)
            if let inChunkIdx = alignment.incomingChunkIndex,
               let inChunk = viewModel.chunkForIndex(inChunkIdx),
               let trigger = inChunk.profile.boundaryTrigger {
                Text("\(trigger.type.displayName) (\(trigger.confidence.rawValue.prefix(3).uppercased()))")
                    .font(.caption2)
                    .frame(width: 120, alignment: .leading)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 120, alignment: .leading)
            }

            // Rhetorical transition
            if let outMove = alignment.outgoingMove, let inMove = alignment.incomingMove {
                HStack(spacing: 2) {
                    Text(outMove.moveType.rawValue)
                        .font(.caption2)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7))
                    Text(inMove.moveType.rawValue)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .frame(width: 180, alignment: .leading)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 180, alignment: .leading)
            }

            // Category
            if let outMove = alignment.outgoingMove, let inMove = alignment.incomingMove {
                HStack(spacing: 2) {
                    Text(outMove.moveType.category.rawValue)
                        .font(.caption2)
                    if outMove.moveType.category != inMove.moveType.category {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 7))
                        Text(inMove.moveType.category.rawValue)
                            .font(.caption2)
                    }
                }
                .frame(width: 140, alignment: .leading)
            } else {
                Text("--")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
        .background(alignment.type.color.opacity(0.05))
    }

    // MARK: - Divergence Detail View

    private var divergenceDetailView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.alignments) { alignment in
                    compareRow(alignment)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var compareHeader: some View {
        VStack(spacing: 8) {
            if viewModel.hasRhetoricalData {
                // Stats badges
                HStack(spacing: 8) {
                    statBadge("\(viewModel.matchedCount) matched", color: .green)
                    statBadge("\(viewModel.shiftedCount) shifted", color: .yellow)
                    statBadge("\(viewModel.splitterOnlyCount) splitter-only", color: .orange)
                    statBadge("\(viewModel.sequenceOnlyCount) sequence-only", color: .blue)
                    Spacer()
                    if viewModel.divergenceCount > 0 {
                        FadeOutCopyButton(
                            text: viewModel.allDivergencesText,
                            label: "Copy Summary",
                            systemImage: "doc.on.doc"
                        )
                        FadeOutCopyButton(
                            text: viewModel.allRichDivergencesText,
                            label: "Copy Rich",
                            systemImage: "doc.on.doc.fill"
                        )
                    }
                }

                // Sequence info
                HStack {
                    if let seq = viewModel.rhetoricalSequence {
                        Text("\(seq.moves.count) moves, \(viewModel.chunks.count) chunks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                HStack {
                    if let error = viewModel.rhetoricalLoadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("Load the rhetorical sequence to compare with splitter results")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await viewModel.loadRhetoricalData() }
                    } label: {
                        Label("Load Rhetorical Data", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.isLoadingRhetoricalData)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var compareEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("No Comparison Available")
                .font(.headline)
                .foregroundColor(.secondary)

            if let error = viewModel.rhetoricalLoadError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button {
                Task { await viewModel.loadRhetoricalData() }
            } label: {
                Label("Load Rhetorical Data", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoadingRhetoricalData)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color == .yellow ? .primary : color)
            .cornerRadius(4)
    }

    private func compareRow(_ alignment: BoundaryAlignment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: sentence number + type badge
            HStack(spacing: 8) {
                Text("[\(alignment.displaySentence)]")
                    .font(.caption.monospaced().bold())

                Text(alignment.type.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(alignment.type.color.opacity(0.2))
                    .foregroundColor(alignment.type.color == .yellow ? .primary : alignment.type.color)
                    .cornerRadius(4)

                if alignment.type == .shifted,
                   let sNum = alignment.splitterBoundary?.sentenceNumber,
                   let rNum = alignment.rhetoricalBoundarySentence {
                    Text("(splitter: [\(sNum)], sequence: [\(rNum)])")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Copy button for every boundary
                FadeOutCopyButton(
                    text: viewModel.richCopyDivergenceBlock(for: alignment),
                    label: "Copy",
                    systemImage: "doc.on.doc"
                )
            }

            // Two-column content
            HStack(alignment: .top, spacing: 16) {
                // LEFT: Splitter
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPLITTER")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)

                    if let sb = alignment.splitterBoundary {
                        Text("Split after [\(sb.sentenceNumber)]")
                            .font(.caption)

                        let status = sb.isUnanimous ? "unanimous" : "divergent \(Int(sb.consistency * 100))%"
                        Text("\(sb.runsWithBoundary.count)/\(sb.totalRuns) runs (\(status))")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // First reason
                        if let firstRun = viewModel.runs.first,
                           let boundary = firstRun.boundaries.first(where: { $0.sentenceNumber == sb.sentenceNumber }),
                           let reason = boundary.reasons.first {
                            Text(reason)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .italic()
                        }
                    } else {
                        Text("No split detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // RIGHT: Rhetorical Sequence
                VStack(alignment: .leading, spacing: 2) {
                    Text("RHETORICAL")
                        .font(.caption2.bold())
                        .foregroundColor(.purple)

                    if let outMove = alignment.outgoingMove,
                       let inMove = alignment.incomingMove {
                        HStack(spacing: 4) {
                            Text(outMove.moveType.displayName)
                                .font(.caption)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                            Text(inMove.moveType.displayName)
                                .font(.caption)
                        }

                        // Deterministic trigger that caused this boundary
                        if let inChunkIdx = alignment.incomingChunkIndex,
                           let inChunk = viewModel.chunkForIndex(inChunkIdx),
                           let trigger = inChunk.profile.boundaryTrigger {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8))
                                Text("\(trigger.type.displayName)")
                                    .font(.caption2)
                                Text("(\(trigger.confidence.rawValue.uppercased()))")
                                    .font(.caption2)
                                    .foregroundColor(trigger.confidence == .high ? .green : .yellow)
                            }
                            .foregroundColor(.purple.opacity(0.8))
                        }

                        if let outRange = alignment.outgoingChunkRange {
                            Text("outgoing: \(outRange)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text(outMove.briefDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .italic()
                    } else if alignment.type == .splitterOnly {
                        Text("No boundary here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let nearest = alignment.rhetoricalBoundarySentence {
                            Text("nearest: [\(nearest)]")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Transcript context (compact — 1 sentence before and after)
            let center = alignment.displaySentence
            if center >= 1 && center <= viewModel.sentences.count {
                VStack(alignment: .leading, spacing: 1) {
                    if center > 1 {
                        Text("[\(center - 1)] \(viewModel.sentences[center - 2])")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text("[\(center)] \(viewModel.sentences[center - 1])")
                        .font(.caption2.bold())
                        .lineLimit(2)
                    if center < viewModel.sentences.count {
                        Text("[\(center + 1)] \(viewModel.sentences[center])")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(8)
        .background(alignment.type.color.opacity(0.05))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(alignment.type.color.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    SectionSplitterFidelityView(video: YouTubeVideo(
        videoId: "test",
        channelId: "test",
        title: "Test Video",
        description: "",
        publishedAt: Date(),
        duration: "PT10M",
        thumbnailUrl: "",
        stats: VideoStats(viewCount: 1000, likeCount: 100, commentCount: 10),
        createdAt: Date()
    ))
}
